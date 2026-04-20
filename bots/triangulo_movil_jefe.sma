// triangulo_movil_jefe.sma
//
// Fase 1: el lider (ID 0) concentra al equipo en formacion triangular.
// Fase 2: cuando la formacion esta lista (o vence un timeout),
//         el lider cruza al extremo opuesto del mapa y los followers
//         mantienen la misma estructura triangular alrededor del lider.

#include "core"
#include "math"
#include "bots"

new const LEADER_ID = 0

new const RADIO_CHANNEL_STATE = 61
new const RADIO_CHANNEL_READY = 62
new const WORD_LEADER_ANNOUNCE = 7401
new const WORD_LEADER_PING = 7402
new const WORD_READY = 7403
new const WORD_MOVE_START = 7404

#define MAX_SLOTS 96
#define MAX_ID_TRACK 128

new const float:PI = 3.1415
new const float:TWO_PI = 6.2830
new const float:SQRT3 = 1.73205

new const float:SLOT_SPACING = 3.4
new const float:FORMATION_ANGLE = 0.0
new const float:LEADER_CLEARANCE = 3.6
new const float:AXIS_U_BAND = 1.20
new const float:AXIS_U_HOLD = 0.62
new const float:AXIS_V_HOLD = 0.72
new const float:BLOCK_DIST = 1.35
new const float:BLOCK_YAW = 0.45
new const float:SPREAD_BLOCK_DIST = 2.1
new const float:SPREAD_BLOCK_YAW = 0.95
new const float:SPREAD_BYPASS_ANGLE = 1.10
new const float:SPREAD_BACK_TIME = 0.30
new const float:TOUCH_ESCAPE_SIDE_TIME = 0.45
new const FRONT_STUCK_TICKS_MAX = 6
new const float:REPULSE_DIST = 2.2
new const float:REPULSE_GAIN = 2.2
new const float:WALL_AVOID_DIST = 1.50
new const float:REACQUIRE_TIMEOUT = 1.70

new const float:FORM_TIMEOUT = 18.0
new const float:LEADER_FORM_SETTLE_TIME = 1.8
new const float:READY_HOLD_TIME = 0.90
new const float:READY_RESEND_DT = 0.95
new const float:FORM_CENTER_RADIUS = 1.30
new const float:MOVE_DONE_RADIUS = 1.80
new const float:MAP_SAFE_HALF = 58.0
new const float:TARGET_MARGIN = 3.2

new const float:SPAWN_SEPARATE_TIME_BASE = 2.8
new const float:SPREAD_TIME_BASE = 2.2
new const float:LOOP_DT = 0.06

new float:lastMoveCmdTime = -1000.0
new float:lastSayTime = -1000.0
new float:lastSpeakStateTime = -1000.0

new float:slotU
new float:slotV
new bool:slotReady = false

new leaderId = 0
new bool:leaderKnown = false
new bool:leaderMoveStarted = false
new float:lastLeaderDist = 0.0
new float:lastLeaderAbsDir = 0.0
new float:lastLeaderSeenTime = -1000.0

new bool:followerReady[MAX_ID_TRACK]
new readyCount = 0
new followersExpected = 0

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
  new float:delta = wrapPi(absAngle - cur)
  rotate(cur + delta)
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

stock getTriangleLevels(followers) {
  new levels = 1
  while(levels*(levels+1)/2 < followers)
    ++levels
  return levels
}

stock buildFilledTriangleSlots(followers,
                               float:spacing,
                               float:allU[],
                               float:allV[],
                               &slotCount,
                               order[],
                               &orderCount,
                               &levels) {
  levels = 1
  slotCount = 0

  for(;;) {
    slotCount = 0

    new float:du = spacing * SQRT3 / 2.0
    new float:h = float(levels - 1) * du
    new float:apexU = 2.0*h/3.0

    for(new row = 0; row < levels && slotCount < MAX_SLOTS; ++row) {
      new rowLen = row + 1
      new float:u = apexU - float(row) * du
      new float:center = float(rowLen - 1) / 2.0

      for(new col = 0; col < rowLen && slotCount < MAX_SLOTS; ++col) {
        new float:v = (float(col) - center) * spacing
        if(sqrt(u*u + v*v) < LEADER_CLEARANCE)
          continue

        allU[slotCount] = u
        allV[slotCount] = v
        ++slotCount
      }
    }

    if(slotCount >= followers || slotCount >= MAX_SLOTS || levels >= 32)
      break
    ++levels
  }

  orderCount = slotCount
  for(new i = 0; i < slotCount; ++i)
    order[i] = i

  for(new i = 0; i < slotCount - 1; ++i) {
    new best = i
    new idx0 = order[best]
    new float:bestScore = allU[idx0]*allU[idx0] + allV[idx0]*allV[idx0]

    for(new j = i + 1; j < slotCount; ++j) {
      new idx1 = order[j]
      new float:score = allU[idx1]*allU[idx1] + allV[idx1]*allV[idx1]
      if(score > bestScore) {
        best = j
        bestScore = score
      }
    }

    if(best != i) {
      new tmp = order[i]
      order[i] = order[best]
      order[best] = tmp
    }
  }
}

stock initFollowerSlot() {
  if(getID() == LEADER_ID)
    return

  new followers = getMates() - 1
  if(followers <= 0)
    return
  if(followers > MAX_SLOTS)
    followers = MAX_SLOTS

  new float:allU[MAX_SLOTS]
  new float:allV[MAX_SLOTS]
  new order[MAX_SLOTS]

  new slotCount
  new orderCount
  new levels

  buildFilledTriangleSlots(followers,
                           SLOT_SPACING,
                           allU,
                           allV,
                           slotCount,
                           order,
                           orderCount,
                           levels)

  if(orderCount <= 0)
    return

  new rank = getID() - 1
  if(rank < 0) rank = 0
  if(rank > followers - 1) rank = followers - 1
  if(rank > orderCount - 1) rank = orderCount - 1

  new slotIdx = order[rank]
  slotU = allU[slotIdx]
  slotV = allV[slotIdx]
  slotReady = true
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

stock clampInsideSafe(&float:x, &float:y, float:cx, float:cy, float:safeHalf) {
  x = clampf(x, cx - safeHalf, cx + safeHalf)
  y = clampf(y, cy - safeHalf, cy + safeHalf)
}

stock computeOppositeExtreme(float:cx,
                             float:cy,
                             float:startX,
                             float:startY,
                             &float:tx,
                             &float:ty) {
  new float:vx = startX - cx
  new float:vy = startY - cy
  new float:len = sqrt(vx*vx + vy*vy)
  if(len < 0.001) {
    vx = 1.0
    vy = 0.0
    len = 1.0
  }

  vx /= len
  vy /= len

  new float:r = MAP_SAFE_HALF - TARGET_MARGIN
  if(r < 8.0)
    r = 8.0

  tx = cx - vx * r
  ty = cy - vy * r
}

stock sendLeaderPresence(float:now) {
  if(now - lastSayTime >= getTimeNeededFor(ACTION_SAY)) {
    if(say(WORD_LEADER_PING))
      lastSayTime = now
  }

  if(now - lastSpeakStateTime >= getTimeNeededFor(ACTION_SPEAK)) {
    if(leaderMoveStarted) {
      if(speak(RADIO_CHANNEL_STATE, WORD_MOVE_START))
        lastSpeakStateTime = now
    } else {
      if(speak(RADIO_CHANNEL_STATE, WORD_LEADER_ANNOUNCE))
        lastSpeakStateTime = now
    }
  }
}

stock pollLeaderRadio() {
  new word
  new id

  for(new tries = 0; tries < 6; ++tries) {
    if(!listen(RADIO_CHANNEL_STATE, word, id))
      break

    if(word == WORD_LEADER_ANNOUNCE || word == WORD_MOVE_START) {
      leaderId = id
      leaderKnown = true
      if(word == WORD_MOVE_START)
        leaderMoveStarted = true
    }
  }
}

stock pollReadyRadioLeader() {
  new word
  new id

  for(new tries = 0; tries < 6; ++tries) {
    if(!listen(RADIO_CHANNEL_READY, word, id))
      break

    if(word != WORD_READY)
      continue
    if(id <= LEADER_ID || id >= MAX_ID_TRACK)
      continue
    if(!followerReady[id]) {
      followerReady[id] = true
      ++readyCount
    }
  }
}

stock bool:pollLeaderVoice(&float:dist, &float:absDir) {
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR

  new item = 0
  new sound
  new float:yaw
  new float:pitch
  new id

  dist = hear(item, sound, yaw, pitch, id)
  if(item == FRIEND_WARRIOR && sound == WORD_LEADER_PING && (!leaderKnown || id == leaderId)) {
    leaderId = id
    leaderKnown = true
    absDir = getDirection() + getTorsoYaw() + getHeadYaw() + yaw
    return true
  }
  return false
}

stock bool:watchLeader(&float:dist, &float:absDir) {
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR

  new float:minDist = 0.0
  new float:yaw
  new float:pitch
  new id

  for(new tries = 0; tries < 4; ++tries) {
    new item = FRIEND_WARRIOR
    new float:d = minDist
    watch(item, d, yaw, pitch, id)
    if(item == ITEM_NONE)
      return false

    if(item == FRIEND_WARRIOR && ((leaderKnown && id == leaderId) || (!leaderKnown && id == LEADER_ID))) {
      leaderId = id
      leaderKnown = true
      dist = d
      absDir = getDirection() + getTorsoYaw() + getHeadYaw() + yaw
      return true
    }

    minDist = d + 0.6
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
  if(item == FRIEND_WARRIOR && (!leaderKnown || id != leaderId) && dist < BLOCK_DIST && abs(yaw) < BLOCK_YAW) {
    blockYaw = yaw
    blockDist = dist
    return true
  }

  return false
}

stock bool:getBlockingFriendWide(&float:blockYaw, &float:blockDist) {
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR

  new item = FRIEND_WARRIOR
  new float:dist = 0.0
  new float:yaw
  new float:pitch
  new id

  watch(item, dist, yaw, pitch, id)
  if(item == FRIEND_WARRIOR && (!leaderKnown || id != leaderId) && dist < SPREAD_BLOCK_DIST && abs(yaw) < SPREAD_BLOCK_YAW) {
    blockYaw = yaw
    blockDist = dist
    return true
  }

  return false
}

stock getRepulsionVector(&float:rx, &float:ry) {
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR

  rx = 0.0
  ry = 0.0

  new item = FRIEND_WARRIOR
  new float:dist = 0.0
  new float:yaw
  new float:pitch
  new id

  watch(item, dist, yaw, pitch, id)
  if(item != FRIEND_WARRIOR)
    return
  if(leaderKnown && id == leaderId)
    return
  if(dist >= REPULSE_DIST)
    return

  new float:absDir = getDirection() + getTorsoYaw() + getHeadYaw() + yaw
  new float:w = (REPULSE_DIST - dist) / REPULSE_DIST * REPULSE_GAIN
  rx = -w * cos(absDir)
  ry = -w * sin(absDir)
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

leader() {
  new float:mapCx
  new float:mapCy
  if(!getArenaCenter(mapCx, mapCy)) {
    mapCx = 0.0
    mapCy = 0.0
  }

  new float:startX
  new float:startY
  new float:startZ
  getLocation(startX, startY, startZ)

  new float:targetX
  new float:targetY
  computeOppositeExtreme(mapCx, mapCy, startX, startY, targetX, targetY)
  clampInsideSafe(targetX, targetY, mapCx, mapCy, MAP_SAFE_HALF - TARGET_MARGIN)

  followersExpected = getMates() - 1
  if(followersExpected < 0)
    followersExpected = 0
  if(followersExpected > MAX_SLOTS)
    followersExpected = MAX_SLOTS

  readyCount = 0
  for(new i = 0; i < MAX_ID_TRACK; ++i)
    followerReady[i] = false

  leaderMoveStarted = false
  new bool:centerReached = false
  new bool:targetReached = false
  new float:phaseStart = getTime()
  new float:centerMoveUnlock = phaseStart + LEADER_FORM_SETTLE_TIME

  for(;;) {
    new float:now = getTime()

    sendLeaderPresence(now)

    if(!leaderMoveStarted) {
      if(now < centerMoveUnlock) {
        if(isMoving())
          tryStand()

        pollReadyRadioLeader()
        wait(LOOP_DT)
        continue
      }

      centerReached = navigateToPoint(mapCx, mapCy, FORM_CENTER_RADIUS)
      pollReadyRadioLeader()

      if((centerReached && readyCount >= followersExpected) || now - phaseStart >= FORM_TIMEOUT) {
        leaderMoveStarted = true
        if(now - lastSpeakStateTime >= getTimeNeededFor(ACTION_SPEAK)) {
          if(speak(RADIO_CHANNEL_STATE, WORD_MOVE_START))
            lastSpeakStateTime = now
        }
      }

      wait(LOOP_DT)
      continue
    }

    if(!targetReached) {
      targetReached = navigateToPoint(targetX, targetY, MOVE_DONE_RADIUS)
    } else {
      if(isMoving())
        tryStand()

      if(sight() < LEADER_CLEARANCE + 0.8) {
        rotateTo(getDirection() + (random(2) == 0 ? PI/2.0 : -PI/2.0))
        if(isStanding())
          tryWalk()
      }
    }

    wait(LOOP_DT)
  }
}

follower() {
  initFollowerSlot()
  rotateHead(0.0)

  new float:phaseDt = LOOP_DT + float(getID()%3)*0.015
  new float:cf = cos(FORMATION_ANGLE)
  new float:sf = sin(FORMATION_ANGLE)

  new followers = getMates() - 1
  if(followers < 1) followers = 1
  new rank = getID() - 1
  if(rank < 0) rank = 0
  if(rank > followers - 1) rank = followers - 1

  new float:spreadAngle = FORMATION_ANGLE + TWO_PI * float(rank) / float(followers)
  new float:separateUntil = getTime() + SPAWN_SEPARATE_TIME_BASE + float(rank%5) * 0.20
  new float:spreadUntil = separateUntil + SPREAD_TIME_BASE + float(rank%4) * 0.20

  rotateTo(spreadAngle)
  if(isStanding())
    tryWalk()

  new float:readyHoldSince = -1000.0
  new float:lastReadySent = -1000.0
  new float:spreadBackUntil = -1000.0
  new float:touchBackUntil = -1000.0
  new float:touchSideUntil = -1000.0
  new float:touchSide = 1.0
  new frontStuckTicks = 0

  for(;;) {
    new float:now = getTime()

    pollLeaderRadio()

    new float:d
    new float:adir
    new bool:haveLeader = false
    if(watchLeader(d, adir))
      haveLeader = true
    else if(pollLeaderVoice(d, adir))
      haveLeader = true

    if(haveLeader) {
      lastLeaderDist = d
      lastLeaderAbsDir = adir
      lastLeaderSeenTime = now
    }

    if(now < touchBackUntil) {
      rotateTo(spreadAngle)
      if(isStanding() || isWalking() || isRunning() || isWalkingcr())
        tryWalkBk()

      wait(phaseDt)
      continue
    }

    if(now < touchSideUntil) {
      rotateTo(spreadAngle + touchSide * SPREAD_BYPASS_ANGLE)
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - touchSide * PI/2.4)

      tryWalk()

      wait(phaseDt)
      continue
    }

    new touched = getTouched()
    if(touched) {
      raise(touched)

      touchSide = (getID()%2 == 0 ? 1.0 : -1.0)
      touchBackUntil = now + SPREAD_BACK_TIME
      touchSideUntil = touchBackUntil + TOUCH_ESCAPE_SIDE_TIME
      frontStuckTicks = 0

      wait(phaseDt)
      continue
    }

    if(now < spreadBackUntil) {
      rotateTo(spreadAngle)
      if(isStanding() || isWalking() || isRunning() || isWalkingcr())
        tryWalkBk()

      wait(phaseDt)
      continue
    }

    if(now < separateUntil) {
      new float:sbYaw
      new float:sbDist
      if(getBlockingFriendWide(sbYaw, sbDist)) {
        ++frontStuckTicks

        new float:side = (sbYaw > 0.0 ? -1.0 : 1.0)
        rotateTo(spreadAngle + side * SPREAD_BYPASS_ANGLE)

        if(sbDist < 1.08)
          spreadBackUntil = now + SPREAD_BACK_TIME

        if(frontStuckTicks >= FRONT_STUCK_TICKS_MAX) {
          touchSide = side
          touchBackUntil = now + SPREAD_BACK_TIME
          touchSideUntil = touchBackUntil + TOUCH_ESCAPE_SIDE_TIME
          frontStuckTicks = 0
        }
      } else {
        if(frontStuckTicks > 0)
          --frontStuckTicks
        rotateTo(spreadAngle)
      }

      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() + (getID()%2 == 0 ? PI/6.0 : -PI/6.0))

      if(isStanding())
        tryWalk()

      wait(phaseDt)
      continue
    }

    if(now < spreadUntil) {
      if(sight() < WALL_AVOID_DIST)
        rotateTo(spreadAngle + (getID()%2 == 0 ? PI/7.0 : -PI/7.0))
      else
        rotateTo(spreadAngle)

      if(isStanding())
        tryWalk()

      wait(phaseDt)
      continue
    }

    if(!slotReady) {
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() + (getID()%2 == 0 ? PI/10.0 : -PI/10.0))
      if(isStanding())
        tryWalk()
      wait(phaseDt)
      continue
    }

    if(sight() < WALL_AVOID_DIST) {
      rotateTo(getDirection() + (getID()%2 == 0 ? PI/10.0 : -PI/10.0))
      if(isStanding())
        tryWalk()
      wait(phaseDt)
      continue
    }

    if(now - lastLeaderSeenTime > REACQUIRE_TIMEOUT) {
      readyHoldSince = -1000.0
      rotateTo(getDirection() + (getID()%2 == 0 ? PI/12.0 : -PI/12.0))
      if(isStanding())
        tryWalk()
      wait(phaseDt)
      continue
    }

    new float:lx = lastLeaderDist * cos(lastLeaderAbsDir)
    new float:ly = lastLeaderDist * sin(lastLeaderAbsDir)

    new float:fx = -lx
    new float:fy = -ly
    new float:fU = fx*cf + fy*sf
    new float:fV = -fx*sf + fy*cf

    new float:eU = slotU - fU
    new float:eV = slotV - fV

    if(abs(eU) <= AXIS_U_HOLD && abs(eV) <= AXIS_V_HOLD) {
      if(isMoving())
        tryStand()

      if(readyHoldSince < -999.0)
        readyHoldSince = now

      if(now - readyHoldSince >= READY_HOLD_TIME && now - lastReadySent >= READY_RESEND_DT) {
        if(speak(RADIO_CHANNEL_READY, WORD_READY))
          lastReadySent = now
      }

      wait(phaseDt)
      continue
    }

    readyHoldSince = -1000.0

    new float:tU = 0.0
    new float:tV = 0.0
    if(abs(eU) > AXIS_U_BAND)
      tU = eU
    else
      tV = eV

    new float:tx = tU*cf - tV*sf
    new float:ty = tU*sf + tV*cf

    new float:repX
    new float:repY
    getRepulsionVector(repX, repY)
    tx += repX
    ty += repY

    new float:heading = atan2(ty, tx)

    new float:blockYaw
    new float:blockDist
    if(getBlockingFriend(blockYaw, blockDist)) {
      new float:side
      if(abs(eV) > 0.20)
        side = (eV > 0.0 ? 1.0 : -1.0)
      else if(blockYaw > 0.0)
        side = -1.0
      else
        side = 1.0

      heading = heading + side * (PI/5.0)

      if(blockDist < 0.95 && isMoving())
        tryStand()
    }

    new float:angErr = wrapPi(heading - getDirection())
    if(abs(angErr) > 0.10)
      rotateTo(heading)

    if(abs(tU) > 0.20 || abs(tV) > 0.20) {
      if(isStanding())
        tryWalk()
    } else {
      if(isMoving())
        tryStand()
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
