FROM debian:bookworm-slim

# Variables globales
ENV STEAMCMDDIR=/home/steam/steamcmd \
    GAMEDIR=/opt/sandstorm \
    APPID=581330

# Dépendances minimales
RUN apt-get update && apt-get install -y \
    lib32gcc-s1 \
    lib32stdc++6 \
    wget \
    curl \
    unzip \
    ca-certificates \
    locales \
    && rm -rf /var/lib/apt/lists/*

# Utilisateur non-root
RUN useradd -m steam && mkdir -p ${GAMEDIR} ${STEAMCMDDIR} && \
    chown -R steam:steam /home/steam ${GAMEDIR}

USER steam
WORKDIR /home/steam

# Installer SteamCMD
RUN wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz -O steamcmd.tar.gz \
    && mkdir -p ${STEAMCMDDIR} \
    && tar -xvzf steamcmd.tar.gz -C ${STEAMCMDDIR} \
    && rm steamcmd.tar.gz

# Copier entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR ${GAMEDIR}
VOLUME ["${GAMEDIR}"]

# Ports : Game / Query / Beacon / RCON
EXPOSE 27102/udp 27131/udp 15000/udp 27015/tcp

ENTRYPOINT ["/entrypoint.sh"]
