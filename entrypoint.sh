#!/usr/bin/env bash
set -euo pipefail

STEAMCMDDIR="${STEAMCMDDIR:-/opt/steamcmd}"
SANDSTORM_ROOT="${SANDSTORM_ROOT:-/opt/sandstorm}"
APP_BIN="${SANDSTORM_ROOT}/Insurgency/Binaries/Linux/InsurgencyServer-Linux-Shipping"

GAME_INI="${SANDSTORM_ROOT}/Insurgency/Saved/Config/LinuxServer/Game.ini"
MAPCYCLE_TXT="${SANDSTORM_ROOT}/Insurgency/Config/Server/MapCycle.txt"

# --- Secrets via Docker Swarm (si présents) : /run/secrets/<name> ---
read_secret_file() {
  local var="$1" file="$2"
  if [[ -z "${!var:-}" && -f "$file" ]]; then
    export "$var"="$(tr -d '\r' < "$file")"
  fi
}
read_secret_file STEAM_USER /run/secrets/steam_user
read_secret_file STEAM_PASS /run/secrets/steam_pass
read_secret_file STEAM_2FA  /run/secrets/steam_2fa

# --- Dépose config par défaut si volume vierge (si tu as copié des defaults/) ---
if [[ ! -f "$GAME_INI" && -f "/defaults/Game.ini" ]]; then
  cp -f /defaults/Game.ini "$GAME_INI"
fi
if [[ ! -f "$MAPCYCLE_TXT" && -f "/defaults/MapCycle.txt" ]]; then
  cp -f /defaults/MapCycle.txt "$MAPCYCLE_TXT"
fi

# --- Patch dynamique selon env ---
sed -i "s/^FriendlyBotQuota=.*/FriendlyBotQuota=${FRIENDLY_BOT_QUOTA:-6}/" "$GAME_INI" || true
sed -i "s/^MinimumEnemies=.*/MinimumEnemies=${MIN_ENEMIES:-10}/" "$GAME_INI" || true
sed -i "s/^MaximumEnemies=.*/MaximumEnemies=${MAX_ENEMIES:-24}/" "$GAME_INI" || true

# --- Construction des arguments de login SteamCMD ---
LOGIN_ARGS=()
if [[ -n "${STEAM_USER:-}" && -n "${STEAM_PASS:-}" ]]; then
  # 2FA optionnel : +login user pass [code]
  if [[ -n "${STEAM_2FA:-}" ]]; then
    LOGIN_ARGS=(+login "${STEAM_USER}" "${STEAM_PASS}" "${STEAM_2FA}")
  else
    LOGIN_ARGS=(+login "${STEAM_USER}" "${STEAM_PASS}")
  fi
else
  LOGIN_ARGS=(+login anonymous)
fi

# --- Update/Install (à chaque start si AUTO_UPDATE=1) ---
if [[ "${AUTO_UPDATE:-1}" == "1" ]]; then
  # Force la plateforme Linux et coupe en cas d’échec
  "${STEAMCMDDIR}/steamcmd.sh" +@sSteamCmdForcePlatformType linux +@ShutdownOnFailedCommand 1 +@NoPromptForPassword 1 \
    "${LOGIN_ARGS[@]}" \
    +force_install_dir "${SANDSTORM_ROOT}" \
    +app_update "${STEAMAPPID:-581330}" validate \
    +quit
fi

# --- Checks utiles (log informatif) ---
du -sh "${SANDSTORM_ROOT}" || true
ls -1 "${SANDSTORM_ROOT}/Insurgency/Content/Paks" 2>/dev/null | wc -l || true

# --- Lancement serveur ---
cd "${SANDSTORM_ROOT}/Insurgency/Binaries/Linux"

PORT_ARG="-Port=${SERVER_PORT:-27102}"
QUERY_ARG="-QueryPort=${QUERY_PORT:-27131}"
RCON_FLAGS="-Rcon -RconPassword=${RCON_PASSWORD:-changeme} -RconListenPort=${RCON_PORT:-27015}"
MAPCYCLE_ARG="-MapCycle=MapCycle"
MAXP_ARG="-MaxPlayers=${MAX_PLAYERS:-8}"

SCENARIO_PATH="${SCENARIO:-Scenario_Oilfield_Checkpoint_Security}"
MAPNAME="${MAP:-Oilfield}"

echo ">>> Starting Insurgency: Sandstorm server"
echo "    Map: ${MAPNAME} / Scenario: ${SCENARIO_PATH}"
echo "    Ports: game=${SERVER_PORT} (udp), query=${QUERY_PORT} (udp), rcon=${RCON_PORT} (tcp)"

exec "${APP_BIN}" \
  "${MAPNAME}?Scenario=${SCENARIO_PATH}" \
  ${MAPCYCLE_ARG} ${PORT_ARG} ${QUERY_ARG} ${MAXP_ARG} \
  -log ${RCON_FLAGS}
