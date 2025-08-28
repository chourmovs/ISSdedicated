#!/bin/bash
# ==================================================================
# Insurgency: Sandstorm Dedicated Server - EntryPoint (clean)
# - XP classé (GSLT + GameStats, RCON vide)
# - Admins: Admins.txt + -AdminList
# - Mods (Workshop) chargés; Mutators activés uniquement en Skirmish
# - AiModifier: args via URL UNIQUEMENT si Skirmish + AiModifier actif
# - MapCycle + déduction Asset depuis SCENARIO
# - Logs détaillés + validations
# - AUCUN PRESET FORCÉ (tout par env)
# ==================================================================

set -eo pipefail

# ─────────────────────────────────────────
# 0) Variables / chemins (avec défauts)
# ─────────────────────────────────────────
GAMEDIR="${GAMEDIR:-/opt/sandstorm}"
CFGDIR="${CFGDIR:-${GAMEDIR}/Insurgency/Saved/Config/LinuxServer}"
GAMEINI="${GAMEINI:-${CFGDIR}/Game.ini}"
MAPCYCLE="${MAPCYCLE:-${CFGDIR}/MapCycle.txt}"
STEAMCMDDIR="${STEAMCMDDIR:-/home/steam/steamcmd}"
APPID="${APPID:-581330}"

AUTO_UPDATE="${AUTO_UPDATE:-1}"
PORT="${PORT:-27102}"
QUERYPORT="${QUERYPORT:-27131}"
BEACONPORT="${BEACONPORT:-15000}"
RCON_PASSWORD="${RCON_PASSWORD:-}"     # ← vide = XP classé possible
SS_HOSTNAME="${SS_HOSTNAME:-Chourmovs ISS (PvP)}"
SS_MAXPLAYERS="${SS_MAXPLAYERS:-28}"

SS_GAME_MODE="${SS_GAME_MODE:-Push}"   # Push/Firefight/Skirmish/Domination/Checkpoint/Outpost/Survival
SS_MAP="${SS_MAP:-Crossing}"           
SS_SCENARIO="${SS_SCENARIO:-}"         
SS_MAPCYCLE="${SS_MAPCYCLE:-}"         

# Bots
SS_BOTS_ENABLED="${SS_BOTS_ENABLED:-1}"
SS_BOT_NUM="${SS_BOT_NUM:-12}"
SS_BOT_QUOTA="${SS_BOT_QUOTA:-1.0}"
SS_BOT_DIFFICULTY="${SS_BOT_DIFFICULTY:-0.7}"

# Auto-balance
SS_AUTO_BALANCE="${SS_AUTO_BALANCE:-False}"
SS_AUTO_BALANCE_DELAY="${SS_AUTO_BALANCE_DELAY:-10}"

# QOL / vote
SS_KILL_FEED="${SS_KILL_FEED:-1}"
SS_KILL_CAMERA="${SS_KILL_CAMERA:-0}"
SS_VOICE_ENABLED="${SS_VOICE_ENABLED:-1}"
SS_FRIENDLY_FIRE_SCALE="${SS_FRIENDLY_FIRE_SCALE:-0.2}"
SS_ROUND_TIME="${SS_ROUND_TIME:-900}"
SS_POST_ROUND_TIME="${SS_POST_ROUND_TIME:-15}"
SS_VOTE_ENABLED="${SS_VOTE_ENABLED:-1}"
SS_VOTE_PERCENT="${SS_VOTE_PERCENT:-0.6}"

# XP / Stats
SS_ENABLE_STATS="${SS_ENABLE_STATS:-1}"
GSLT_TOKEN="${GSLT_TOKEN:-}"
GAMESTATS_TOKEN="${GAMESTATS_TOKEN:-}"

# Mods (Workshop) & Mutators
SS_MODS="${SS_MODS:-}"                      
SS_MUTATORS_SKIRMISH="${SS_MUTATORS_SKIRMISH:-}"   # UNIQUEMENT Skirmish
EXTRA_SERVER_ARGS="${EXTRA_SERVER_ARGS:-}"

# Admins
SS_ADMINS="${SS_ADMINS:-}"

# AiModifier placeholders (tous optionnels, même liste que ton script précédent)
# Exemple :
AIMOD_DIFFICULTY="${AIMOD_DIFFICULTY:-}"
AIMOD_ACCURACY_MULT="${AIMOD_ACCURACY_MULT:-}"
AIMOD_CHANCE_COVER="${AIMOD_CHANCE_COVER:-}"
# … (garde toute la liste de tes AIMOD_* ici)

echo "────────────────────────────────────────────────────────"
echo "▶️  Starting Insurgency Sandstorm Dedicated Server"
echo "    GAMEDIR=${GAMEDIR}"
echo "    CFGDIR=${CFGDIR}"
echo "    APPID=${APPID}"
echo "    PORT=${PORT} | QUERYPORT=${QUERYPORT} | BEACONPORT=${BEACONPORT}"
echo "    HOSTNAME='${SS_HOSTNAME}'"
echo "    MAXPLAYERS=${SS_MAXPLAYERS}"
echo "    AUTO_UPDATE=${AUTO_UPDATE}"
echo "────────────────────────────────────────────────────────"

# ─────────────────────────────────────────
# 1) Préparation FS
# ─────────────────────────────────────────
need_paths=(
  "${GAMEDIR}"
  "${GAMEDIR}/Insurgency"
  "${GAMEDIR}/Insurgency/Config/Server"
  "${GAMEDIR}/Insurgency/Saved"
  "${GAMEDIR}/Insurgency/Saved/SaveGames"
  "${CFGDIR}"
)
for p in "${need_paths[@]}"; do
  if [ ! -d "$p" ]; then
    echo "📁 Creating: $p"
    mkdir -p "$p" || {
      echo "❌ Permission denied creating: $p"
      echo "   ➜ chown -R 1000:1000 ${GAMEDIR} /home/steam/Steam"
      exit 1
    }
  fi
done

# ─────────────────────────────────────────
# 2) Admins
# ─────────────────────────────────────────
ADMINSDIR="${GAMEDIR}/Insurgency/Config/Server"
ADMINSLIST_NAME="Admins"
ADMINSLIST_PATH="${ADMINSDIR}/${ADMINSLIST_NAME}.txt"
mkdir -p "${ADMINSDIR}"
: > "${ADMINSLIST_PATH}"

if [ -n "${SS_ADMINS}" ]; then
  IFS=',' read -ra _admins <<< "${SS_ADMINS}"
  for id in "${_admins[@]}"; do
    id_trim="$(echo "$id" | xargs)"
    [[ "$id_trim" =~ ^[0-9]{17}$ ]] && echo "$id_trim" >> "${ADMINSLIST_PATH}"
  done
fi

# ─────────────────────────────────────────
# 3) SteamCMD update
# ─────────────────────────────────────────
if [ "${AUTO_UPDATE}" = "1" ]; then
  "${STEAMCMDDIR}/steamcmd.sh" +@sSteamCmdForcePlatformType linux \
      +force_install_dir "${GAMEDIR}" \
      +login anonymous \
      +app_update "${APPID}" validate \
      +quit || echo "⚠️ SteamCMD failed"
fi

# ─────────────────────────────────────────
# 4) MapCycle
# ─────────────────────────────────────────
if [ -n "${SS_MAPCYCLE}" ]; then
  echo "${SS_MAPCYCLE}" | tr '\r' '\n' | sed '/^\s*$/d' > "${MAPCYCLE}"
fi

# ─────────────────────────────────────────
# 5) Déduction scenario
# ─────────────────────────────────────────
if [[ -z "${SS_SCENARIO}" || ! "${SS_SCENARIO}" =~ ^Scenario_ ]]; then
  SS_SCENARIO="Scenario_Farmhouse_Push_Security"
fi
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
  PUSH)        MODE_SECTION="/Script/Insurgency.INSPushGameMode" ;;
  FIREFIGHT)   MODE_SECTION="/Script/Insurgency.INSFirefightGameMode" ;;
  SKIRMISH)    MODE_SECTION="/Script/Insurgency.INSSkirmishGameMode" ;;
  DOMINATION)  MODE_SECTION="/Script/Insurgency.INSDominationGameMode" ;;
  CHECKPOINT)  MODE_SECTION="/Script/Insurgency.INSCheckpointGameMode" ;;
  OUTPOST)     MODE_SECTION="/Script/Insurgency.INSOutpostGameMode" ;;
  SURVIVAL)    MODE_SECTION="/Script/Insurgency.INSSurvivalGameMode" ;;
  *)           MODE_SECTION="/Script/Insurgency.INSPushGameMode" ;;
esac

if [[ "${scenario_mode}" == "CHECKPOINT" || "${scenario_mode}" == "OUTPOST" || "${scenario_mode}" == "SURVIVAL" ]]; then
  RULES_SECTION="/Script/Insurgency.INSCoopMode"
else
  RULES_SECTION="/Script/Insurgency.INSMultiplayerMode"
fi

# ─────────────────────────────────────────
# 6) AiModifier URL args
# ─────────────────────────────────────────
AIMOD_ARGS=()
add_arg() { [ -n "$2" ] && AIMOD_ARGS+=("$1=$2"); }
# (ajoute tous tes add_arg AIMOD_* ici comme avant)

AIMOD_URL_ARGS=""
if [ "${#AIMOD_ARGS[@]}" -gt 0 ]; then
  AIMOD_URL_ARGS="$(printf '%s' "${AIMOD_ARGS[0]}")"
  for ((i=1; i<${#AIMOD_ARGS[@]}; i++)); do
    AIMOD_URL_ARGS="${AIMOD_URL_ARGS}?${AIMOD_ARGS[$i]}"
  done
fi

# ─────────────────────────────────────────
# 7) Écriture Game.ini
# ─────────────────────────────────────────
{
  cat <<EOF
[/Script/Insurgency.INSGameMode]
bKillFeed=${SS_KILL_FEED}
bKillCamera=${SS_KILL_CAMERA}
bVoiceEnabled=${SS_VOICE_ENABLED}
FriendlyFireDamageScale=${SS_FRIENDLY_FIRE_SCALE}
RoundTime=${SS_ROUND_TIME}
PostRoundTime=${SS_POST_ROUND_TIME}
bAllowVoting=${SS_VOTE_ENABLED}
RequiredVotePercentage=${SS_VOTE_PERCENT}
bDisableStats=$([ "${SS_ENABLE_STATS}" = "1" ] && echo "False" || echo "True")
EOF

  if [ -n "${SS_MODS}" ]; then
    IFS=',' read -ra _mods <<< "${SS_MODS}"
    for mid in "${_mods[@]}"; do
      mid_trim="$(echo "$mid" | xargs)"
      [ -n "$mid_trim" ] && echo "Mods=${mid_trim}"
    done
  fi

  cat <<EOF

[${RULES_SECTION}]
bAutoBalanceTeams=${SS_AUTO_BALANCE}
AutoBalanceDelay=${SS_AUTO_BALANCE_DELAY}

[${MODE_SECTION}]
bBots=${SS_BOTS_ENABLED}
NumBots=${SS_BOT_NUM}
BotQuota=${SS_BOT_QUOTA}
BotDifficulty=${SS_BOT_DIFFICULTY}
EOF

  if [[ "${RULES_SECTION}" == "/Script/Insurgency.INSCoopMode" ]]; then
    echo "FriendlyBotQuota=${SS_FRIENDLY_BOT_QUOTA:-0}"
    [[ -n "${SS_MIN_ENEMIES:-}" ]] && echo "MinimumEnemies=${SS_MIN_ENEMIES}"
    [[ -n "${SS_MAX_ENEMIES:-}" ]] && echo "MaximumEnemies=${SS_MAX_ENEMIES}"
  fi

  # sections vides pour les autres modes
  cat <<'EOF'
[/Script/Insurgency.INSPushGameMode]
[/Script/Insurgency.INSFirefightGameMode]
[/Script/Insurgency.INSDominationGameMode]
[/Script/Insurgency.INSCheckpointGameMode]
[/Script/Insurgency.INSOutpostGameMode]
[/Script/Insurgency.INSSurvivalGameMode]
EOF

  # Mutators uniquement pour Skirmish
  if [ -n "${SS_MUTATORS_SKIRMISH}" ]; then
    echo
    echo "[/Script/Insurgency.INSSkirmishGameMode]"
    echo "Mutators=${SS_MUTATORS_SKIRMISH}"
  else
    echo
    echo "[/Script/Insurgency.INSSkirmishGameMode]"
  fi
} > "${GAMEINI}"

# ─────────────────────────────────────────
# 8) Construction URL minimale
# ─────────────────────────────────────────
LAUNCH_URL="${MAP_ASSET}?Scenario=${SS_SCENARIO}"
if [[ "${scenario_mode}" == "SKIRMISH" && -n "${SS_MUTATORS_SKIRMISH}" && "${SS_MUTATORS_SKIRMISH}" =~ (^|,)\ *AiModifier\ *(,|$) && -n "${AIMOD_URL_ARGS}" ]]; then
  LAUNCH_URL="${LAUNCH_URL}?Mutators=AiModifier?${AIMOD_URL_ARGS}"
fi

# ─────────────────────────────────────────
# 9) XP flags
# ─────────────────────────────────────────
XP_ARGS=()
if [ -n "${GSLT_TOKEN}" ] && [ -n "${GAMESTATS_TOKEN}" ] && [ -z "${RCON_PASSWORD}" ]; then
  XP_ARGS+=( "-GSLTToken=${GSLT_TOKEN}" "-GameStatsToken=${GAMESTATS_TOKEN}" )
fi

# ─────────────────────────────────────────
# 10) Lancement
# ─────────────────────────────────────────
cd "${GAMEDIR}/Insurgency/Binaries/Linux" || exit 1
RCON_ARGS=()
[ -n "${RCON_PASSWORD}" ] && RCON_ARGS+=("-Rcon" "-RconPassword=${RCON_PASSWORD}")

exec ./InsurgencyServer-Linux-Shipping \
  "${LAUNCH_URL}" \
  -hostname="${SS_HOSTNAME}" \
  -Port="${PORT}" -QueryPort="${QUERYPORT}" -BeaconPort="${BEACONPORT}" \
  -AdminList="Admins" \
  -log \
  ${EXTRA_SERVER_ARGS} \
  "${XP_ARGS[@]}" \
  "${RCON_ARGS[@]}"

  ${EXTRA_SERVER_ARGS} \
  "${XP_ARGS[@]}" \
  "${RCON_ARGS[@]}"
