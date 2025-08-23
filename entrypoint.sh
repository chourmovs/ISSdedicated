#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────
# Dossiers / chemins
# ─────────────────────────────────────────
GAMEDIR="${GAMEDIR:-/opt/sandstorm}"
CFGDIR="${GAMEDIR}/Insurgency/Saved/Config/LinuxServer"
GAMEINI="${CFGDIR}/Game.ini"
MAPCYCLE="${CFGDIR}/MapCycle.txt"
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
: "${SS_MAP:=Crossing}"                # informatif uniquement
: "${SS_SCENARIO:=}"
: "${SS_MAPCYCLE:=}"

# Fallback anti-range si scénario vide ou invalide
if [[ -z "${SS_SCENARIO}" || ! "${SS_SCENARIO}" =~ ^Scenario_ ]]; then
  echo "⚠️  SS_SCENARIO vide/invalide ('${SS_SCENARIO:-<unset>}'), fallback → Scenario_Farmhouse_Push_Security"
  SS_SCENARIO="Scenario_Farmhouse_Push_Security"
fi

# ─────────────────────────────────────────
# Bots (VERSUS)
# ─────────────────────────────────────────
: "${SS_BOTS_ENABLED:=1}"
: "${SS_BOT_NUM:=12}"
: "${SS_BOT_QUOTA:=1.0}"
: "${SS_BOT_DIFFICULTY:=0.7}"

# ─────────────────────────────────────────
# Auto-balance
# ─────────────────────────────────────────
: "${SS_AUTO_BALANCE:=False}"     # True | False
: "${SS_AUTO_BALANCE_DELAY:=10}"

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
# XP & Stats
# ─────────────────────────────────────────
: "${SS_ENABLE_STATS:=1}"              # écrit bDisableStats=False si =1
: "${GSLT_TOKEN:=}"                    # AppID 581320
: "${GAMESTATS_TOKEN:=}"               # https://gamestats.sandstorm.game

# ─────────────────────────────────────────
# MODS / MUTATORS
# ─────────────────────────────────────────
# SS_MODS           = liste d'IDs Mod.io séparés par virgules (ex: "1141916,1234567")
# SS_MUTATORS       = liste de noms séparés par virgules (ex: "AiModifier,HeadshotOnly")
# SS_MUTATOR_URL_ARGS = arguments avancés à mettre dans l’URL (ex: "AIModifier.MaxCount=30?AIModifier.Accuracy=0.8")
: "${SS_MODS:=}"
: "${SS_MUTATORS:=}"
: "${SS_MUTATOR_URL_ARGS:=}"           # clés/valeurs de mutators passées en URL
: "${EXTRA_SERVER_ARGS:=}"             # args supplémentaires raw

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
  echo "${SS_MAPCYCLE}" | tr '\r' '\n' | sed '/^\s*$/d' > "${MAPCYCLE}"
  echo "   → ${MAPCYCLE} écrit ($(wc -l < "${MAPCYCLE}") lignes)"
else
  echo "   → Aucun SS_MAPCYCLE fourni, on saute l'écriture."
fi

# ─────────────────────────────────────────
# Déduction section de mode (fallback propre)
# ─────────────────────────────────────────
MODE_UPPER="$(echo "${SS_GAME_MODE}" | tr '[:lower:]' '[:upper:]')"
case "${MODE_UPPER}" in
  PUSH)       MODE_SECTION="/Script/Insurgency.INSPushGameMode" ;;
  FIREFIGHT)  MODE_SECTION="/Script/Insurgency.INSFirefightGameMode" ;;
  SKIRMISH)   MODE_SECTION="/Script/Insurgency.INSSkirmishGameMode" ;;
  DOMINATION) MODE_SECTION="/Script/Insurgency.INSDominationGameMode" ;;
  *)          MODE_SECTION="/Script/Insurgency.INSPushGameMode" ; SS_GAME_MODE="Push" ;;
esac

# ─────────────────────────────────────────
# Admins (Admins.txt + switch -AdminList)
# ─────────────────────────────────────────
: "${SS_ADMINS:=}"   # ex: "76561198000000001,76561198000000002"
ADMINSDIR="${GAMEDIR}/Insurgency/Config/Server"
ADMINSLIST_NAME="Admins"
mkdir -p "${ADMINSDIR}"

ADMINSLIST_PATH="${ADMINSDIR}/${ADMINSLIST_NAME}.txt"
if [ -n "${SS_ADMINS}" ]; then
  echo "🛡️  Writing ${ADMINSLIST_PATH}"
  : > "${ADMINSLIST_PATH}"
  IFS=',' read -ra _admins <<< "${SS_ADMINS}"
  for id in "${_admins[@]}"; do
    id_trim="$(echo "$id" | xargs)"
    [[ "$id_trim" =~ ^[0-9]{17}$ ]] && echo "$id_trim" >> "${ADMINSLIST_PATH}"
  done
  echo "   → $(wc -l < "${ADMINSLIST_PATH}") admin(s) ajouté(s)."
else
  # crée le fichier vide si absent (certains serveurs aiment bien le switch même vide)
  [ -f "${ADMINSLIST_PATH}" ] || : > "${ADMINSLIST_PATH}"
fi


# ─────────────────────────────────────────
# Game.ini (core + stats + mods/mutators)
# ─────────────────────────────────────────
echo "🧩 Writing Game.ini..."
MODE_UPPER="$(echo "${SS_GAME_MODE}" | tr '[:lower:]' '[:upper:]')"
case "${MODE_UPPER}" in
  PUSH)       MODE_SECTION="/Script/Insurgency.INSPushGameMode" ;;
  FIREFIGHT)  MODE_SECTION="/Script/Insurgency.INSFirefightGameMode" ;;
  SKIRMISH)   MODE_SECTION="/Script/Insurgency.INSSkirmishGameMode" ;;
  DOMINATION) MODE_SECTION="/Script/Insurgency.INSDominationGameMode" ;;
  *)          MODE_SECTION="/Script/Insurgency.INSPushGameMode" ; SS_GAME_MODE="Push" ;;
esac

{
  cat <<EOF
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
bDisableStats=$([ "${SS_ENABLE_STATS:-1}" = "1" ] && echo "False" || echo "True")
EOF

  # Mods= (un par ligne)
  if [ -n "${SS_MODS:-}" ]; then
    IFS=',' read -ra _mods <<< "${SS_MODS}"
    for mid in "${_mods[@]}"; do
      mid_trim="$(echo "$mid" | xargs)"
      [ -n "$mid_trim" ] && echo "Mods=${mid_trim}"
    done
  fi

  # Mutators= (peut rester sur une seule ligne)
  if [ -n "${SS_MUTATORS:-}" ]; then
    echo "Mutators=${SS_MUTATORS}"
  fi

  cat <<EOF

${MODE_SECTION}
bBots=${SS_BOTS_ENABLED}
NumBots=${SS_BOT_NUM}
BotQuota=${SS_BOT_QUOTA}
BotDifficulty=${SS_BOT_DIFFICULTY}

[/Script/Insurgency.INSMultiplayerMode]
bAutoBalanceTeams=${SS_AUTO_BALANCE}
AutoBalanceDelay=${SS_AUTO_BALANCE_DELAY}
EOF
} > "${GAMEINI}"
echo "   → Game.ini écrit (${SS_GAME_MODE})"


# ─────────────────────────────────────────
# Déduction Asset depuis SCENARIO (anti-range)
# ─────────────────────────────────────────
scenario_core="$(printf '%s' "${SS_SCENARIO#Scenario_}" | cut -d'_' -f1)"
scenario_mode="$(printf '%s' "${SS_SCENARIO}" | awk -F'_' '{print $(NF-1)}' | tr '[:lower:]' '[:upper:]')"

case "${scenario_core}" in
  Crossing)   MAP_ASSET="Canyon"   ;;
  Hideout)    MAP_ASSET="Town"     ;;
  Hillside)   MAP_ASSET="Sinjar"   ;;
  Refinery)   MAP_ASSET="Oilfield" ;;
  *)          MAP_ASSET="${scenario_core}" ;;
esac

case "${scenario_mode}" in
  PUSH)       MODE_SECTION="/Script/Insurgency.INSPushGameMode" ;;
  FIREFIGHT)  MODE_SECTION="/Script/Insurgency.INSFirefightGameMode" ;;
  SKIRMISH)   MODE_SECTION="/Script/Insurgency.INSSkirmishGameMode" ;;
  DOMINATION) MODE_SECTION="/Script/Insurgency.INSDominationGameMode" ;;
  *)          MODE_SECTION="/Script/Insurgency.INSPushGameMode" ; scenario_mode="PUSH" ;;
esac
echo "🧭 Scenario=${SS_SCENARIO} → Asset=${MAP_ASSET} | MODE=${scenario_mode}"

# ─────────────────────────────────────────
# Construction URL de lancement
# ─────────────────────────────────────────
LAUNCH_URL="${MAP_ASSET}?Scenario=${SS_SCENARIO}?MaxPlayers=${SS_MAXPLAYERS}\
?bBots=${SS_BOTS_ENABLED}?NumBots=${SS_BOT_NUM}?BotQuota=${SS_BOT_QUOTA}?BotDifficulty=${SS_BOT_DIFFICULTY}"

# Mutators dans l’URL (en plus de Game.ini, pour forcer le chargement)
# Mutators dans l’URL (double sécurité)
if [ -n "${SS_MUTATORS:-}" ]; then
  LAUNCH_URL="${LAUNCH_URL}?Mutators=${SS_MUTATORS}"
fi
if [ -n "${SS_MUTATOR_URL_ARGS:-}" ]; then
  LAUNCH_URL="${LAUNCH_URL}?${SS_MUTATOR_URL_ARGS}"
fi


# Arguments URL supplémentaires pour mutators (clé=valeur reliées par '?')
# ex: SS_MUTATOR_URL_ARGS="AIModifier.MaxCount=30?AIModifier.Accuracy=0.8"
if [ -n "${SS_MUTATOR_URL_ARGS}" ]; then
  # s’assure de préfixer par '?' si besoin
  if [[ "${LAUNCH_URL}" != *"?"* ]]; then
    LAUNCH_URL="${LAUNCH_URL}?${SS_MUTATOR_URL_ARGS}"
  else
    LAUNCH_URL="${LAUNCH_URL}?${SS_MUTATOR_URL_ARGS}"
  fi
fi

echo "▶️  Launch: ${LAUNCH_URL}"

# ─────────────────────────────────────────
# XP flags (conditions officielles)
# ─────────────────────────────────────────
XP_ARGS=()
if [ -n "${GSLT_TOKEN}" ] && [ -n "${GAMESTATS_TOKEN}" ] && [ -z "${RCON_PASSWORD}" ]; then
  XP_ARGS+=( "-GSLTToken=${GSLT_TOKEN}" "-GameStatsToken=${GAMESTATS_TOKEN}" )
  echo "✨ XP flags activés (RCON password vide, tokens présents)."
else
  echo "ℹ️ XP non activé (tokens manquants ou RCON défini)."
fi

# ─────────────────────────────────────────
# Lancement
# ─────────────────────────────────────────
cd "${GAMEDIR}/Insurgency/Binaries/Linux"
exec ./InsurgencyServer-Linux-Shipping \
  "${LAUNCH_URL}" \
  -hostname="${SS_HOSTNAME}" \
  -AdminList="${ADMINSLIST_NAME}" \
  -Port="${PORT}" -QueryPort="${QUERYPORT}" -BeaconPort="${BEACONPORT}" \
  -log \
  ${EXTRA_SERVER_ARGS} \
  "${XP_ARGS[@]}"
