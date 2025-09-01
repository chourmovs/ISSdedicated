#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Watcher Insurgency: Sandstorm → ntfy push

- Tail -F robuste (rotation, truncation)
- Détection connexion joueur via REGEX (configurable)
- Anti-doublon (TTL)
- ntfy via HTTP(S) POST (pas de dépendances externes)

ENV attendues (valeurs par défaut entre []):
  LOG_FILE                [/opt/sandstorm/Insurgency/Saved/Logs/Insurgency.log]
  NTFY_ENABLED            [1]           # 1=on, 0=off
  NTFY_SERVER             [https://ntfy.sh]
  NTFY_TOPIC              (requis si NTFY_ENABLED=1)
  NTFY_TITLE_PREFIX       [Sandstorm • Connexion]
  NTFY_PRIORITY           [high]        # min, low, default, high, max
  NTFY_TAGS               [video_game]  # tags séparés par virgules
  NTFY_CLICK              []            # URL cliquable dans la notif (optionnel)
  NTFY_TOKEN              []            # Authorization: Bearer <token> (si ntfy protégé)
  NTFY_USER               []            # ou Basic auth
  NTFY_PASS               []
  DEDUP_TTL               [600]         # secondes anti-spam par (id,name)
  LOG_LEVEL               [INFO]

  REGEX                   # pattern principal (doit capturer 'id' et idéalement 'name')
  FALLBACK_REGEX_1..N     # patterns alternatifs (optionnels)

Utilisation:
  /usr/bin/python3 /opt/sandstorm/log_notify_ntfy.py
"""
import os, re, time, logging, base64
import urllib.request, urllib.error
from pathlib import Path
from datetime import datetime, timedelta

# ---------- Config ----------
LOG_FILE        = os.environ.get("LOG_FILE", "/opt/sandstorm/Insurgency/Saved/Logs/Insurgency.log")
ENABLED         = os.environ.get("NTFY_ENABLED", "1") == "1"
SERVER          = os.environ.get("NTFY_SERVER", "https://ntfy.sh").rstrip("/")
TOPIC           = os.environ.get("NTFY_TOPIC", "")
TITLE_PREFIX    = os.environ.get("NTFY_TITLE_PREFIX", "Sandstorm • Connexion")
PRIORITY        = os.environ.get("NTFY_PRIORITY", "high")
TAGS            = os.environ.get("NTFY_TAGS", "video_game")
CLICK_URL       = os.environ.get("NTFY_CLICK", "")
TOKEN           = os.environ.get("NTFY_TOKEN", "")
BASIC_USER      = os.environ.get("NTFY_USER", "")
BASIC_PASS      = os.environ.get("NTFY_PASS", "")
TTL_SECONDS     = int(os.environ.get("DEDUP_TTL", "600"))

REGEX_MAIN = os.environ.get(
    "REGEX",
    # Fréquent sur Sandstorm (à adapter si besoin)
    r"LogNet:\s+Login.*?Name=(?P<name>[^,\]\s]+).*?SteamID(?:64)?[:=]\s*(?P<id>\d{7,20})"
)

# Fallbacks courants
fallbacks = []
i = 1
while True:
    val = os.environ.get(f"FALLBACK_REGEX_{i}")
    if not val: break
    fallbacks.append(val)
    i += 1
if not fallbacks:
    fallbacks = [
        r"PlayerConnected.*?SteamID[:=]\s*(?P<id>\d{7,20})\b.*?Name[:=]\s*(?P<name>[^,\]\s]+)",
        r"\b(?P<name>.+?)\s+joined\s+the\s+game.*?(?P<id>\d{7,20})",
    ]

PATS = [re.compile(REGEX_MAIN)]
PATS.extend(re.compile(p) for p in fallbacks)

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# ---------- ntfy ----------
def ntfy_post(title: str, message: str):
    if not ENABLED or not TOPIC:
        return
    url = f"{SERVER}/{TOPIC}"
    body = message.encode("utf-8")
    req = urllib.request.Request(url, data=body, method="POST")
    # Headers ntfy
    req.add_header("Title", title)
    req.add_header("Priority", PRIORITY)
    if TAGS.strip():
        req.add_header("Tags", TAGS)
    if CLICK_URL.strip():
        req.add_header("Click", CLICK_URL)
    # Auth optionnelle
    if TOKEN:
        req.add_header("Authorization", f"Bearer {TOKEN}")
    elif BASIC_USER and BASIC_PASS:
        token = base64.b64encode(f"{BASIC_USER}:{BASIC_PASS}".encode("utf-8")).decode("ascii")
        req.add_header("Authorization", f"Basic {token}")

    # TLS OK (ca-certificates)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status >= 300:
                raise RuntimeError(f"ntfy HTTP {resp.status}")
    except urllib.error.HTTPError as e:
        logging.error("ntfy HTTPError: %s %s", e.code, e.read())
    except Exception as e:
        logging.exception("ntfy POST failed: %s", e)

# ---------- tail -F ----------
def follow(path: Path):
    f = None
    cur_sig = None
    while True:
        try:
            st = path.stat()
            sig = (st.st_ino, st.st_dev)
            reopen = f is None or sig != cur_sig
            if reopen:
                if f: 
                    try: f.close()
                    except: pass
                # Ouvre et positionne à la fin (on notifie seulement le nouveau)
                f = path.open("r", errors="ignore")
                f.seek(0, 2)
                cur_sig = sig
                logging.info("Ouverture du log: %s", path)

            line = f.readline()
            if line:
                yield line.rstrip("\r\n")
            else:
                # Troncature? (f.tell() > st.st_size) → réouvrir
                try:
                    if f.tell() > st.st_size:
                        logging.info("Troncature détectée, réouverture...")
                        f.close(); f = None
                except Exception:
                    pass
                time.sleep(0.5)
        except FileNotFoundError:
            time.sleep(1.0)
        except Exception as e:
            logging.exception("Erreur tail: %s", e)
            time.sleep(1.0)

def detect(line: str):
    for pat in PATS:
        m = pat.search(line)
        if m:
            gid = (m.groupdict().get("id") or "").strip()
            name = (m.groupdict().get("name") or "").strip()
            if gid:
                return gid, name
    return None

def main():
    if not ENABLED:
        logging.info("NTFY_ENABLED=0 → watcher désactivé.")
        return
    if not TOPIC:
        raise SystemExit("NTFY_TOPIC manquant. Désactive NTFY_ENABLED ou fournis un topic long/secret.")

    log_path = Path(LOG_FILE)
    logging.info("Surveillance: %s", log_path)
    logging.info("ntfy vers: %s/%s", SERVER, TOPIC)

    last_sent = {}  # (id,name) -> datetime
    ttl = timedelta(seconds=TTL_SECONDS)

    for line in follow(log_path):
        hit = detect(line)
        if not hit:
            continue
        gid, name = hit
        key = (gid, name)
        now = datetime.now()
        if key in last_sent and (now - last_sent[key]) < ttl:
            # Anti-spam
            continue
        last_sent[key] = now

        human = now.strftime("%Y-%m-%d %H:%M:%S")
        title = f"{TITLE_PREFIX}: {name or 'Unknown'} ({gid})"
        msg = f"Joueur connecté\n• Nom : {name or 'Unknown'}\n• ID : {gid}\n• Quand : {human}\n(log={LOG_FILE})\n"
        ntfy_post(title, msg)
        logging.info("Notif envoyée: %s", title)

if __name__ == "__main__":
    main()
