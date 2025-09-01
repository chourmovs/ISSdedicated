#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Watcher Insurgency: Sandstorm → ntfy push (requests)
- Tail -F robuste (rotation/troncature)
- REGEX configurable (capture id/name/team)
- Anti-doublon (TTL)
- Logs détaillés (ouverture log, match, post ntfy avec status)
"""

import os, re, time, logging, base64, socket
from pathlib import Path
from datetime import datetime, timedelta
import requests

# ============= Config =============
LOG_FILE        = os.environ.get("LOG_FILE", "/opt/sandstorm/Insurgency/Saved/Logs/Insurgency.log")
ENABLED         = os.environ.get("NTFY_ENABLED", "1") == "1"

SERVER          = os.environ.get("NTFY_SERVER", "https://ntfy.sh").rstrip("/")
TOPIC           = (os.environ.get("NTFY_TOPIC", "") or "").strip()

TITLE_PREFIX    = os.environ.get("NTFY_TITLE_PREFIX", "Sandstorm • Connexion")
PRIORITY        = os.environ.get("NTFY_PRIORITY", "high")   # min|low|default|high|max ou 1..5
TAGS            = os.environ.get("NTFY_TAGS", "video_game")
CLICK_URL       = os.environ.get("NTFY_CLICK", "")
TOKEN           = os.environ.get("NTFY_TOKEN", "")
BASIC_USER      = os.environ.get("NTFY_USER", "")
BASIC_PASS      = os.environ.get("NTFY_PASS", "")
TTL_SECONDS     = int(os.environ.get("DEDUP_TTL", "600"))

LOG_LEVEL       = os.environ.get("LOG_LEVEL", "INFO").upper()
TEST_ON_START   = os.environ.get("NTFY_TEST_ON_START", "1") == "1"
LOG_REQUEST     = os.environ.get("NTFY_LOG_REQUEST", "1") == "1"  # log URL/titre/message (tronqué)

REGEX_MAIN = os.environ.get(
    "REGEX",
    r"LogGameMode:\s+Display:\s+Player\s+(?P<id>\d+)\s+'(?P<name>[^']+)'\s+joined\s+team\s+(?P<team>\d+)"
)

# Fallbacks (facultatif)
fallbacks = []
i = 1
while True:
    val = os.environ.get(f"FALLBACK_REGEX_{i}")
    if not val: break
    fallbacks.append(val)
    i += 1
if not fallbacks:
    fallbacks = [
        r"Player\s+(?P<id>\d+)\s+'(?P<name>[^']+)'\s+joined\s+team\s+(?P<team>\d+)",
    ]

PATS = [re.compile(REGEX_MAIN)]
PATS.extend(re.compile(p) for p in fallbacks)

logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s [%(levelname)s] %(message)s"
)

# ============= ntfy POST (requests) =============
def ntfy_post(title: str, message: str) -> int:
    if not ENABLED or not TOPIC:
        logging.warning("ntfy_post appelé mais ENABLED=%s TOPIC='%s'", ENABLED, TOPIC)
        return -1

    url = f"{SERVER}/{TOPIC}"
    headers = {
        "Title": title,
        "Priority": str(PRIORITY),
    }
    if TAGS.strip():   headers["Tags"]  = TAGS
    if CLICK_URL.strip(): headers["Click"] = CLICK_URL
    if TOKEN:
        headers["Authorization"] = f"Bearer {TOKEN}"
    elif BASIC_USER and BASIC_PASS:
        token = base64.b64encode(f"{BASIC_USER}:{BASIC_PASS}".encode("utf-8")).decode("ascii")
        headers["Authorization"] = f"Basic {token}"

    data = message.encode("utf-8")

    if LOG_REQUEST:
        preview = (message[:200] + "…") if len(message) > 200 else message
        logging.info("ntfy POST → %s | Title='%s' | len(body)=%d | preview='%s'",
                     url, title, len(data), preview.replace("\n", "\\n"))

    try:
        r = requests.post(url, data=data, headers=headers, timeout=10)
        logging.info("ntfy POST status=%s reason=%s", r.status_code, getattr(r, "reason", ""))
        if r.status_code >= 300:
            logging.error("ntfy response body: %s", r.text[:500])
        return r.status_code
    except requests.RequestException as e:
        logging.exception("ntfy POST failed: %s", e)
        return -2

# ============= Tail -F =============
def follow(path: Path):
    f = None
    cur_sig = None
    while True:
        try:
            st = path.stat()
            sig = (st.st_ino, st.st_dev)
            if f is None or sig != cur_sig:
                if f:
                    try: f.close()
                    except: pass
                f = path.open("r", errors="ignore")
                # se placer à la fin: on ne notifie que du nouveau
                f.seek(0, 2)
                cur_sig = sig
                logging.info("Ouverture du log: %s (inode=%s)", path, sig)
            line = f.readline()
            if line:
                yield line.rstrip("\r\n")
            else:
                # rotation/troncature
                if f.tell() > st.st_size:
                    logging.info("Troncature détectée, réouverture…")
                    f.close(); f = None
                time.sleep(0.5)
        except FileNotFoundError:
            logging.warning("Log introuvable: %s (on réessaie)", path)
            time.sleep(1.0)
        except Exception as e:
            logging.exception("Erreur tail: %s", e)
            time.sleep(1.0)

def detect(line: str):
    for pat in PATS:
        m = pat.search(line)
        if m:
            return m.groupdict()
    return None

# ============= Main =============
def main():
    if not ENABLED:
        logging.info("NTFY_ENABLED=0 → watcher inactif.")
        return
    if not TOPIC:
        raise SystemExit("NTFY_TOPIC manquant. Fournis un sujet (long/secret).")

    host = socket.gethostname()
    logging.info("=== ntfy watcher démarré ===")
    logging.info("Server: %s | Topic: %s | Log: %s | Host: %s", SERVER, TOPIC, LOG_FILE, host)
    logging.info("Regex: %s", REGEX_MAIN)
    if fallbacks:
        logging.info("Fallbacks: %s", "; ".join(fallbacks))

    # Test de publication au démarrage (pour valider la chaîne de notif)
    if TEST_ON_START:
        code = ntfy_post(
            f"{TITLE_PREFIX} • watcher started",
            f"Watcher opérationnel sur {host} ({datetime.now():%Y-%m-%d %H:%M:%S}).\n"
            f"Log suivi: {LOG_FILE}\n"
            f"Regex: {REGEX_MAIN}"
        )
        logging.info("Test start post → code=%s", code)

    last_sent = {}   # clé=(id,name,team) -> datetime
    ttl = timedelta(seconds=TTL_SECONDS)

    path = Path(LOG_FILE)
    for line in follow(path):
        if "joined team" in line or "LogGameMode" in line:
            logging.debug("Ligne candidate: %s", line.strip())
        info = detect(line)
        if not info:
            continue

        gid  = (info.get("id") or "").strip()
        name = (info.get("name") or "").strip()
        team = (info.get("team") or "").strip()
        key  = (gid, name, team)

        now = datetime.now()
        if key in last_sent and (now - last_sent[key]) < ttl:
            logging.debug("Dedup TTL ignore: %s", key)
            continue
        last_sent[key] = now

        logging.info("Match: name='%s' id=%s team=%s", name, gid, team)

        title = f"{TITLE_PREFIX}: {name or 'Unknown'} ({gid})"
        body  = (
            f"Joueur connecté\n"
            f"• Nom  : {name or 'Unknown'}\n"
            f"• ID   : {gid or '?'}\n"
            f"• Team : {team or '?'}\n"
            f"• Quand: {now:%Y-%m-%d %H:%M:%S}\n"
            f"(log={LOG_FILE})\n"
        )
        code = ntfy_post(title, body)
        logging.info("Notification envoyée (code=%s) pour %s/%s", code, name, gid)

if __name__ == "__main__":
    main()
