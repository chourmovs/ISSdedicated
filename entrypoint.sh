#!/bin/bash
set -euo pipefail

echo "▶️ Starting Insurgency Sandstorm Dedicated Server..."

PORT=${PORT:-27102}
QUERYPORT=${QUERYPORT:-27131}
BEACONPORT=${BEACONPORT:-15000}
RCON_PASSWORD=${RCON_PASSWORD:-"ChangeMe!"}
AUTO_UPDATE=${AUTO_UPDATE:-1}
STEAM_USER=${STEAM_USER:-anonymous}
STEAM_PASS=${STEAM_PASS:-""}

echo "  PORT=$PORT | QUERYPORT=$QUERYPORT | BEACONPORT=$BEACONPORT"
echo "  RCON_PASSWORD=$RCON_PASSWORD | AUTO_UPDATE=$AUTO_UPDATE"

STEAMCMD="/home/steam/steamcmd/steamcmd.sh"
GAME_DIR="/opt/sandstorm"
CONFIG_DIR="$GAME_DIR/Insurgency/Config"
SAVED_DIR="$GAME_DIR/Insurgency/Saved"

# ──────────────────────────────
# SteamCMD Update
# ──────────────────────────────
if [ "$AUTO_UPDATE" = "1" ]; then
  echo "📥 Updating server via SteamCMD..."
  if ! "$STEAMCMD" \
      +force_install_dir "$GAME_DIR" \
      +login "$STEAM_USER" "$STEAM_PASS" \
      +app_update 581330 validate \
      +quit; then
    echo "⚠️ validate failed, retrying without validate..."
    "$STEAMCMD" \
      +force_install_dir "$GAME_DIR" \
      +login "$STEAM_USER" "$STEAM_PASS" \
      +app_update 581330 \
      +quit
  fi
fi

# ──────────────────────────────
# Config files bootstrap
# ──────────────────────────────
mkdir -p "$CONFIG_DIR/LinuxServer"
mkdir -p "$SAVED_DIR/Logs"

if [ ! -f "$CONFIG_DIR/LinuxServer/Game.ini" ]; then
  echo "⚙️  Creating default Game.ini..."
  cat > "$CONFIG_DIR/LinuxServer/Game.ini" <<EOF
[/Script/Insurgency.INSGameMode]
bKillFeed=True
bEnableHud=True
EOF
fi

if [ ! -f "$CONFIG_DIR/MapCycle.txt" ]; then
  echo "⚙️  Creating default MapCycle.txt..."
  cat > "$CONFIG_DIR/MapCycle.txt" <<EOF
Scenario_Refinery_Checkpoint_Security
Scenario_Crossing_Checkpoint_Insurgents
EOF
fi

# ──────────────────────────────
# Run server
# ──────────────────────────────
cd "$GAME_DIR"

exec ./Insurgency/Binaries/Linux/InsurgencyServer-Linux-Shipping \
  "Oilfield?Scenario=Scenario_Refinery_Checkpoint_Security" \
  -Port="$PORT" \
  -QueryPort="$QUERYPORT" \
  -BeaconPort="$BEACONPORT" \
  -log \
  -hostname="chourmovs ISS" \
  -Rcon \
  -RconPassword="$RCON_PASSWORD"
