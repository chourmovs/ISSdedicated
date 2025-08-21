FROM debian:bullseye-slim

LABEL maintainer="toi"

# Variables globales
ENV STEAMCMDDIR=/opt/steamcmd \
    GAMEDIR=/opt/sandstorm \
    PATH=$PATH:/opt/steamcmd

# Préparer système
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates locales curl wget unzip \
       lib32gcc-s1 lib32stdc++6 \
    && rm -rf /var/lib/apt/lists/*

# Locales
RUN sed -i 's/# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
    && locale-gen
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Créer utilisateur steam
RUN useradd -m steam

# Installer SteamCMD
RUN mkdir -p ${STEAMCMDDIR} \
    && chown -R steam:steam ${STEAMCMDDIR} \
    && su steam -c "curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
       | tar -xz -C ${STEAMCMDDIR}"

# Créer arborescence du serveur (avec droits steam)
RUN mkdir -p ${GAMEDIR}/Insurgency/Saved/Config/LinuxServer \
    ${GAMEDIR}/Insurgency/Config/Server \
    && chown -R steam:steam ${GAMEDIR}

# Copier entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 27102/udp 27131/udp 27102/tcp 15000/udp

WORKDIR ${GAMEDIR}
USER steam

ENTRYPOINT ["/entrypoint.sh"]
