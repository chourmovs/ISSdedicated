# app.py — ISS WebInfo v3 (FastAPI + SSE + A2S + Game.ini + MapCycle + Admins + Rules)
import os, re, time, threading, asyncio, json
from datetime import datetime
from collections import deque, Counter, defaultdict
from pathlib import Path
from typing import Dict, Any, Optional, List

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, StreamingResponse

# ───────── Config
LOG_FILE  = os.environ.get("LOG_FILE", "/opt/sandstorm/Insurgency/Saved/Logs/Insurgency.log")
GAME_INI  = os.environ.get("GAME_INI", "/opt/sandstorm/Insurgency/Saved/Config/LinuxServer/Game.ini")
MAPCYCLE  = os.environ.get("MAPCYCLE", "/opt/sandstorm/Insurgency/Saved/Config/LinuxServer/MapCycle.txt")
ADMINS_TXT= os.environ.get("ADMINS_TXT","/opt/sandstorm/Insurgency/Config/Server/Admins.txt")
A2S_HOST  = os.environ.get("A2S_HOST", "sandstorm")
A2S_PORT  = int(os.environ.get("A2S_PORT", "27131"))
A2S_POLL_INTERVAL = float(os.environ.get("A2S_POLL_INTERVAL", "5"))
ROOT_PATH = os.environ.get("ROOT_PATH", "").strip()
EVENT_HISTORY_MAX = int(os.environ.get("EVENT_HISTORY_MAX", "600"))

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

# ───────── État mémoire
players_online: Dict[str, Dict[str, Any]] = {}
name_to_team: Dict[str, str] = {}
events = deque(maxlen=EVENT_HISTORY_MAX)
join_count_per_player = Counter()
join_count_per_day = defaultdict(int)
last_line_ts: Optional[str] = None

live_info: Dict[str, Any] = {
    "ok": False, "host": A2S_HOST, "port": A2S_PORT,
    "hostname": None, "map": None, "player_count": 0, "max_players": 0,
    "players": [], "updated_at": None, "round_start": None,
}
playercount_series = deque(maxlen=720)
series_started_at = datetime.utcnow()

a2s_rules_cache: Dict[str, Any] = {"ts": None, "data": {}}

subscribers = set()
sub_lock = threading.Lock()

app = FastAPI(root_path=ROOT_PATH or None)

# ───────── Helpers
def now_iso(): return datetime.utcnow().isoformat()+"Z"

def parse_join(line):
    m = JOIN_REGEX.search(line) or JOIN_FALLBACK.search(line)
    return None if not m else {"type":"join","id":m.group("id"),"name":m.group("name"),"team":m.group("team")}

def parse_leave(line):
    m = LEAVE_REGEX.search(line) or LEAVE_FALLBACK.search(line)
    return None if not m else {"type":"leave","id":m.group("id"),"name":m.group("name"),"team":m.group("team")}

def publish(ev: Dict[str, Any]):
    data = json.dumps(ev)
    dead = []
    with sub_lock:
        for q in list(subscribers):
            try: q.put_nowait(data)
            except asyncio.QueueFull: dead.append(q)
        for q in dead: subscribers.discard(q)

def record_event(ev_type, pid, name, team, line):
    global last_line_ts
    ts = now_iso(); last_line_ts = ts
    ev = {"ts": ts, "type": ev_type, "id": pid, "name": name, "team": team, "line": line[:400]}
    events.append(ev); publish(ev)

# ───────── Tail -F
def follow(path: Path):
    f=None; sig=None
    while True:
        try:
            st = path.stat()
            if f is None or sig!=(st.st_ino,st.st_dev) or f.tell()>st.st_size:
                if f:
                    try: f.close()
                    except: pass
                f = path.open("r", errors="ignore"); f.seek(0,2)
                sig=(st.st_ino,st.st_dev)
                print(f"[webinfo] open log {path} inode={sig}", flush=True)
            line=f.readline()
            if line: yield line.rstrip("\r\n")
            else: time.sleep(0.5)
        except FileNotFoundError:
            time.sleep(1.0)
        except Exception as e:
            print("[webinfo] tail error:", e, flush=True); time.sleep(1.0)

def tail_thread():
    for line in follow(Path(LOG_FILE)):
        ev = parse_join(line) or parse_leave(line)
        if not ev: continue
        pid,name,team = ev["id"],ev["name"],ev["team"]
        name_to_team[name]=team
        if ev["type"]=="join":
            players_online[pid]={"id":pid,"name":name,"team":team,"since":now_iso()}
            join_count_per_player[name]+=1
            join_count_per_day[datetime.utcnow().strftime("%Y-%m-%d")]+=1
        else:
            players_online.pop(pid, None)
        record_event(ev["type"], pid, name, team, line)

# ───────── A2S + merge
def _merge_players(a2s_players, from_logs: Dict[str,Dict[str,Any]]):
    by_name={}
    for p in a2s_players or []:
        nm=(p.get("name") or "").strip()
        if not nm: continue
        by_name[nm]={"name":nm,"score":p.get("score"),"time":p.get("time"),"team":p.get("team")}
    for _pid,pl in (from_logs or {}).items():
        nm=(pl.get("name") or "").strip()
        if not nm: continue
        if nm not in by_name: by_name[nm]={"name":nm,"score":None,"time":None,"team":pl.get("team")}
        elif by_name[nm].get("team") is None and pl.get("team") is not None:
            by_name[nm]["team"]=pl.get("team")
    return list(by_name.values())

def a2s_poller():
    import a2s
    last_map=None; i=0
    while True:
        try:
            addr=(A2S_HOST, A2S_PORT)
            info=a2s.info(addr, timeout=2.0)

            players_a2s=[]
            try:
                for p in a2s.players(addr, timeout=2.0):
                    players_a2s.append({
                        "name": p.name,
                        "score": getattr(p,"score",None),
                        "time": int(getattr(p,"duration",0)),
                        "team": name_to_team.get(p.name),
                    })
            except Exception as e:
                print("[webinfo] A2S players failed:", e, flush=True)

            count_a2s=int(getattr(info,"player_count",0) or 0)
            count_logs=len(players_online)
            eff_count=max(count_a2s, count_logs)
            if eff_count!=count_a2s:
                print(f"[webinfo] A2S player_count={count_a2s} ; logs_count={count_logs} → using {eff_count}", flush=True)

            live_info.update({
                "ok": True,
                "hostname": getattr(info,"server_name",None),
                "map": getattr(info,"map_name",None),
                "player_count": eff_count,
                "max_players": getattr(info,"max_players",0),
                "players": _merge_players(players_a2s, players_online),
                "updated_at": now_iso(),
            })

            # round (map change)
            cur_map=live_info.get("map")
            if cur_map!=last_map:
                last_map=cur_map; live_info["round_start"]=now_iso()

            # timeseries
            playercount_series.append({"t": (datetime.utcnow()-series_started_at).total_seconds(), "v": eff_count})

            # A2S rules 1 fois sur 3
            i=(i+1)%3
            if i==0:
                try:
                    rules=a2s.rules(addr, timeout=2.0)  # dict
                    # normalise en str pour JSON
                    a2s_rules_cache["data"]={str(k): (str(v) if not isinstance(v,(int,float,bool)) else v) for k,v in (rules or {}).items()}
                    a2s_rules_cache["ts"]=now_iso()
                except Exception as e:
                    # beaucoup de jeux ne supportent pas; on ignore
                    pass

        except Exception as e:
            live_info.update({"ok":False,"players":[],"updated_at":now_iso()})
            print("[webinfo] A2S info failed:", e, flush=True)

        time.sleep(A2S_POLL_INTERVAL)

# ───────── Parse fichiers config (Game.ini / MapCycle / Admins)
def _read_lines(path: str) -> List[str]:
    p=Path(path); 
    if not p.exists(): return []
    try:
        return [l.rstrip("\r\n") for l in p.read_text(errors="ignore").splitlines()]
    except Exception:
        return []

def parse_game_ini(path: str):
    data={"mods":[], "mutators":{"Push":[], "Firefight":[], "Domination":[], "Skirmish":[], "Checkpoint":[], "Outpost":[], "Survival":[]}, "stats_enabled":None}
    p=Path(path)
    if not p.exists(): return data
    section=None
    modes={
        "/Script/Insurgency.INSPushGameMode":"Push",
        "/Script/Insurgency.INSFirefightGameMode":"Firefight",
        "/Script/Insurgency.INSDominationGameMode":"Domination",
        "/Script/Insurgency.INSSkirmishGameMode":"Skirmish",
        "/Script/Insurgency.INSCheckpointGameMode":"Checkpoint",
        "/Script/Insurgency.INSOutpostGameMode":"Outpost",
        "/Script/Insurgency.INSSurvivalGameMode":"Survival",
        "/Script/Insurgency.INSGameMode":"_root"
    }
    try:
        for raw in p.read_text(errors="ignore").splitlines():
            line=raw.strip()
            if not line or line.startswith(";"): continue
            if line.startswith("[") and line.endswith("]"):
                section=line[1:-1]; continue
            if "Mods=" in line:
                v=line.split("=",1)[1].strip()
                if v: data["mods"].append(v)
            if "Mutators=" in line and section in modes and modes[section]!="__ignore__":
                muts=[m.strip() for m in line.split("=",1)[1].split(",") if m.strip()]
                if section in modes and modes[section]!="__ignore__":
                    if modes[section] in data["mutators"]:
                        data["mutators"][modes[section]]=muts
            if section=="/Script/Insurgency.INSGameMode" and line.lower().startswith("bdisablestats="):
                v=line.split("=",1)[1].strip().lower()
                data["stats_enabled"] = (v!="true")
    except Exception as e:
        print("[webinfo] parse Game.ini failed:", e, flush=True)
    return data

def parse_mapcycle(path: str):
    lines=_read_lines(path)
    out=[]
    for ln in lines:
        s=ln.strip()
        if not s or s.startswith("#") or not s.startswith("Scenario_"): continue
        out.append(s)
    return out

def parse_admins(path: str):
    lines=_read_lines(path)
    ids=[ln.strip() for ln in lines if ln.strip() and ln.strip()[0].isdigit()]
    return ids

def guess_ranked(stats_enabled: Optional[bool], rules: Dict[str,Any]):
    # heuristique : stats ON + keywords contenant "gs", "gamestats", "ranked", "gslT"
    kw=(rules.get("keywords") or rules.get("Keywords") or rules.get("tags") or rules.get("Tag") or "")
    kws=str(kw).lower()
    if stats_enabled is False: return False
    if stats_enabled is True and any(x in kws for x in ("gs","gamestats","ranked","gsl", "xp")):
        return True
    return None  # inconnu

_config_cache=None
def get_config_bundle():
    global _config_cache
    gi=parse_game_ini(GAME_INI)
    mc=parse_mapcycle(MAPCYCLE)
    admins=parse_admins(ADMINS_TXT)
    rules=a2s_rules_cache.get("data",{}) or {}
    ranked = guess_ranked(gi.get("stats_enabled"), rules)
    return {
        "mods": gi["mods"], "mutators": gi["mutators"],
        "stats_enabled": gi.get("stats_enabled"),
        "xp_guess": ranked,
        "mapcycle": mc,
        "admins": admins,
        "rules": rules,
        "rules_ts": a2s_rules_cache.get("ts"),
    }

# ───────── Boot
_started=False
def ensure_started():
    global _started
    if _started: return
    _started=True
    threading.Thread(target=tail_thread, daemon=True).start()
    threading.Thread(target=a2s_poller, daemon=True).start()
ensure_started()

# ───────── API
@app.get("/api/health")
def health():
    return {"ok":True,"log_file":LOG_FILE,"game_ini":GAME_INI,"mapcycle":MAPCYCLE,"admins_file":ADMINS_TXT,
            "players_online":len(players_online),"last_line_ts":last_line_ts}

@app.get("/api/live")
def api_live():
    live=dict(live_info)
    live["players"]=[{**p,"team":p.get("team") or name_to_team.get(p.get("name") or "", None)} for p in live_info.get("players",[])]
    if live.get("round_start"):
        try:
            started=datetime.fromisoformat(live["round_start"].replace("Z",""))
            live["round_elapsed"]=int((datetime.utcnow()-started).total_seconds())
        except: live["round_elapsed"]=None
    else:
        live["round_elapsed"]=None
    return live

@app.get("/api/config")
def api_config():
    return get_config_bundle()

@app.get("/api/summary")
def summary():
    return {"online":list(players_online.values()),
            "events":list(events)[-80:],
            "join_per_player": join_count_per_player.most_common(25),
            "join_per_day": dict(join_count_per_day),
            "config": get_config_bundle(),
            "live": api_live(),
            "series": list(playercount_series)}

@app.get("/events")
async def sse():
    q=asyncio.Queue(maxsize=100)
    with sub_lock: subscribers.add(q)
    async def gen():
        try:
            yield "data: " + json.dumps({"ts": now_iso(), "type":"hello"}) + "\n\n"
            while True:
                data=await q.get()
                yield f"data: {data}\n\n"
        finally:
            with sub_lock: subscribers.discard(q)
    return StreamingResponse(gen(), media_type="text/event-stream", headers={"Cache-Control":"no-cache"})

# ───────── UI
INDEX_HTML = """
<!doctype html><html lang="fr"><head>
<meta charset="utf-8"/><meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Insurgency Sandstorm • Dashboard</title>
<style>
:root{--bg:#0b0f14;--panel:#111827;--muted:#94a3b8;--fg:#e5e7eb;--accent:#10b981;--accent2:#60a5fa;--border:#1f2937;--warn:#f59e0b;--danger:#ef4444}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.5 system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif}
header{padding:18px 24px;border-bottom:1px solid var(--border);background:linear-gradient(180deg,#0f172a,#0b1220)}
h1{margin:0;font-size:20px;font-weight:700}
.grid{display:grid;gap:16px;padding:16px 24px;grid-template-columns:2fr 1fr}
.card{background:var(--panel);border:1px solid var(--border);border-radius:14px;padding:16px}
.title{margin:0 0 12px 0;font-size:16px;display:flex;align-items:center;gap:8px}
.pill{background:#172554;color:#93c5fd;padding:2px 8px;border-radius:999px;font-size:12px}
.kv{display:grid;grid-template-columns:140px 1fr;gap:6px 10px;font-size:13px}
.kv div:nth-child(odd){color:var(--muted)}
ul{list-style:none;margin:0;padding:0}
li{padding:6px 0;border-bottom:1px dotted var(--border)}
.players{max-height:320px;overflow:auto}
.events{max-height:220px;overflow:auto;font-family:ui-monospace,Consolas,monospace;background:#0a0f17;border-radius:10px;border:1px solid var(--border);padding:8px}
.row{display:flex;align-items:center;justify-content:space-between;gap:10px}
.badge{display:inline-flex;gap:6px;background:#052e2b;color:#9ef0d4;border:1px solid #0b3b36;border-radius:999px;padding:3px 10px;font-size:12px}
.mut{background:#1e293b;padding:4px 8px;border-radius:999px;border:1px solid var(--border);font-size:12px;margin:2px}
.twocol{display:grid;gap:16px;grid-template-columns:1fr 1fr}
.small{font-size:12px;color:var(--muted)}
pre{white-space:pre-wrap;word-break:break-word}
canvas{background:#0a0f17;border:1px solid var(--border);border-radius:10px;padding:8px}
@media (max-width:1100px){.grid{grid-template-columns:1fr}}
</style>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head><body>
<header>
  <h1>Insurgency Sandstorm • Dashboard <span id="online" class="pill">0 en ligne</span></h1>
  <div class="small" id="lf"></div>
</header>

<div class="grid">
  <div class="card">
    <h2 class="title">Partie en cours</h2>
    <div class="kv" id="livekv"></div>
    <div style="height:8px"></div>
    <div class="twocol">
      <div class="card">
        <h3 class="title">Joueurs (live)</h3>
        <ul id="liveplayers" class="players"></ul>
      </div>
      <div class="card">
        <h3 class="title">Connexions (1h)</h3>
        <canvas id="chartSeries" height="160"></canvas>
      </div>
    </div>
  </div>

  <div class="card">
    <h2 class="title">Config serveur</h2>
    <div class="kv" id="cfg-main"></div>
    <div style="height:8px"></div>
    <div class="twocol">
      <div class="card">
        <h3 class="title">Mutators par mode</h3>
        <div id="mutators"></div>
      </div>
      <div class="card">
        <h3 class="title">A2S détails</h3>
        <div id="rules" class="small"></div>
      </div>
    </div>
    <div class="twocol">
      <div class="card">
        <h3 class="title">MapCycle</h3>
        <ul id="mc" class="small"></ul>
      </div>
      <div class="card">
        <h3 class="title">Admins</h3>
        <ul id="admins" class="small"></ul>
      </div>
    </div>
    <div class="card">
      <h3 class="title">Top joueurs (joins)</h3>
      <ul id="topplayers"></ul>
    </div>
  </div>

  <div class="card" style="grid-column:1 / -1">
    <h2 class="title">Évènements</h2>
    <div id="events" class="events"></div>
  </div>
</div>

<script>
const BASE = window.location.pathname.endsWith('/') ? window.location.pathname : window.location.pathname + '/';
const api  = (p) => BASE + p;

const onlineEl=document.getElementById('online');
const lfEl=document.getElementById('lf');
const livekv=document.getElementById('livekv');
const liveplayers=document.getElementById('liveplayers');
const eventsEl=document.getElementById('events');
const cfgMain=document.getElementById('cfg-main');
const mutDiv=document.getElementById('mutators');
const rulesDiv=document.getElementById('rules');
const mcUl=document.getElementById('mc');
const adminsUl=document.getElementById('admins');
const topUl=document.getElementById('topplayers');

function h(ts){ try{ return new Date(ts).toLocaleString(); }catch{return ts;}}
function fmtDur(s){ if(s==null) return '—'; s=+s; const m=Math.floor(s/60), sec=s%60; return m+'m '+sec+'s'; }

function renderLiveKV(obj){
  livekv.innerHTML='';
  const kv=[['Hostname',obj.hostname||'—'],['Map',obj.map||'—'],['Joueurs',`${obj.player_count||0} / ${obj.max_players||0}`],
            ['Round',obj.round_elapsed!=null?fmtDur(obj.round_elapsed):'—'],['MAJ',obj.updated_at?h(obj.updated_at):'—']];
  kv.forEach(([k,v])=>{const a=document.createElement('div');a.textContent=k;const b=document.createElement('div');b.textContent=v;livekv.appendChild(a);livekv.appendChild(b);});
}
function renderPlayers(list){
  liveplayers.innerHTML='';
  list.forEach(p=>{
    const li=document.createElement('li'); li.className='row';
    const left=document.createElement('div'); left.textContent=p.name||'—';
    const right=document.createElement('div');
    right.innerHTML=`<span class="badge">score ${p.score??'—'}</span> <span class="badge">temps ${fmtDur(p.time)}</span> <span class="badge">${p.team?('team '+p.team):'—'}</span>`;
    li.appendChild(left); li.appendChild(right); liveplayers.appendChild(li);
  });
  onlineEl.textContent=`${list.length} en ligne`;
}

let chartSeries;
function renderSeries(series){
  const labels=series.map(p=>(p.t/60).toFixed(1)), data=series.map(p=>p.v);
  const ctx=document.getElementById('chartSeries').getContext('2d'); if(chartSeries) chartSeries.destroy();
  chartSeries=new Chart(ctx,{type:'line',data:{labels,datasets:[{label:'Joueurs',data,tension:.25,fill:true}]},
    options:{responsive:true,plugins:{legend:{display:false}},scales:{x:{title:{display:true,text:'minutes'}}}});
}

function renderCfgMain(cfg){
  cfgMain.innerHTML='';
  const mods=(cfg.mods&&cfg.mods.length)?cfg.mods.join(', '):'—';
  const stats=(cfg.stats_enabled===true)?'activées':(cfg.stats_enabled===false?'désactivées':'—');
  const xp = cfg.xp_guess===true?'oui (heuristique)':(cfg.xp_guess===false?'non':'inconnu');
  const kv=[['Mods', mods], ['Stats', stats], ['XP/Ranked (guess)', xp]];
  kv.forEach(([k,v])=>{const a=document.createElement('div');a.textContent=k;const b=document.createElement('div');b.textContent=v;cfgMain.appendChild(a);cfgMain.appendChild(b);});
}
function renderMutators(cfg){
  mutDiv.innerHTML='';
  const muts=cfg.mutators||{};
  const wrap=document.createElement('div');
  Object.keys(muts).forEach(mode=>{
    const h=document.createElement('div'); h.className='small'; h.style.margin='8px 0 4px'; h.textContent=mode;
    wrap.appendChild(h);
    const row=document.createElement('div');
    (muts[mode]||[]).forEach(m=>{const s=document.createElement('span'); s.className='mut'; s.textContent=m; row.appendChild(s);});
    if(!(muts[mode]||[]).length){ row.textContent='—'; row.className='small'; }
    wrap.appendChild(row);
  });
  mutDiv.appendChild(wrap);
}
function renderRules(r){
  const lines=[];
  if(!r||Object.keys(r).length===0){ rulesDiv.textContent='(pas de données rules A2S)'; return; }
  const keys=['game','version','keywords','secure','vac','password','dedicated'];
  keys.forEach(k=>{ if(r[k]!=null) lines.push(`${k}: ${r[k]}`); });
  // dump extra keys if any
  Object.keys(r).sort().forEach(k=>{ if(!keys.includes(k)) lines.push(`${k}: ${r[k]}`);});
  rulesDiv.innerHTML='<pre>'+lines.join('\\n')+'</pre>';
}
function renderList(ul, items){
  ul.innerHTML=''; (items||[]).forEach(v=>{const li=document.createElement('li'); li.textContent=v; ul.appendChild(li);});
  if(!(items||[]).length){ const li=document.createElement('li'); li.textContent='—'; ul.appendChild(li); }
}

function appendEvent(ev){
  const row=document.createElement('div'); const t=ev.type==='join'?'🟢 join':ev.type==='leave'?'🔴 leave':'ℹ️';
  row.textContent=`[${h(ev.ts)}] ${t} ${ev.name} (id:${ev.id}) team:${ev.team}`; eventsEl.appendChild(row);
  eventsEl.scrollTop=eventsEl.scrollHeight;
}

async function boot(){
  const s=await fetch(api('api/summary')).then(r=>r.json());
  renderLiveKV(s.live||{}); renderPlayers((s.live&&s.live.players)||[]); renderSeries(s.series||[]);
  const cfg=s.config||{};
  renderCfgMain(cfg); renderMutators(cfg); renderRules(cfg.rules||{}); renderList(mcUl, cfg.mapcycle||[]); renderList(adminsUl, cfg.admins||[]);
  // top joins
  topUl.innerHTML=''; (s.join_per_player||[]).forEach(([n,c])=>{const li=document.createElement('li'); li.className='row'; li.innerHTML=`<div>${n}</div><div class="badge">${c} joins</div>`; topUl.appendChild(li);});
  // bandeau fichier
  const health=await fetch(api('api/health')).then(r=>r.json());
  lfEl.textContent=`Log: ${health.log_file} • Game.ini: ${health.game_ini} • MapCycle: ${health.mapcycle} • last update: ${health.last_line_ts||'—'}`;
}
async function refreshLive(){
  try{ const live=await fetch(api('api/live')).then(r=>r.json());
    renderLiveKV(live||{}); renderPlayers((live&&live.players)||[]);
  }catch(e){}
}
setInterval(refreshLive, 5000);

// SSE
const es=new EventSource(api('events'));
es.onmessage=(e)=>{ if(!e.data) return; const ev=JSON.parse(e.data); if(ev.type==='hello') return; appendEvent(ev); };

boot();
</script>
</body></html>
"""

@app.get("/", response_class=HTMLResponse)
def index(): return HTMLResponse(INDEX_HTML)
