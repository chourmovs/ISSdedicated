# app.py — ISS WebInfo v2 (FastAPI + SSE + A2S + Game.ini parser)
import os, re, time, threading, asyncio, json
from datetime import datetime, timedelta
from collections import deque, Counter, defaultdict
from pathlib import Path
from typing import Dict, Any, Optional

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, StreamingResponse, JSONResponse

# ─────────────────────────────────────────────────────────
# Config
# ─────────────────────────────────────────────────────────
LOG_FILE  = os.environ.get("LOG_FILE", "/opt/sandstorm/Insurgency/Saved/Logs/Insurgency.log")
GAME_INI  = os.environ.get("GAME_INI", "/opt/sandstorm/Insurgency/Saved/Config/LinuxServer/Game.ini")
# A2S: hôte/port du serveur (vu depuis ce container). Par défaut, le nom de service docker "sandstorm".
A2S_HOST  = os.environ.get("A2S_HOST", "sandstorm")
A2S_PORT  = int(os.environ.get("A2S_PORT", "27131"))  # QueryPort
A2S_POLL_INTERVAL = float(os.environ.get("A2S_POLL_INTERVAL", "5.0"))

# Regex logs
JOIN_REGEX = re.compile(os.environ.get(
    "JOIN_REGEX",
    r"LogGameMode:\s+Display:\s+Player\s+(?P<id>\d+)\s+'(?P<name>[^']+)'\s+joined\s+team\s+(?P<team>\d+)"
))
LEAVE_REGEX = re.compile(os.environ.get(
    "LEAVE_REGEX",
    r"LogGameMode:\s+Display:\s+Player\s+(?P<id>\d+)\s+'(?P<name>[^']+)'\s+left\s+team\s+(?P<team>\d+)"
))
JOIN_FALLBACK  = re.compile(r"Player\s+(?P<id>\d+)\s+'(?P<name>[^']+)'\s+joined\s+team\s+(?P<team>\d+)")
LEAVE_FALLBACK = re.compile(r"Player\s+(?P<id>\d+)\s+'(?P<name>[^']+)'\s+left\s+team\s+(?P<team>\d+)")

EVENT_HISTORY_MAX   = int(os.environ.get("EVENT_HISTORY_MAX", "600"))
STATS_RETENTION_DAYS= int(os.environ.get("STATS_RETENTION_DAYS", "21"))
ROOT_PATH           = os.environ.get("ROOT_PATH", "").strip()  # ex: "/iss" si tu veux

# ─────────────────────────────────────────────────────────
# État global
# ─────────────────────────────────────────────────────────
players_online: Dict[str, Dict[str, Any]] = {}   # id -> {id,name,team,since}
name_to_team: Dict[str, str] = {}                # map rapide pour A2S (name -> team)
events = deque(maxlen=EVENT_HISTORY_MAX)         # feed temps réel (join/leave)
join_count_per_player = Counter()                # name -> count
join_count_per_day = defaultdict(int)            # date -> count
last_line_ts: Optional[str] = None

# Infos live A2S
live_info: Dict[str, Any] = {
    "ok": False,
    "host": A2S_HOST, "port": A2S_PORT,
    "hostname": None, "map": None, "player_count": 0, "max_players": 0,
    "players": [],  # [{name, score, time, team?}]
    "updated_at": None,
    "round_start": None,  # ISO quand la map a changé
}
playercount_series = deque(maxlen=720)  # ~1h si poll 5s → 720*5s=3600s
series_started_at = datetime.utcnow()

# Diffuseurs SSE
subscribers = set()
sub_lock = threading.Lock()

# FastAPI
app = FastAPI(root_path=ROOT_PATH or None)

# ─────────────────────────────────────────────────────────
# Utils
# ─────────────────────────────────────────────────────────
def now_iso() -> str:
    return datetime.utcnow().isoformat() + "Z"

def parse_join(line: str):
    m = JOIN_REGEX.search(line) or JOIN_FALLBACK.search(line)
    if not m: return None
    return {"type":"join","id":m.group("id"),"name":m.group("name"),"team":m.group("team")}

def parse_leave(line: str):
    m = LEAVE_REGEX.search(line) or LEAVE_FALLBACK.search(line)
    if not m: return None
    return {"type":"leave","id":m.group("id"),"name":m.group("name"),"team":m.group("team")}

def publish(ev: Dict[str, Any]) -> None:
    data = json.dumps(ev)
    dead = []
    with sub_lock:
        for q in list(subscribers):
            try: q.put_nowait(data)
            except asyncio.QueueFull: dead.append(q)
        for q in dead: subscribers.discard(q)

def record_event(ev_type: str, pid: str, name: str, team: str, line: str) -> None:
    global last_line_ts
    ts = now_iso()
    last_line_ts = ts
    ev = {"ts": ts, "type": ev_type, "id": pid, "name": name, "team": team, "line": line[:400]}
    events.append(ev)
    publish(ev)

def cleanup_stats() -> None:
    cutoff = datetime.utcnow().date() - timedelta(days=STATS_RETENTION_DAYS)
    for day in list(join_count_per_day.keys()):
        try: d = datetime.strptime(day, "%Y-%m-%d").date()
        except: continue
        if d < cutoff:
            del join_count_per_day[day]

# ─────────────────────────────────────────────────────────
# Tail -F des logs (thread)
# ─────────────────────────────────────────────────────────
def follow(path: Path):
    f = None; sig = None
    while True:
        try:
            st = path.stat()
            if f is None or sig != (st.st_ino, st.st_dev) or f.tell() > st.st_size:
                if f:
                    try: f.close()
                    except: pass
                f = path.open("r", errors="ignore")
                f.seek(0, 2)
                sig = (st.st_ino, st.st_dev)
                print(f"[webinfo] open log {path} inode={sig}", flush=True)
            line = f.readline()
            if line: yield line.rstrip("\r\n")
            else: time.sleep(0.5)
        except FileNotFoundError:
            time.sleep(1.0)
        except Exception as e:
            print(f"[webinfo] tail error: {e}", flush=True)
            time.sleep(1.0)

def tail_thread():
    path = Path(LOG_FILE)
    for line in follow(path):
        ev = parse_join(line) or parse_leave(line)
        if not ev: continue
        pid, name, team = ev["id"], ev["name"], ev["team"]
        name_to_team[name] = team
        if ev["type"] == "join":
            players_online[pid] = {"id": pid, "name": name, "team": team, "since": now_iso()}
            join_count_per_player[name] += 1
            join_count_per_day[datetime.utcnow().strftime("%Y-%m-%d")] += 1
            cleanup_stats()
        else:
            players_online.pop(pid, None)
        record_event(ev["type"], pid, name, team, line)

# ─────────────────────────────────────────────────────────
# A2S poller (thread)
# ─────────────────────────────────────────────────────────
def a2s_poller():
    import a2s
    global live_info
    last_map = None
    while True:
        try:
            addr = (A2S_HOST, A2S_PORT)
            info = a2s.info(addr, timeout=2.0)
            players = []
            try:
                pl = a2s.players(addr, timeout=2.0)
                for p in pl:
                    # p.name, p.score, p.duration (seconds)
                    players.append({
                        "name": p.name,
                        "score": getattr(p, "score", None),
                        "time": int(getattr(p, "duration", 0)),
                        "team": name_to_team.get(p.name)  # best-effort via logs
                    })
            except Exception as e:
                print("[webinfo] A2S players failed:", e, flush=True)

            live_info.update({
                "ok": True,
                "hostname": getattr(info, "server_name", None),
                "map": getattr(info, "map_name", None),
                "player_count": getattr(info, "player_count", 0),
                "max_players": getattr(info, "max_players", 0),
                "players": players,
                "updated_at": now_iso()
            })

            # round start heuristique: map a changé
            cur_map = live_info.get("map")
            if cur_map != last_map:
                last_map = cur_map
                live_info["round_start"] = now_iso()

            # timeline joueurs
            playercount_series.append({
                "t": (datetime.utcnow()-series_started_at).total_seconds(),
                "v": live_info["player_count"]
            })

        except Exception as e:
            live_info.update({
                "ok": False,
                "players": [],
                "updated_at": now_iso()
            })
            print("[webinfo] A2S info failed:", e, flush=True)

        time.sleep(A2S_POLL_INTERVAL)

# ─────────────────────────────────────────────────────────
# Parsing Game.ini (mods/mutators)
# ─────────────────────────────────────────────────────────
def parse_game_ini(path: str):
    data = {
        "mods": [],
        "mutators": {  # par mode Unreal
            "Push": [], "Firefight": [], "Domination": [], "Skirmish": [],
            "Checkpoint": [], "Outpost": [], "Survival": []
        }
    }
    p = Path(path)
    if not p.exists():
        return data

    section = None
    modes_map = {
        "/Script/Insurgency.INSPushGameMode": "Push",
        "/Script/Insurgency.INSFirefightGameMode": "Firefight",
        "/Script/Insurgency.INSDominationGameMode": "Domination",
        "/Script/Insurgency.INSSkirmishGameMode": "Skirmish",
        "/Script/Insurgency.INSCheckpointGameMode": "Checkpoint",
        "/Script/Insurgency.INSOutpostGameMode": "Outpost",
        "/Script/Insurgency.INSSurvivalGameMode": "Survival",
    }
    try:
        with p.open("r", errors="ignore") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith(";"):
                    continue
                if line.startswith("[") and line.endswith("]"):
                    section = line[1:-1]
                    continue
                if "Mods=" in line:
                    val = line.split("=",1)[1].strip()
                    if val:
                        data["mods"].append(val)
                if "Mutators=" in line and section in modes_map:
                    val = line.split("=",1)[1].strip()
                    if val:
                        # split CSV propre
                        muts = [m.strip() for m in val.split(",") if m.strip()]
                        data["mutators"][modes_map[section]] = muts
    except Exception as e:
        print("[webinfo] parse Game.ini failed:", e, flush=True)
    return data

# state initial (chargé à la demande aussi)
_config_cache = None
def get_config():
    global _config_cache
    if _config_cache is None:
        _config_cache = parse_game_ini(GAME_INI)
    return _config_cache

# ─────────────────────────────────────────────────────────
# Boot des threads
# ─────────────────────────────────────────────────────────
_started = False
def ensure_started():
    global _started
    if _started: return
    _started = True
    threading.Thread(target=tail_thread, name="log-tail", daemon=True).start()
    threading.Thread(target=a2s_poller, name="a2s", daemon=True).start()
ensure_started()

# ─────────────────────────────────────────────────────────
# API
# ─────────────────────────────────────────────────────────
@app.get("/api/health")
def health():
    return {
        "ok": True,
        "log_file": LOG_FILE,
        "game_ini": GAME_INI,
        "players_online": len(players_online),
        "last_line_ts": last_line_ts
    }

@app.get("/api/players")
def api_players():
    return {"online": list(players_online.values())}

@app.get("/api/config")
def api_config():
    return get_config()

@app.get("/api/live")
def api_live():
    # fusionne team depuis logs si trouvable
    live = dict(live_info)
    live["players"] = [
        {**p, "team": p.get("team") or name_to_team.get(p.get("name") or "", None)}
        for p in live_info.get("players", [])
    ]
    # durée round en secondes (depuis change de map)
    if live.get("round_start"):
        try:
            started = datetime.fromisoformat(live["round_start"].replace("Z",""))
            live["round_elapsed"] = int((datetime.utcnow()-started).total_seconds())
        except Exception:
            live["round_elapsed"] = None
    else:
        live["round_elapsed"] = None
    return live

@app.get("/api/summary")
def summary():
    return {
        "online": list(players_online.values()),
        "events": list(events)[-80:],
        "join_per_player": join_count_per_player.most_common(25),
        "join_per_day": dict(join_count_per_day),
        "config": get_config(),
        "live": api_live(),
        "series": list(playercount_series),
    }

@app.get("/events")
async def sse():
    q = asyncio.Queue(maxsize=100)
    with sub_lock: subscribers.add(q)

    async def gen():
        try:
            yield "data: " + json.dumps({"ts": now_iso(), "type": "hello"}) + "\n\n"
            while True:
                data = await q.get()
                yield f"data: {data}\n\n"
        finally:
            with sub_lock: subscribers.discard(q)

    headers = {"Cache-Control": "no-cache"}
    return StreamingResponse(gen(), media_type="text/event-stream", headers=headers)

# ─────────────────────────────────────────────────────────
# UI
# ─────────────────────────────────────────────────────────
INDEX_HTML = """
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>ISS Dashboard</title>
  <style>
    :root{
      --bg:#0b0f14; --panel:#111827; --muted:#94a3b8; --fg:#e5e7eb; --accent:#10b981; --accent2:#60a5fa;
      --border:#1f2937; --warn:#f59e0b; --danger:#ef4444;
    }
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif}
    header{padding:18px 24px;border-bottom:1px solid var(--border);background:linear-gradient(180deg,#0f172a, #0b1220)}
    h1{margin:0;font-size:20px;font-weight:700;letter-spacing:.3px}
    .grid{display:grid;gap:16px;padding:16px 24px;grid-template-columns:2fr 1fr}
    .card{background:var(--panel);border:1px solid var(--border);border-radius:14px;padding:16px}
    .title{margin:0 0 12px 0;font-size:16px;display:flex;align-items:center;gap:8px}
    .pill{background:#172554;color:#93c5fd;padding:2px 8px;border-radius:999px;font-size:12px}
    .kv{display:grid;grid-template-columns:140px 1fr;gap:6px 10px;font-size:13px}
    .kv div:nth-child(odd){color:var(--muted)}
    ul{list-style:none;margin:0;padding:0}
    li{padding:6px 0;border-bottom:1px dotted var(--border)}
    .muted{color:var(--muted)}
    .players{max-height:320px;overflow:auto}
    .events{max-height:220px;overflow:auto;font-family:ui-monospace,Consolas,monospace;background:#0a0f17;border-radius:10px;border:1px solid var(--border);padding:8px}
    .row{display:flex;align-items:center;justify-content:space-between;gap:10px}
    .badge{display:inline-flex;align-items:center;gap:6px;background:#052e2b;color:#9ef0d4;border:1px solid #0b3b36;border-radius:999px;padding:3px 10px;font-size:12px}
    .mutlist{display:flex;flex-wrap:wrap;gap:8px}
    .mut{background:#1e293b;padding:4px 8px;border-radius:999px;border:1px solid var(--border);font-size:12px}
    .twocol{display:grid;gap:16px;grid-template-columns:1fr 1fr}
    canvas{background:#0a0f17;border:1px solid var(--border);border-radius:10px;padding:8px}
    footer{padding:12px 24px;color:var(--muted);font-size:12px}
    @media (max-width:1100px){.grid{grid-template-columns:1fr}}
  </style>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
<header>
  <h1>Insurgency Sandstorm • Dashboard <span id="online" class="pill">0 en ligne</span></h1>
  <div class="muted" id="lf"></div>
</header>

<div class="grid">
  <div class="card">
    <h2 class="title">Partie en cours</h2>
    <div class="kv" id="livekv"></div>
    <div style="height:8px"></div>
    <div class="twocol">
      <div class="card">
        <h3 class="title">Joueurs (live)</h3>
        <div class="players">
          <ul id="liveplayers"></ul>
        </div>
      </div>
      <div class="card">
        <h3 class="title">Connexions (1h)</h3>
        <canvas id="chartSeries" height="160"></canvas>
      </div>
    </div>
  </div>

  <div class="card">
    <h2 class="title">Config serveur</h2>
    <div id="cfg"></div>
    <div style="height:12px"></div>
    <div class="card">
      <h3 class="title">Top joueurs (joins)</h3>
      <ul id="topplayers"></ul>
    </div>
  </div>

  <div class="card" style="grid-column:1 / -1">
    <h2 class="title">Évènements</h2>
    <div class="events" id="events"></div>
  </div>
</div>

<footer>
  <span class="muted">Données live via Steam A2S • Logs via SSE • UI auto-refresh</span>
</footer>

<script>
  // base relative (support du sous-chemin /iss)
  const BASE = window.location.pathname.endsWith('/') ? window.location.pathname : window.location.pathname + '/';
  const api  = (p) => BASE + p;

  const onlineEl  = document.getElementById('online');
  const lfEl      = document.getElementById('lf');
  const livekv    = document.getElementById('livekv');
  const liveplayers = document.getElementById('liveplayers');
  const eventsEl  = document.getElementById('events');
  const cfgEl     = document.getElementById('cfg');
  const topEl     = document.getElementById('topplayers');

  function h(ts){ try { return new Date(ts).toLocaleString(); } catch { return ts; } }
  function fmtDur(s){ if(!s&&s!==0) return '—'; s=+s; const m=Math.floor(s/60), sec=s%60; return m+'m '+sec+'s'; }

  function renderKV(obj){
    livekv.innerHTML='';
    const kv = [
      ['Hostname', obj.hostname||'—'],
      ['Map', obj.map||'—'],
      ['Joueurs', `${obj.player_count||0} / ${obj.max_players||0}`],
      ['Round', obj.round_elapsed!=null? fmtDur(obj.round_elapsed):'—'],
      ['MAJ', obj.updated_at? h(obj.updated_at):'—'],
    ];
    kv.forEach(([k,v])=>{
      const a=document.createElement('div'); a.textContent=k;
      const b=document.createElement('div'); b.textContent=v;
      livekv.appendChild(a); livekv.appendChild(b);
    });
  }

  function renderPlayers(list){
    liveplayers.innerHTML='';
    list.forEach(p=>{
      const li=document.createElement('li');
      li.className='row';
      const left=document.createElement('div');
      left.textContent = p.name || '—';
      const right=document.createElement('div');
      right.innerHTML = `<span class="badge">score ${p.score??'—'}</span> <span class="badge">temps ${fmtDur(p.time)}</span> <span class="badge">${p.team ? ('team '+p.team) : '—'}</span>`;
      li.appendChild(left); li.appendChild(right);
      liveplayers.appendChild(li);
    });
    onlineEl.textContent = `${list.length} en ligne`;
  }

  function renderConfig(cfg){
    const mods = cfg.mods && cfg.mods.length ? cfg.mods.join(', ') : '—';
    const wrap = document.createElement('div');
    wrap.innerHTML = `
      <div class="kv">
        <div>Mods</div><div>${mods}</div>
      </div>
      <div style="height:8px"></div>
      <div class="twocol">
        ${Object.entries(cfg.mutators||{}).map(([mode,muts])=>{
          const pills = (muts&&muts.length) ? muts.map(m=>`<span class="mut">${m}</span>`).join(' ') : '<span class="muted">—</span>';
          return `<div><div class="title" style="margin-bottom:8px">${mode}</div><div class="mutlist">${pills}</div></div>`;
        }).join('')}
      </div>
    `;
    cfgEl.innerHTML='';
    cfgEl.appendChild(wrap);
  }

  let chartSeries;
  function renderSeries(series){
    const labels = series.map(p=> (p.t/60).toFixed(1) ); // minutes
    const data   = series.map(p=> p.v );
    const ctx = document.getElementById('chartSeries').getContext('2d');
    if(chartSeries) chartSeries.destroy();
    chartSeries = new Chart(ctx,{
      type:'line',
      data:{ labels, datasets:[{label:'Joueurs', data, tension:.25, fill:true}]},
      options:{responsive:true, plugins:{legend:{display:false}}, scales:{x:{title:{display:true,text:'minutes'}}}}
    });
  }

  function appendEvent(ev){
    const row = document.createElement('div');
    const t = ev.type==='join' ? '🟢 join' : ev.type==='leave' ? '🔴 leave' : 'ℹ️';
    row.textContent = `[${h(ev.ts)}] ${t} ${ev.name} (id:${ev.id}) team:${ev.team}`;
    eventsEl.appendChild(row);
    eventsEl.scrollTop = eventsEl.scrollHeight;
  }

  async function loadAll(){
    // one-shot snapshot complet
    const s = await fetch(api('api/summary')).then(r=>r.json());
    renderConfig(s.config||{});
    renderKV(s.live||{});
    renderPlayers((s.live&&s.live.players)||[]);
    renderSeries(s.series||[]);
    // top players
    topEl.innerHTML='';
    (s.join_per_player||[]).forEach(([name,count])=>{
      const li=document.createElement('li'); li.className='row';
      li.innerHTML = `<div>${name}</div><div class="badge">${count} joins</div>`;
      topEl.appendChild(li);
    });
    // bandeau
    const health = await fetch(api('api/health')).then(r=>r.json());
    lfEl.textContent = `Log: ${health.log_file} • Game.ini: ${health.game_ini} • last update: ${health.last_line_ts||'—'}`;
  }

  // rafraîchissement live A2S (toutes les 5s)
  async function refreshLive(){
    try{
      const live = await fetch(api('api/live')).then(r=>r.json());
      renderKV(live||{});
      renderPlayers((live&&live.players)||[]);
    }catch(e){}
  }
  setInterval(refreshLive, 5000);

  // SSE join/leave
  const es = new EventSource(api('events'));
  es.onmessage = (e)=>{
    if(!e.data) return;
    const ev = JSON.parse(e.data);
    if(ev.type==='hello') return;
    appendEvent(ev);
  };

  loadAll();
</script>
</body>
</html>
"""

@app.get("/", response_class=HTMLResponse)
def index():
    return HTMLResponse(INDEX_HTML)


