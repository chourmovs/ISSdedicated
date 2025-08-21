FROM debian:bullseye-slim

# Préparer environnement
RUN apt-get update && apt-get install -y \
    lib32gcc-s1 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Créer user non-root
RUN useradd -m steam

# Installer steamcmd
RUN mkdir -p /home/steam/steamcmd && \
    cd /home/steam/steamcmd && \
    curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    | tar -xz && \
    chown -R steam:steam /home/steam

USER steam
WORKDIR /home/steam

# Variables par défaut
ENV GAMEDIR=/opt/sandstorm \
    STEAMCMDDIR=/home/steam/steamcmd \
    APPID=581330

# Copier entrypoint
COPY --chown=steam:steam entrypoint.sh /home/steam/entrypoint.sh
RUN chmod +x /home/steam/entrypoint.sh

# Créer dossier jeu
RUN mkdir -p ${GAMEDIR}

# Exposer ports
EXPOSE 27102/udp 27131/udp 15000/udp 27015/tcp

# Volumes (configs persistants)
VOLUME ["${GAMEDIR}"]

# Entrypoint
ENTRYPOINT ["/home/steam/entrypoint.sh"]
