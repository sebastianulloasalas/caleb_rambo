// circulo_movil_simple.sma
//
// Script simple y robusto para toolchains viejos:
// 1) Los bots forman un circulo alrededor del lider (ID 0).
// 2) Tras un tiempo de armado, el lider avanza hacia un lado del mapa.
// 3) Los followers siguen al lider manteniendo su posicion relativa.

#include "core"
#include "math"
#include "bots"

new const LEADER_ID = 0

new const RADIO_CHANNEL_LEADER = 71
new const WORD_LEADER_PING = 8601

new const float:PI = 3.1415
new const float:TWO_PI = 6.2830

new const float:MAP_SAFE_HALF = 58.0
new const float:TARGET_MARGIN = 4.0

new const float:FORM_TIMEOUT = 9.0
new const float:FORM_CENTER_RADIUS = 1.3
new const float:LEADER_ARRIVE_RADIUS = 2.0

new const float:SLOT_RADIUS_BASE = 5.2
new const float:SLOT_RADIUS_PER_BOT = 0.22
new const float:SLOT_MOVE_RADIUS = 1.05
new const float:SLOT_HOLD_RADIUS = 0.72

new const float:WALL_AVOID_DIST = 1.45
new const float:BLOCK_DIST = 1.45
new const float:BLOCK_YAW = 0.52
new const float:REACQUIRE_TIMEOUT = 1.70

new const float:ESC_BACK_TIME = 0.26
new const float:ESC_SIDE_TIME = 0.46

new const float:LOOP_DT = 0.07

new float:lastMoveCmdTime = -1000.0
new float:lastSayTime = -1000.0

new float:slotX = 0.0
new float:slotY = 0.0
new slotReady = 0

new float:lastLeaderDist = 0.0
new float:lastLeaderAbsDir = 0.0
new float:lastLeaderSeenTime = -1000.0

stock float:wrapPi(float:angle) {
  while(angle > PI) angle -= TWO_PI
  while(angle < -PI) angle += TWO_PI
  return angle
}

stock float:atan2(float:y, float:x) {
  new const float:EPS = 0.00001
  if(abs(x) < EPS) {
    if(y > 0.0) return PI/2.0
    if(y < 0.0) return -PI/2.0
    return 0.0
  }

  new float:a = atan(y/x)
  if(x < 0.0 && y >= 0.0) return a + PI
  if(x < 0.0 && y < 0.0) return a - PI
  return a
}

stock float:clampf(float:v, float:mn, float:mx) {
  if(v < mn) return mn
  if(v > mx) return mx
  return v
}

stock rotateTo(float:absAngle) {
  new float:cur = getDirection()
  rotate(cur + wrapPi(absAngle - cur))
}

stock bool:isMoving() {
  if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
    return true
  return false
}

stock bool:moveReady() {
  return (getTime() - lastMoveCmdTime) >= getTimeNeededFor(ACTION_MOVE)
}

stock bool:tryStand() {
  if(!moveReady()) return false
  if(stand()) {
    lastMoveCmdTime = getTime()
    return true
  }
  return false
}

stock bool:tryWalk() {
  if(!moveReady()) return false
  if(walk()) {
    lastMoveCmdTime = getTime()
    return true
  }
  return false
}

stock bool:tryWalkBk() {
  if(!moveReady()) return false
  if(walkbk()) {
    lastMoveCmdTime = getTime()
    return true
  }
  return false
}

stock bool:getArenaCenter(&float:cx, &float:cy) {
  cx = 0.0
  cy = 0.0

  new count = 0
  for(new t = 0; t < getTeams(); ++t) {
    new float:gx
    new float:gy
    if(getGoalLocation(t, gx, gy)) {
      cx += gx
      cy += gy
      ++count
    }
  }

  if(count <= 0)
    return false

  cx /= float(count)
  cy /= float(count)
  return true
}

stock bool:watchLeader(&float:dist, &float:absDir) {
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR

  new float:minDist = 0.0
  new float:yaw
  new float:pitch
  new id

  for(new tries = 0; tries < 6; ++tries) {
    new item = FRIEND_WARRIOR
    new float:d = minDist
    watch(item, d, yaw, pitch, id)
    if(item == ITEM_NONE)
      return false

    if(item == FRIEND_WARRIOR && id == LEADER_ID) {
      dist = d
      absDir = getDirection() + getTorsoYaw() + getHeadYaw() + yaw
      return true
    }

    minDist = d + 0.5
  }

  return false
}

stock bool:pollLeaderVoice(&float:dist, &float:absDir) {
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR

  new item = 0
  new sound
  new float:yaw
  new float:pitch
  new id

  dist = hear(item, sound, yaw, pitch, id)
  if(item == FRIEND_WARRIOR && id == LEADER_ID && sound == WORD_LEADER_PING) {
    absDir = getDirection() + getTorsoYaw() + getHeadYaw() + yaw
    return true
  }

  return false
}

stock bool:getBlockingFriend(&float:blockYaw, &float:blockDist) {
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR

  new item = FRIEND_WARRIOR
  new float:dist = 0.0
  new float:yaw
  new float:pitch
  new id

  watch(item, dist, yaw, pitch, id)
  if(item == FRIEND_WARRIOR && id != LEADER_ID && id != getID() && dist < BLOCK_DIST && abs(yaw) < BLOCK_YAW) {
    blockYaw = yaw
    blockDist = dist
    return true
  }

  return false
}

stock bool:navigateToPoint(float:tx, float:ty, float:arriveRadius) {
  new float:x
  new float:y
  new float:z
  getLocation(x, y, z)

  new float:dx = tx - x
  new float:dy = ty - y
  new float:dist = sqrt(dx*dx + dy*dy)

  if(dist <= arriveRadius) {
    if(isMoving())
      tryStand()
    return true
  }

  new float:heading = atan2(dy, dx)

  if(sight() < WALL_AVOID_DIST)
    heading = heading + (random(2) == 0 ? PI/3.5 : -PI/3.5)

  rotateTo(heading)
  if(isStanding())
    tryWalk()

  return false
}

stock initFollowerSlotCircle() {
  if(getID() == LEADER_ID)
    return

  new followers = getMates() - 1
  if(followers < 1)
    followers = 1

  new rank = getID() - 1
  if(rank < 0)
    rank = 0
  if(rank > followers - 1)
    rank = followers - 1

  new float:radius = SLOT_RADIUS_BASE + SLOT_RADIUS_PER_BOT * float(followers)
  new float:ang = TWO_PI * float(rank) / float(followers)

  slotX = radius * cos(ang)
  slotY = radius * sin(ang)
  slotReady = 1
}

leader() {
  new float:mapCx
  new float:mapCy
  if(!getArenaCenter(mapCx, mapCy)) {
    mapCx = 0.0
    mapCy = 0.0
  }

  new float:targetX = mapCx + (MAP_SAFE_HALF - TARGET_MARGIN)
  new float:targetY = mapCy
  targetX = clampf(targetX, mapCx - MAP_SAFE_HALF, mapCx + MAP_SAFE_HALF)

  new float:phaseStart = getTime()
  new movePhase = 0

  for(;;) {
    new float:now = getTime()

    if(now - lastSayTime >= getTimeNeededFor(ACTION_SAY)) {
      if(say(WORD_LEADER_PING))
        lastSayTime = now
    }

    if(movePhase == 0) {
      navigateToPoint(mapCx, mapCy, FORM_CENTER_RADIUS)
      if(now - phaseStart >= FORM_TIMEOUT)
        movePhase = 1

      wait(LOOP_DT)
      continue
    }

    navigateToPoint(targetX, targetY, LEADER_ARRIVE_RADIUS)
    wait(LOOP_DT)
  }
}

follower() {
  initFollowerSlotCircle()
  rotateHead(0.0)

  new float:phaseDt = LOOP_DT + float(getID()%3) * 0.015
  new float:escapeBackUntil = -1000.0
  new float:escapeSideUntil = -1000.0
  new float:escapeSide = 1.0

  for(;;) {
    new float:now = getTime()

    if(now < escapeBackUntil) {
      rotateTo(getDirection())
      if(isStanding() || isWalking() || isRunning() || isWalkingcr())
        tryWalkBk()

      wait(phaseDt)
      continue
    }

    if(now < escapeSideUntil) {
      rotateTo(getDirection() + escapeSide * PI/2.0)
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - escapeSide * PI/2.4)

      if(isStanding())
        tryWalk()

      wait(phaseDt)
      continue
    }

    new touched = getTouched()
    if(touched) {
      raise(touched)
      if((getID()%2) == 0)
        escapeSide = 1.0
      else
        escapeSide = -1.0

      escapeBackUntil = now + ESC_BACK_TIME
      escapeSideUntil = escapeBackUntil + ESC_SIDE_TIME

      wait(phaseDt)
      continue
    }

    new float:d
    new float:adir
    new haveLeader = 0

    if(watchLeader(d, adir))
      haveLeader = 1
    else if(pollLeaderVoice(d, adir))
      haveLeader = 1

    if(haveLeader != 0) {
      lastLeaderDist = d
      lastLeaderAbsDir = adir
      lastLeaderSeenTime = now
    }

    if(now - lastLeaderSeenTime > REACQUIRE_TIMEOUT) {
      rotateTo(getDirection() + ((getID()%2) == 0 ? PI/9.0 : -PI/9.0))
      if(isStanding())
        tryWalk()
      wait(phaseDt)
      continue
    }

    if(slotReady == 0) {
      if(isStanding())
        tryWalk()
      wait(phaseDt)
      continue
    }

    // follower -> leader vector in world
    new float:lx = lastLeaderDist * cos(lastLeaderAbsDir)
    new float:ly = lastLeaderDist * sin(lastLeaderAbsDir)

    // desired error for fixed world-frame circle around leader
    new float:eX = slotX + lx
    new float:eY = slotY + ly
    new float:err = sqrt(eX*eX + eY*eY)

    new float:heading = atan2(eY, eX)

    new float:blockYaw
    new float:blockDist
    if(getBlockingFriend(blockYaw, blockDist)) {
      if(blockYaw > 0.0)
        heading = heading - PI/4.0
      else
        heading = heading + PI/4.0

      if(blockDist < 0.95 && isMoving())
        tryStand()
    }

    if(sight() < WALL_AVOID_DIST)
      heading = heading + ((getID()%2) == 0 ? PI/6.0 : -PI/6.0)

    rotateTo(heading)

    if(err > SLOT_MOVE_RADIUS) {
      if(isStanding())
        tryWalk()
    } else if(err <= SLOT_HOLD_RADIUS) {
      if(isMoving())
        tryStand()
    } else {
      if(isStanding())
        tryWalk()
    }

    wait(phaseDt)
  }
}

main() {
  if(getID() == LEADER_ID)
    leader()
  else
    follower()
}
