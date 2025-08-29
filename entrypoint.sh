#!/bin/bash
set -eo pipefail

# ─────────────────────────────────────────
# 0) Chemins / base
# ─────────────────────────────────────────
GAMEDIR="${GAMEDIR:-/opt/sandstorm}"
CFGDIR="${CFGDIR:-${GAMEDIR}/Insurgency/Config/Server}"
GAMEINI="${GAMEINI:-${CFGDIR}/Game.ini}"
MAPCYCLE="${MAPCYCLE:-${CFGDIR}/MapCycle.txt}"
STEAMCMDDIR="${STEAMCMDDIR:-/home/steam/steamcmd}"
APPID="${APPID:-581330}"

AUTO_UPDATE="${AUTO_UPDATE:-1}"
PORT="${PORT:-27102}"
QUERYPORT="${QUERYPORT:-27131}"
BEACONPORT="${BEACONPORT:-15000}"

SS_HOSTNAME="${SS_HOSTNAME:-CHOURMOVS ISS • COOP}"
SS_MAXPLAYERS="${SS_MAXPLAYERS:-24}"

# Lancement par défaut (COOP)
SS_SCENARIO="${SS_SCENARIO:-Scenario_Farmhouse_Checkpoint_Security}"

# QoL / vote / timers
SS_KILL_FEED="${SS_KILL_FEED:-1}"
SS_KILL_CAMERA="${SS_KILL_CAMERA:-0}"
SS_VOICE_ENABLED="${SS_VOICE_ENABLED:-1}"
SS_FRIENDLY_FIRE_SCALE="${SS_FRIENDLY_FIRE_SCALE:-0.2}"
SS_ROUND_TIME="${SS_ROUND_TIME:-900}"
SS_POST_ROUND_TIME="${SS_POST_ROUND_TIME:-15}"
SS_VOTE_ENABLED="${SS_VOTE_ENABLED:-1}"
SS_VOTE_PERCENT="${SS_VOTE_PERCENT:-0.6}"

# Bots (COOP)
SS_BOTS_ENABLED="${SS_BOTS_ENABLED:-1}"
SS_BOT_NUM="${SS_BOT_NUM:-0}"
SS_BOT_QUOTA="${SS_BOT_QUOTA:-6.0}"
SS_BOT_DIFFICULTY="${SS_BOT_DIFFICULTY:-0.9}"
SS_FRIENDLY_BOT_QUOTA="${SS_FRIENDLY_BOT_QUOTA:-0}"
SS_MIN_ENEMIES="${SS_MIN_ENEMIES:-10}"
SS_MAX_ENEMIES="${SS_MAX_ENEMIES:-10}"

# XP / Stats
SS_ENABLE_STATS="${SS_ENABLE_STATS:-1}"
GSLT_TOKEN="${GSLT_TOKEN:-}"
GAMESTATS_TOKEN="${GAMESTATS_TOKEN:-}"
RCON_PASSWORD="${RCON_PASSWORD:-}"

# Workshop / Mutators
SS_MODS="${SS_MODS:-}"            # "1141916,12345"
SS_MUTATORS="${SS_MUTATORS:-}"    # "AiModifier,..."
EXTRA_SERVER_ARGS="${EXTRA_SERVER_ARGS:-}"

echo "────────────────────────────────────────"
echo "▶️  Boot Sandstorm | ${SS_HOSTNAME}"
echo "   Scenario=${SS_SCENARIO} | Max=${SS_MAXPLAYERS}"
echo "────────────────────────────────────────"

# ─────────────────────────────────────────
# 1) FS
# ─────────────────────────────────────────
mkdir -p "${CFGDIR}" "$(dirname "${MAPCYCLE}")"

# ─────────────────────────────────────────
# 2) SteamCMD update (tolérant)
# ─────────────────────────────────────────
if [ "${AUTO_UPDATE}" = "1" ]; then
  echo "📥 SteamCMD updating app ${APPID}..."
  "${STEAMCMDDIR}/steamcmd.sh" +@sSteamCmdForcePlatformType linux \
    +force_install_dir "${GAMEDIR}" +login anonymous +app_update "${APPID}" validate +quit \
    || echo "⚠️ SteamCMD failed (continuing anyway)"
fi

# ─────────────────────────────────────────
# 3) MapCycle (COOP par défaut, propre)
# ─────────────────────────────────────────
if [ -n "${SS_MAPCYCLE}" ]; then
  echo "${SS_MAPCYCLE}" | tr '\r' '\n' | sed '/^\s*$/d' > "${MAPCYCLE}"
else
  cat > "${MAPCYCLE}" <<EOF
Scenario_Farmhouse_Checkpoint_Security
Scenario_Crossing_Checkpoint_Security
Scenario_Hideout_Checkpoint_Security
Scenario_Refinery_Checkpoint_Security
Scenario_Summit_Checkpoint_Security
Scenario_Hillside_Checkpoint_Security
EOF
fi
echo "🗺️  MapCycle → ${MAPCYCLE}"

# ─────────────────────────────────────────
# 4) Game.ini (valeurs réelles)
# ─────────────────────────────────────────
{
  cat <<EOF
; ------------------------------------------------------------------
; Insurgency Sandstorm - Game.ini (generated)
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

[/Script/Insurgency.INSMultiplayerMode]
bMapVoting=True
bUseMapCycle=True
EOF

  # Mods Workshop
  if [ -n "${SS_MODS}" ]; then
    IFS=',' read -ra _mods <<< "${SS_MODS}"
    for mid in "${_mods[@]}"; do
      mid_trim="$(echo "$mid" | xargs)"
      [ -n "${mid_trim}" ] && echo "Mods=${mid_trim}"
    done
  fi

  # Mutators (déclaration)
  [ -n "${SS_MUTATORS}" ] && echo "Mutators=${SS_MUTATORS}"

  cat <<EOF

[/Script/Insurgency.INSCoopMode]
bAutoBalanceTeams=False
AutoBalanceDelay=10

[/Script/Insurgency.INSCheckpointGameMode]
bBots=${SS_BOTS_ENABLED}
NumBots=${SS_BOT_NUM}
BotQuota=${SS_BOT_QUOTA}
BotDifficulty=${SS_BOT_DIFFICULTY}
FriendlyBotQuota=${SS_FRIENDLY_BOT_QUOTA}
MinimumEnemies=${SS_MIN_ENEMIES}
MaximumEnemies=${SS_MAX_ENEMIES}

[/Script/Insurgency.INSOutpostGameMode]
[/Script/Insurgency.INSSurvivalGameMode]
EOF
} > "${GAMEINI}"
echo "📝 Game.ini written."

# ─────────────────────────────────────────
# 5) AiModifier → URL (toutes les CVAR)
# ─────────────────────────────────────────
AIMOD_ARGS=()
add_arg() { local k="$1"; local v="$2"; [ -n "${v:-}" ] && AIMOD_ARGS+=("${k}=${v}"); }

# 1) Skill
add_arg "AIModifier.Difficulty" "${AIMOD_DIFFICULTY}"
add_arg "AIModifier.Accuracy" "${AIMOD_ACCURACY}"
add_arg "AIModifier.ReactionTime" "${AIMOD_REACTION}"

# 2) Sight
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

# 3) Spot chance
add_arg "AIModifier.ChanceSprintMultiplier" "${AIMOD_CH_SPRINT_MULT}"
add_arg "AIModifier.ChanceMovingMultiplier" "${AIMOD_CH_MOVING_MULT}"
add_arg "AIModifier.ChanceAtDistanceStanding" "${AIMOD_CH_STAND_DIST}"
add_arg "AIModifier.ChanceAtCloseRangeStanding" "${AIMOD_CH_STAND_CLOSE}"
add_arg "AIModifier.ChanceAtDistanceCrouched" "${AIMOD_CH_CROUCH_DIST}"
add_arg "AIModifier.ChanceAtCloseRangeCrouched" "${AIMOD_CH_CROUCH_CLOSE}"
add_arg "AIModifier.ChanceAtDistanceProne" "${AIMOD_CH_PRONE_DIST}"
add_arg "AIModifier.ChanceAtCloseRangeProne" "${AIMOD_CH_PRONE_CLOSE}"

# 4) Hearing
add_arg "AIModifier.HearAwareDistanceRadial" "${AIMOD_HEAR_AWARE_RADIAL}"
add_arg "AIModifier.HearAwareDistanceGunshot" "${AIMOD_HEAR_AWARE_GUNSHOT}"
add_arg "AIModifier.HearAwareDistanceSprintFootstep" "${AIMOD_HEAR_AWARE_SPRINT}"
add_arg "AIModifier.HearAwareDistanceFootsteps" "${AIMOD_HEAR_AWARE_FOOT}"
add_arg "AIModifier.HearDistanceFootstepsSprinting" "${AIMOD_HEAR_DIST_SPRINT}"
add_arg "AIModifier.HearDistanceFootstepsRunning" "${AIMOD_HEAR_DIST_RUN}"
add_arg "AIModifier.HearAbilityZOffsetMin" "${AIMOD_HEAR_Z_MIN}"
add_arg "AIModifier.HearAbilityZOffsetMax" "${AIMOD_HEAR_Z_MAX}"
add_arg "AIModifier.FencedTargetHearAbilityModifier" "${AIMOD_HEAR_FENCED_MOD}"

# 5) Turn speed
add_arg "AIModifier.TurnSpeedMaxAngleThreshold" "${AIMOD_TURNSPD_MAX_ANGLE_TH}"
add_arg "AIModifier.TurnSpeedMinAngleThreshold" "${AIMOD_TURNSPD_MIN_ANGLE_TH}"
add_arg "AIModifier.TurnSpeedMaxAngle" "${AIMOD_TURNSPD_MAX}"
add_arg "AIModifier.TurnSpeedMinAngle" "${AIMOD_TURNSPD_MIN}"
add_arg "AIModifier.TurnSpeedDistanceThreshold" "${AIMOD_TURNSPD_DIST_TH}"
add_arg "AIModifier.TurnSpeedScaleModifierMax" "${AIMOD_TURNSPD_SCALE_MAX}"
add_arg "AIModifier.TurnSpeedScaleModifierMin" "${AIMOD_TURNSPD_SCALE_MIN}"

# 6) Attack & ranges
add_arg "AIModifier.AttackDelayClose" "${AIMOD_ATTACK_DELAY_CLOSE}"
add_arg "AIModifier.AttackDelayDistant" "${AIMOD_ATTACK_DELAY_DIST}"
add_arg "AIModifier.AttackDelayMelee" "${AIMOD_ATTACK_DELAY_MELEE}"
add_arg "AIModifier.DistanceRange" "${AIMOD_DISTANCE_RANGE}"
add_arg "AIModifier.CloseRange" "${AIMOD_CLOSE_RANGE}"
add_arg "AIModifier.MiddleRange" "${AIMOD_MID_RANGE}"
add_arg "AIModifier.FarRange" "${AIMOD_FAR_RANGE}"
add_arg "AIModifier.MeleeRange" "${AIMOD_MELEE_RANGE}"

# 7) Accuracy / bloatbox
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

# 8) Comportements
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

# 9) Spotting / leaning
add_arg "AIModifier.bonusSpotLossStartingDistance" "${AIMOD_BONUS_SPOT_START}"
add_arg "AIModifier.maxBonusSpotChanceHearing" "${AIMOD_MAX_BONUS_SPOT_HEAR}"
add_arg "AIModifier.maxBonusSpotChanceAlert" "${AIMOD_MAX_BONUS_SPOT_ALERT}"
add_arg "AIModifier.ChanceLeanMultiplier" "${AIMOD_CH_LEAN_MULT}"
add_arg "AIModifier.minChance2Hear" "${AIMOD_MIN_CHANCE_HEAR}"
add_arg "AIModifier.InjuredDmgThreshold" "${AIMOD_INJ_DMG_TH}"
add_arg "AIModifier.InjuredHPRatioThreshold" "${AIMOD_INJ_HP_RATIO}"

# 10) Objectives
add_arg "AIModifier.DistanceNear2Objective" "${AIMOD_DIST_NEAR_OBJ}"
add_arg "AIModifier.DistanceMid2Objective" "${AIMOD_DIST_MID_OBJ}"
add_arg "AIModifier.DistanceFar2Objective" "${AIMOD_DIST_FAR_OBJ}"
add_arg "AIModifier.ratioBotsClose2Objective" "${AIMOD_RATIO_BOTS_CLOSE_OBJ}"

# 11) Suppression
add_arg "AIModifier.minTime2StopFiringNLOS" "${AIMOD_STOP_FIRE_NLOS_MIN}"
add_arg "AIModifier.maxTime2StopFiringNLOS" "${AIMOD_STOP_FIRE_NLOS_MAX}"
add_arg "AIModifier.minSuppressionTime" "${AIMOD_SUPPR_TIME_MIN}"
add_arg "AIModifier.maxSuppressionTime" "${AIMOD_SUPPR_TIME_MAX}"
add_arg "AIModifier.SuppressionMinDistance" "${AIMOD_SUPPR_MIN_DIST}"
add_arg "AIModifier.BaseChance2Suppress" "${AIMOD_SUPPR_BASE_CH}"
add_arg "AIModifier.AddChance2SuppressPerFriend" "${AIMOD_SUPPR_ADD_FRIEND}"

# 12) Head/body ratio
add_arg "AIModifier.ratioAimingHead2Body" "${AIMOD_HEAD2BODY_RATIO}"
add_arg "AIModifier.ratioAimingHead2Body" "${AIMOD_RATIO_AIM_HEAD}"

# 13) Variable difficulty
add_arg "AIModifier.PlayerCountForMinAIDifficulty" "${AIMOD_VAR_PC_MIN}"
add_arg "AIModifier.PlayerCountForMaxAIDifficulty" "${AIMOD_VAR_PC_MAX}"
add_arg "AIModifier.MinAIDifficulty" "${AIMOD_VAR_MIN_DIFFICULTY}"
add_arg "AIModifier.MaxAIDifficulty" "${AIMOD_VAR_MAX_DIFFICULTY}"

# 14) Respawns
add_arg "AIModifier.MaxCount" "${AIMOD_MAXCOUNT}"
add_arg "AIModifier.RespawnTimeMin" "${AIMOD_RESPAWN_MIN}"
add_arg "AIModifier.RespawnTimeMax" "${AIMOD_RESPAWN_MAX}"
add_arg "AIModifier.SpawnDelay" "${AIMOD_SPAWN_DELAY}"

# 15) Divers
add_arg "AIModifier.bOverwriteBotSkillCfg" "${AIMOD_OVERWRITE_BOTCFG}"
add_arg "AIModifier.bBotUsesSmokeGrenade" "${AIMOD_BOT_USES_SMOKE}"
add_arg "AIModifier.bSuppression4MgOnly" "${AIMOD_SUPPR_4MG_ONLY}"
add_arg "AIModifier.MemoryMaxAge" "${AIMOD_MEMORY_MAX_AGE}"

# 16) Knife & squads
add_arg "AIModifier.AllowMelee" "${AIMOD_ALLOW_MELEE}"
add_arg "AIModifier.StayInSquads" "${AIMOD_STAY_IN_SQUADS}"
add_arg "AIModifier.SquadSize" "${AIMOD_SQUAD_SIZE}"

# Compose URL string
SS_MUTATOR_URL_ARGS=""
if [ ${#AIMOD_ARGS[@]} -gt 0 ]; then
  SS_MUTATOR_URL_ARGS="$(IFS='?'; echo "${AIMOD_ARGS[*]}")"
fi

# ─────────────────────────────────────────
# 6) Déduction du MAP_ASSET depuis SS_SCENARIO
# ─────────────────────────────────────────
scenario_core="$(echo "${SS_SCENARIO#Scenario_}" | cut -d'_' -f1)"
case "${scenario_core}" in
  Crossing)   MAP_ASSET="Canyon" ;;
  Hideout)    MAP_ASSET="Town" ;;
  Hillside)   MAP_ASSET="Sinjar" ;;
  Refinery)   MAP_ASSET="Oilfield" ;;
  *)          MAP_ASSET="${scenario_core}" ;;
esac

# ─────────────────────────────────────────
# 7) Construction URL de lancement
# ─────────────────────────────────────────
LAUNCH_URL="${MAP_ASSET}?Scenario=${SS_SCENARIO}?MaxPlayers=${SS_MAXPLAYERS}"
[ -n "${SS_MUTATORS}" ] && LAUNCH_URL="${LAUNCH_URL}?Mutators=${SS_MUTATORS}"
[ -n "${SS_MUTATOR_URL_ARGS}" ] && LAUNCH_URL="${LAUNCH_URL}?${SS_MUTATOR_URL_ARGS}"

echo "▶️  Launch URL: ${LAUNCH_URL}"

# XP flags
XP_ARGS=()
if [ -n "${GSLT_TOKEN}" ] && [ -n "${GAMESTATS_TOKEN}" ] && [ -z "${RCON_PASSWORD}" ]; then
  XP_ARGS+=( "-GSLTToken=${GSLT_TOKEN}" "-GameStatsToken=${GAMESTATS_TOKEN}" )
  echo "✨ XP enabled."
else
  echo "ℹ️ XP disabled (tokens missing or RCON set)."
fi

# RCON flags
RCON_ARGS=()
[ -n "${RCON_PASSWORD}" ] && RCON_ARGS+=( "-Rcon" "-RconPassword=${RCON_PASSWORD}" )

# ─────────────────────────────────────────
# 8) Exécution finale
# ─────────────────────────────────────────
cd "${GAMEDIR}/Insurgency/Binaries/Linux" || exit 1

exec ./InsurgencyServer-Linux-Shipping \
  "${LAUNCH_URL}" \
  -hostname="${SS_HOSTNAME}" \
  -Port="${PORT}" -QueryPort="${QUERYPORT}" -BeaconPort="${BEACONPORT}" \
  -AdminList=Admins \
  -log \
  "${XP_ARGS[@]}" \
  "${RCON_ARGS[@]}" \
  ${EXTRA_SERVER_ARGS}

