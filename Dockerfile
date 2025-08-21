# Dockerfile (fix permissions + robuster curl)
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

# Paquets (inclut tar, curl, certificats, 32-bit libs)
RUN dpkg --add-architecture i386 && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl lib32gcc-s1 lib32stdc++6 \
      tini python3 procps bash \
    && rm -rf /var/lib/apt/lists/*

# Crée les dossiers /opt en root puis change propriétaire
RUN mkdir -p ${STEAMCMDDIR} ${SANDSTORM_ROOT} && \
    useradd -ms /bin/bash steam && \
    chown -R steam:steam ${STEAMCMDDIR} ${SANDSTORM_ROOT}

# Télécharge SteamCMD en root (écriture OK) puis chown pour steam
RUN set -eux; \
    cd ${STEAMCMDDIR}; \
    curl -fL --retry 5 --retry-delay 2 \
         https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz; \
    chown -R steam:steam ${STEAMCMDDIR}

# Passe en user non-root pour la suite
USER steam
WORKDIR /home/steam

# Pré-install serveur (non bloquant en CI si le CDN flanche ponctuellement)
RUN ${STEAMCMDDIR}/steamcmd.sh +login anonymous \
    +force_install_dir ${SANDSTORM_ROOT} \
    +app_update ${STEAMAPPID} validate +quit || true

# Arbo configs
RUN mkdir -p ${SANDSTORM_ROOT}/Insurgency/Saved/Config/LinuxServer \
             ${SANDSTORM_ROOT}/Insurgency/Config/Server

# Fichiers du projet
COPY --chown=steam:steam entrypoint.sh /entrypoint.sh
COPY --chown=steam:steam Game.ini ${SANDSTORM_ROOT}/Insurgency/Saved/Config/LinuxServer/Game.ini
COPY --chown=steam:steam MapCycle.txt ${SANDSTORM_ROOT}/Insurgency/Config/Server/MapCycle.txt
RUN chmod +x /entrypoint.sh

EXPOSE 27102/udp 27131/udp 27015/tcp
VOLUME ["${SANDSTORM_ROOT}/Insurgency/Saved", "${SANDSTORM_ROOT}/Insurgency/Config"]

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
