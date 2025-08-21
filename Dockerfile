FROM debian:bookworm-slim

# ───────────────────────────────
# Préparer environnement
# ───────────────────────────────
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    STEAMCMDDIR=/home/steam/steamcmd \
    SERVERDIR=/opt/sandstorm

RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      locales \
      curl \
      net-tools \
      iproute2 \
      tini \
      lib32gcc-s1 \
      libc6:i386 \
      libstdc++6:i386 \
      zlib1g:i386 \
      libnss3:i386 \
      libcurl4:i386 \
 && locale-gen en_US.UTF-8 \
 && useradd -m steam \
 && mkdir -p ${STEAMCMDDIR} ${SERVERDIR} \
 && chown -R steam:steam /home/steam ${SERVERDIR} \
 && rm -rf /var/lib/apt/lists/*

USER steam
WORKDIR /home/steam

# ───────────────────────────────
# Installer SteamCMD
# ───────────────────────────────
RUN curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
    | tar -xz -C ${STEAMCMDDIR} \
 && chmod +x ${STEAMCMDDIR}/steamcmd.sh \
 && chmod +x ${STEAMCMDDIR}/linux32/steamcmd

# ───────────────────────────────
# Copier entrypoint
# ───────────────────────────────
COPY --chown=steam:steam entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR ${SERVERDIR}

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
