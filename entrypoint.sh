#!/bin/bash
# ==================================================================
# Insurgency: Sandstorm Dedicated Server - EntryPoint (verbose/full)
# - XP classé (GSLT + GameStats, RCON vide)
# - Admins: Admins.txt + -AdminList
# - Mods & Mutators (Game.ini + URL)
# - AiModifier placeholders (AIMOD_*) -> SS_MUTATOR_URL_ARGS
# - MapCycle + déduction Asset depuis SCENARIO
# - Logs détaillés + validations
# ==================================================================
set -euo pipefail

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
RCON_PASSWORD="${RCON_PASSWORD:-}"     # ← doit rester vide pour XP classé
SS_HOSTNAME="${SS_HOSTNAME:-Chourmovs ISS (PvP)}"
SS_MAXPLAYERS="${SS_MAXPLAYERS:-28}"

SS_GAME_MODE="${SS_GAME_MODE:-Push}"   # Push | Firefight | Skirmish | Domination
SS_MAP="${SS_MAP:-Crossing}"           # informatif
SS_SCENARIO="${SS_SCENARIO:-}"         # on gère le fallback juste après
SS_MAPCYCLE="${SS_MAPCYCLE:-}"         # multi-lignes possibles

# Bots (VERSUS)
SS_BOTS_ENABLED="${SS_BOTS_ENABLED:-1}"
SS_BOT_NUM="${SS_BOT_NUM:-12}"
SS_BOT_QUOTA="${SS_BOT_QUOTA:-1.0}"
SS_BOT_DIFFICULTY="${SS_BOT_DIFFICULTY:-0.7}"

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
GSLT_TOKEN="${GSLT_TOKEN:-}"           # https://steamcommunity.com/dev/managegameservers
GAMESTATS_TOKEN="${GAMESTATS_TOKEN:-}" # https://gamestats.sandstorm.game

# Mods & Mutators
SS_MODS="${SS_MODS:-}"                 # "1141916,12345"
SS_MUTATORS="${SS_MUTATORS:-}"         # "AiModifier,HeadshotOnly"
SS_MUTATOR_URL_ARGS="${SS_MUTATOR_URL_ARGS:-}"
EXTRA_SERVER_ARGS="${EXTRA_SERVER_ARGS:-}"

# Admins (SteamID64, virgules)
SS_ADMINS="${SS_ADMINS:-}"

# AiModifier placeholders
AIMOD_DIFFICULTY="${AIMOD_DIFFICULTY:-}"
AIMOD_ACCURACY="${AIMOD_ACCURACY:-}"
AIMOD_REACTION="${AIMOD_REACTION:-}"
AIMOD_MAXCOUNT="${AIMOD_MAXCOUNT:-}"
AIMOD_RESPAWN_MIN="${AIMOD_RESPAWN_MIN:-}"
AIMOD_RESPAWN_MAX="${AIMOD_RESPAWN_MAX:-}"
AIMOD_SPAWN_DELAY="${AIMOD_SPAWN_DELAY:-}"
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
# 2) Admins: Admins.txt + -AdminList=Admins
# ─────────────────────────────────────────
ADMINSDIR="${GAMEDIR}/Insurgency/Config/Server"
ADMINSLIST_NAME="Admins"
ADMINSLIST_PATH="${ADMINSDIR}/${ADMINSLIST_NAME}.txt"
mkdir -p "${ADMINSDIR}"

if [ -n "${SS_ADMINS}" ]; then
  echo "🛡️  Writing Admins list → ${ADMINSLIST_PATH}"
  : > "${ADMINSLIST_PATH}"
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
else
  [ -f "${ADMINSLIST_PATH}" ] || : > "${ADMINSLIST_PATH}"
  echo "ℹ️  No SS_ADMINS provided; empty Admins.txt ensured."
fi

# ─────────────────────────────────────────
# 3) SteamCMD auto-update (avec retry)
# ─────────────────────────────────────────
if [ "${AUTO_UPDATE}" = "1" ]; then
  echo "📥 Updating server via SteamCMD..."
  tries=3
  for i in $(seq 1 $tries); do
    if "${STEAMCMDDIR}/steamcmd.sh" +@sSteamCmdForcePlatformType linux \
        +force_install_dir "${GAMEDIR}" \
        +login anonymous \
        +app_update "${APPID}" validate \
        +quit; then
      echo "✅ SteamCMD update success (try ${i}/${tries})"
      break
    fi
    echo "⚠️  SteamCMD failed (try ${i}/${tries}). Retrying in 5s..."
    sleep 5
    if [ "${i}" -eq "${tries}" ]; then
      echo "⚠️  Continuing despite SteamCMD failures."
    fi
  done
else
  echo "ℹ️  AUTO_UPDATE=0 → skipping SteamCMD update."
fi

# ─────────────────────────────────────────
# 4) MapCycle.txt (si fourni)
# ─────────────────────────────────────────
echo "🗺️  Writing MapCycle (if any)..."
if [ -n "${SS_MAPCYCLE}" ]; then
  echo "${SS_MAPCYCLE}" | tr '\r' '\n' | sed '/^\s*$/d' > "${MAPCYCLE}"
  echo "   → MapCycle written at ${MAPCYCLE} ($(wc -l < "${MAPCYCLE}") lines)"
else
  echo "   → No SS_MAPCYCLE provided."
fi

# ─────────────────────────────────────────
# 5) Validation/normalisation du mode
# ─────────────────────────────────────────
MODE_UPPER="$(echo "${SS_GAME_MODE}" | tr '[:lower:]' '[:upper:]')"
case "${MODE_UPPER}" in
  # PvP
  PUSH)        MODE_SECTION="/Script/Insurgency.INSPushGameMode" ;;
  FIREFIGHT)   MODE_SECTION="/Script/Insurgency.INSFirefightGameMode" ;;
  SKIRMISH)    MODE_SECTION="/Script/Insurgency.INSSkirmishGameMode" ;;
  DOMINATION)  MODE_SECTION="/Script/Insurgency.INSDominationGameMode" ;;
  # COOP
  CHECKPOINT)  MODE_SECTION="/Script/Insurgency.INSCheckpointGameMode" ;;
  OUTPOST)     MODE_SECTION="/Script/Insurgency.INSOutpostGameMode" ;;
  SURVIVAL)    MODE_SECTION="/Script/Insurgency.INSSurvivalGameMode" ;;
  *)           MODE_SECTION="/Script/Insurgency.INSPushGameMode" ; SS_GAME_MODE="Push" ;;
esac

echo "🎮 Mode deduced → ${SS_GAME_MODE} (${MODE_SECTION})"


# ─────────────────────────────────────────
#  6) AiModifier placeholders → URL args (ENRAGED capable)
# ─────────────────────────────────────────
echo "🧩 Building AiModifier URL args from placeholders..."
AIMOD_ARGS=()

# Skill de base
[ -n "${AIMOD_DIFFICULTY:-}" ]  && AIMOD_ARGS+=("AIModifier.Difficulty=${AIMOD_DIFFICULTY}")
[ -n "${AIMOD_ACCURACY:-}" ]    && AIMOD_ARGS+=("AIModifier.Accuracy=${AIMOD_ACCURACY}")
[ -n "${AIMOD_REACTION:-}" ]    && AIMOD_ARGS+=("AIModifier.ReactionTime=${AIMOD_REACTION}")

# Sight / vision
[ -n "${AIMOD_SIGHT_ALERT:-}" ]         && AIMOD_ARGS+=("AIModifier.SightRangeAlert=${AIMOD_SIGHT_ALERT}")
[ -n "${AIMOD_SIGHT_IDLE:-}" ]          && AIMOD_ARGS+=("AIModifier.SightRangeIdle=${AIMOD_SIGHT_IDLE}")
[ -n "${AIMOD_SIGHT_SMOKE:-}" ]         && AIMOD_ARGS+=("AIModifier.SightRangeWithinSmokeGrenade=${AIMOD_SIGHT_SMOKE}")
[ -n "${AIMOD_SIGHT_SMOKE_EYE:-}" ]     && AIMOD_ARGS+=("AIModifier.SightRangeWithinSmokeGrenadeEye=${AIMOD_SIGHT_SMOKE_EYE}")
[ -n "${AIMOD_SIGHT_SMOKE_EYE_FRAC:-}" ]&& AIMOD_ARGS+=("AIModifier.SightRangeSmokeEyeFrac=${AIMOD_SIGHT_SMOKE_EYE_FRAC}")
[ -n "${AIMOD_MIN_LI_SEE:-}" ]          && AIMOD_ARGS+=("AIModifier.MinLightIntensityToSeeTarget=${AIMOD_MIN_LI_SEE}")
[ -n "${AIMOD_MIN_LI_NIGHT:-}" ]        && AIMOD_ARGS+=("AIModifier.MinLightIntensitytoSeeTargetatNight=${AIMOD_MIN_LI_NIGHT}")
[ -n "${AIMOD_LI_FULLY_VISIBLE:-}" ]    && AIMOD_ARGS+=("AIModifier.LightIntensityforFullyVisibleTarget=${AIMOD_LI_FULLY_VISIBLE}")
[ -n "${AIMOD_TIME_NOTICE_VISIB_MULT:-}" ] && AIMOD_ARGS+=("AIModifier.TimetoNoticeVisibilityMultiplier=${AIMOD_TIME_NOTICE_VISIB_MULT}")
[ -n "${AIMOD_MIN_LI_AFFECT_NV:-}" ]    && AIMOD_ARGS+=("AIModifier.MinLightIntensitytoAffectNightVision=${AIMOD_MIN_LI_AFFECT_NV}")
[ -n "${AIMOD_MIN_NV_STRENGTH:-}" ]     && AIMOD_ARGS+=("AIModifier.MinNightVisionSightStrength=${AIMOD_MIN_NV_STRENGTH}")

# Chances d’être spotté
[ -n "${AIMOD_CH_SPRINT_MULT:-}" ]      && AIMOD_ARGS+=("AIModifier.ChanceSprintMultiplier=${AIMOD_CH_SPRINT_MULT}")
[ -n "${AIMOD_CH_MOVING_MULT:-}" ]      && AIMOD_ARGS+=("AIModifier.ChanceMovingMultiplier=${AIMOD_CH_MOVING_MULT}")
[ -n "${AIMOD_CH_STAND_DIST:-}" ]       && AIMOD_ARGS+=("AIModifier.ChanceAtDistanceStanding=${AIMOD_CH_STAND_DIST}")
[ -n "${AIMOD_CH_STAND_CLOSE:-}" ]      && AIMOD_ARGS+=("AIModifier.ChanceAtCloseRangeStanding=${AIMOD_CH_STAND_CLOSE}")
[ -n "${AIMOD_CH_CROUCH_DIST:-}" ]      && AIMOD_ARGS+=("AIModifier.ChanceAtDistanceCrouched=${AIMOD_CH_CROUCH_DIST}")
[ -n "${AIMOD_CH_CROUCH_CLOSE:-}" ]     && AIMOD_ARGS+=("AIModifier.ChanceAtCloseRangeCrouched=${AIMOD_CH_CROUCH_CLOSE}")
[ -n "${AIMOD_CH_PRONE_DIST:-}" ]       && AIMOD_ARGS+=("AIModifier.ChanceAtDistanceProne=${AIMOD_CH_PRONE_DIST}")
[ -n "${AIMOD_CH_PRONE_CLOSE:-}" ]      && AIMOD_ARGS+=("AIModifier.ChanceAtCloseRangeProne=${AIMOD_CH_PRONE_CLOSE}")

# Ouïe
[ -n "${AIMOD_HEAR_AWARE_RADIAL:-}" ]   && AIMOD_ARGS+=("AIModifier.HearAwareDistanceRadial=${AIMOD_HEAR_AWARE_RADIAL}")
[ -n "${AIMOD_HEAR_AWARE_GUNSHOT:-}" ]  && AIMOD_ARGS+=("AIModifier.HearAwareDistanceGunshot=${AIMOD_HEAR_AWARE_GUNSHOT}")
[ -n "${AIMOD_HEAR_AWARE_SPRINT:-}" ]   && AIMOD_ARGS+=("AIModifier.HearAwareDistanceSprintFootstep=${AIMOD_HEAR_AWARE_SPRINT}")
[ -n "${AIMOD_HEAR_AWARE_FOOT:-}" ]     && AIMOD_ARGS+=("AIModifier.HearAwareDistanceFootsteps=${AIMOD_HEAR_AWARE_FOOT}")
[ -n "${AIMOD_HEAR_DIST_SPRINT:-}" ]    && AIMOD_ARGS+=("AIModifier.HearDistanceFootstepsSprinting=${AIMOD_HEAR_DIST_SPRINT}")
[ -n "${AIMOD_HEAR_DIST_RUN:-}" ]       && AIMOD_ARGS+=("AIModifier.HearDistanceFootstepsRunning=${AIMOD_HEAR_DIST_RUN}")
[ -n "${AIMOD_HEAR_Z_MIN:-}" ]          && AIMOD_ARGS+=("AIModifier.HearAbilityZOffsetMin=${AIMOD_HEAR_Z_MIN}")
[ -n "${AIMOD_HEAR_Z_MAX:-}" ]          && AIMOD_ARGS+=("AIModifier.HearAbilityZOffsetMax=${AIMOD_HEAR_Z_MAX}")
[ -n "${AIMOD_HEAR_FENCED_MOD:-}" ]     && AIMOD_ARGS+=("AIModifier.FencedTargetHearAbilityModifier=${AIMOD_HEAR_FENCED_MOD}")

# Vitesse de rotation
[ -n "${AIMOD_TURNSPD_MAX_ANGLE_TH:-}" ]&& AIMOD_ARGS+=("AIModifier.TurnSpeedMaxAngleThreshold=${AIMOD_TURNSPD_MAX_ANGLE_TH}")
[ -n "${AIMOD_TURNSPD_MIN_ANGLE_TH:-}" ]&& AIMOD_ARGS+=("AIModifier.TurnSpeedMinAngleThreshold=${AIMOD_TURNSPD_MIN_ANGLE_TH}")
[ -n "${AIMOD_TURNSPD_MAX:-}" ]         && AIMOD_ARGS+=("AIModifier.TurnSpeedMaxAngle=${AIMOD_TURNSPD_MAX}")
[ -n "${AIMOD_TURNSPD_MIN:-}" ]         && AIMOD_ARGS+=("AIModifier.TurnSpeedMinAngle=${AIMOD_TURNSPD_MIN}")
[ -n "${AIMOD_TURNSPD_DIST_TH:-}" ]     && AIMOD_ARGS+=("AIModifier.TurnSpeedDistanceThreshold=${AIMOD_TURNSPD_DIST_TH}")
[ -n "${AIMOD_TURNSPD_SCALE_MAX:-}" ]   && AIMOD_ARGS+=("AIModifier.TurnSpeedScaleModifierMax=${AIMOD_TURNSPD_SCALE_MAX}")

# Attaque & distances
[ -n "${AIMOD_ATTACK_DELAY_CLOSE:-}" ]  && AIMOD_ARGS+=("AIModifier.AttackDelayClose=${AIMOD_ATTACK_DELAY_CLOSE}")
[ -n "${AIMOD_ATTACK_DELAY_DIST:-}" ]   && AIMOD_ARGS+=("AIModifier.AttackDelayDistant=${AIMOD_ATTACK_DELAY_DIST}")
[ -n "${AIMOD_ATTACK_DELAY_MELEE:-}" ]  && AIMOD_ARGS+=("AIModifier.AttackDelayMelee=${AIMOD_ATTACK_DELAY_MELEE}")
[ -n "${AIMOD_DISTANCE_RANGE:-}" ]      && AIMOD_ARGS+=("AIModifier.DistanceRange=${AIMOD_DISTANCE_RANGE}")
[ -n "${AIMOD_CLOSE_RANGE:-}" ]         && AIMOD_ARGS+=("AIModifier.CloseRange=${AIMOD_CLOSE_RANGE}")
[ -n "${AIMOD_MID_RANGE:-}" ]           && AIMOD_ARGS+=("AIModifier.MiddleRange=${AIMOD_MID_RANGE}")

# Précision / bloatbox
[ -n "${AIMOD_ACCURACY_MULT:-}" ]       && AIMOD_ARGS+=("AIModifier.AccuracyMultiplier=${AIMOD_ACCURACY_MULT}")
[ -n "${AIMOD_SUPPRESS_ACCURACY_MULT:-}" ] && AIMOD_ARGS+=("AIModifier.SuppressionAccuracyMultiplier=${AIMOD_SUPPRESS_ACCURACY_MULT}")
[ -n "${AIMOD_NIGHT_ACC_FACTOR:-}" ]    && AIMOD_ARGS+=("AIModifier.NightAccuracyFactor=${AIMOD_NIGHT_ACC_FACTOR}")
[ -n "${AIMOD_ZERO_TIME_EASY:-}" ]      && AIMOD_ARGS+=("AIModifier.ZeroTimeMultiplierEasy=${AIMOD_ZERO_TIME_EASY}")
[ -n "${AIMOD_ZERO_TIME_HARD:-}" ]      && AIMOD_ARGS+=("AIModifier.ZeroTimeMultiplierHard=${AIMOD_ZERO_TIME_HARD}")
[ -n "${AIMOD_BLOAT_MULT_EASY:-}" ]     && AIMOD_ARGS+=("AIModifier.BloatBoxMultiplierEasy=${AIMOD_BLOAT_MULT_EASY}")
[ -n "${AIMOD_BLOAT_MULT_HARD:-}" ]     && AIMOD_ARGS+=("AIModifier.BloatBoxMultiplierHard=${AIMOD_BLOAT_MULT_HARD}")
[ -n "${AIMOD_BLOAT_DIST_MULT:-}" ]     && AIMOD_ARGS+=("AIModifier.BloatBoxMultiplierDistance=${AIMOD_BLOAT_DIST_MULT}")
[ -n "${AIMOD_BLOAT_MAX_DIST:-}" ]      && AIMOD_ARGS+=("AIModifier.BloatBoxMultiplierMaxDistance=${AIMOD_BLOAT_MAX_DIST}")
[ -n "${AIMOD_BLOAT_MIN_DIST:-}" ]      && AIMOD_ARGS+=("AIModifier.BloatBoxMultiplierMinDistance=${AIMOD_BLOAT_MIN_DIST}")

# Comportements offensifs
[ -n "${AIMOD_CHANCE_COVER:-}" ]        && AIMOD_ARGS+=("AIModifier.Chance2Cover=${AIMOD_CHANCE_COVER}")
[ -n "${AIMOD_CHANCE_COVER_IMPRO:-}" ]  && AIMOD_ARGS+=("AIModifier.Chance2ImprovisedCover=${AIMOD_CHANCE_COVER_IMPRO}")
[ -n "${AIMOD_CHANCE_COVER_FAR:-}" ]    && AIMOD_ARGS+=("AIModifier.Chance2CoverFar=${AIMOD_CHANCE_COVER_FAR}")
[ -n "${AIMOD_MAX_DIST_2COVER:-}" ]     && AIMOD_ARGS+=("AIModifier.MaxDistance2Cover=${AIMOD_MAX_DIST_2COVER}")
[ -n "${AIMOD_CHANCE_WANDER:-}" ]       && AIMOD_ARGS+=("AIModifier.Chance2Wander=${AIMOD_CHANCE_WANDER}")
[ -n "${AIMOD_DEF_WANDER_DIST:-}" ]     && AIMOD_ARGS+=("AIModifier.DefaultWanderDistance=${AIMOD_DEF_WANDER_DIST}")
[ -n "${AIMOD_WANDER_DIST_MAX_MULT:-}" ]&& AIMOD_ARGS+=("AIModifier.WanderDistanceMaxMultiplier=${AIMOD_WANDER_DIST_MAX_MULT}")
[ -n "${AIMOD_CHANCE_FLANK:-}" ]        && AIMOD_ARGS+=("AIModifier.Chance2Flank=${AIMOD_CHANCE_FLANK}")
[ -n "${AIMOD_CHANCE_RUSH:-}" ]         && AIMOD_ARGS+=("AIModifier.Chance2Rush=${AIMOD_CHANCE_RUSH}")
[ -n "${AIMOD_CHANCE_HUNT:-}" ]         && AIMOD_ARGS+=("AIModifier.Chance2Hunt=${AIMOD_CHANCE_HUNT}")
[ -n "${AIMOD_CHANCE_FORCE_HUNT:-}" ]   && AIMOD_ARGS+=("AIModifier.Chance2ForceHunt=${AIMOD_CHANCE_FORCE_HUNT}")
[ -n "${AIMOD_CHANCE_REGROUP:-}" ]      && AIMOD_ARGS+=("AIModifier.Chance2Regroup=${AIMOD_CHANCE_REGROUP}")
[ -n "${AIMOD_BONUS_SPOT_START:-}" ]    && AIMOD_ARGS+=("AIModifier.bonusSpotLossStartingDistance=${AIMOD_BONUS_SPOT_START}")
[ -n "${AIMOD_MAX_BONUS_SPOT_HEAR:-}" ] && AIMOD_ARGS+=("AIModifier.maxBonusSpotChanceHearing=${AIMOD_MAX_BONUS_SPOT_HEAR}")
[ -n "${AIMOD_MAX_BONUS_SPOT_ALERT:-}" ]&& AIMOD_ARGS+=("AIModifier.maxBonusSpotChanceAlert=${AIMOD_MAX_BONUS_SPOT_ALERT}")
[ -n "${AIMOD_CH_LEAN_MULT:-}" ]        && AIMOD_ARGS+=("AIModifier.ChanceLeanMultiplier=${AIMOD_CH_LEAN_MULT}")
[ -n "${AIMOD_MIN_CHANCE_HEAR:-}" ]     && AIMOD_ARGS+=("AIModifier.minChance2Hear=${AIMOD_MIN_CHANCE_HEAR}")
[ -n "${AIMOD_INJ_DMG_TH:-}" ]          && AIMOD_ARGS+=("AIModifier.InjuredDmgThreshold=${AIMOD_INJ_DMG_TH}")
[ -n "${AIMOD_INJ_HP_RATIO:-}" ]        && AIMOD_ARGS+=("AIModifier.InjuredHPRatioThreshold=${AIMOD_INJ_HP_RATIO}")
[ -n "${AIMOD_DIST_NEAR_OBJ:-}" ]       && AIMOD_ARGS+=("AIModifier.DistanceNear2Objective=${AIMOD_DIST_NEAR_OBJ}")
[ -n "${AIMOD_DIST_MID_OBJ:-}" ]        && AIMOD_ARGS+=("AIModifier.DistanceMid2Objective=${AIMOD_DIST_MID_OBJ}")
[ -n "${AIMOD_DIST_FAR_OBJ:-}" ]        && AIMOD_ARGS+=("AIModifier.DistanceFar2Objective=${AIMOD_DIST_FAR_OBJ}")
[ -n "${AIMOD_RATIO_BOTS_CLOSE_OBJ:-}" ]&& AIMOD_ARGS+=("AIModifier.ratioBotsClose2Objective=${AIMOD_RATIO_BOTS_CLOSE_OBJ}")
[ -n "${AIMOD_STOP_FIRE_NLOS_MIN:-}" ]  && AIMOD_ARGS+=("AIModifier.minTime2StopFiringNLOS=${AIMOD_STOP_FIRE_NLOS_MIN}")
[ -n "${AIMOD_STOP_FIRE_NLOS_MAX:-}" ]  && AIMOD_ARGS+=("AIModifier.maxTime2StopFiringNLOS=${AIMOD_STOP_FIRE_NLOS_MAX}")
[ -n "${AIMOD_SUPPR_TIME_MIN:-}" ]      && AIMOD_ARGS+=("AIModifier.minSuppressionTime=${AIMOD_SUPPR_TIME_MIN}")
[ -n "${AIMOD_SUPPR_TIME_MAX:-}" ]      && AIMOD_ARGS+=("AIModifier.maxSuppressionTime=${AIMOD_SUPPR_TIME_MAX}")
[ -n "${AIMOD_SUPPR_MIN_DIST:-}" ]      && AIMOD_ARGS+=("AIModifier.SuppressionMinDistance=${AIMOD_SUPPR_MIN_DIST}")
[ -n "${AIMOD_SUPPR_BASE_CH:-}" ]       && AIMOD_ARGS+=("AIModifier.BaseChance2Suppress=${AIMOD_SUPPR_BASE_CH}")
[ -n "${AIMOD_SUPPR_ADD_FRIEND:-}" ]    && AIMOD_ARGS+=("AIModifier.AddChance2SuppressPerFriend=${AIMOD_SUPPR_ADD_FRIEND}")
[ -n "${AIMOD_HEAD2BODY_RATIO:-}" ]     && AIMOD_ARGS+=("AIModifier.ratioAimingHead2Body=${AIMOD_HEAD2BODY_RATIO}")

# Difficulté variable
[ -n "${AIMOD_VAR_PC_MIN:-}" ]          && AIMOD_ARGS+=("AIModifier.PlayerCountForMinAIDifficulty=${AIMOD_VAR_PC_MIN}")
[ -n "${AIMOD_VAR_PC_MAX:-}" ]          && AIMOD_ARGS+=("AIModifier.PlayerCountForMaxAIDifficulty=${AIMOD_VAR_PC_MAX}")
[ -n "${AIMOD_VAR_MIN_DIFFICULTY:-}" ]  && AIMOD_ARGS+=("AIModifier.MinAIDifficulty=${AIMOD_VAR_MIN_DIFFICULTY}")
[ -n "${AIMOD_VAR_MAX_DIFFICULTY:-}" ]  && AIMOD_ARGS+=("AIModifier.MaxAIDifficulty=${AIMOD_VAR_MAX_DIFFICULTY}")

# Misc
[ -n "${AIMOD_OVERWRITE_BOTCFG:-}" ]    && AIMOD_ARGS+=("AIModifier.bOverwriteBotSkillCfg=${AIMOD_OVERWRITE_BOTCFG}")
[ -n "${AIMOD_BOT_USES_SMOKE:-}" ]      && AIMOD_ARGS+=("AIModifier.bBotUsesSmokeGrenade=${AIMOD_BOT_USES_SMOKE}")
[ -n "${AIMOD_SUPPR_4MG_ONLY:-}" ]      && AIMOD_ARGS+=("AIModifier.bSuppression4MgOnly=${AIMOD_SUPPR_4MG_ONLY}")
[ -n "${AIMOD_MEMORY_MAX_AGE:-}" ]      && AIMOD_ARGS+=("AIModifier.MemoryMaxAge=${AIMOD_MEMORY_MAX_AGE}")
[ -n "${AIMOD_RATIO_AIM_HEAD:-}" ]      && AIMOD_ARGS+=("AIModifier.ratioAimingHead2Body=${AIMOD_RATIO_AIM_HEAD}")

# “Pas de couteau” & “rester en squads” (déjà présents)
[ -n "${AIMOD_ALLOW_MELEE:-}" ]         && AIMOD_ARGS+=("AIModifier.AllowMelee=${AIMOD_ALLOW_MELEE}")
[ -n "${AIMOD_STAY_IN_SQUADS:-}" ]      && AIMOD_ARGS+=("AIModifier.StayInSquads=${AIMOD_STAY_IN_SQUADS}")
[ -n "${AIMOD_SQUAD_SIZE:-}" ]          && AIMOD_ARGS+=("AIModifier.SquadSize=${AIMOD_SQUAD_SIZE}")

if [ ${#AIMOD_ARGS[@]} -gt 0 ]; then
  SS_MUTATOR_URL_ARGS="$(IFS='?'; echo "${AIMOD_ARGS[*]}")"
  echo "   → SS_MUTATOR_URL_ARGS composed (${#AIMOD_ARGS[@]} keys)."
else
  echo "   → No AIMOD_* placeholders provided."
fi


# ─────────────────────────────────────────
# 7) Première écriture Game.ini (base)
# ─────────────────────────────────────────
echo "📝 Writing Game.ini (base)..."
{
  cat <<EOF
; ------------------------------------------------------------------
; Insurgency Sandstorm - Game.ini (VERSUS / PvP) - base
; ------------------------------------------------------------------

[/Script/Insurgency.INSGameMode]
bKillFeed=${SS_KILL_FEED}
bKillCamera=${SS_KILL_CAMERA}
bVoiceEnabled=${SS_VOICE_ENABLED}
FriendlyFireDamageScale=${SS_FRIENDLY_FIRE_SCALE}
RoundTime=${SS_ROUND_TIME}
PostRoundTime=${SS_POST_ROUND_TIME}
bAllowVoting=${SS_VOTE_ENABLED}
RequiredVotePercentage=${SS_VOTE_PERCENT}
bDisableStats=$([ "${SS_ENABLE_STATS}" = "1" ] && echo "False" || echo "True")
EOF

  # Mods (= un par ligne)
  if [ -n "${SS_MODS}" ]; then
    IFS=',' read -ra _mods <<< "${SS_MODS}"
    for mid in "${_mods[@]}"; do
      mid_trim="$(echo "$mid" | xargs)"
      [ -n "$mid_trim" ] && echo "Mods=${mid_trim}"
    done
  fi

  # Mutators (ligne unique ok)
  if [ -n "${SS_MUTATORS}" ]; then
    echo "Mutators=${SS_MUTATORS}"
  fi

  cat <<EOF

${MODE_SECTION}
bBots=${SS_BOTS_ENABLED}
NumBots=${SS_BOT_NUM}
BotQuota=${SS_BOT_QUOTA}
BotDifficulty=${SS_BOT_DIFFICULTY}

[/Script/Insurgency.INSMultiplayerMode]
bAutoBalanceTeams=${SS_AUTO_BALANCE}
AutoBalanceDelay=${SS_AUTO_BALANCE_DELAY}
EOF
} > "${GAMEINI}"
echo "   → ${GAMEINI} (base) written."

# ─────────────────────────────────────────
# 8) Déduction Asset depuis SCENARIO (anti-range) + re-écriture
# ─────────────────────────────────────────
if [[ -z "${SS_SCENARIO}" || ! "${SS_SCENARIO}" =~ ^Scenario_ ]]; then
  echo "⚠️  SS_SCENARIO invalid or empty ('${SS_SCENARIO:-<unset>}'), fallback → Scenario_Farmhouse_Push_Security"
  SS_SCENARIO="Scenario_Farmhouse_Push_Security"
fi

scenario_core="$(printf '%s' "${SS_SCENARIO#Scenario_}" | cut -d'_' -f1)"
scenario_mode="$(printf '%s' "${SS_SCENARIO}" | awk -F'_' '{print $(NF-1)}' | tr '[:lower:]' '[:upper:]')"

case "${scenario_core}" in
  Crossing)   MAP_ASSET="Canyon"   ;;
  Hideout)    MAP_ASSET="Town"     ;;
  Hillside)   MAP_ASSET="Sinjar"   ;;
  Refinery)   MAP_ASSET="Oilfield" ;;
  *)          MAP_ASSET="${scenario_core}" ;;
esac
# Juste après avoir calculé scenario_core et scenario_mode :
case "${scenario_mode}" in
  PUSH)        MODE_SECTION="/Script/Insurgency.INSPushGameMode" ;;
  FIREFIGHT)   MODE_SECTION="/Script/Insurgency.INSFirefightGameMode" ;;
  SKIRMISH)    MODE_SECTION="/Script/Insurgency.INSSkirmishGameMode" ;;
  DOMINATION)  MODE_SECTION="/Script/Insurgency.INSDominationGameMode" ;;
  CHECKPOINT)  MODE_SECTION="/Script/Insurgency.INSCheckpointGameMode" ;;
  OUTPOST)     MODE_SECTION="/Script/Insurgency.INSOutpostGameMode" ;;
  SURVIVAL)    MODE_SECTION="/Script/Insurgency.INSSurvivalGameMode" ;;
  *)           MODE_SECTION="/Script/Insurgency.INSPushGameMode" ; scenario_mode="PUSH" ;;
esac

echo "🧭 Scenario='${SS_SCENARIO}' → Asset='${MAP_ASSET}' | MODE='${scenario_mode}'"

# Re-écriture alignée au scenario_mode (reproduit ton flux “long”)
echo "📝 Rewriting Game.ini aligned to scenario..."
{
  cat <<EOF
; ------------------------------------------------------------------
; Insurgency Sandstorm - Game.ini (VERSUS / PvP) - aligned to scenario
; ------------------------------------------------------------------

[/Script/Insurgency.INSGameMode]
bKillFeed=${SS_KILL_FEED}
bKillCamera=${SS_KILL_CAMERA}
bVoiceEnabled=${SS_VOICE_ENABLED}
FriendlyFireDamageScale=${SS_FRIENDLY_FIRE_SCALE}
RoundTime=${SS_ROUND_TIME}
PostRoundTime=${SS_POST_ROUND_TIME}
bAllowVoting=${SS_VOTE_ENABLED}
RequiredVotePercentage=${SS_VOTE_PERCENT}
bDisableStats=$([ "${SS_ENABLE_STATS}" = "1" ] && echo "False" || echo "True")
EOF

  # Mods & Mutators de nouveau pour s'assurer qu'ils restent présents
  if [ -n "${SS_MODS}" ]; then
    IFS=',' read -ra _mods <<< "${SS_MODS}"
    for mid in "${_mods[@]}"; do
      mid_trim="$(echo "$mid" | xargs)"
      [ -n "$mid_trim" ] && echo "Mods=${mid_trim}"
    done
  fi
  if [ -n "${SS_MUTATORS}" ]; then
    echo "Mutators=${SS_MUTATORS}"
  fi

  cat <<EOF

${MODE_SECTION}
bBots=${SS_BOTS_ENABLED}
NumBots=${SS_BOT_NUM}
BotQuota=${SS_BOT_QUOTA}
BotDifficulty=${SS_BOT_DIFFICULTY}

[/Script/Insurgency.INSMultiplayerMode]
bAutoBalanceTeams=${SS_AUTO_BALANCE}
AutoBalanceDelay=${SS_AUTO_BALANCE_DELAY}
EOF
} > "${GAMEINI}"
echo "   → ${GAMEINI} (aligned) rewritten."

# ─────────────────────────────────────────
# 9) Construction de l’URL de lancement
# ─────────────────────────────────────────
LAUNCH_URL="${MAP_ASSET}?Scenario=${SS_SCENARIO}?MaxPlayers=${SS_MAXPLAYERS}\
?bBots=${SS_BOTS_ENABLED}?NumBots=${SS_BOT_NUM}?BotQuota=${SS_BOT_QUOTA}?BotDifficulty=${SS_BOT_DIFFICULTY}"

# Mutators + Args en URL (double sécurité)
if [ -n "${SS_MUTATORS}" ]; then
  LAUNCH_URL="${LAUNCH_URL}?Mutators=${SS_MUTATORS}"
fi
if [ -n "${SS_MUTATOR_URL_ARGS}" ]; then
  # Si SS_MUTATOR_URL_ARGS contient déjà des '?', on les garde, on chaîne simplement
  LAUNCH_URL="${LAUNCH_URL}?${SS_MUTATOR_URL_ARGS}"
fi

echo "▶️  Launch URL:"
echo "    ${LAUNCH_URL}"

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
cd "${GAMEDIR}/Insurgency/Binaries/Linux" || {
  echo "❌ Cannot cd to ${GAMEDIR}/Insurgency/Binaries/Linux"
  exit 1
}

echo "🚀 Launching InsurgencyServer-Linux-Shipping..."
echo "    Hostname='${SS_HOSTNAME}'"
echo "    Ports: -Port=${PORT} -QueryPort=${QUERYPORT} -BeaconPort=${BEACONPORT}"
echo "    AdminList='${ADMINSLIST_NAME}' (${ADMINSLIST_PATH})"
echo "    Extra args: '${EXTRA_SERVER_ARGS}'"
echo "────────────────────────────────────────────────────────"

exec ./InsurgencyServer-Linux-Shipping \
  "${LAUNCH_URL}" \
  -hostname="${SS_HOSTNAME}" \
  -Port="${PORT}" -QueryPort="${QUERYPORT}" -BeaconPort="${BEACONPORT}" \
  -AdminList="${ADMINSLIST_NAME}" \
  -Rcon ${RCON_PASSWORD:+-RconPassword="${RCON_PASSWORD}"} \
  -log \
  ${EXTRA_SERVER_ARGS} \
  "${XP_ARGS[@]}"
