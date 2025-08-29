#!/bin/bash
set -eo pipefail

# ─────────────────────────────────────────
# 0) Chemins / base
# ─────────────────────────────────────────
GAMEDIR="${GAMEDIR:-/opt/sandstorm}"
CFGDIR="${CFGDIR:-${GAMEDIR}/Insurgency/Config/Server}"
GAMEINI="${GAMEINI:-${CFGDIR}/Game.ini}"
MAPCYCLE="${MAPCYCLE:-${CFGDIR}/MapCycle.txt}"
STEAMCMDDIR="${STEAMCMDDIR:-/home/steam/steamcmd}"
APPID="${APPID:-581330}"

AUTO_UPDATE="${AUTO_UPDATE:-1}"
PORT="${PORT:-27102}"
QUERYPORT="${QUERYPORT:-27131}"
BEACONPORT="${BEACONPORT:-15000}"

SS_HOSTNAME="${SS_HOSTNAME:-CHOURMOVS ISS • COOP}"
SS_MAXPLAYERS="${SS_MAXPLAYERS:-24}"

# Lancement par défaut (COOP)
SS_SCENARIO="${SS_SCENARIO:-Scenario_Farmhouse_Checkpoint_Security}"

# QoL / vote / timers
SS_KILL_FEED="${SS_KILL_FEED:-1}"
SS_KILL_CAMERA="${SS_KILL_CAMERA:-0}"
SS_VOICE_ENABLED="${SS_VOICE_ENABLED:-1}"
SS_FRIENDLY_FIRE_SCALE="${SS_FRIENDLY_FIRE_SCALE:-0.2}"
SS_ROUND_TIME="${SS_ROUND_TIME:-900}"
SS_POST_ROUND_TIME="${SS_POST_ROUND_TIME:-15}"
SS_VOTE_ENABLED="${SS_VOTE_ENABLED:-1}"
SS_VOTE_PERCENT="${SS_VOTE_PERCENT:-0.6}"

# Bots (COOP)
SS_BOTS_ENABLED="${SS_BOTS_ENABLED:-1}"
SS_BOT_NUM="${SS_BOT_NUM:-0}"
SS_BOT_QUOTA="${SS_BOT_QUOTA:-6.0}"
SS_BOT_DIFFICULTY="${SS_BOT_DIFFICULTY:-0.9}"
SS_FRIENDLY_BOT_QUOTA="${SS_FRIENDLY_BOT_QUOTA:-0}"
SS_MIN_ENEMIES="${SS_MIN_ENEMIES:-10}"
SS_MAX_ENEMIES="${SS_MAX_ENEMIES:-10}"

# XP / Stats
SS_ENABLE_STATS="${SS_ENABLE_STATS:-1}"
GSLT_TOKEN="${GSLT_TOKEN:-}"
GAMESTATS_TOKEN="${GAMESTATS_TOKEN:-}"
RCON_PASSWORD="${RCON_PASSWORD:-}"

# Workshop / Mutators
SS_MODS="${SS_MODS:-}"            # "1141916,12345"
SS_MUTATORS="${SS_MUTATORS:-}"    # "AiModifier,..."
EXTRA_SERVER_ARGS="${EXTRA_SERVER_ARGS:-}"

echo "────────────────────────────────────────"
echo "▶️  Boot Sandstorm | ${SS_HOSTNAME}"
echo "   Scenario=${SS_SCENARIO} | Max=${SS_MAXPLAYERS}"
echo "────────────────────────────────────────"

# ─────────────────────────────────────────
# 1) FS
# ─────────────────────────────────────────
mkdir -p "${CFGDIR}" "$(dirname "${MAPCYCLE}")"

# ─────────────────────────────────────────
# 2) SteamCMD update (tolérant)
# ─────────────────────────────────────────
if [ "${AUTO_UPDATE}" = "1" ]; then
  echo "📥 SteamCMD updating app ${APPID}..."
  "${STEAMCMDDIR}/steamcmd.sh" +@sSteamCmdForcePlatformType linux \
    +force_install_dir "${GAMEDIR}" +login anonymous +app_update "${APPID}" validate +quit \
    || echo "⚠️ SteamCMD failed (continuing anyway)"
fi

# ─────────────────────────────────────────
# 3) MapCycle (COOP par défaut, propre)
# ─────────────────────────────────────────
if [ -n "${SS_MAPCYCLE}" ]; then
  echo "${SS_MAPCYCLE}" | tr '\r' '\n' | sed '/^\s*$/d' > "${MAPCYCLE}"
else
  cat > "${MAPCYCLE}" <<EOF
Scenario_Farmhouse_Checkpoint_Security
Scenario_Crossing_Checkpoint_Security
Scenario_Hideout_Checkpoint_Security
Scenario_Refinery_Checkpoint_Security
Scenario_Summit_Checkpoint_Security
Scenario_Hillside_Checkpoint_Security
EOF
fi
echo "🗺️  MapCycle → ${MAPCYCLE}"

# ─────────────────────────────────────────
# 4) Game.ini (valeurs réelles)
# ─────────────────────────────────────────
{
  cat <<EOF
; ------------------------------------------------------------------
; Insurgency Sandstorm - Game.ini (generated)
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
bDisableStats=$([ "${SS_ENABLE_STATS}" = "1" ] && echo "False" || echo "True")

[/Script/Insurgency.INSMultiplayerMode]
bMapVoting=True
bUseMapCycle=True
EOF

  # Mods Workshop
  if [ -n "${SS_MODS}" ]; then
    IFS=',' read -ra _mods <<< "${SS_MODS}"
    for mid in "${_mods[@]}"; do
      mid_trim="$(echo "$mid" | xargs)"
      [ -n "${mid_trim}" ] && echo "Mods=${mid_trim}"
    done
  fi

  # Mutators (déclaration)
  [ -n "${SS_MUTATORS}" ] && echo "Mutators=${SS_MUTATORS}"

  cat <<EOF

[/Script/Insurgency.INSCoopMode]
bAutoBalanceTeams=False
AutoBalanceDelay=10

[/Script/Insurgency.INSCheckpointGameMode]
bBots=${SS_BOTS_ENABLED}
NumBots=${SS_BOT_NUM}
BotQuota=${SS_BOT_QUOTA}
BotDifficulty=${SS_BOT_DIFFICULTY}
FriendlyBotQuota=${SS_FRIENDLY_BOT_QUOTA}
MinimumEnemies=${SS_MIN_ENEMIES}
MaximumEnemies=${SS_MAX_ENEMIES}

[/Script/Insurgency.INSOutpostGameMode]
[/Script/Insurgency.INSSurvivalGameMode]
EOF
} > "${GAMEINI}"
echo "📝 Game.ini written."

# ─────────────────────────────────────────
# 5) AiModifier → URL (toutes les CVAR)
# ─────────────────────────────────────────
AIMOD_ARGS=()
add_arg() { local k="$1"; local v="$2"; [ -n "${v:-}" ] && AIMOD_ARGS+=("${k}=${v}"); }

# (👉 Ici toutes les CVAR AiModifier comme détaillé précédemment)
# Exemple :
add_arg "AIModifier.Difficulty" "${AIMOD_DIFFICULTY}"
add_arg "AIModifier.Accuracy" "${AIMOD_ACCURACY}"
add_arg "AIModifier.ReactionTime" "${AIMOD_REACTION}"
# … (toutes les autres catégories déjà listées) …

SS_MUTATOR_URL_ARGS=""
if [ ${#AIMOD_ARGS[@]} -gt 0 ]; then
  SS_MUTATOR_URL_ARGS="$(IFS='?'; echo "${AIMOD_ARGS[*]}")"
fi

# ─────────────────────────────────────────
# 6) Déduction du MAP_ASSET depuis SS_SCENARIO
# ─────────────────────────────────────────
scenario_core="$(echo "${SS_SCENARIO#Scenario_}" | cut -d'_' -f1)"
case "${scenario_core}" in
  Crossing)   MAP_ASSET="Canyon" ;;
  Hideout)    MAP_ASSET="Town" ;;
  Hillside)   MAP_ASSET="Sinjar" ;;
  Refinery)   MAP_ASSET="Oilfield" ;;
  *)          MAP_ASSET="${scenario_core}" ;;
esac

# ─────────────────────────────────────────
# 7) Construction URL de lancement
# ─────────────────────────────────────────
LAUNCH_URL="${MAP_ASSET}?Scenario=${SS_SCENARIO}?MaxPlayers=${SS_MAXPLAYERS}"
[ -n "${SS_MUTATORS}" ] && LAUNCH_URL="${LAUNCH_URL}?Mutators=${SS_MUTATORS}"
[ -n "${SS_MUTATOR_URL_ARGS}" ] && LAUNCH_URL="${LAUNCH_URL}?${SS_MUTATOR_URL_ARGS}"

echo "▶️  Launch URL: ${LAUNCH_URL}"

# XP flags
XP_ARGS=()
if [ -n "${GSLT_TOKEN}" ] && [ -n "${GAMESTATS_TOKEN}" ] && [ -z "${RCON_PASSWORD}" ]; then
  XP_ARGS+=( "-GSLTToken=${GSLT_TOKEN}" "-GameStatsToken=${GAMESTATS_TOKEN}" )
  echo "✨ XP enabled."
else
  echo "ℹ️ XP disabled (tokens missing or RCON set)."
fi

# RCON flags
RCON_ARGS=()
[ -n "${RCON_PASSWORD}" ] && RCON_ARGS+=( "-Rcon" "-RconPassword=${RCON_PASSWORD}" )

# ─────────────────────────────────────────
# 8) Exécution finale
# ─────────────────────────────────────────
cd "${GAMEDIR}/Insurgency/Binaries/Linux" || exit 1

exec ./InsurgencyServer-Linux-Shipping \
  "${LAUNCH_URL}" \
  -hostname="${SS_HOSTNAME}" \
  -Port="${PORT}" -QueryPort="${QUERYPORT}" -BeaconPort="${BEACONPORT}" \
  -AdminList=Admins \
  -log \
  "${XP_ARGS[@]}" \
  "${RCON_ARGS[@]}" \
  ${EXTRA_SERVER_ARGS}
