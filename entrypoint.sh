#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────
# Dossiers / chemins
# ─────────────────────────────────────────
GAMEDIR="${GAMEDIR:-/opt/sandstorm}"
CFGDIR="${GAMEDIR}/Insurgency/Saved/Config/LinuxServer"
GAMEINI="${CFGDIR}/Game.ini"
MAPCYCLE="${GAMEDIR}/Insurgency/Config/Server/MapCycle.txt"
STEAMCMDDIR="${STEAMCMDDIR:-/home/steam/steamcmd}"
APPID="${APPID:-581330}"

# ─────────────────────────────────────────
# Valeurs par défaut (réseau / identité)
# ─────────────────────────────────────────
: "${AUTO_UPDATE:=1}"
: "${PORT:=27102}"
: "${QUERYPORT:=27131}"
: "${BEACONPORT:=15000}"
: "${RCON_PASSWORD:=}"                 # ← vide si tu veux XP officiel
: "${SS_HOSTNAME:=Chourmovs ISS (PvP)}"
: "${SS_MAXPLAYERS:=28}"               # <= 28 recommandé en PvP

# ─────────────────────────────────────────
# Mode / Map / Scénario (VERSUS par défaut)
# ─────────────────────────────────────────
: "${SS_GAME_MODE:=Push}"              # Push | Firefight | Skirmish | Domination
: "${SS_MAP:=Crossing}"
: "${SS_SCENARIO:=Scenario_Crossing_Push_Security}"   # doit matcher le mode
: "${SS_MAPCYCLE:=}"                   # évite "unbound variable" si non fourni

# ─────────────────────────────────────────
# Bots (VERSUS)
# ─────────────────────────────────────────
: "${SS_BOTS_ENABLED:=1}"
: "${SS_BOT_NUM:=12}"
: "${SS_BOT_QUOTA:=1.0}"
: "${SS_BOT_DIFFICULTY:=0.7}"

# ─────────────────────────────────────────
# QOL / Timings / Vote
# ─────────────────────────────────────────
: "${SS_KILL_FEED:=1}"
: "${SS_KILL_CAMERA:=0}"
: "${SS_VOICE_ENABLED:=1}"
: "${SS_FRIENDLY_FIRE_SCALE:=0.2}"
: "${SS_ROUND_TIME:=900}"
: "${SS_POST_ROUND_TIME:=15}"
: "${SS_VOTE_ENABLED:=1}"
: "${SS_VOTE_PERCENT:=0.6}"

# ─────────────────────────────────────────
# Tokens XP (optionnels)
# ─────────────────────────────────────────
: "${GSLT_TOKEN:=}"                    # AppID 581320
: "${GAMESTATS_TOKEN:=}"               # https://gamestats.sandstorm.game

echo "▶️ Starting Insurgency Sandstorm Dedicated Server...

  PORT=${PORT} | QUERYPORT=${QUERYPORT} | BEACONPORT=${BEACONPORT}
  RCON_PASSWORD=$([ -n "${RCON_PASSWORD}" ] && echo '********' || echo '(empty)')
  AUTO_UPDATE=${AUTO_UPDATE}
  MAP=${SS_MAP} | SCENARIO=${SS_SCENARIO} | MODE=${SS_GAME_MODE}
"

# ─────────────────────────────────────────
# Préparation FS (permissions / dossiers)
# ─────────────────────────────────────────
need_paths=(
  "${GAMEDIR}"
  "${GAMEDIR}/Insurgency"
  "${GAMEDIR}/Insurgency/Saved"
  "${GAMEDIR}/Insurgency/Saved/SaveGames"
  "${GAMEDIR}/Insurgency/Config/Server"
  "${CFGDIR}"
)
for p in "${need_paths[@]}"; do
  if [ ! -d "$p" ]; then
    mkdir -p "$p" || {
      echo "❌ Permission refusée pour créer: $p"
      echo "   ➜ chown -R 1000:1000 ${GAMEDIR} /home/steam/Steam"
      exit 1
    }
  fi
done
echo "write-test" > "${GAMEDIR}/.writetest" || {
  echo "❌ Impossible d'écrire dans ${GAMEDIR} (permissions)."
  exit 1
}
rm -f "${GAMEDIR}/.writetest"

# ─────────────────────────────────────────
# Auto-update SteamCMD (avec retry)
# ─────────────────────────────────────────
if [ "${AUTO_UPDATE}" = "1" ]; then
  echo "📥 Updating server via SteamCMD..."
  tries=3
  for i in $(seq 1 $tries); do
    if "${STEAMCMDDIR}/steamcmd.sh" +@sSteamCmdForcePlatformType linux \
        +force_install_dir "${GAMEDIR}" \
        +login anonymous \
        +app_update "${APPID}" validate \
        +quit; then
      break
    fi
    echo "⚠️  SteamCMD validate failed (try ${i}/${tries}). Retrying..."
    sleep 5
    [ "${i}" -eq "${tries}" ] && echo "⚠️  Continue anyway."
  done
fi

# ─────────────────────────────────────────
# MapCycle.txt (seulement si fourni)
# ─────────────────────────────────────────
echo "🗺️  Writing MapCycle..."
if [ -n "${SS_MAPCYCLE}" ]; then
  {
    # pas de commentaires ni lignes vides → certain parseurs sont chatouilleux
    echo "${SS_MAPCYCLE}" | tr '\r' '\n' | sed '/^\s*$/d'
  } > "${MAPCYCLE}"
  echo "   → MapCycle.txt écrit ($(wc -l < "${MAPCYCLE}") lignes)"
else
  echo "   → Aucun SS_MAPCYCLE fourni, on saute l'écriture."
fi

# ─────────────────────────────────────────
# Game.ini (VERSUS)
# ─────────────────────────────────────────
echo "🧩 Writing Game.ini..."
# Choix de la section en fonction du mode PvP
MODE_UPPER="$(echo "${SS_GAME_MODE}" | tr '[:lower:]' '[:upper:]')"
case "${MODE_UPPER}" in
  PUSH)       MODE_SECTION="/Script/Insurgency.INSPushGameMode" ;;
  FIREFIGHT)  MODE_SECTION="/Script/Insurgency.INSFirefightGameMode" ;;
  SKIRMISH)   MODE_SECTION="/Script/Insurgency.INSSkirmishGameMode" ;;
  DOMINATION) MODE_SECTION="/Script/Insurgency.INSDominationGameMode" ;;
  *)          MODE_SECTION="/Script/Insurgency.INSPushGameMode" ; SS_GAME_MODE="Push" ;;
esac

cat > "${GAMEINI}" <<EOF
; ------------------------------------------------------------------
; Insurgency Sandstorm - Game.ini (VERSUS / PvP)
; ------------------------------------------------------------------

[/Script/Insurgency.INSGameMode]
bKillFeed=${SS_KILL_FEED}
bKillCamera=${SS_KILL_CAMERA}
bVoiceEnabled=${SS_VOICE_ENABLED}
FriendlyFireDamageScale=${SS_FRIENDLY_FIRE_SCALE}
RoundTime=${SS_ROUND_TIME}
PostRoundTime=${SS_POST_ROUND_TIME}
bAllowVoting=${SS_VOTE_ENABLED}
RequiredVotePercentage=${SS_VOTE_PERCENT}

${MODE_SECTION}
bBots=${SS_BOTS_ENABLED}
NumBots=${SS_BOT_NUM}
BotQuota=${SS_BOT_QUOTA}
BotDifficulty=${SS_BOT_DIFFICULTY}
EOF
echo "   → Game.ini écrit (${SS_GAME_MODE})"

# ─────────────────────────────────────────
# Lancement serveur
# ─────────────────────────────────────────
cd "${GAMEDIR}/Insurgency/Binaries/Linux"

LAUNCH_MAP="${SS_MAP}?Scenario=${SS_SCENARIO}?MaxPlayers=${SS_MAXPLAYERS}"

# Flags XP (optionnels) — uniquement si tokens fournis et RCON_PASSWORD vide
XP_ARGS=()
if [ -n "${GSLT_TOKEN}" ] && [ -n "${GAMESTATS_TOKEN}" ] && [ -z "${RCON_PASSWORD}" ]; then
  XP_ARGS+=( "-GSLTToken=${GSLT_TOKEN}" "-GameStatsToken=${GAMESTATS_TOKEN}" )
  echo "✨ XP flags activés (RCON password vide, tokens présents)."
else
  echo "ℹ️ XP non activé (tokens manquants ou RCON défini)."
fi

exec ./InsurgencyServer-Linux-Shipping \
  "${LAUNCH_MAP}" \
  -hostname="${SS_HOSTNAME}" \
  -Port="${PORT}" -QueryPort="${QUERYPORT}" -BeaconPort="${BEACONPORT}" \
  -Rcon ${RCON_PASSWORD:+-RconPassword="${RCON_PASSWORD}"} \
  -log \
  "${XP_ARGS[@]}"
