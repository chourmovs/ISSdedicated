# Dockerfile
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    STEAMCMDDIR=/opt/steamcmd \
    SANDSTORM_ROOT=/opt/sandstorm \
    STEAMAPPID=581330 \
    # Defaults (surchargés par -e … au run)
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
    # update à chaque démarrage (1 = oui)
    AUTO_UPDATE=1

# Dépendances 32 bits + outils
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl lib32gcc-s1 lib32stdc++6 \
    tini python3 procps bash \
    && rm -rf /var/lib/apt/lists/*

# steam user non root
RUN useradd -ms /bin/bash steam
USER steam
WORKDIR /home/steam

# Installer SteamCMD
RUN mkdir -p ${STEAMCMDDIR} ${SANDSTORM_ROOT} && \
    cd ${STEAMCMDDIR} && \
    curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz | tar -xz

# Pré-install (couche de build) — non bloquant si l’app n’existe pas encore
RUN ${STEAMCMDDIR}/steamcmd.sh +login anonymous \
    +force_install_dir ${SANDSTORM_ROOT} \
    +app_update ${STEAMAPPID} validate +quit || true

# Arbo config (persistante)
RUN mkdir -p ${SANDSTORM_ROOT}/Insurgency/Saved/Config/LinuxServer \
             ${SANDSTORM_ROOT}/Insurgency/Config/Server

# Copie de l’entrypoint et des templates de conf
COPY --chown=steam:steam entrypoint.sh /entrypoint.sh
COPY --chown=steam:steam Game.ini ${SANDSTORM_ROOT}/Insurgency/Saved/Config/LinuxServer/Game.ini
COPY --chown=steam:steam MapCycle.txt ${SANDSTORM_ROOT}/Insurgency/Config/Server/MapCycle.txt

# Exposer ports
#  - SERVER_PORT/UDP : jeu
#  - QUERY_PORT/UDP  : query
#  - RCON_PORT/TCP   : RCON
EXPOSE 27102/udp 27131/udp 27015/tcp

# Volumes (configs + sauvegardes)
VOLUME ["${SANDSTORM_ROOT}/Insurgency/Saved", "${SANDSTORM_ROOT}/Insurgency/Config"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
