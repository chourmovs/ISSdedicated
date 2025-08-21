#!/bin/bash
set -e

echo "▶️ Starting Insurgency Sandstorm Dedicated Server..."
echo "  PORT=${PORT:-27102} | QUERYPORT=${QUERYPORT:-27131} | BEACONPORT=${BEACONPORT:-15000}"
echo "  RCON_PASSWORD=${RCON_PASSWORD:-changeme} | AUTO_UPDATE=${AUTO_UPDATE:-1}"

# Dossiers configs et saves
mkdir -p ${SERVERDIR}/Insurgency/Config
mkdir -p ${SERVERDIR}/Insurgency/Saved

# Mise à jour si demandé
if [ "${AUTO_UPDATE}" = "1" ]; then
    echo "📥 Updating server via SteamCMD..."
    ${STEAMCMDDIR}/steamcmd.sh \
        +@sSteamCmdForcePlatformType linux \
        +login ${STEAM_USER:-anonymous} ${STEAM_PASS:-} ${STEAM_2FA:-} \
        +force_install_dir ${SERVERDIR} \
        +app_update 581330 validate \
        +quit || {
            echo "❌ SteamCMD update failed."
            exit 1
        }
fi

# Lancer serveur (il lira Game.ini et MapCycle.txt dans Config)
exec ${SERVERDIR}/Insurgency/Binaries/Linux/InsurgencyServer-Linux-Shipping \
    "Oilfield?Scenario=Scenario_Refinery_Checkpoint_Security" \
    -Port=${PORT:-27102} \
    -QueryPort=${QUERYPORT:-27131} \
    -BeaconPort=${BEACONPORT:-15000} \
    -hostname="${HOSTNAME:-chourmovs ISS}" \
    -log
