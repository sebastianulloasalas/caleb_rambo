// Rookie

#include "core"
#include "math"
#include "bots"

/* Rookie is a slight improvement of Recruit. Its srategy still
   consists in looking around and shoot directly to every enemy
   it sees, but it also use ears to hear enemy shots and point
   to hidden enemies. At the beginning, the chief of the team
   orders to its mates to change their forward direction pointing
   outside the group. In addition the bots launch the grenades
   over the heads of its mates. Even this bot uses the same
   strategy for every goal, so it doesn't worry to protect the
   chief when it should be better to do it.
*/
fight() {
// some constants to make the source more readable
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR
  new const ENEMY_WARRIOR = ITEM_ENEMY|ITEM_WARRIOR
  new const ENEMY_GUN = ITEM_ENEMY|ITEM_GUN
// constant that defines the rate of direction changes
  new const float:CHANGE_DIR_TIME = 10.0
// small angle to change direction in front of the walls
  new const float:AVOID_WALL_DIR = (getID()%2 == 0? 0.31415: -0.31415)
// maximum extension of head rotations (all angles are in radians)
  new float:headDir = 1.047
// needed for change of direction countdown
  new float:lastTime = getTime()
//// If the bot is the chief, order to turn back
  if(getID() == 0) {
    say(1)
//// If the bot is a mate, obey the chief's order
  } else {
//// Hear from which direction comes the order...
    new item
    new sound
    new float:yaw
    do {
      item = 0
      hear(item,sound,yaw)
    } while(item != FRIEND_WARRIOR)
//// ... and turn your back towards that direction
    new float:halfTurn = 3.1415
    if(yaw > 0) halfTurn = -halfTurn
    rotate(getDirection()+yaw+halfTurn)
  }
//// Wait until the turn has completed, then walk
  wait(1.5)
  walk()
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
//// ... point to the enemy
      rotate(yaw+getDirection())
      bendTorso(pitch) // inclines the torso towards the enemy
      bendHead(-pitch) // make to head look forward horizontally
      rotateHead(0.0)  // (above bends needed for crouched enemies)
//// If walking, run
      if(isWalking())
        run()
//// If enemy in range, launch a grenade...
      if(getGrenadeLoad() > 0 && dist > 30 && dist < 60) {
//// Bend the torso to launch the grenade above the heads of the mates
        bendTorso(0.5236)
        wait(0.5) // temporization needed to reach the requested angle
        launchGrenade()
        bendTorso(pitch)
        wait(0.5)
      } else {
//// ... else shoot a bullet
        aim(item) // checks for friends right in front of the gun
        if(item != FRIEND_WARRIOR)
          shootBullet()
      }
//// If there is no enemy in view...
    } else {
//// ... hear enemy shots
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

