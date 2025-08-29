#!/bin/bash
# ==================================================================
# Insurgency: Sandstorm Dedicated Server - EntryPoint (coop-first, safe)
# - XP classé (GSLT + GameStats, RCON vide)
# - Admins: Admins.txt + -AdminList
# - Mods (Workshop) chargés; Mutators actifs UNIQUEMENT en Skirmish
# - AiModifier: paramètres via URL UNIQUEMENT si Skirmish + AiModifier actif
# - MapCycle + déduction Asset depuis SCENARIO + anti-casse (fallback)
# - Whitelists Mods/Mutators (bots-only)
# - Logs détaillés + validations
# - AUCUN PRESET FORCÉ (tout par ENV)
# ==================================================================

set -eo pipefail

# ─────────────────────────────────────────
# 0) Variables / chemins (avec défauts)
# ─────────────────────────────────────────
GAMEDIR="${GAMEDIR:-/opt/sandstorm}"
CFGDIR="${CFGDIR:-${GAMEDIR}/Insurgency/Saved/Config/LinuxServer}"
GAMEINI="${GAMEINI:-${CFGDIR}/Game.ini}"
MAPCYCLE="${MAPCYCLE:-${CFGDIR}/MapCycle.txt}"
STEAMCMDDIR="${STEAMCMDDIR:-/home/steam/steamcmd}"
APPID="${APPID:-581330}"

AUTO_UPDATE="${AUTO_UPDATE:-1}"
PORT="${PORT:-27102}"
QUERYPORT="${QUERYPORT:-27131}"
BEACONPORT="${BEACONPORT:-15000}"
RCON_PASSWORD="${RCON_PASSWORD:-}"     # ← vide = XP classé possible
SS_HOSTNAME="${SS_HOSTNAME:-CHOURMOVS ISS • COOP}"
SS_MAXPLAYERS="${SS_MAXPLAYERS:-24}"

# Modes: Push/Firefight/Skirmish/Domination/Checkpoint/Outpost/Survival
SS_GAME_MODE="${SS_GAME_MODE:-Checkpoint}"
SS_MAP="${SS_MAP:-Farmhouse}"           # informatif
SS_SCENARIO="${SS_SCENARIO:-}"          # fallback plus bas
SS_MAPCYCLE="${SS_MAPCYCLE:-}"          # multi-lignes possibles

# Bots
SS_BOTS_ENABLED="${SS_BOTS_ENABLED:-1}"
SS_BOT_NUM="${SS_BOT_NUM:-0}"
SS_BOT_QUOTA="${SS_BOT_QUOTA:-1.0}"
SS_BOT_DIFFICULTY="${SS_BOT_DIFFICULTY:-0.8}"

# Auto-balance
SS_AUTO_BALANCE="${SS_AUTO_BALANCE:-False}"
SS_AUTO_BALANCE_DELAY="${SS_AUTO_BALANCE_DELAY:-10}"

# QOL / vote
SS_KILL_FEED="${SS_KILL_FEED:-1}"
SS_KILL_CAMERA="${SS_KILL_CAMERA:-0}"
SS_VOICE_ENABLED="${SS_VOICE_ENABLED:-1}"
SS_FRIENDLY_FIRE_SCALE="${SS_FRIENDLY_FIRE_SCALE:-0.2}"
SS_ROUND_TIME="${SS_ROUND_TIME:-900}"
SS_POST_ROUND_TIME="${SS_POST_ROUND_TIME:-15}"
SS_VOTE_ENABLED="${SS_VOTE_ENABLED:-1}"
SS_VOTE_PERCENT="${SS_VOTE_PERCENT:-0.6}"

# XP / Stats
SS_ENABLE_STATS="${SS_ENABLE_STATS:-1}"
GSLT_TOKEN="${GSLT_TOKEN:-}"
GAMESTATS_TOKEN="${GAMESTATS_TOKEN:-}"

# Mods (Workshop) & Mutators
SS_MODS="${SS_MODS:-}"                        # "1141916,12345"
SS_MUTATORS_SKIRMISH="${SS_MUTATORS_SKIRMISH:-}"  # "AiModifier,HeadshotOnly"
EXTRA_SERVER_ARGS="${EXTRA_SERVER_ARGS:-}"

# Admins
SS_ADMINS="${SS_ADMINS:-}"

# Options de verrouillage
SS_FORCE_COOP_ONLY="${SS_FORCE_COOP_ONLY:-0}"      # 1 = interdit Push/FF/Skirmish/DM
SS_VALIDATE_MAPCYCLE="${SS_VALIDATE_MAPCYCLE:-0}"  # 1 = nettoie MapCycle incompatible

# Whitelists (bots-only)
SS_MUTATOR_WHITELIST="${SS_MUTATOR_WHITELIST:-AiModifier}"
SS_ENFORCE_MUTATOR_WHITELIST="${SS_ENFORCE_MUTATOR_WHITELIST:-1}"
SS_MODS_WHITELIST="${SS_MODS_WHITELIST:-}"
SS_ENFORCE_MODS_WHITELIST="${SS_ENFORCE_MODS_WHITELIST:-0}"

# ─────────────────────────────────────────
# AiModifier placeholders (TOUS optionnels)
# ─────────────────────────────────────────
# 1) Skill de base
AIMOD_DIFFICULTY="${AIMOD_DIFFICULTY:-}"
AIMOD_ACCURACY="${AIMOD_ACCURACY:-}"
AIMOD_REACTION="${AIMOD_REACTION:-}"

# 2) Sight / vision
AIMOD_SIGHT_ALERT="${AIMOD_SIGHT_ALERT:-}"
AIMOD_SIGHT_IDLE="${AIMOD_SIGHT_IDLE:-}"
AIMOD_SIGHT_SMOKE="${AIMOD_SIGHT_SMOKE:-}"
AIMOD_SIGHT_SMOKE_EYE="${AIMOD_SIGHT_SMOKE_EYE:-}"
AIMOD_SIGHT_SMOKE_EYE_FRAC="${AIMOD_SIGHT_SMOKE_EYE_FRAC:-}"
AIMOD_MIN_LI_SEE="${AIMOD_MIN_LI_SEE:-}"
AIMOD_MIN_LI_NIGHT="${AIMOD_MIN_LI_NIGHT:-}"
AIMOD_LI_FULLY_VISIBLE="${AIMOD_LI_FULLY_VISIBLE:-}"
AIMOD_TIME_NOTICE_VISIB_MULT="${AIMOD_TIME_NOTICE_VISIB_MULT:-}"
AIMOD_MIN_LI_AFFECT_NV="${AIMOD_MIN_LI_AFFECT_NV:-}"
AIMOD_MIN_NV_STRENGTH="${AIMOD_MIN_NV_STRENGTH:-}"

# 3) Chances d’être spotté
AIMOD_CH_SPRINT_MULT="${AIMOD_CH_SPRINT_MULT:-}"
AIMOD_CH_MOVING_MULT="${AIMOD_CH_MOVING_MULT:-}"
AIMOD_CH_STAND_DIST="${AIMOD_CH_STAND_DIST:-}"
AIMOD_CH_STAND_CLOSE="${AIMOD_CH_STAND_CLOSE:-}"
AIMOD_CH_CROUCH_DIST="${AIMOD_CH_CROUCH_DIST:-}"
AIMOD_CH_CROUCH_CLOSE="${AIMOD_CH_CROUCH_CLOSE:-}"
AIMOD_CH_PRONE_DIST="${AIMOD_CH_PRONE_DIST:-}"
AIMOD_CH_PRONE_CLOSE="${AIMOD_CH_PRONE_CLOSE:-}"

# 4) Ouïe
AIMOD_HEAR_AWARE_RADIAL="${AIMOD_HEAR_AWARE_RADIAL:-}"
AIMOD_HEAR_AWARE_GUNSHOT="${AIMOD_HEAR_AWARE_GUNSHOT:-}"
AIMOD_HEAR_AWARE_SPRINT="${AIMOD_HEAR_AWARE_SPRINT:-}"
AIMOD_HEAR_AWARE_FOOT="${AIMOD_HEAR_AWARE_FOOT:-}"
AIMOD_HEAR_DIST_SPRINT="${AIMOD_HEAR_DIST_SPRINT:-}"
AIMOD_HEAR_DIST_RUN="${AIMOD_HEAR_DIST_RUN:-}"
AIMOD_HEAR_Z_MIN="${AIMOD_HEAR_Z_MIN:-}"
AIMOD_HEAR_Z_MAX="${AIMOD_HEAR_Z_MAX:-}"
AIMOD_HEAR_FENCED_MOD="${AIMOD_HEAR_FENCED_MOD:-}"

# 5) Vitesse de rotation
AIMOD_TURNSPD_MAX_ANGLE_TH="${AIMOD_TURNSPD_MAX_ANGLE_TH:-}"
AIMOD_TURNSPD_MIN_ANGLE_TH="${AIMOD_TURNSPD_MIN_ANGLE_TH:-}"
AIMOD_TURNSPD_MAX="${AIMOD_TURNSPD_MAX:-}"
AIMOD_TURNSPD_MIN="${AIMOD_TURNSPD_MIN:-}"
AIMOD_TURNSPD_DIST_TH="${AIMOD_TURNSPD_DIST_TH:-}"
AIMOD_TURNSPD_SCALE_MAX="${AIMOD_TURNSPD_SCALE_MAX:-}"
AIMOD_TURNSPD_SCALE_MIN="${AIMOD_TURNSPD_SCALE_MIN:-}"

# 6) Attaque & distances
AIMOD_ATTACK_DELAY_CLOSE="${AIMOD_ATTACK_DELAY_CLOSE:-}"
AIMOD_ATTACK_DELAY_DIST="${AIMOD_ATTACK_DELAY_DIST:-}"
AIMOD_ATTACK_DELAY_MELEE="${AIMOD_ATTACK_DELAY_MELEE:-}"
AIMOD_DISTANCE_RANGE="${AIMOD_DISTANCE_RANGE:-}"
AIMOD_CLOSE_RANGE="${AIMOD_CLOSE_RANGE:-}"
AIMOD_MID_RANGE="${AIMOD_MID_RANGE:-}"
AIMOD_FAR_RANGE="${AIMOD_FAR_RANGE:-}"
AIMOD_MELEE_RANGE="${AIMOD_MELEE_RANGE:-}"

# 7) Précision / bloatbox
AIMOD_ACCURACY_MULT="${AIMOD_ACCURACY_MULT:-}"
AIMOD_SUPPRESS_ACCURACY_MULT="${AIMOD_SUPPRESS_ACCURACY_MULT:-}"
AIMOD_NIGHT_ACC_FACTOR="${AIMOD_NIGHT_ACC_FACTOR:-}"
AIMOD_ZERO_TIME_EASY="${AIMOD_ZERO_TIME_EASY:-}"
AIMOD_ZERO_TIME_MED="${AIMOD_ZERO_TIME_MED:-}"
AIMOD_ZERO_TIME_HARD="${AIMOD_ZERO_TIME_HARD:-}"
AIMOD_BLOAT_MULT_EASY="${AIMOD_BLOAT_MULT_EASY:-}"
AIMOD_BLOAT_MULT_MED="${AIMOD_BLOAT_MULT_MED:-}"
AIMOD_BLOAT_MULT_HARD="${AIMOD_BLOAT_MULT_HARD:-}"
AIMOD_BLOAT_DIST_MULT="${AIMOD_BLOAT_DIST_MULT:-}"
AIMOD_BLOAT_MAX_DIST="${AIMOD_BLOAT_MAX_DIST:-}"
AIMOD_BLOAT_MIN_DIST="${AIMOD_BLOAT_MIN_DIST:-}"

# 8) Comportements offensifs / cover / wander / flanking
AIMOD_CHANCE_COVER="${AIMOD_CHANCE_COVER:-}"
AIMOD_CHANCE_COVER_IMPRO="${AIMOD_CHANCE_COVER_IMPRO:-}"
AIMOD_CHANCE_COVER_FAR="${AIMOD_CHANCE_COVER_FAR:-}"
AIMOD_MAX_DIST_2COVER="${AIMOD_MAX_DIST_2COVER:-}"
AIMOD_CHANCE_WANDER="${AIMOD_CHANCE_WANDER:-}"
AIMOD_DEF_WANDER_DIST="${AIMOD_DEF_WANDER_DIST:-}"
AIMOD_WANDER_DIST_MAX_MULT="${AIMOD_WANDER_DIST_MAX_MULT:-}"
AIMOD_CHANCE_FLANK="${AIMOD_CHANCE_FLANK:-}"
AIMOD_CHANCE_RUSH="${AIMOD_CHANCE_RUSH:-}"
AIMOD_CHANCE_HUNT="${AIMOD_CHANCE_HUNT:-}"
AIMOD_CHANCE_FORCE_HUNT="${AIMOD_CHANCE_FORCE_HUNT:-}"
AIMOD_CHANCE_REGROUP="${AIMOD_CHANCE_REGROUP:-}"

# 9) Spotting bonus / leaning / hearing min / injured thresholds
AIMOD_BONUS_SPOT_START="${AIMOD_BONUS_SPOT_START:-}"
AIMOD_MAX_BONUS_SPOT_HEAR="${AIMOD_MAX_BONUS_SPOT_HEAR:-}"
AIMOD_MAX_BONUS_SPOT_ALERT="${AIMOD_MAX_BONUS_SPOT_ALERT:-}"
AIMOD_CH_LEAN_MULT="${AIMOD_CH_LEAN_MULT:-}"
AIMOD_MIN_CHANCE_HEAR="${AIMOD_MIN_CHANCE_HEAR:-}"
AIMOD_INJ_DMG_TH="${AIMOD_INJ_DMG_TH:-}"
AIMOD_INJ_HP_RATIO="${AIMOD_INJ_HP_RATIO:-}"

# 10) Objectifs / distances à l’objectif
AIMOD_DIST_NEAR_OBJ="${AIMOD_DIST_NEAR_OBJ:-}"
AIMOD_DIST_MID_OBJ="${AIMOD_DIST_MID_OBJ:-}"
AIMOD_DIST_FAR_OBJ="${AIMOD_DIST_FAR_OBJ:-}"
AIMOD_RATIO_BOTS_CLOSE_OBJ="${AIMOD_RATIO_BOTS_CLOSE_OBJ:-}"

# 11) Suppression / NLOS stop firing / durées / distances
AIMOD_STOP_FIRE_NLOS_MIN="${AIMOD_STOP_FIRE_NLOS_MIN:-}"
AIMOD_STOP_FIRE_NLOS_MAX="${AIMOD_STOP_FIRE_NLOS_MAX:-}"
AIMOD_SUPPR_TIME_MIN="${AIMOD_SUPPR_TIME_MIN:-}"
AIMOD_SUPPR_TIME_MAX="${AIMOD_SUPPR_TIME_MAX:-}"
AIMOD_SUPPR_MIN_DIST="${AIMOD_SUPPR_MIN_DIST:-}"
AIMOD_SUPPR_BASE_CH="${AIMOD_SUPPR_BASE_CH:-}"
AIMOD_SUPPR_ADD_FRIEND="${AIMOD_SUPPR_ADD_FRIEND:-}"

# 12) Head/body ratio (doublon volontairement géré)
AIMOD_HEAD2BODY_RATIO="${AIMOD_HEAD2BODY_RATIO:-}"
AIMOD_RATIO_AIM_HEAD="${AIMOD_RATIO_AIM_HEAD:-}"

# 13) Difficulté variable / nb joueurs
AIMOD_VAR_PC_MIN="${AIMOD_VAR_PC_MIN:-}"
AIMOD_VAR_PC_MAX="${AIMOD_VAR_PC_MAX:-}"
AIMOD_VAR_MIN_DIFFICULTY="${AIMOD_VAR_MIN_DIFFICULTY:-}"
AIMOD_VAR_MAX_DIFFICULTY="${AIMOD_VAR_MAX_DIFFICULTY:-}"

# 14) Respawns & population
AIMOD_MAXCOUNT="${AIMOD_MAXCOUNT:-}"
AIMOD_RESPAWN_MIN="${AIMOD_RESPAWN_MIN:-}"
AIMOD_RESPAWN_MAX="${AIMOD_RESPAWN_MAX:-}"
AIMOD_SPAWN_DELAY="${AIMOD_SPAWN_DELAY:-}"

# 15) Divers / toggles
AIMOD_OVERWRITE_BOTCFG="${AIMOD_OVERWRITE_BOTCFG:-}"
AIMOD_BOT_USES_SMOKE="${AIMOD_BOT_USES_SMOKE:-}"
AIMOD_SUPPR_4MG_ONLY="${AIMOD_SUPPR_4MG_ONLY:-}"
AIMOD_MEMORY_MAX_AGE="${AIMOD_MEMORY_MAX_AGE:-}"

# 16) “Pas de couteau” & squads
AIMOD_ALLOW_MELEE="${AIMOD_ALLOW_MELEE:-}"
AIMOD_STAY_IN_SQUADS="${AIMOD_STAY_IN_SQUADS:-}"
AIMOD_SQUAD_SIZE="${AIMOD_SQUAD_SIZE:-}"

echo "────────────────────────────────────────────────────────"
echo "▶️  Starting Insurgency Sandstorm Dedicated Server"
echo "    GAMEDIR=${GAMEDIR}"
echo "    CFGDIR=${CFGDIR}"
echo "    APPID=${APPID}"
echo "    PORT=${PORT} | QUERYPORT=${QUERYPORT} | BEACONPORT=${BEACONPORT}"
echo "    HOSTNAME='${SS_HOSTNAME}'"
echo "    MAXPLAYERS=${SS_MAXPLAYERS}"
echo "    AUTO_UPDATE=${AUTO_UPDATE}"
echo "────────────────────────────────────────────────────────"

# ─────────────────────────────────────────
# 1) Préparation FS & permissions
# ─────────────────────────────────────────
need_paths=(
  "${GAMEDIR}"
  "${GAMEDIR}/Insurgency"
  "${GAMEDIR}/Insurgency/Config/Server"
  "${GAMEDIR}/Insurgency/Saved"
  "${GAMEDIR}/Insurgency/Saved/SaveGames"
  "${CFGDIR}"
)
for p in "${need_paths[@]}"; do
  if [ ! -d "$p" ]; then
    echo "📁 Creating: $p"
    mkdir -p "$p" || {
      echo "❌ Permission denied creating: $p"
      echo "   ➜ chown -R 1000:1000 ${GAMEDIR} /home/steam/Steam"
      exit 1
    }
  fi
done
echo "🔏 FS write test..."
echo "write-test" > "${GAMEDIR}/.writetest" || { echo "❌ Cannot write into ${GAMEDIR}"; exit 1; }
rm -f "${GAMEDIR}/.writetest"
echo "✅ FS OK"

# ─────────────────────────────────────────
# 2) Admins: Admins.txt + -AdminList
# ─────────────────────────────────────────
ADMINSDIR="${GAMEDIR}/Insurgency/Config/Server"
ADMINSLIST_NAME="Admins"
ADMINSLIST_PATH="${ADMINSDIR}/${ADMINSLIST_NAME}.txt"
mkdir -p "${ADMINSDIR}"
: > "${ADMINSLIST_PATH}"

if [ -n "${SS_ADMINS}" ]; then
  IFS=',' read -ra _admins <<< "${SS_ADMINS}"
  count=0
  for id in "${_admins[@]}"; do
    id_trim="$(echo "$id" | xargs)"
    if [[ "$id_trim" =~ ^[0-9]{17}$ ]]; then
      echo "$id_trim" >> "${ADMINSLIST_PATH}"
      count=$((count+1))
    else
      echo "⚠️  Skipping invalid SteamID64: '${id_trim}'"
    fi
  done
  echo "   → ${count} admin(s) written."
fi

# ─────────────────────────────────────────
# 3) SteamCMD auto-update
# ─────────────────────────────────────────
if [ "${AUTO_UPDATE}" = "1" ]; then
  echo "📥 Updating server via SteamCMD..."
  "${STEAMCMDDIR}/steamcmd.sh" +@sSteamCmdForcePlatformType linux \
      +force_install_dir "${GAMEDIR}" \
      +login anonymous \
      +app_update "${APPID}" validate \
      +quit || echo "⚠️ SteamCMD failed (continuing)"
else
  echo "ℹ️  AUTO_UPDATE=0 → skipping SteamCMD update."
fi

# ─────────────────────────────────────────
# 4) MapCycle.txt (si fourni)
# ─────────────────────────────────────────
echo "🗺️  Writing MapCycle (if any)..."
if [ -n "${SS_MAPCYCLE}" ]; then
  echo "${SS_MAPCYCLE}" | tr '\r' '\n' | sed '/^\s*$/d' > "${MAPCYCLE}"
  lines="$(wc -l < "${MAPCYCLE}" | xargs || true)"
  echo "   → MapCycle written at ${MAPCYCLE} (${lines:-0} lines)"
else
  echo "   → No SS_MAPCYCLE provided."
fi

# ─────────────────────────────────────────
# 5) Mode par défaut (si pas de scénario)
# ─────────────────────────────────────────
MODE_UPPER="$(echo "${SS_GAME_MODE}" | tr '[:lower:]' '[:upper:]')"
case "${MODE_UPPER}" in
  PUSH)        MODE_SECTION_DEF="/Script/Insurgency.INSPushGameMode" ;;
  FIREFIGHT)   MODE_SECTION_DEF="/Script/Insurgency.INSFirefightGameMode" ;;
  SKIRMISH)    MODE_SECTION_DEF="/Script/Insurgency.INSSkirmishGameMode" ;;
  DOMINATION)  MODE_SECTION_DEF="/Script/Insurgency.INSDominationGameMode" ;;
  CHECKPOINT)  MODE_SECTION_DEF="/Script/Insurgency.INSCheckpointGameMode" ;;
  OUTPOST)     MODE_SECTION_DEF="/Script/Insurgency.INSOutpostGameMode" ;;
  SURVIVAL)    MODE_SECTION_DEF="/Script/Insurgency.INSSurvivalGameMode" ;;
  *)           MODE_SECTION_DEF="/Script/Insurgency.INSCheckpointGameMode" ; SS_GAME_MODE="Checkpoint" ;;
esac
echo "🎮 Default mode → ${SS_GAME_MODE} (${MODE_SECTION_DEF})"

# ─────────────────────────────────────────
# 6) AiModifier placeholders → URL args (Skirmish only)
# ─────────────────────────────────────────
echo "🧩 Building AiModifier URL args from placeholders..."
AIMOD_ARGS=()
add_arg() { local key="$1"; local val="$2"; if [ -n "${val:-}" ]; then AIMOD_ARGS+=("${key}=${val}"); fi; }

# 1) Skill de base
add_arg "AIModifier.Difficulty" "${AIMOD_DIFFICULTY}"
add_arg "AIModifier.Accuracy" "${AIMOD_ACCURACY}"
add_arg "AIModifier.ReactionTime" "${AIMOD_REACTION}"

# 2) Sight / vision
add_arg "AIModifier.SightRangeAlert" "${AIMOD_SIGHT_ALERT}"
add_arg "AIModifier.SightRangeIdle" "${AIMOD_SIGHT_IDLE}"
add_arg "AIModifier.SightRangeWithinSmokeGrenade" "${AIMOD_SIGHT_SMOKE}"
add_arg "AIModifier.SightRangeWithinSmokeGrenadeEye" "${AIMOD_SIGHT_SMOKE_EYE}"
add_arg "AIModifier.SightRangeSmokeEyeFrac" "${AIMOD_SIGHT_SMOKE_EYE_FRAC}"
add_arg "AIModifier.MinLightIntensityToSeeTarget" "${AIMOD_MIN_LI_SEE}"
add_arg "AIModifier.MinLightIntensitytoSeeTargetatNight" "${AIMOD_MIN_LI_NIGHT}"
add_arg "AIModifier.LightIntensityforFullyVisibleTarget" "${AIMOD_LI_FULLY_VISIBLE}"
add_arg "AIModifier.TimetoNoticeVisibilityMultiplier" "${AIMOD_TIME_NOTICE_VISIB_MULT}"
add_arg "AIModifier.MinLightIntensitytoAffectNightVision" "${AIMOD_MIN_LI_AFFECT_NV}"
add_arg "AIModifier.MinNightVisionSightStrength" "${AIMOD_MIN_NV_STRENGTH}"

# 3) Chances d’être spotté
add_arg "AIModifier.ChanceSprintMultiplier" "${AIMOD_CH_SPRINT_MULT}"
add_arg "AIModifier.ChanceMovingMultiplier" "${AIMOD_CH_MOVING_MULT}"
add_arg "AIModifier.ChanceAtDistanceStanding" "${AIMOD_CH_STAND_DIST}"
add_arg "AIModifier.ChanceAtCloseRangeStanding" "${AIMOD_CH_STAND_CLOSE}"
add_arg "AIModifier.ChanceAtDistanceCrouched" "${AIMOD_CH_CROUCH_DIST}"
add_arg "AIModifier.ChanceAtCloseRangeCrouched" "${AIMOD_CH_CROUCH_CLOSE}"
add_arg "AIModifier.ChanceAtDistanceProne" "${AIMOD_CH_PRONE_DIST}"
add_arg "AIModifier.ChanceAtCloseRangeProne" "${AIMOD_CH_PRONE_CLOSE}"

# 4) Ouïe
add_arg "AIModifier.HearAwareDistanceRadial" "${AIMOD_HEAR_AWARE_RADIAL}"
add_arg "AIModifier.HearAwareDistanceGunshot" "${AIMOD_HEAR_AWARE_GUNSHOT}"
add_arg "AIModifier.HearAwareDistanceSprintFootstep" "${AIMOD_HEAR_AWARE_SPRINT}"
add_arg "AIModifier.HearAwareDistanceFootsteps" "${AIMOD_HEAR_AWARE_FOOT}"
add_arg "AIModifier.HearDistanceFootstepsSprinting" "${AIMOD_HEAR_DIST_SPRINT}"
add_arg "AIModifier.HearDistanceFootstepsRunning" "${AIMOD_HEAR_DIST_RUN}"
add_arg "AIModifier.HearAbilityZOffsetMin" "${AIMOD_HEAR_Z_MIN}"
add_arg "AIModifier.HearAbilityZOffsetMax" "${AIMOD_HEAR_Z_MAX}"
add_arg "AIModifier.FencedTargetHearAbilityModifier" "${AIMOD_HEAR_FENCED_MOD}"

# 5) Vitesse de rotation
add_arg "AIModifier.TurnSpeedMaxAngleThreshold" "${AIMOD_TURNSPD_MAX_ANGLE_TH}"
add_arg "AIModifier.TurnSpeedMinAngleThreshold" "${AIMOD_TURNSPD_MIN_ANGLE_TH}"
add_arg "AIModifier.TurnSpeedMaxAngle" "${AIMOD_TURNSPD_MAX}"
add_arg "AIModifier.TurnSpeedMinAngle" "${AIMOD_TURNSPD_MIN}"
add_arg "AIModifier.TurnSpeedDistanceThreshold" "${AIMOD_TURNSPD_DIST_TH}"
add_arg "AIModifier.TurnSpeedScaleModifierMax" "${AIMOD_TURNSPD_SCALE_MAX}"
add_arg "AIModifier.TurnSpeedScaleModifierMin" "${AIMOD_TURNSPD_SCALE_MIN}"

# 6) Attaque & distances
add_arg "AIModifier.AttackDelayClose" "${AIMOD_ATTACK_DELAY_CLOSE}"
add_arg "AIModifier.AttackDelayDistant" "${AIMOD_ATTACK_DELAY_DIST}"
add_arg "AIModifier.AttackDelayMelee" "${AIMOD_ATTACK_DELAY_MELEE}"
add_arg "AIModifier.DistanceRange" "${AIMOD_DISTANCE_RANGE}"
add_arg "AIModifier.CloseRange" "${AIMOD_CLOSE_RANGE}"
add_arg "AIModifier.MiddleRange" "${AIMOD_MID_RANGE}"
add_arg "AIModifier.FarRange" "${AIMOD_FAR_RANGE}"
add_arg "AIModifier.MeleeRange" "${AIMOD_MELEE_RANGE}"

# 7) Précision / bloatbox
add_arg "AIModifier.AccuracyMultiplier" "${AIMOD_ACCURACY_MULT}"
add_arg "AIModifier.SuppressionAccuracyMultiplier" "${AIMOD_SUPPRESS_ACCURACY_MULT}"
add_arg "AIModifier.NightAccuracyFactor" "${AIMOD_NIGHT_ACC_FACTOR}"
add_arg "AIModifier.ZeroTimeMultiplierEasy" "${AIMOD_ZERO_TIME_EASY}"
add_arg "AIModifier.ZeroTimeMultiplierMed" "${AIMOD_ZERO_TIME_MED}"
add_arg "AIModifier.ZeroTimeMultiplierHard" "${AIMOD_ZERO_TIME_HARD}"
add_arg "AIModifier.BloatBoxMultiplierEasy" "${AIMOD_BLOAT_MULT_EASY}"
add_arg "AIModifier.BloatBoxMultiplierMed" "${AIMOD_BLOAT_MULT_MED}"
add_arg "AIModifier.BloatBoxMultiplierHard" "${AIMOD_BLOAT_MULT_HARD}"
add_arg "AIModifier.BloatBoxMultiplierDistance" "${AIMOD_BLOAT_DIST_MULT}"
add_arg "AIModifier.BloatBoxMultiplierMaxDistance" "${AIMOD_BLOAT_MAX_DIST}"
add_arg "AIModifier.BloatBoxMultiplierMinDistance" "${AIMOD_BLOAT_MIN_DIST}"

# 8) Comportements offensifs
add_arg "AIModifier.Chance2Cover" "${AIMOD_CHANCE_COVER}"
add_arg "AIModifier.Chance2ImprovisedCover" "${AIMOD_CHANCE_COVER_IMPRO}"
add_arg "AIModifier.Chance2CoverFar" "${AIMOD_CHANCE_COVER_FAR}"
add_arg "AIModifier.MaxDistance2Cover" "${AIMOD_MAX_DIST_2COVER}"
add_arg "AIModifier.Chance2Wander" "${AIMOD_CHANCE_WANDER}"
add_arg "AIModifier.DefaultWanderDistance" "${AIMOD_DEF_WANDER_DIST}"
add_arg "AIModifier.WanderDistanceMaxMultiplier" "${AIMOD_WANDER_DIST_MAX_MULT}"
add_arg "AIModifier.Chance2Flank" "${AIMOD_CHANCE_FLANK}"
add_arg "AIModifier.Chance2Rush" "${AIMOD_CHANCE_RUSH}"
add_arg "AIModifier.Chance2Hunt" "${AIMOD_CHANCE_HUNT}"
add_arg "AIModifier.Chance2ForceHunt" "${AIMOD_CHANCE_FORCE_HUNT}"
add_arg "AIModifier.Chance2Regroup" "${AIMOD_CHANCE_REGROUP}"

# 9) Spotting / leaning / injured / hearing min
add_arg "AIModifier.bonusSpotLossStartingDistance" "${AIMOD_BONUS_SPOT_START}"
add_arg "AIModifier.maxBonusSpotChanceHearing" "${AIMOD_MAX_BONUS_SPOT_HEAR}"
add_arg "AIModifier.maxBonusSpotChanceAlert" "${AIMOD_MAX_BONUS_SPOT_ALERT}"
add_arg "AIModifier.ChanceLeanMultiplier" "${AIMOD_CH_LEAN_MULT}"
add_arg "AIModifier.minChance2Hear" "${AIMOD_MIN_CHANCE_HEAR}"
add_arg "AIModifier.InjuredDmgThreshold" "${AIMOD_INJ_DMG_TH}"
add_arg "AIModifier.InjuredHPRatioThreshold" "${AIMOD_INJ_HP_RATIO}"

# 10) Objectifs
add_arg "AIModifier.DistanceNear2Objective" "${AIMOD_DIST_NEAR_OBJ}"
add_arg "AIModifier.DistanceMid2Objective" "${AIMOD_DIST_MID_OBJ}"
add_arg "AIModifier.DistanceFar2Objective" "${AIMOD_DIST_FAR_OBJ}"
add_arg "AIModifier.ratioBotsClose2Objective" "${AIMOD_RATIO_BOTS_CLOSE_OBJ}"

# 11) Suppression & NLOS
add_arg "AIModifier.minTime2StopFiringNLOS" "${AIMOD_STOP_FIRE_NLOS_MIN}"
add_arg "AIModifier.maxTime2StopFiringNLOS" "${AIMOD_STOP_FIRE_NLOS_MAX}"
add_arg "AIModifier.minSuppressionTime" "${AIMOD_SUPPR_TIME_MIN}"
add_arg "AIModifier.maxSuppressionTime" "${AIMOD_SUPPR_TIME_MAX}"
add_arg "AIModifier.SuppressionMinDistance" "${AIMOD_SUPPR_MIN_DIST}"
add_arg "AIModifier.BaseChance2Suppress" "${AIMOD_SUPPR_BASE_CH}"
add_arg "AIModifier.AddChance2SuppressPerFriend" "${AIMOD_SUPPR_ADD_FRIEND}"

# 12) Head/body ratio (doublons couverts)
add_arg "AIModifier.ratioAimingHead2Body" "${AIMOD_HEAD2BODY_RATIO}"
add_arg "AIModifier.ratioAimingHead2Body" "${AIMOD_RATIO_AIM_HEAD}"

# 13) Difficulté variable
add_arg "AIModifier.PlayerCountForMinAIDifficulty" "${AIMOD_VAR_PC_MIN}"
add_arg "AIModifier.PlayerCountForMaxAIDifficulty" "${AIMOD_VAR_PC_MAX}"
add_arg "AIModifier.MinAIDifficulty" "${AIMOD_VAR_MIN_DIFFICULTY}"
add_arg "AIModifier.MaxAIDifficulty" "${AIMOD_VAR_MAX_DIFFICULTY}"

# 14) Respawns & population
add_arg "AIModifier.MaxCount" "${AIMOD_MAXCOUNT}"
add_arg "AIModifier.RespawnTimeMin" "${AIMOD_RESPAWN_MIN}"
add_arg "AIModifier.RespawnTimeMax" "${AIMOD_RESPAWN_MAX}"
add_arg "AIModifier.SpawnDelay" "${AIMOD_SPAWN_DELAY}"

# 15) Divers / toggles
add_arg "AIModifier.bOverwriteBotSkillCfg" "${AIMOD_OVERWRITE_BOTCFG}"
add_arg "AIModifier.bBotUsesSmokeGrenade" "${AIMOD_BOT_USES_SMOKE}"
add_arg "AIModifier.bSuppression4MgOnly" "${AIMOD_SUPPR_4MG_ONLY}"
add_arg "AIModifier.MemoryMaxAge" "${AIMOD_MEMORY_MAX_AGE}"

# 16) Knife & squads
add_arg "AIModifier.AllowMelee" "${AIMOD_ALLOW_MELEE}"
add_arg "AIModifier.StayInSquads" "${AIMOD_STAY_IN_SQUADS}"
add_arg "AIModifier.SquadSize" "${AIMOD_SQUAD_SIZE}"

AIMOD_URL_ARGS=""
if [ "${#AIMOD_ARGS[@]}" -gt 0 ]; then
  AIMOD_URL_ARGS="$(printf '%s' "${AIMOD_ARGS[0]}")"
  for ((i=1; i<${#AIMOD_ARGS[@]}; i++)); do
    AIMOD_URL_ARGS="${AIMOD_URL_ARGS}?${AIMOD_ARGS[$i]}"
  done
  echo "   → AiModifier URL args composed (${#AIMOD_ARGS[@]} keys). len=${#AIMOD_URL_ARGS}"
else
  echo "   → No AIMOD_* placeholders provided."
fi

# ─────────────────────────────────────────
# 6b) Whitelist Mods/Mutators (bots-only)
# ─────────────────────────────────────────
filter_csv_by_whitelist() {
  local csv="$1" wl="$2"
  [[ -z "$csv" ]] && { echo ""; return; }
  [[ -z "$wl"  ]] && { echo "$csv"; return; }
  IFS=',' read -ra items <<< "$csv"
  IFS=',' read -ra allowed <<< "$wl"
  declare -A allow
  for ok in "${allowed[@]}"; do
    k="$(echo "$ok" | xargs | tr '[:upper:]' '[:lower:]')"
    [[ -n "$k" ]] && allow["$k"]=1
  done
  out=()
  for it in "${items[@]}"; do
    val="$(echo "$it" | xargs)"
    key="$(echo "$val" | tr '[:upper:]' '[:lower:]')"
    if [[ -n "$val" && -n "${allow[$key]:-}" ]]; then
      out+=("$val")
    else
      [[ -n "$val" ]] && echo "🚫 filtered out (not whitelisted): '$val'" >&2
    fi
  done
  (IFS=','; echo "${out[*]}")
}
ACTIVE_MUTATORS_SKIRMISH="${SS_MUTATORS_SKIRMISH}"
if [[ "${SS_ENFORCE_MUTATOR_WHITELIST}" == "1" ]]; then
  ACTIVE_MUTATORS_SKIRMISH="$(filter_csv_by_whitelist "${SS_MUTATORS_SKIRMISH}" "${SS_MUTATOR_WHITELIST}")"
fi
ACTIVE_MODS="${SS_MODS}"
if [[ "${SS_ENFORCE_MODS_WHITELIST}" == "1" && -n "${SS_MODS_WHITELIST}" ]]; then
  ACTIVE_MODS="$(filter_csv_by_whitelist "${SS_MODS}" "${SS_MODS_WHITELIST}")"
fi

# ─────────────────────────────────────────
# 7) Validation “anti-casse” des scénarios (mode ↔ map) + fallback
# ─────────────────────────────────────────
if [[ -z "${SS_SCENARIO}" || ! "${SS_SCENARIO}" =~ ^Scenario_ ]]; then
  echo "⚠️  SS_SCENARIO invalide/absent → fallback 'Scenario_Farmhouse_Checkpoint_Security'"
  SS_SCENARIO="Scenario_Farmhouse_Checkpoint_Security"
fi
scenario_core="$(printf '%s' "${SS_SCENARIO#Scenario_}" | cut -d'_' -f1)"
scenario_mode="$(printf '%s' "${SS_SCENARIO}" | awk -F'_' '{print $(NF-1)}' | tr '[:lower:]' '[:upper:]')"
scenario_team="$(printf '%s' "${SS_SCENARIO}" | awk -F'_' '{print $NF}')"
[[ -z "${scenario_team}" ]] && scenario_team="Security"

# Listes blanches “sûres”
declare -A OK_SKIRMISH=([Crossing]=1 [Farmhouse]=1 [Refinery]=1 [Hideout]=1 [Summit]=1 [Hillside]=1)
declare -A OK_PUSH=([Crossing]=1 [Farmhouse]=1 [Refinery]=1 [Hideout]=1 [Summit]=1 [Hillside]=1 [Precinct]=1 [Ministry]=1 [PowerPlant]=1 [Outskirts]=1)
declare -A OK_FIREFIGHT=([Crossing]=1 [Farmhouse]=1 [Refinery]=1 [Hideout]=1 [Summit]=1 [Hillside]=1 [Precinct]=1 [Ministry]=1)
declare -A OK_DOMINATION=([Crossing]=1 [Farmhouse]=1 [Hideout]=1 [Summit]=1 [Precinct]=1 [Ministry]=1)
declare -A OK_CHECKPOINT=([Crossing]=1 [Farmhouse]=1 [Refinery]=1 [Hideout]=1 [Summit]=1 [Hillside]=1 [Precinct]=1 [Ministry]=1 [Outskirts]=1 [PowerPlant]=1)
declare -A OK_OUTPOST=([Crossing]=1 [Farmhouse]=1 [Refinery]=1 [Hideout]=1 [Summit]=1 [Hillside]=1)
declare -A OK_SURVIVAL=([Crossing]=1 [Farmhouse]=1 [Hideout]=1 [Summit]=1)

fallback_for_mode() {
  case "$1" in
    SKIRMISH)   echo "Crossing"   ;;
    PUSH)       echo "Crossing"   ;;
    FIREFIGHT)  echo "Farmhouse"  ;;
    DOMINATION) echo "Precinct"   ;;
    CHECKPOINT) echo "Farmhouse"  ;;
    OUTPOST)    echo "Crossing"   ;;
    SURVIVAL)   echo "Farmhouse"  ;;
    *)          echo "Crossing"   ;;
  esac
}
is_ok_for_mode() {
  local mode="$1" core="$2"
  if [[ "${SS_FORCE_COOP_ONLY:-0}" == "1" ]]; then
    case "$mode" in CHECKPOINT|OUTPOST|SURVIVAL) : ;; *) return 1 ;; esac
  fi
  case "$mode" in
    SKIRMISH)   [[ -n "${OK_SKIRMISH[$core]:-}"   ]] ;;
    PUSH)       [[ -n "${OK_PUSH[$core]:-}"       ]] ;;
    FIREFIGHT)  [[ -n "${OK_FIREFIGHT[$core]:-}"  ]] ;;
    DOMINATION) [[ -n "${OK_DOMINATION[$core]:-}" ]] ;;
    CHECKPOINT) [[ -n "${OK_CHECKPOINT[$core]:-}" ]] ;;
    OUTPOST)    [[ -n "${OK_OUTPOST[$core]:-}"    ]] ;;
    SURVIVAL)   [[ -n "${OK_SURVIVAL[$core]:-}"   ]] ;;
    *)          return 1 ;;
  esac
}
if ! is_ok_for_mode "${scenario_mode}" "${scenario_core}"; then
  echo "⚠️  '${scenario_core}' ne supporte pas '${scenario_mode}' → fallback"
  scenario_core="$(fallback_for_mode "${scenario_mode}")"
  SS_SCENARIO="Scenario_${scenario_core}_${scenario_mode^}_${scenario_team}"
fi

# Déduction asset
case "${scenario_core}" in
  Crossing)   MAP_ASSET="Canyon"   ;;
  Hideout)    MAP_ASSET="Town"     ;;
  Hillside)   MAP_ASSET="Sinjar"   ;;
  Refinery)   MAP_ASSET="Oilfield" ;;
  *)          MAP_ASSET="${scenario_core}" ;;
esac

# Section GameMode
case "${scenario_mode}" in
  PUSH)        MODE_SECTION="/Script/Insurgency.INSPushGameMode" ;;
  FIREFIGHT)   MODE_SECTION="/Script/Insurgency.INSFirefightGameMode" ;;
  SKIRMISH)    MODE_SECTION="/Script/Insurgency.INSSkirmishGameMode" ;;
  DOMINATION)  MODE_SECTION="/Script/Insurgency.INSDominationGameMode" ;;
  CHECKPOINT)  MODE_SECTION="/Script/Insurgency.INSCheckpointGameMode" ;;
  OUTPOST)     MODE_SECTION="/Script/Insurgency.INSOutpostGameMode" ;;
  SURVIVAL)    MODE_SECTION="/Script/Insurgency.INSSurvivalGameMode" ;;
  *)           MODE_SECTION="${MODE_SECTION_DEF}" ; scenario_mode="$(echo "${SS_GAME_MODE}" | tr '[:lower:]' '[:upper:]')" ;;
esac

# Rules (coop vs versus)
if [[ "${scenario_mode}" == "CHECKPOINT" || "${scenario_mode}" == "OUTPOST" || "${scenario_mode}" == "SURVIVAL" ]]; then
  RULES_SECTION="/Script/Insurgency.INSCoopMode"
else
  RULES_SECTION="/Script/Insurgency.INSMultiplayerMode"
fi

echo "🧭 Scenario validé → '${SS_SCENARIO}' | Asset='${MAP_ASSET}' | MODE='${scenario_mode}'"

# (Optionnel) Nettoyage MapCycle
if [[ "${SS_VALIDATE_MAPCYCLE:-0}" == "1" && -s "${MAPCYCLE}" ]]; then
  echo "🧹 Validation MapCycle (SS_VALIDATE_MAPCYCLE=1)…"
  tmp_mc="${MAPCYCLE}.validated"
  : > "${tmp_mc}"
  while IFS= read -r line || [ -n "$line" ]; do
    ltrim="$(echo "$line" | xargs)"
    [[ -z "$ltrim" ]] && continue
    if [[ ! "$ltrim" =~ ^Scenario_ ]]; then
      echo "   ✗ Ignore (format) : $ltrim"
      continue
    fi
    core="$(printf '%s' "${ltrim#Scenario_}" | cut -d'_' -f1)"
    mode="$(printf '%s' "${ltrim}" | awk -F'_' '{print $(NF-1)}' | tr '[:lower:]' '[:upper:]')"
    if is_ok_for_mode "${mode}" "${core}"; then
      echo "$ltrim" >> "${tmp_mc}"
      echo "   ✓ OK : $ltrim"
    else
      echo "   ✗ Remove (incompatible ${mode}) : $ltrim"
    fi
  done < "${MAPCYCLE}"
  mv -f "${tmp_mc}" "${MAPCYCLE}"
  echo "   → MapCycle nettoyé."
fi

# ─────────────────────────────────────────
# 8) Écriture Game.ini (server-driven)
# ─────────────────────────────────────────
echo "📝 Writing Game.ini…"
{
  cat <<EOF
; ------------------------------------------------------------------
; Insurgency Sandstorm - Game.ini (server-driven)
; ------------------------------------------------------------------

[/Script/Insurgency.INSGameMode]
bKillFeed=%SS_KILL_FEED%
bKillCamera=%SS_KILL_CAMERA%
bVoiceEnabled=%SS_VOICE_ENABLED%
FriendlyFireDamageScale=%SS_FRIENDLY_FIRE_SCALE%
RoundTime=%SS_ROUND_TIME%
PostRoundTime=%SS_POST_ROUND_TIME%
bAllowVoting=%SS_VOTE_ENABLED%
RequiredVotePercentage=%SS_VOTE_PERCENT%
bDisableStats=%DISABLE_STATS%     

[/Script/Insurgency.INSMultiplayerMode]
; 🎯 Choisis l’un OU l’autre :
bMapVoting=True
bUseMapCycle=False


EOF

  # Mods (Workshop) chargés globalement (filtrés)
  if [ -n "${ACTIVE_MODS}" ]; then
    IFS=',' read -ra _mods <<< "${ACTIVE_MODS}"
    for mid in "${_mods[@]}"; do
      mid_trim="$(echo "$mid" | xargs)"
      [ -n "$mid_trim" ] && echo "Mods=${mid_trim}"
    done
  fi

  # Bloc règles
  cat <<EOF

[${RULES_SECTION}]
bAutoBalanceTeams=${SS_AUTO_BALANCE}
AutoBalanceDelay=${SS_AUTO_BALANCE_DELAY}

[${MODE_SECTION}]
bBots=${SS_BOTS_ENABLED}
NumBots=${SS_BOT_NUM}
BotQuota=${SS_BOT_QUOTA}
BotDifficulty=${SS_BOT_DIFFICULTY}
EOF

  # Coop extras si besoin
  if [[ "${RULES_SECTION}" == "/Script/Insurgency.INSCoopMode" ]]; then
    echo "FriendlyBotQuota=${SS_FRIENDLY_BOT_QUOTA:-0}"
    [[ -n "${SS_MIN_ENEMIES:-}" ]] && echo "MinimumEnemies=${SS_MIN_ENEMIES}"
    [[ -n "${SS_MAX_ENEMIES:-}" ]] && echo "MaximumEnemies=${SS_MAX_ENEMIES}"
  fi

  # Sections disponibles (selon COOP-only)
  if [[ "${SS_FORCE_COOP_ONLY:-0}" == "1" ]]; then
    cat <<'EOF'
[/Script/Insurgency.INSCheckpointGameMode]
[/Script/Insurgency.INSOutpostGameMode]
[/Script/Insurgency.INSSurvivalGameMode]
EOF
  else
    cat <<'EOF'
[/Script/Insurgency.INSPushGameMode]
[/Script/Insurgency.INSFirefightGameMode]
[/Script/Insurgency.INSDominationGameMode]
[/Script/Insurgency.INSCheckpointGameMode]
[/Script/Insurgency.INSOutpostGameMode]
[/Script/Insurgency.INSSurvivalGameMode]
EOF
    # Mutators UNIQUEMENT en Skirmish (filtrés)
    echo
    echo "[/Script/Insurgency.INSSkirmishGameMode]"
    [ -n "${ACTIVE_MUTATORS_SKIRMISH}" ] && echo "Mutators=${ACTIVE_MUTATORS_SKIRMISH}"
  fi

} > "${GAMEINI}"
echo "   → ${GAMEINI} written."

# ─────────────────────────────────────────
# 9) Construction URL minimale
# ─────────────────────────────────────────
LAUNCH_URL="${MAP_ASSET}?Scenario=${SS_SCENARIO}"
# Ajoute AiModifier+args UNIQUEMENT si Skirmish & whiteliste
if [[ "${scenario_mode}" == "SKIRMISH" && -n "${ACTIVE_MUTATORS_SKIRMISH}" && "${ACTIVE_MUTATORS_SKIRMISH}" =~ (^|,)\ *AiModifier\ *(,|$) && -n "${AIMOD_URL_ARGS}" ]]; then
  LAUNCH_URL="${LAUNCH_URL}?Mutators=AiModifier?${AIMOD_URL_ARGS}"
fi

echo "▶️  Launch URL: ${LAUNCH_URL}"

# ─────────────────────────────────────────
# 10) XP flags (conditions officielles)
# ─────────────────────────────────────────
XP_ARGS=()
if [ -n "${GSLT_TOKEN}" ] && [ -n "${GAMESTATS_TOKEN}" ] && [ -z "${RCON_PASSWORD}" ]; then
  XP_ARGS+=( "-GSLTToken=${GSLT_TOKEN}" "-GameStatsToken=${GAMESTATS_TOKEN}" )
  echo "✨ XP enabled (tokens present & RCON empty)."
else
  echo "ℹ️  XP disabled (missing tokens or RCON set)."
  [ -z "${GSLT_TOKEN}" ] && echo "   ↳ GSLT_TOKEN missing."
  [ -z "${GAMESTATS_TOKEN}" ] && echo "   ↳ GAMESTATS_TOKEN missing."
  [ -n "${RCON_PASSWORD}" ] && echo "   ↳ RCON_PASSWORD is set (must be empty for XP)."
fi

# ─────────────────────────────────────────
# 11) Démarrage serveur
# ─────────────────────────────────────────
cd "${GAMEDIR}/Insurgency/Binaries/Linux" || { echo "❌ Cannot cd to ${GAMEDIR}/Insurgency/Binaries/Linux"; exit 1; }

# Ajoute -MapCycle si disponible
if [ -s "${MAPCYCLE}" ]; then
  EXTRA_SERVER_ARGS="${EXTRA_SERVER_ARGS} -MapCycle=$(basename "${MAPCYCLE}")"
fi

echo "🚀 Launching InsurgencyServer-Linux-Shipping..."
echo "    Hostname='${SS_HOSTNAME}'"
echo "    Ports: -Port=${PORT} -QueryPort=${QUERYPORT} -BeaconPort=${BEACONPORT}"
echo "    AdminList='${ADMINSLIST_NAME}' (${ADMINSLIST_PATH})"
echo "    Extra args: '${EXTRA_SERVER_ARGS}'"
echo "────────────────────────────────────────────────────────"

RCON_ARGS=()
if [ -n "${RCON_PASSWORD}" ]; then
  RCON_ARGS+=("-Rcon" "-RconPassword=${RCON_PASSWORD}")
fi

exec ./InsurgencyServer-Linux-Shipping \
  "${LAUNCH_URL}" \
  -hostname="${SS_HOSTNAME}" \
  -Port="${PORT}" -QueryPort="${QUERYPORT}" -BeaconPort="${BEACONPORT}" \
  -AdminList="${ADMINSLIST_NAME}" \
  -log \
  ${EXTRA_SERVER_ARGS} \
  "${XP_ARGS[@]}" \
  "${RCON_ARGS[@]}"
