# ──────────────────────────────
# Dockerfile : ISS Dedicated Server
# ──────────────────────────────
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Install deps (32-bit libs + utilitaires)
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
      lib32gcc-s1 lib32stdc++6 \
      ca-certificates curl locales \
      tini && \
    locale-gen en_US.UTF-8 && \
    useradd -m steam && \
    rm -rf /var/lib/apt/lists/*

# SteamCMD install
WORKDIR /home/steam
RUN mkdir -p /home/steam/steamcmd && \
    cd /home/steam/steamcmd && \
    curl -sSL https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz \
      | tar -xz

# Create Sandstorm dirs as root (⚠️ avant USER steam)
RUN mkdir -p /opt/sandstorm/Insurgency/Saved/Config/LinuxServer && \
    chown -R steam:steam /opt/sandstorm

# Switch to steam user
USER steam

# Copy entrypoint
COPY --chown=steam:steam entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /opt/sandstorm
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
