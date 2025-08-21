#!/usr/bin/env bash
set -euo pipefail

STEAMCMDDIR="${STEAMCMDDIR:-/opt/steamcmd}"
SANDSTORM_ROOT="${SANDSTORM_ROOT:-/opt/sandstorm}"
APP_BIN="${SANDSTORM_ROOT}/Insurgency/Binaries/Linux/InsurgencyServer-Linux-Shipping"

# Mise à jour/Installation si demandé
if [[ "${AUTO_UPDATE:-1}" == "1" ]]; then
  "${STEAMCMDDIR}/steamcmd.sh" +login anonymous \
    +force_install_dir "${SANDSTORM_ROOT}" \
    +app_update "${STEAMAPPID:-581330}" validate +quit
fi

# S’assurer que les fichiers de conf existent (si volume vierge)
GAME_INI="${SANDSTORM_ROOT}/Insurgency/Saved/Config/LinuxServer/Game.ini"
MAPCYCLE_TXT="${SANDSTORM_ROOT}/Insurgency/Config/Server/MapCycle.txt"

[[ -f "${GAME_INI}" ]] || cp -f "${SANDSTORM_ROOT}/Insurgency/Saved/Config/LinuxServer/Game.ini" "${GAME_INI}"
[[ -f "${MAPCYCLE_TXT}" ]] || cp -f "${SANDSTORM_ROOT}/Insurgency/Config/Server/MapCycle.txt" "${MAPCYCLE_TXT}"

# Patch dynamique de Game.ini selon variables d'env
# (on remplace les valeurs clés si présentes)
sed -i "s/^FriendlyBotQuota=.*/FriendlyBotQuota=${FRIENDLY_BOT_QUOTA:-6}/" "${GAME_INI}" || true
sed -i "s/^MinimumEnemies=.*/MinimumEnemies=${MIN_ENEMIES:-10}/" "${GAME_INI}" || true
sed -i "s/^MaximumEnemies=.*/MaximumEnemies=${MAX_ENEMIES:-24}/" "${GAME_INI}" || true

# Lancement
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
