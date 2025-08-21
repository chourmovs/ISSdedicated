# ───────────────────────────────
# Dockerfile Insurgency: Sandstorm Dedicated
# ───────────────────────────────
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    STEAMCMDDIR=/opt/steamcmd \
    SANDSTORM_ROOT=/opt/sandstorm \
    STEAMAPPID=581330 \
    SERVER_PORT=27102 \
    QUERY_PORT=27131 \
    RCON_PORT=27015 \
    MAX_PLAYERS=8 \
    RCON_PASSWORD=changeme \
    MAP="Oilfield" \
    SCENARIO="Scenario_Oilfield_Checkpoint_Security" \
    FRIENDLY_BOT_QUOTA=6 \
    MIN_ENEMIES=10 \
    MAX_ENEMIES=24 \
    AUTO_UPDATE=1

# Dépendances (32 bits + outils)
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl lib32gcc-s1 lib32stdc++6 \
      tini python3 procps bash \
    && rm -rf /var/lib/apt/lists/*

# Création des répertoires et utilisateur
RUN mkdir -p ${STEAMCMDDIR} ${SANDSTORM_ROOT} /defaults && \
    useradd -ms /bin/bash steam && \
    chown -R steam:steam ${STEAMCMDDIR} ${SANDSTORM_ROOT} /defaults

# Téléchargement SteamCMD en root puis chown
RUN set -eux; \
    cd ${STEAMCMDDIR}; \
    curl -fL --retry 5 --retry-delay 2 \
         https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz; \
    chown -R steam:steam ${STEAMCMDDIR}

# Passage en utilisateur non-root
USER steam
WORKDIR /home/steam

# Pré-install (non bloquante si réseau HS)
RUN ${STEAMCMDDIR}/steamcmd.sh +@sSteamCmdForcePlatformType linux +login anonymous \
    +force_install_dir ${SANDSTORM_ROOT} \
    +app_update ${STEAMAPPID} validate +quit || true

# Arborescence de config
RUN mkdir -p ${SANDSTORM_ROOT}/Insurgency/Saved/Config/LinuxServer \
             ${SANDSTORM_ROOT}/Insurgency/Config/Server

# Copie entrypoint + templates par défaut
COPY --chown=steam:steam entrypoint.sh /entrypoint.sh
COPY --chown=steam:steam Game.ini /defaults/Game.ini
COPY --chown=steam:steam MapCycle.txt /defaults/MapCycle.txt

# Pré-dépose (facultatif) : met aussi les fichiers initiaux
COPY --chown=steam:steam Game.ini ${SANDSTORM_ROOT}/Insurgency/Saved/Config/LinuxServer/Game.ini
COPY --chown=steam:steam MapCycle.txt ${SANDSTORM_ROOT}/Insurgency/Config/Server/MapCycle.txt

RUN chmod +x /entrypoint.sh

# Exposition des ports
EXPOSE 27102/udp 27131/udp 27015/tcp

# Volumes pour persistance
VOLUME ["${SANDSTORM_ROOT}/Insurgency/Saved", \
        "${SANDSTORM_ROOT}/Insurgency/Config", \
        "/home/steam/Steam"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
