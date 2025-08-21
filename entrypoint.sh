#!/bin/bash
set -e

echo "▶️ Starting Insurgency Sandstorm Dedicated Server..."

# Variables par défaut
PORT=${PORT:-27102}
QUERYPORT=${QUERYPORT:-27131}
BEACONPORT=${BEACONPORT:-15000}
MAP=${MAP:-Farmhouse}
MODE=${MODE:-Checkpoint}
SCENARIO=${SCENARIO:-Scenario_Farmhouse_Checkpoint_Security}
RCON_PASSWORD=${RCON_PASSWORD:-changeme}
FRIENDLY_BOT_QUOTA=${FRIENDLY_BOT_QUOTA:-6}
MIN_ENEMIES=${MIN_ENEMIES:-10}
MAX_ENEMIES=${MAX_ENEMIES:-24}
AUTO_UPDATE=${AUTO_UPDATE:-1}

echo "  PORT=$PORT | QUERYPORT=$QUERYPORT | BEACONPORT=$BEACONPORT"
echo "  RCON_PASSWORD=******** | AUTO_UPDATE=$AUTO_UPDATE"
echo "  MAP=$MAP | SCENARIO=$SCENARIO | MODE=$MODE"

# 📥 Mise à jour auto si demandé
if [ "$AUTO_UPDATE" = "1" ]; then
  echo "📥 Updating server via SteamCMD..."
  ${STEAMCMDDIR}/steamcmd.sh +@sSteamCmdForcePlatformType linux \
    +login anonymous \
    +force_install_dir ${GAMEDIR} \
    +app_update 581330 validate \
    +quit || echo "⚠️ SteamCMD update failed (continuing if server already present)"
fi

# 📝 Config Game.ini
cat > ${GAMEDIR}/Insurgency/Saved/Config/LinuxServer/Game.ini <<EOF
[/Script/Insurgency.INSGameMode]
bAllowFriendlyFire=False
GameStartingIntermissionTime=10
RoundLimit=1

[/Script/Insurgency.INSCheckpointGameMode]
bBots=True
FriendlyBotQuota=${FRIENDLY_BOT_QUOTA}
MinimumEnemies=${MIN_ENEMIES}
MaximumEnemies=${MAX_ENEMIES}
bBotsUseVehicleInsertion=True
SoloEnemies=0
RespawnDPR=0.5
DefendCaptureTime=45

[/Script/Insurgency.INSCoopMode]
bKickIdleSpectators=True

[Rcon]
bEnabled=True
Password=${RCON_PASSWORD}
ListenPort=27015
EOF

# 🗺️ MapCycle
cat > ${GAMEDIR}/Insurgency/Config/Server/MapCycle.txt <<EOF
$SCENARIO
EOF

# 🚀 Lancer le serveur
exec ${GAMEDIR}/Insurgency/Binaries/Linux/InsurgencyServer-Linux-Shipping \
  "${MAP}?Scenario=${SCENARIO}?Game=${MODE}" \
  -Port=${PORT} -QueryPort=${QUERYPORT} -BeaconPort=${BEACONPORT} \
  -log
