# ──────────────────────────────
# Dockerfile Insurgency Sandstorm
# ──────────────────────────────
FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    APPID=581330 \
    STEAMCMDDIR=/home/steam/steamcmd \
    GAMEDIR=/opt/sandstorm \
    SS_ENABLE_STATS=1 \
    SS_MODS="" \
    SS_MUTATORS="" \
    SS_MUTATOR_URL_ARGS="" \
    EXTRA_SERVER_ARGS=""

RUN apt-get update && apt-get install -y \
    locales \
    lib32gcc-s1 \
    lib32stdc++6 \
    libtinfo6 \
    libcurl4 \
    libcurl3-gnutls \
    curl \
    wget \
    tar \
    ca-certificates \
    tini \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

RUN useradd -m steam && mkdir -p ${GAMEDIR} && chown -R steam:steam ${GAMEDIR}
USER steam
WORKDIR /home/steam

RUN mkdir -p ${STEAMCMDDIR} && cd ${STEAMCMDDIR} \
    && wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    && tar -xvzf steamcmd_linux.tar.gz \
    && rm steamcmd_linux.tar.gz \
    && chmod +x ${STEAMCMDDIR}/steamcmd.sh \
    && chmod +x ${STEAMCMDDIR}/linux32/steamcmd

VOLUME ["${GAMEDIR}", "/home/steam/Steam"]

COPY --chown=steam:steam entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 27102/udp 27131/udp 15000/udp 27015/tcp
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
