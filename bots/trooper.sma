// Trooper

#include "core"
#include "math"
#include "bots"

/* Trooper is different from Rookie since all the bots point at
   the beginning in the same direction. Its srategy still
   consists in looking around and shoot directly to every enemy
   it sees, but its firepower is stronger because a lot of bots
   fire in the same direction. In addition, some bots look for
   the second nearest enemy bot, to fire to multipe targets.
   It also use ears to hear enemy shots and point to hidden
   enemies. Grenades are again launched horizontally to possibly
   explode in close contact with enemies. Even this bot uses the
   same strategy for every goal, so it doesn't worry to protect
   the chief when it should be better to do it.
*/
fight() {
// some constants to make the source more readable
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR
  new const ENEMY_WARRIOR = ITEM_ENEMY|ITEM_WARRIOR
  new const ENEMY_GUN = ITEM_ENEMY|ITEM_GUN
// constant that defines the rate of direction changes
  new const float:CHANGE_DIR_TIME = 20.0
// small angle to change direction in front of the walls
  new const float:AVOID_WALL_DIR = 0.31415
// maximum extension of head rotations (all angles are in radians)
  new float:headDir = 1.047
// needed for change of direction countdown
  new float:lastTime = getTime()
//// All the mates rotate towards the same direction
  rotate(3.1415)
//// Wait to be sure that all completed the rotation
  wait(2.0)
//// Walk (and wait a bit to be sure to be walking for next calls)
  walk()
  wait(0.02)
// loop forever
  for(;;) {
    new float:thisTime = getTime()
//// Change direction of 90 degrees every 10 seconds
    if(thisTime-lastTime > CHANGE_DIR_TIME) {
      lastTime = thisTime
      new float:randAngle = float(random(3)-1)*1.5758
      rotate(getDirection()+randAngle)
//// If standing, change direction (maybe the bot hit another bot)
    } else if(isStanding()) {
      rotate(getDirection()+1.5708)
      wait(1.0)
      walk()
//// If the wall is nearest than 5 m, change direction
    } else if(sight() < 5.0) {
      rotate(getDirection()+AVOID_WALL_DIR)
    }
//// If there is anything touched, raise it (may be a powerup)
    new touched = getTouched()
    if(touched) raise(touched)
//// Look for enemies
    new item = ENEMY_WARRIOR
    new float:dist = 0.0
    new float:yaw
    new float:pitch
    watch(item,dist,yaw,pitch)
//// If there is an enemy...
    if(item == ENEMY_WARRIOR) {
      if(getID()%2 == 0) {
//// ... and ID is even look again for another target...
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
//// ... then point to the enemy...
      rotate(yaw+getDirection())
      bendTorso(pitch) // inclines the torso towards the enemy
      bendHead(-pitch) // make to head look forward horizontally
      rotateHead(0.0)  // (above bends needed for crouched enemies)
//// ... if walking, run...
      if(isWalking())
        run()
//// ... if enemy in range, launch a grenade...
      if(getGrenadeLoad() > 0 && dist > 30 && dist < 60) {
        new aimItem
        aim(aimItem)
        if(aimItem != FRIEND_WARRIOR)
          launchGrenade()
//// ... otherwise shoot a bullet...
      } else {
        new aimItem
        aim(aimItem)
        if(aimItem != FRIEND_WARRIOR)
          shootBullet()
      }
    }
//// In case that no enemy was seen...
    if(item != ENEMY_WARRIOR) {
//// ... hear for guns
      new sound
      dist = hear(item,sound,yaw)
//// Shot heard, run and rotate
      if(item == ENEMY_GUN) {
        if(isWalking())
          run()
        rotate(yaw+getDirection())
        wait(0.5)
//// Nothing heard, walk and look around
      } else {
        if(isRunning())
          walk()
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

