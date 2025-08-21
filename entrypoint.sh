#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Lecture secrets si montés par Swarm/K8s
# ──────────────────────────────────────────────
read_secret() {
  local var="$1"
  local file_var="${var}_FILE"
  if [[ -n "${!file_var:-}" ]] && [[ -f "${!file_var}" ]]; then
    export "$var"="$(< "${!file_var}")"
  fi
}

for s in STEAM_USER STEAM_PASS STEAM_2FA RCON_PASSWORD; do
  read_secret "$s"
done

# ──────────────────────────────────────────────
# Défauts variables
# ──────────────────────────────────────────────
STEAMCMDDIR="${STEAMCMDDIR:-/opt/steamcmd}"
SANDSTORM_ROOT="${SANDSTORM_ROOT:-/opt/sandstorm}"
STEAMAPPID="${STEAMAPPID:-581330}"
AUTO_UPDATE="${AUTO_UPDATE:-1}"
ONE_TRY_ONLY="${ONE_TRY_ONLY:-1}"

# ──────────────────────────────────────────────
# Prépare les arguments de login Steam
# ──────────────────────────────────────────────
LOGIN_ARGS=()
if [[ -n "${STEAM_USER:-}" ]] && [[ -n "${STEAM_PASS:-}" ]]; then
  LOGIN_ARGS+=(+login "$STEAM_USER" "$STEAM_PASS")
  [[ -n "${STEAM_2FA:-}" ]] && LOGIN_ARGS+=(+set_steam_guard_code "$STEAM_2FA")
else
  LOGIN_ARGS+=(+login anonymous)
fi

# ──────────────────────────────────────────────
# SteamCMD install / update (1 seule tentative)
# ──────────────────────────────────────────────
if [[ "$AUTO_UPDATE" == "1" ]]; then
  echo ">>> SteamCMD: tentative unique d’installation/mise à jour…"

  STEAMCMD_CMD=(
    "${STEAMCMDDIR}/steamcmd.sh"
    +@sSteamCmdForcePlatformType linux
    +@NoPromptForPassword 1
    +@ShutdownOnFailedCommand 1
    "${LOGIN_ARGS[@]}"
    +force_install_dir "${SANDSTORM_ROOT}"
    +app_update "$STEAMAPPID" validate
    +quit
  )

  set +e
  tmp_log="$(mktemp)"
  "${STEAMCMD_CMD[@]}" | tee "$tmp_log"
  sc=$?
  set -e

  if [[ "$sc" -ne 0 ]]; then
    echo "!!! SteamCMD a échoué (exit=$sc)"
    if [[ "$ONE_TRY_ONLY" == "1" ]]; then
      echo "!!! ONE_TRY_ONLY=1 → arrêt du conteneur pour éviter tout retry bloquant"
      echo "    Dernières lignes SteamCMD :"
      tail -n 30 "$tmp_log" || true
      rm -f "$tmp_log"
      exit 90
    fi
  fi
  rm -f "$tmp_log"
fi

# ──────────────────────────────────────────────
# Lancement du serveur Insurgency Sandstorm
# ──────────────────────────────────────────────
echo ">>> Lancement du serveur Insurgency Sandstorm…"

cd "${SANDSTORM_ROOT}"
exec ./Insurgency/Binaries/Linux/InsurgencyServer-Linux-Shipping \
  "Scenario=Scenario_Crossing_Checkpoint" \
  -Port="${PORT:-27102}" \
  -QueryPort="${QUERYPORT:-27131}" \
  -log \
  -hostname="${HOSTNAME:-Sandstorm Docker Server}" \
  -Rcon \
  -RconPassword="${RCON_PASSWORD:-ChangeMe!}" \
  ${EXTRA_ARGS:-}
