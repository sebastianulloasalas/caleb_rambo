// Triangle formation (filled) - DEPRECADED
//
// Design goals:
// - Leader is always getID() == 0
// - Followers occupy a FILLED triangular lattice around the leader
// - Formation is stable: fewer heading flips and fewer move-state oscillations

#include "core"
#include "math"
#include "bots"

new const LEADER_ID = 0

new const RADIO_CHANNEL_LEADER = 7
new const WORD_LEADER_ANNOUNCE = 4241
new const WORD_LEADER_PING = 4242

#define MAX_SLOTS 96

new const float:PI = 3.1415
new const float:TWO_PI = 6.2830
new const float:SQRT3 = 1.73205

new const float:SLOT_SPACING = 3.4
new const float:FORMATION_ANGLE = 0.0
new const float:LEADER_CLEARANCE = 3.6
new const float:SPREAD_TIME_BASE = 2.4
new const float:AXIS_U_BAND = 1.20
new const float:AXIS_U_HOLD = 0.60
new const float:AXIS_V_HOLD = 0.70
new const float:BLOCK_DIST = 1.35
new const float:BLOCK_YAW = 0.45
new const float:REPULSE_DIST = 2.2
new const float:REPULSE_GAIN = 2.2
new const float:WALL_AVOID_DIST = 1.50
new const float:REACQUIRE_TIMEOUT = 1.60
new const float:LOOP_DT = 0.06
new const bool:DEBUG_STATIONARY_LEADER = true
new const bool:DEBUG_SPIN_LEADER = true
new const float:LEADER_SPIN_PERIOD = 3.2

new float:lastMoveCmdTime = -1000.0
new float:lastSayTime = -1000.0
new float:lastSpeakTime = -1000.0
new float:lastLeaderSpinTime = -1000.0

new float:slotU
new float:slotV
new bool:slotReady = false

new leaderId = 0
new bool:leaderKnown = false
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

stock rotateTo(float:absAngle) {
  new float:cur = getDirection()
  new float:delta = wrapPi(absAngle - cur)
  rotate(cur + delta)
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

stock getTriangleLevels(followers) {
  new levels = 1
  while(levels*(levels+1)/2 < followers)
    ++levels
  return levels
}

stock float:getRequiredFrontSpace() {
  new followers = getMates() - 1
  if(followers < 1) return 2.0
  if(followers > MAX_SLOTS) followers = MAX_SLOTS

  new levels = getTriangleLevels(followers)
  new float:du = SLOT_SPACING * SQRT3 / 2.0
  new float:h = float(levels - 1) * du

  // Apex span + clearance zone around the leader.
  return 2.0*h/3.0 + SLOT_SPACING + LEADER_CLEARANCE
}

stock pushOrder(idx, order[], &count, bool:used[], limit) {
  if(idx < 0 || idx >= limit) return
  if(used[idx]) return
  if(count >= limit) return
  used[idx] = true
  order[count] = idx
  ++count
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

  // Increase triangle size until we have enough slots AFTER removing
  // positions too close to the leader.
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

  // Assign outer slots first to reduce crossing in the center.
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

stock pollLeaderRadio() {
  new word
  new id

  if(listen(RADIO_CHANNEL_LEADER, word, id)) {
    if(word == WORD_LEADER_ANNOUNCE) {
      leaderId = id
      leaderKnown = true
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

leader() {
  new float:frontNeed = getRequiredFrontSpace()

  // Initial short move to leave the spawn cluster.
  new float:moveUntil = getTime() + 3.0
  if(!DEBUG_STATIONARY_LEADER)
    tryWalk()

  for(;;) {
    new float:now = getTime()

    if(now - lastSayTime >= getTimeNeededFor(ACTION_SAY)) {
      if(say(WORD_LEADER_PING))
        lastSayTime = now
    }

    if(now - lastSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
      if(speak(RADIO_CHANNEL_LEADER, WORD_LEADER_ANNOUNCE))
        lastSpeakTime = now
    }

    if(DEBUG_STATIONARY_LEADER) {
      // Keep the leader almost fixed to make formation debugging easier.
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        tryStand()

      // If spawned too close to a wall, take a short step away once.
      if(sight() < LEADER_CLEARANCE + 1.0) {
        rotateTo(getDirection() + (random(2) == 0 ? PI/2.0 : -PI/2.0))
        if(isStanding())
          tryWalk()
      }

      // Visual marker: a full 360-degree spin every few seconds.
      if(DEBUG_SPIN_LEADER && !isRotating() && now - lastLeaderSpinTime >= LEADER_SPIN_PERIOD) {
        lastLeaderSpinTime = now
        rotate(getDirection() + TWO_PI)
      }

      wait(LOOP_DT)
      continue
    }

    if(now < moveUntil) {
      if(sight() < frontNeed)
        rotateTo(getDirection() + (random(2) == 0 ? PI/2.0 : -PI/2.0))

      if(isStanding())
        tryWalk()
    } else {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        tryStand()

      // If near a wall, step away and let followers re-build the triangle.
      if(sight() < frontNeed) {
        rotateTo(getDirection() + (random(2) == 0 ? PI/2.0 : -PI/2.0))
        moveUntil = now + 2.0
        tryWalk()
      } else if(isStanding() && random(100) < 2) {
        // Tiny drift to avoid being stuck forever in a bad local configuration.
        rotateTo(getDirection() + float(random(3) - 1) * (PI/3.0))
        moveUntil = now + 1.0
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
  new float:spreadUntil = getTime() + SPREAD_TIME_BASE + float(rank%4) * 0.20

  rotateTo(spreadAngle)
  if(isStanding())
    tryWalk()

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
      rotateTo(getDirection() + (getID()%2 == 0 ? PI/12.0 : -PI/12.0))
      if(isStanding())
        tryWalk()
      wait(phaseDt)
      continue
    }

    // follower -> leader (world)
    new float:lx = lastLeaderDist * cos(lastLeaderAbsDir)
    new float:ly = lastLeaderDist * sin(lastLeaderAbsDir)

    // Fixed-orientation formation frame (does not rotate with leader).
    new float:ca = cf
    new float:sa = sf

    // follower coordinates in leader-local frame.
    // (leader->follower) = -(follower->leader)
    new float:fx = -lx
    new float:fy = -ly
    new float:fU = fx*ca + fy*sa
    new float:fV = -fx*sa + fy*ca

    new float:eU = slotU - fU
    new float:eV = slotV - fV

    // Hold area with hysteresis to avoid micro-oscillation.
    if(abs(eU) <= AXIS_U_HOLD && abs(eV) <= AXIS_V_HOLD) {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        tryStand()
      wait(phaseDt)
      continue
    }

    // Axis-priority controller:
    // 1) Reach the proper row/depth (U), then 2) spread laterally (V).
    new float:tU = 0.0
    new float:tV = 0.0
    if(abs(eU) > AXIS_U_BAND)
      tU = eU
    else
      tV = eV

    // Local target vector -> world vector.
    new float:tx = tU*ca - tV*sa
    new float:ty = tU*sa + tV*ca

    new float:repX
    new float:repY
    getRepulsionVector(repX, repY)
    tx += repX
    ty += repY

    new float:heading = atan2(ty, tx)

    new float:blockYaw
    new float:blockDist
    if(getBlockingFriend(blockYaw, blockDist)) {
      // Bias lateral bypass to the side where this slot should end up.
      new float:side
      if(abs(eV) > 0.20)
        side = (eV > 0.0 ? 1.0 : -1.0)
      else if(blockYaw > 0.0)
        side = -1.0
      else
        side = 1.0

      heading = heading + side * (PI/5.0)

      if(blockDist < 0.95 && (isWalking() || isRunning() || isWalkingbk() || isWalkingcr()))
        tryStand()
    }

    new float:angErr = wrapPi(heading - getDirection())
    if(abs(angErr) > 0.10)
      rotateTo(heading)

    if(abs(tU) > 0.20 || abs(tV) > 0.20) {
      if(isStanding())
        tryWalk()
    } else {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        tryStand()
    }

    wait(phaseDt)
  }
}

// Simple fallback for non-fight modes.
simpleSoccer() {
  rotate(getDirection() + TWO_PI)

  new float:dist
  new float:yaw
  new item

  do {
    item = ITEM_TARGET
    dist = 0.0
    watch(item, dist, yaw)
  } while(item != ITEM_TARGET)

  rotate(getDirection() + yaw)
  setKickSpeed(getMaxKickSpeed())
  bendTorso(0.3)
  bendHead(-0.3)
  tryWalk()

  for(;;) {
    if(sight() < 2.0)
      rotateTo(getDirection() + (getID()%2 == 0 ? PI/10.0 : -PI/10.0))

    item = ITEM_TARGET
    dist = 0.0
    watch(item, dist, yaw)
    if(item == ITEM_TARGET)
      rotateTo(getDirection() + yaw)

    wait(0.1)
  }
}

main() {
  if(getPlay() == PLAY_SOCCER) {
    simpleSoccer()
    return
  }

  if(getID() == LEADER_ID)
    leader()
  else
    follower()
}
