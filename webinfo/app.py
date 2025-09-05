# app.py
# Dashboard temps réel (FastAPI + SSE) pour Insurgency: Sandstorm
# - lit le log en continu (tail -F)
# - détecte "joined team" / "left team"
# - expose / (UI), /api/* (JSON), /events (SSE)
# Dépendances: fastapi, uvicorn

import os
import re
import time
import threading
import asyncio
import json
from datetime import datetime, timedelta
from collections import deque, Counter, defaultdict
from pathlib import Path
from typing import Dict, Any, Optional

from fastapi import FastAPI
from fastapi.responses import HTMLResponse, StreamingResponse, JSONResponse

# ----------------- Configuration -----------------
LOG_FILE = os.environ.get("LOG_FILE", "/opt/sandstorm/Insurgency/Saved/Logs/Insurgency.log")

JOIN_REGEX = re.compile(
    os.environ.get(
        "JOIN_REGEX",
        r"LogGameMode:\s+Display:\s+Player\s+(?P<id>\d+)\s+'(?P<name>[^']+)'\s+joined\s+team\s+(?P<team>\d+)"
    )
)
LEAVE_REGEX = re.compile(
    os.environ.get(
        "LEAVE_REGEX",
        r"LogGameMode:\s+Display:\s+Player\s+(?P<id>\d+)\s+'(?P<name>[^']+)'\s+left\s+team\s+(?P<team>\d+)"
    )
)
# Fallbacks souples
JOIN_FALLBACK = re.compile(r"Player\s+(?P<id>\d+)\s+'(?P<name>[^']+)'\s+joined\s+team\s+(?P<team>\d+)")
LEAVE_FALLBACK = re.compile(r"Player\s+(?P<id>\d+)\s+'(?P<name>[^']+)'\s+left\s+team\s+(?P<team>\d+)")

EVENT_HISTORY_MAX = int(os.environ.get("EVENT_HISTORY_MAX", "500"))
STATS_RETENTION_DAYS = int(os.environ.get("STATS_RETENTION_DAYS", "14"))

# Optionnel: si tu veux que l'app vive sous /iss sans rewrite nginx
ROOT_PATH = os.environ.get("ROOT_PATH", "").strip()  # ex: "/iss" (sinon laisse vide)

# ----------------- État -----------------
players_online: Dict[str, Dict[str, Any]] = {}  # id -> {id,name,team,since}
events = deque(maxlen=EVENT_HISTORY_MAX)        # [{ts,type,id,name,team,line}]
join_count_per_player = Counter()               # name -> count
join_count_per_day = defaultdict(int)           # "YYYY-MM-DD" -> count
last_line_ts: Optional[str] = None

# Diffuseurs SSE
subscribers = set()
sub_lock = threading.Lock()

# FastAPI
app = FastAPI(root_path=ROOT_PATH or None)


# ----------------- Utilitaires -----------------
def now_iso() -> str:
    return datetime.utcnow().isoformat() + "Z"

def parse_join(line: str) -> Optional[Dict[str, str]]:
    m = JOIN_REGEX.search(line) or JOIN_FALLBACK.search(line)
    if not m:
        return None
    return {"type": "join", "id": m.group("id"), "name": m.group("name"), "team": m.group("team")}

def parse_leave(line: str) -> Optional[Dict[str, str]]:
    m = LEAVE_REGEX.search(line) or LEAVE_FALLBACK.search(line)
    if not m:
        return None
    return {"type": "leave", "id": m.group("id"), "name": m.group("name"), "team": m.group("team")}

def publish(ev: Dict[str, Any]) -> None:
    data = json.dumps(ev)
    dead = []
    with sub_lock:
        for q in list(subscribers):
            try:
                q.put_nowait(data)
            except asyncio.QueueFull:
                dead.append(q)
        for q in dead:
            subscribers.discard(q)

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
        try:
            d = datetime.strptime(day, "%Y-%m-%d").date()
        except ValueError:
            continue
        if d < cutoff:
            del join_count_per_day[day]


# ----------------- Tail -F robuste -----------------
def follow(path: Path):
    f = None
    sig = None
    while True:
        try:
            st = path.stat()
            if f is None or sig != (st.st_ino, st.st_dev) or f.tell() > st.st_size:
                if f:
                    try:
                        f.close()
                    except Exception:
                        pass
                f = path.open("r", errors="ignore")
                f.seek(0, 2)  # fin = on ne lit que le nouveau
                sig = (st.st_ino, st.st_dev)
                print(f"[webinfo] open log {path} inode={sig}", flush=True)

            line = f.readline()
            if line:
                yield line.rstrip("\r\n")
            else:
                time.sleep(0.5)
        except FileNotFoundError:
            time.sleep(1.0)
        except Exception as e:
            print(f"[webinfo] tail error: {e}", flush=True)
            time.sleep(1.0)

def tail_thread():
    path = Path(LOG_FILE)
    for line in follow(path):
        ev = parse_join(line) or parse_leave(line)
        if not ev:
            continue

        pid, name, team = ev["id"], ev["name"], ev["team"]
        if ev["type"] == "join":
            players_online[pid] = {"id": pid, "name": name, "team": team, "since": now_iso()}
            join_count_per_player[name] += 1
            join_count_per_day[datetime.utcnow().strftime("%Y-%m-%d")] += 1
            cleanup_stats()
        elif ev["type"] == "leave":
            players_online.pop(pid, None)

        record_event(ev["type"], pid, name, team, line)


# Démarrer le tail une seule fois (évite doublons avec --reload)
_started = False
def ensure_started():
    global _started
    if _started:
        return
    _started = True
    threading.Thread(target=tail_thread, name="log-tail", daemon=True).start()
ensure_started()


# ----------------- API -----------------
@app.get("/api/health")
def health():
    return {
        "ok": True,
        "log_file": LOG_FILE,
        "players_online": len(players_online),
        "last_line_ts": last_line_ts
    }

@app.get("/api/players")
def api_players():
    return {"online": list(players_online.values())}

@app.get("/api/summary")
def summary():
    return {
        "online": list(players_online.values()),
        "events": list(events)[-50:],  # derniers 50 pour l’UI
        "join_per_player": join_count_per_player.most_common(20),
        "join_per_day": dict(join_count_per_day),
    }

@app.get("/events")
async def sse():
    # SSE simple via Queue asyncio
    q = asyncio.Queue(maxsize=100)
    with sub_lock:
        subscribers.add(q)

    async def gen():
        try:
            # hello initial
            yield "data: " + json.dumps({"ts": now_iso(), "type": "hello"}) + "\n\n"
            while True:
                data = await q.get()
                # event-stream
                yield f"data: {data}\n\n"
        finally:
            with sub_lock:
                subscribers.discard(q)

    headers = {"Cache-Control": "no-cache"}
    return StreamingResponse(gen(), media_type="text/event-stream", headers=headers)


# ----------------- UI -----------------
INDEX_HTML = """
<!doctype html>
<html lang="fr">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>ISS WebInfo</title>
  <style>
    body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial,sans-serif;margin:0;padding:0;background:#0d1117;color:#c9d1d9}
    header{padding:16px 24px;background:#161b22;border-bottom:1px solid #30363d}
    .wrap{padding:16px 24px;display:grid;gap:16px;grid-template-columns:1fr 1fr}
    .card{background:#161b22;border:1px solid #30363d;border-radius:10px;padding:16px}
    h2{margin:0 0 12px 0;font-size:18px}
    ul{list-style:none;margin:0;padding:0}
    li{padding:6px 0;border-bottom:1px dotted #30363d}
    .pill{display:inline-block;padding:2px 8px;border-radius:999px;background:#238636;color:white;font-size:12px;margin-left:6px}
    .events{max-height:320px;overflow:auto;font-family:ui-monospace,Consolas,monospace;font-size:13px}
    .muted{opacity:.75}
    canvas{background:#0d1117;border:1px solid #30363d;border-radius:8px;padding:8px}
    @media (max-width:1000px){.wrap{grid-template-columns:1fr}}
  </style>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
<header>
  <h1>Insurgency Sandstorm • WebInfo <span id="online" class="pill">0 en ligne</span></h1>
  <div class="muted" id="lf"></div>
</header>
<div class="wrap">
  <div class="card">
    <h2>Joueurs en ligne</h2>
    <ul id="players"></ul>
  </div>
  <div class="card">
    <h2>Connexions/jour</h2>
    <canvas id="chartDay" height="200"></canvas>
  </div>
  <div class="card" style="grid-column:1 / -1">
    <h2>Évènements (temps réel)</h2>
    <div class="events" id="events"></div>
  </div>
</div>

<script>
  // --- Support du sous-chemin (/iss) : base toujours avec un slash ---
  const BASE = window.location.pathname.endsWith('/') ? window.location.pathname : window.location.pathname + '/';
  const api  = (p) => BASE + p;
  // -------------------------------------------------------------------

  const playersEl = document.getElementById('players');
  const onlineEl  = document.getElementById('online');
  const eventsEl  = document.getElementById('events');
  const lfEl      = document.getElementById('lf');

  function h(ts){ try { return new Date(ts).toLocaleString(); } catch { return ts; } }

  function renderPlayers(list){
    playersEl.innerHTML = '';
    list.forEach(p=>{
      const li = document.createElement('li');
      li.textContent = `${p.name} (id:${p.id}) depuis ${h(p.since)} team:${p.team}`;
      playersEl.appendChild(li);
    });
    onlineEl.textContent = `${list.length} en ligne`;
  }

  function appendEvent(ev){
    const row = document.createElement('div');
    const t = ev.type==='join' ? '🟢 join' : ev.type==='leave' ? '🔴 leave' : 'ℹ️';
    row.textContent = `[${h(ev.ts)}] ${t} ${ev.name} (id:${ev.id}) team:${ev.team}`;
    eventsEl.appendChild(row);
    eventsEl.scrollTop = eventsEl.scrollHeight;
  }

  // Chart Connexions/jour
  let chart;
  function renderChart(joinPerDay){
    const labels = Object.keys(joinPerDay).sort();
    const data = labels.map(k => joinPerDay[k]);
    const ctx = document.getElementById('chartDay').getContext('2d');
    if(chart) chart.destroy();
    chart = new Chart(ctx,{
      type:'bar',
      data:{ labels, datasets:[{label:'Connexions', data}]},
      options:{responsive:true, plugins:{legend:{display:false}}}
    });
  }

  async function bootstrap(){
    const s = await fetch(api('api/summary')).then(r=>r.json());
    renderPlayers(s.online);
    s.events.forEach(appendEvent);
    renderChart(s.join_per_day);

    const health = await fetch(api('api/health')).then(r=>r.json());
    lfEl.textContent = `Log: ${health.log_file} | last update: ${health.last_line_ts||'—'}`;

    const es = new EventSource(api('events'));
    es.onmessage = (e)=>{
      if(!e.data) return;
      const ev = JSON.parse(e.data);
      if(ev.type==='hello') return;
      appendEvent(ev);
      // Sync simple des players
      if(ev.type==='join'){
        s.online = s.online.filter(p=>p.id!==ev.id);
        s.online.push({id:ev.id,name:ev.name,team:ev.team,since:ev.ts});
      } else if(ev.type==='leave'){
        s.online = s.online.filter(p=>p.id!==ev.id);
      }
      renderPlayers(s.online);
      // incrément stats jour
      const day = ev.ts.slice(0,10);
      s.join_per_day[day] = (s.join_per_day[day]||0) + (ev.type==='join'?1:0);
      renderChart(s.join_per_day);
    };
  }
  bootstrap();
</script>
</body>
</html>
"""

@app.get("/", response_class=HTMLResponse)
def index():
    return HTMLResponse(INDEX_HTML)

# -------------- run via: uvicorn app:app --host 0.0.0.0 --port 8080 --------------

