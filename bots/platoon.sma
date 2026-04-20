// Platoon

#include "core"
#include "math"
#include "bots"

/* Platoon is the same as Trooper, but it doesn't run and some
   of the mates crouch to free the line of fire to their mates.
   The firepower increases greately, but the mobility of the
   team is decreased. Some additional temporization is needed
   because after crouch() a bot needs to wait 1 second before
   beginning a walk crouched.
*/
fight() {
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR
  new const ENEMY_WARRIOR = ITEM_ENEMY|ITEM_WARRIOR
  new const ENEMY_GUN = ITEM_ENEMY|ITEM_GUN
  new const float:CHANGE_DIR_TIME = 20.0
  new const float:AVOID_WALL_DIR = 0.31415
  new float:headDir = 1.047
  new float:lastTime = getTime()
  rotate(3.1415)
  wait(2.0)
  if(getID()%2 == 0)
    crouch()
  wait(1.0)
  if(getID()%2 == 0)
    walkcr()
  else
    walk()
  wait(0.02)
  for(;;) {
    new float:thisTime = getTime()
    if(thisTime-lastTime > CHANGE_DIR_TIME) {
      lastTime = thisTime
      new float:randAngle = float(random(3)-1)*1.5758
      rotate(getDirection()+randAngle)
    } else if(isStanding()) {
      rotate(getDirection()+0.7854)
      if(getID()%2 == 0) {
        wait(0.5)
        crouch()
        wait(1.0)
        walkcr()
      } else {
        walk()
      }
    } else if(sight() < 5.0) {
      rotate(getDirection()+AVOID_WALL_DIR)
    }
    new touched = getTouched()
    if(touched) raise(touched)
    new item = ENEMY_WARRIOR
    new float:dist = 0.0
    new float:yaw
    new float:pitch
    watch(item,dist,yaw,pitch)
    if(item == ENEMY_WARRIOR) {
      if(getID()%2 == 0) {
        new float:oldDist = dist
        new float:oldYaw = yaw
        new float:oldPitch =pitch
        item = ENEMY_WARRIOR
        watch(item,dist,yaw,pitch)
        if(item == ITEM_NONE) {
          item = ENEMY_WARRIOR
          dist = oldDist
          yaw = oldYaw
          pitch = oldPitch
        }
      }
      rotate(yaw+getDirection())
      bendTorso(pitch)
      bendHead(-pitch)
      rotateHead(0.0)
      if(getGrenadeLoad() > 0 && dist > 30 && dist < 60) {
        new aimItem
        aim(aimItem)
        if(aimItem != FRIEND_WARRIOR)
          launchGrenade()
      } else {
        new aimItem
        aim(aimItem)
        if(aimItem != FRIEND_WARRIOR)
          shootBullet()
      }
    }
    if(item != ENEMY_WARRIOR) {
      new sound
      dist = hear(item,sound,yaw)
      if(item == ENEMY_GUN) {
        rotate(yaw+getDirection())
        wait(0.5)
      } else {
        rotateHead(headDir)
        if(getHeadYaw() == headDir)
          headDir = -headDir
      }
    }
  }
}

/* basic soccer code */
soccer() {
  new const float:PI = 3.1415
// small angle to change direction in front of the walls
  new const float:AVOID_WALL_DIR =
    (getID()%2 == 0? PI/10.0: -PI/10.0)
// constant that defines the rate of direction changes
  new const float:CHANGE_DIR_TIME = 10.0
// needed for several countdowns
  new float:lastTime = getTime()
// rotate, find target and move
  rotate(getDirection()+PI*2.0)
// look for target
  new float:dist
  new float:yaw
  new item
  do {
    item = ITEM_TARGET
    dist = 0.0
    watch(item,dist,yaw)
  } while(item != ITEM_TARGET)
// point to the target
  rotate(getDirection()+yaw)
  setKickSpeed(getMaxKickSpeed());
  bendTorso(0.3);
  bendHead(-0.3);
  new float:waitTime = 3-getTime()+lastTime;
  if(waitTime > 0)
    wait(waitTime)
  walk()
  wait(0.1)
// loop forever
  for(;;) {
    new float:thisTime = getTime()
// change direction of 90 degrees every 10 seconds
    if(thisTime-lastTime > CHANGE_DIR_TIME) {
      lastTime = thisTime
      rotate(getDirection()+(float(random(2))-0.5)*PI)
// if standing, change direction (maybe the bot hit another bot)
    } else if(isStanding()) {
      rotate(getDirection()+(float(random(2))-0.5)*PI)
      wait(1.0)
      walk()
// if the wall is nearest than 2 m, change direction
    } else if(sight() < 2.0) {
      rotate(getDirection()+AVOID_WALL_DIR)
    }
// if there is anything touched, raise it (may be a powerup)
    new touched = getTouched()
    if(touched) raise(touched)
// look for target
    item = ITEM_TARGET
    dist = 0.0
    watch(item,dist,yaw)
// if there is a target...
    if(item == ITEM_TARGET) {
// ... point to the target
      rotate(yaw+getDirection())
// if walking, run
      if(isWalking())
        run()
    }
  }
}

/* main entry */
main() {
  switch(getPlay()) {
    case PLAY_FIGHT: fight()
    case PLAY_SOCCER: soccer()
// no code specific for RACE mode yet
    case PLAY_RACE: fight()
  }
}

