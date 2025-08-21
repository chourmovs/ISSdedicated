#!/usr/bin/env bash
set -euo pipefail

# Defaults
PORT="${PORT:-27102}"
QUERYPORT="${QUERYPORT:-27132}"
BEACONPORT="${BEACONPORT:-15000}"
RCON_PASSWORD="${RCON_PASSWORD:-ChangeMe!}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
STEAM_USER="${STEAM_USER:-anonymous}"
STEAM_PASS="${STEAM_PASS:-}"
AUTO_UPDATE="${AUTO_UPDATE:-1}"

echo "▶️ Starting Insurgency Sandstorm Dedicated Server..."
echo "  PORT=$PORT | QUERYPORT=$QUERYPORT | BEACONPORT=$BEACONPORT"
echo "  RCON_PASSWORD=${RCON_PASSWORD:+********} | AUTO_UPDATE=$AUTO_UPDATE"

if [[ "$AUTO_UPDATE" == "1" ]]; then
  echo "📥 Updating server via SteamCMD..."
  if ! /home/steam/steamcmd/steamcmd.sh \
       +@NoPromptForPassword 1 \
       +force_install_dir /opt/sandstorm \
       +login "$STEAM_USER" "$STEAM_PASS" \
       +app_update 581330 validate +quit; then
    echo "⚠️ steamcmd.sh non exécutable ? Tentative via bash..."
    bash /home/steam/steamcmd/steamcmd.sh \
       +@NoPromptForPassword 1 \
       +force_install_dir /opt/sandstorm \
       +login "$STEAM_USER" "$STEAM_PASS" \
       +app_update 581330 validate +quit
  fi
fi

# Minimal Game.ini config injection if missing
INI="/opt/sandstorm/Insurgency/Saved/Config/LinuxServer/Game.ini"
if [[ ! -f "$INI" ]]; then
  echo "⚙️ Creating default Game.ini..."
  cat >"$INI" <<EOF
[/Script/Insurgency.INSGameInstance]
RconEnabled=True
RconPassword=$RCON_PASSWORD
RconListenPort=27015
EOF
fi

# Default MapCycle if missing
MAPCYCLE="/opt/sandstorm/Insurgency/Saved/Config/LinuxServer/MapCycle.txt"
if [[ ! -f "$MAPCYCLE" ]]; then
  echo "⚙️ Creating default MapCycle.txt..."
  cat >"$MAPCYCLE" <<EOF
Scenario=Scenario_Farmhouse_Checkpoint_Security
Scenario=Scenario_Summit_Checkpoint_Security
Scenario=Scenario_Refinery_Checkpoint_Security
EOF
fi

# Launch server
exec /opt/sandstorm/Insurgency/Binaries/Linux/InsurgencyServer-Linux-Shipping \
  "Farmhouse?Scenario=Scenario_Farmhouse_Checkpoint_Security?MaxPlayers=16" \
  -hostname="chourmovs ISS" \
  -Port=$PORT -QueryPort=$QUERYPORT -BeaconPort=$BEACONPORT \
  -log $EXTRA_ARGS
