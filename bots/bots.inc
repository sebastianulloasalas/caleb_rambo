#if defined _bots_included
  #endinput
#endif
#define _bots_included

enum {GOAL_TERMINATE_CHIEF = 0, GOAL_TERMINATE_TEAM, GOAL_CAPTURE_SIGN};
enum {PLAY_FIGHT = 0, PLAY_SOCCER, PLAY_RACE};
enum {ATTRIBUTE_NONE = 0, ATTRIBUTE_HAS_GUN, ATTRIBUTE_HAS_SIGN};
enum {SOUND_NONE = 0, SOUND_SHOT, SOUND_LAUNCH, SOUND_BOOM};
enum {
  ACTION_MOVE = 0,
  ACTION_DROP,
  ACTION_SHOOT,
  ACTION_SAY,
  ACTION_HEAR,
  ACTION_SIGHT,
  ACTION_AIM,
  ACTION_WATCH,
  ACTION_SPEAK,
  ACTION_LISTEN
}
enum {
  ITEM_NONE     = 0,
  ITEM_FRIEND   = 1,
  ITEM_ENEMY    = 2,
  ITEM_WARRIOR  = 4,
  ITEM_GUN      = 8,
  ITEM_BULLET   = 16,
  ITEM_GRENADE  = 32,
  ITEM_MEDIKIT  = 64,
  ITEM_FOOD     = 128,
  ITEM_ARMOR    = 256,
  ITEM_BULLETS  = 512,
  ITEM_GRENADES = 1024,
  ITEM_SIGN     = 2048,
  ITEM_TARGET   = 4096
};

native getGoal();
native getPlay();
native getTeams();
native getMates();
native getTimeout();
native getKilledEnemies();
native getKilledFriends();
native bool:getGoalLocation(team,&float:x,&float:y,&float:z=0.0);
native float:getGoalSize();
native float:getTargetSize();
native float:getTargetMaxSpeed();
native float:getTime();
native getTicksCount();
native float:getSimulationStep();
native float:getCPUPeriod();
native float:getTimeNeededFor(action);
native float:getTimeForRespawn(item);
native float:getTimeLostTo(action);
native getMemorySize();
native getID();
native getLocation(&float:x,&float:y,&float:z=0.0);
native float:getSize();
native float:getHeight();
native float:getWeaponHeight();
native float:getWeaponLength();
native bool:isStanding();
native bool:isCrouched();
native bool:isWalking();
native bool:isWalkingcr();
native bool:isWalkingbk();
native bool:isRunning();
native bool:stand();
native bool:crouch();
native bool:walk();
native bool:walkcr();
native bool:walkbk();
native bool:run();
native bool:rotate(float:angle);
native bool:isRotating();
native bool:rotateTorso(float:angle);
native bool:isTorsoRotating();
native bool:rotateHead(float:angle);
native bool:isHeadRotating();
native bool:bendTorso(float:angle);
native bool:isTorsoBending();
native bool:bendHead(float:angle);
native bool:isHeadBending();
native bool:wait(float:time);
native bool:say(word);
native bool:speak(channel,word);
native bool:listen(channel,&word,&id=0);
native float:hear(&item,&sound,&float:yaw=0.0,&float:pitch=0.0,&id=0);
native float:getMaxKickSpeed();
native float:getKickSpeed();
native float:setKickSpeed(float:speed);
native float:getWalkSpeed();
native float:getWalkcrSpeed();
native float:getWalkbkSpeed();
native float:getRunSpeed();
native float:getFallMaxSpeed();
native watch(&item,&float:dist,&float:yaw=0.0,&float:pitch=0.0,&id=0);
native float:sight();
native float:aim(&item);
native float:getEnergy();
native float:getMaxEnergy();
native float:getRunEnergyLoss();
native float:getStandEnergyGain();
native float:getHealth();
native float:getMaxHealth();
native float:getBulletHealthLoss();
native float:getGrenadeMaxDamage();
native float:getArmor();
native float:getMaxArmor();
native getOwned();
native getTouched();
native float:getDropAmount(item)
native bool:drop(item);
native bool:raise(item);
native float:getDirection();
native float:getRotSpeed();
native float:getTorsoYaw();
native float:getTorsoMinYaw();
native float:getTorsoMaxYaw();
native float:getTorsoPitch();
native float:getTorsoMinPitch();
native float:getTorsoMaxPitch();
native float:getTorsoRotSpeed();
native float:getHeadYaw();
native float:getHeadMinYaw();
native float:getHeadMaxYaw();
native float:getHeadPitch();
native float:getHeadMinPitch();
native float:getHeadMaxPitch();
native float:getHeadRotSpeed();
native float:getAngleOfView();
native float:getSensorsRange();
native bool:shootBullet();
native float:getBulletSpeed();
native getBulletLoad();
native getBulletMaxLoad();
native bool:launchGrenade();
native float:getGrenadeSpeed();
native getGrenadeLoad();
native getGrenadeMaxLoad();
native getGrenadeMaxRange();
native getGrenadeDelay();
native getExplosionTimeLen();
native float:getGravity();
native float:getGroundElasticity();
