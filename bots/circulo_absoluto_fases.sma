// circulo_absoluto_fases.sma
//
// Fases estrictas:
// 1) FORMAR: lider en el centro, followers en un circulo absoluto alrededor.
// 2) ALINEAR: todos miran al mismo rumbo.
// 3) AVANZAR: el lider se mueve hacia un lado y el grupo conserva el circulo.
//
// Disenado para toolchains AMX viejos (logica simple, sin estados complejos).

#include "core"
#include "math"
#include "bots"

new const LEADER_ID = 0

new const PHASE_FORM = 0
new const PHASE_ALIGN = 1
new const PHASE_MOVE = 2

new const RADIO_CHANNEL_PHASE = 81
new const RADIO_CHANNEL_READY = 82

new const WORD_PHASE_FORM_BASE = 12000
new const WORD_PHASE_ALIGN = 12100
new const WORD_PHASE_MOVE = 12101
new const WORD_READY_FORM = 12211
new const WORD_READY_ALIGN = 12212
new const WORD_LEADER_PING = 12220

#define MAX_ID_TRACK 128

new const float:PI = 3.1415
new const float:TWO_PI = 6.2830

new const float:MAP_SAFE_HALF = 58.0
new const float:MAP_MARGIN = 3.6

new const float:CIRCLE_RADIUS_BASE = 2.8
new const float:CIRCLE_RADIUS_PER_BOT = 0.18
new const float:CIRCLE_RADIUS_MIN = 2.5
new const float:CIRCLE_RADIUS_MAX = 4.2

new const float:FORM_POS_RADIUS = 0.95
new const float:FORM_HOLD_TIME = 0.90
new const float:ALIGN_YAW_TOL = 0.14
new const float:ALIGN_HOLD_TIME = 0.70
new const float:READY_RESEND_DT = 0.90

new const float:MOVE_DONE_RADIUS = 1.60
new const float:MOVE_HEADING = 0.0
new const float:MOVE_SYNC_BIAS = 0.55

new const float:WALL_AVOID_DIST = 1.45
new const float:BLOCK_DIST = 1.45
new const float:BLOCK_YAW = 0.52
new const float:REACQUIRE_TIMEOUT = 1.75

new const float:ESC_BACK_TIME = 0.26
new const float:ESC_SIDE_TIME = 0.46
new const FRONT_STUCK_TICKS_MAX = 7

new const float:LOOP_DT = 0.07

new float:lastMoveCmdTime = -1000.0
new float:lastSayTime = -1000.0
new float:lastSpeakPhaseTime = -1000.0

new float:mapCx = 0.0
new float:mapCy = 0.0
new float:circleRadius = 3.0

new float:centerStartX = 0.0
new float:centerStartY = 0.0
new float:centerTargetX = 0.0
new float:centerTargetY = 0.0

new float:mySlotX = 0.0
new float:mySlotY = 0.0

new bool:readyFormFrom[MAX_ID_TRACK]
new bool:readyAlignFrom[MAX_ID_TRACK]
new readyFormCount = 0
new readyAlignCount = 0

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

stock bool:getBlockingFriend(&float:blockYaw, &float:blockDist) {
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR

  new item = FRIEND_WARRIOR
  new float:dist = 0.0
  new float:yaw
  new float:pitch
  new id

  watch(item, dist, yaw, pitch, id)
  if(item == FRIEND_WARRIOR && id != getID() && dist < BLOCK_DIST && abs(yaw) < BLOCK_YAW) {
    blockYaw = yaw
    blockDist = dist
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

stock computeSharedGeometry() {
  if(!getArenaCenter(mapCx, mapCy)) {
    mapCx = 0.0
    mapCy = 0.0
  }

  centerStartX = mapCx
  centerStartY = mapCy

  new mates = getMates()
  if(mates < 1)
    mates = 1

  circleRadius = CIRCLE_RADIUS_BASE + CIRCLE_RADIUS_PER_BOT * float(mates - 1)
  circleRadius = clampf(circleRadius, CIRCLE_RADIUS_MIN, CIRCLE_RADIUS_MAX)

  new float:safeHalf = MAP_SAFE_HALF - MAP_MARGIN
  if(safeHalf < 5.0)
    safeHalf = 5.0

  if(circleRadius > safeHalf - 1.2)
    circleRadius = safeHalf - 1.2
  if(circleRadius < CIRCLE_RADIUS_MIN)
    circleRadius = CIRCLE_RADIUS_MIN

  // Centro de llegada para el movimiento hacia +X, manteniendo todo el circulo dentro.
  centerTargetX = mapCx + safeHalf - circleRadius - 0.8
  centerTargetY = mapCy

  centerTargetX = clampf(centerTargetX, mapCx - safeHalf + circleRadius, mapCx + safeHalf - circleRadius)
  centerTargetY = clampf(centerTargetY, mapCy - safeHalf + circleRadius, mapCy + safeHalf - circleRadius)

  // Lider fijo al centro del circulo.
  if(getID() == LEADER_ID) {
    mySlotX = 0.0
    mySlotY = 0.0
    return
  }

  // Slots solo para followers en el perimetro.
  new followers = mates - 1
  if(followers < 1)
    followers = 1

  new rank = getID() - 1
  if(rank < 0)
    rank = 0
  if(rank >= followers)
    rank = rank % followers

  new float:ang = TWO_PI * float(rank) / float(followers)
  mySlotX = circleRadius * cos(ang)
  mySlotY = circleRadius * sin(ang)
}

stock getAbsTargetFromCenter(float:cx, float:cy, &float:tx, &float:ty) {
  tx = cx + mySlotX
  ty = cy + mySlotY
}

stock bool:isAtPoint(float:tx, float:ty, float:r) {
  new float:x
  new float:y
  new float:z
  getLocation(x, y, z)

  new float:dx = tx - x
  new float:dy = ty - y
  return sqrt(dx*dx + dy*dy) <= r
}

stock navigateToPoint(float:tx, float:ty, &frontStuckTicks) {
  new float:x
  new float:y
  new float:z
  getLocation(x, y, z)

  new float:dx = tx - x
  new float:dy = ty - y
  new float:heading = atan2(dy, dx)

  new float:blockYaw
  new float:blockDist
  if(getBlockingFriend(blockYaw, blockDist)) {
    ++frontStuckTicks
    if(blockYaw > 0.0)
      heading -= PI/4.0
    else
      heading += PI/4.0
  } else if(frontStuckTicks > 0) {
    --frontStuckTicks
  }

  if(sight() < WALL_AVOID_DIST)
    heading += (getID()%2 == 0 ? PI/5.5 : -PI/5.5)

  rotateTo(heading)
  if(isStanding())
    tryWalk()
}

stock performEscape(float:side) {
  rotateTo(getDirection() + side * PI/2.0)
  if(isStanding() || isWalking() || isRunning() || isWalkingcr())
    tryWalkBk()
}

stock sendPhaseWord(phase, activeFormId, float:now) {
  if(now - lastSpeakPhaseTime < getTimeNeededFor(ACTION_SPEAK))
    return

  new word
  if(phase == PHASE_FORM) {
    if(activeFormId < 1)
      activeFormId = 1
    if(activeFormId >= MAX_ID_TRACK)
      activeFormId = MAX_ID_TRACK - 1
    word = WORD_PHASE_FORM_BASE + activeFormId
  } else if(phase == PHASE_ALIGN) {
    word = WORD_PHASE_ALIGN
  } else {
    word = WORD_PHASE_MOVE
  }

  if(speak(RADIO_CHANNEL_PHASE, word))
    lastSpeakPhaseTime = now
}

stock leaderPollReady() {
  new word
  new id

  for(new tries = 0; tries < 6; ++tries) {
    if(!listen(RADIO_CHANNEL_READY, word, id))
      break

    if(id <= LEADER_ID || id >= MAX_ID_TRACK)
      continue

    if(word == WORD_READY_FORM) {
      if(!readyFormFrom[id]) {
        readyFormFrom[id] = true
        ++readyFormCount
      }
    } else if(word == WORD_READY_ALIGN) {
      if(!readyAlignFrom[id]) {
        readyAlignFrom[id] = true
        ++readyAlignCount
      }
    }
  }
}

stock followerPollPhase(&phase, &activeFormId) {
  new word
  new id

  for(new tries = 0; tries < 6; ++tries) {
    if(!listen(RADIO_CHANNEL_PHASE, word, id))
      break

    if(id != LEADER_ID)
      continue

    if(word >= WORD_PHASE_FORM_BASE && word < WORD_PHASE_FORM_BASE + MAX_ID_TRACK) {
      phase = PHASE_FORM
      activeFormId = word - WORD_PHASE_FORM_BASE
    } else if(word == WORD_PHASE_ALIGN)
      phase = PHASE_ALIGN
    else if(word == WORD_PHASE_MOVE)
      phase = PHASE_MOVE
  }
}

leader() {
  computeSharedGeometry()

  new followersExpected = getMates() - 1
  if(followersExpected < 0)
    followersExpected = 0

  for(new i = 0; i < MAX_ID_TRACK; ++i) {
    readyFormFrom[i] = false
    readyAlignFrom[i] = false
  }
  readyFormCount = 0
  readyAlignCount = 0

  new phase = PHASE_FORM
  new activeFormId = 1

  new float:formHoldSince = -1000.0
  new float:alignHoldSince = -1000.0
  new bool:leaderReadyForm = false
  new bool:leaderReadyAlign = false

  new float:escapeBackUntil = -1000.0
  new float:escapeSideUntil = -1000.0
  new float:escapeSide = 1.0
  new frontStuckTicks = 0

  for(;;) {
    new float:now = getTime()

    leaderPollReady()

    if(phase == PHASE_FORM) {
      while(activeFormId <= followersExpected && activeFormId < MAX_ID_TRACK && readyFormFrom[activeFormId])
        ++activeFormId

      if(activeFormId > followersExpected)
        activeFormId = followersExpected
      if(activeFormId < 1)
        activeFormId = 1
    }

    sendPhaseWord(phase, activeFormId, now)

    if(now - lastSayTime >= getTimeNeededFor(ACTION_SAY)) {
      if(say(WORD_LEADER_PING))
        lastSayTime = now
    }

    if(now < escapeBackUntil) {
      performEscape(escapeSide)
      wait(LOOP_DT)
      continue
    }

    if(now < escapeSideUntil) {
      rotateTo(getDirection() + escapeSide * PI/2.0)
      if(isStanding())
        tryWalk()
      wait(LOOP_DT)
      continue
    }

    new touched = getTouched()
    if(touched) {
      raise(touched)
      escapeSide = (random(2) == 0 ? 1.0 : -1.0)
      escapeBackUntil = now + ESC_BACK_TIME
      escapeSideUntil = escapeBackUntil + ESC_SIDE_TIME

      wait(LOOP_DT)
      continue
    }

    if(frontStuckTicks >= FRONT_STUCK_TICKS_MAX) {
      escapeSide = (random(2) == 0 ? 1.0 : -1.0)
      escapeBackUntil = now + ESC_BACK_TIME
      escapeSideUntil = escapeBackUntil + ESC_SIDE_TIME
      frontStuckTicks = 0

      wait(LOOP_DT)
      continue
    }

    if(phase == PHASE_FORM) {
      new float:tx
      new float:ty
      getAbsTargetFromCenter(centerStartX, centerStartY, tx, ty)

      if(!isAtPoint(tx, ty, FORM_POS_RADIUS)) {
        formHoldSince = -1000.0
        leaderReadyForm = false
        navigateToPoint(tx, ty, frontStuckTicks)
      } else {
        if(isMoving())
          tryStand()

        if(formHoldSince < -999.0)
          formHoldSince = now

        if(now - formHoldSince >= FORM_HOLD_TIME)
          leaderReadyForm = true
      }

      if(leaderReadyForm && readyFormCount >= followersExpected) {
        phase = PHASE_ALIGN
        alignHoldSince = -1000.0
        leaderReadyAlign = false
      }

      wait(LOOP_DT)
      continue
    }

    if(phase == PHASE_ALIGN) {
      new float:tx
      new float:ty
      getAbsTargetFromCenter(centerStartX, centerStartY, tx, ty)

      // Mantener posicion durante alineacion.
      if(!isAtPoint(tx, ty, FORM_POS_RADIUS))
        navigateToPoint(tx, ty, frontStuckTicks)
      else if(isMoving())
        tryStand()

      rotateTo(MOVE_HEADING)
      new float:yawErr = abs(wrapPi(MOVE_HEADING - getDirection()))
      if(yawErr <= ALIGN_YAW_TOL) {
        if(alignHoldSince < -999.0)
          alignHoldSince = now
        if(now - alignHoldSince >= ALIGN_HOLD_TIME)
          leaderReadyAlign = true
      } else {
        alignHoldSince = -1000.0
        leaderReadyAlign = false
      }

      if(leaderReadyAlign && readyAlignCount >= followersExpected)
        phase = PHASE_MOVE

      wait(LOOP_DT)
      continue
    }

    // PHASE_MOVE
    new float:mx
    new float:my
    getAbsTargetFromCenter(centerTargetX, centerTargetY, mx, my)

    if(!isAtPoint(mx, my, MOVE_DONE_RADIUS))
      navigateToPoint(mx, my, frontStuckTicks)
    else {
      rotateTo(MOVE_HEADING)
      if(isMoving())
        tryStand()
    }

    wait(LOOP_DT)
  }
}

follower() {
  computeSharedGeometry()

  new phase = PHASE_FORM
  new activeFormId = 1

  new float:lastReadyFormSent = -1000.0
  new float:lastReadyAlignSent = -1000.0

  new float:formHoldSince = -1000.0
  new float:alignHoldSince = -1000.0

  new float:escapeBackUntil = -1000.0
  new float:escapeSideUntil = -1000.0
  new float:escapeSide = 1.0
  new frontStuckTicks = 0

  rotateHead(0.0)

  for(;;) {
    new float:now = getTime()

    followerPollPhase(phase, activeFormId)

    if(now < escapeBackUntil) {
      performEscape(escapeSide)
      wait(LOOP_DT)
      continue
    }

    if(now < escapeSideUntil) {
      rotateTo(getDirection() + escapeSide * PI/2.0)
      if(isStanding())
        tryWalk()
      wait(LOOP_DT)
      continue
    }

    new touched = getTouched()
    if(touched) {
      raise(touched)
      escapeSide = (random(2) == 0 ? 1.0 : -1.0)
      escapeBackUntil = now + ESC_BACK_TIME
      escapeSideUntil = escapeBackUntil + ESC_SIDE_TIME

      wait(LOOP_DT)
      continue
    }

    if(frontStuckTicks >= FRONT_STUCK_TICKS_MAX) {
      escapeSide = (random(2) == 0 ? 1.0 : -1.0)
      escapeBackUntil = now + ESC_BACK_TIME
      escapeSideUntil = escapeBackUntil + ESC_SIDE_TIME
      frontStuckTicks = 0

      wait(LOOP_DT)
      continue
    }

    if(phase == PHASE_FORM) {
      if(getID() != activeFormId) {
        formHoldSince = -1000.0
        if(isMoving())
          tryStand()

        wait(LOOP_DT)
        continue
      }

      new float:tx
      new float:ty
      getAbsTargetFromCenter(centerStartX, centerStartY, tx, ty)

      if(!isAtPoint(tx, ty, FORM_POS_RADIUS)) {
        formHoldSince = -1000.0
        navigateToPoint(tx, ty, frontStuckTicks)
      } else {
        if(isMoving())
          tryStand()

        if(formHoldSince < -999.0)
          formHoldSince = now

        if(now - formHoldSince >= FORM_HOLD_TIME && now - lastReadyFormSent >= READY_RESEND_DT) {
          if(speak(RADIO_CHANNEL_READY, WORD_READY_FORM))
            lastReadyFormSent = now
        }
      }

      wait(LOOP_DT)
      continue
    }

    if(phase == PHASE_ALIGN) {
      new float:tx
      new float:ty
      getAbsTargetFromCenter(centerStartX, centerStartY, tx, ty)

      if(!isAtPoint(tx, ty, FORM_POS_RADIUS)) {
        alignHoldSince = -1000.0
        navigateToPoint(tx, ty, frontStuckTicks)
      } else {
        if(isMoving())
          tryStand()

        rotateTo(MOVE_HEADING)
        new float:yawErr = abs(wrapPi(MOVE_HEADING - getDirection()))
        if(yawErr <= ALIGN_YAW_TOL) {
          if(alignHoldSince < -999.0)
            alignHoldSince = now

          if(now - alignHoldSince >= ALIGN_HOLD_TIME && now - lastReadyAlignSent >= READY_RESEND_DT) {
            if(speak(RADIO_CHANNEL_READY, WORD_READY_ALIGN))
              lastReadyAlignSent = now
          }
        } else {
          alignHoldSince = -1000.0
        }
      }

      wait(LOOP_DT)
      continue
    }

    // PHASE_MOVE
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
      rotateTo(getDirection() + (getID()%2 == 0 ? PI/9.0 : -PI/9.0))
      if(isStanding())
        tryWalk()
      wait(LOOP_DT)
      continue
    }

    new float:x
    new float:y
    new float:z
    getLocation(x, y, z)

    new float:leaderX = x + lastLeaderDist * cos(lastLeaderAbsDir)
    new float:leaderY = y + lastLeaderDist * sin(lastLeaderAbsDir)

    new float:centerX = leaderX
    new float:centerY = leaderY

    new float:tx = centerX + mySlotX
    new float:ty = centerY + mySlotY

    if(!isAtPoint(tx, ty, FORM_POS_RADIUS)) {
      new float:mx
      new float:my
      new float:mz
      getLocation(mx, my, mz)

      new float:dx = tx - mx
      new float:dy = ty - my
      new float:heading = atan2(dy, dx)

      // Mantener direccion comun de avance con una correccion lateral limitada.
      new float:hd = wrapPi(heading - MOVE_HEADING)
      if(hd > MOVE_SYNC_BIAS)
        heading = MOVE_HEADING + MOVE_SYNC_BIAS
      else if(hd < -MOVE_SYNC_BIAS)
        heading = MOVE_HEADING - MOVE_SYNC_BIAS

      new float:blockYaw
      new float:blockDist
      if(getBlockingFriend(blockYaw, blockDist)) {
        ++frontStuckTicks
        if(blockYaw > 0.0)
          heading -= PI/5.0
        else
          heading += PI/5.0
      } else if(frontStuckTicks > 0) {
        --frontStuckTicks
      }

      if(sight() < WALL_AVOID_DIST)
        heading += (getID()%2 == 0 ? PI/5.5 : -PI/5.5)

      rotateTo(heading)
      if(isStanding())
        tryWalk()
    } else {
      rotateTo(MOVE_HEADING)
      if(isStanding())
        tryWalk()
    }

    wait(LOOP_DT)
  }
}

main() {
  if(getID() == LEADER_ID)
    leader()
  else
    follower()
}
