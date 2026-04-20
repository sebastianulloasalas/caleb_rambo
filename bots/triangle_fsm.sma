// triangle_fsm (sequential + give-way, compact) - DEPRECATED

#include "core"
#include "math"
#include "bots"

new const LEADER_ID = 0

new const RADIO_CHANNEL_LEADER = 9
new const RADIO_CHANNEL_SEQ = 6
new const RADIO_CHANNEL_PASS = 8

new const WORD_LEADER_ANNOUNCE = 6101
new const WORD_LEADER_READY = 6102
new const WORD_LEADER_PING = 6103

new const WORD_SEQ_CALL = 6301
new const WORD_SEQ_CLAIM = 6302
new const WORD_SEQ_DONE = 6303
new const WORD_SEQ_ASSIGN_BASE = 6400

new const WORD_PASS_LEFT = 6501
new const WORD_PASS_RIGHT = 6502

#define MAX_TRACKED_BOTS 64

new const float:PI = 3.1415
new const float:TWO_PI = 6.2830
new const float:SQRT3 = 1.73205

new const float:SLOT_SPACING = 2.5
new const float:LEADER_CLEARANCE = 2.0
new const float:HOLD_RADIUS = 1.0

new const float:WALL_AVOID_DIST = 2.4
new const float:BLOCK_DIST = 1.9
new const float:BLOCK_YAW = 0.45

new const float:LEADER_CENTER_REACHED = 2.2
new const float:LEADER_RELOCATE_TIME = 26.0
new const float:READY_FAILSAFE_DELAY = 18.0

new const float:SEQ_CALL_PERIOD = 0.70
new const float:SEQ_ASSIGN_REPEAT = 1.00
new const float:SEQ_ACTIVE_TIMEOUT = 12.0

new const float:PASS_STEP_TIME = 0.70
new const float:PASS_HOLD_TIME = 0.55
new const float:PASS_SIDE_ANGLE = 1.05
new const float:PASS_TRIGGER_DIST = 3.0
new const float:PASS_FRONT_YAW = 0.65

new const float:LOOP_DT = 0.06
new const float:JUMP_DT = 0.65
new const float:DIAG_ESCAPE_ANGLE = 0.95
new const float:DIAG_ESCAPE_TIME = 0.75
new const float:STUCK_CHECK_DT = 0.55
new const float:STUCK_ERR_EPS = 0.12
new const STUCK_MAX = 2

new float:lastSayTime = -1000.0
new float:lastLeaderSpeakTime = -1000.0
new float:lastLeaderJumpTime = -1000.0

new leaderId
new bool:leaderKnown
new bool:leaderReady
new bool:leaderArrived
new bool:leaderMsgPrinted
new bool:leaderJumpCrouched

stock bool:isFriendWarrior(item) {
  if((item & ITEM_FRIEND) && (item & ITEM_WARRIOR))
    return true
  return false
}

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
  rotate(cur + wrapPi(absAngle - cur))
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

stock bool:getSlotForRank(rank, &float:slotU, &float:slotV) {
  new const MAX_ROWS = 26
  new float:du = SLOT_SPACING * SQRT3 / 2.0
  new count = 0

  for(new row = 1; row <= MAX_ROWS; ++row) {
    new rowLen = row
    new float:u = -float(row) * du
    new float:center = float(rowLen - 1) / 2.0

    for(new col = 0; col < rowLen; ++col) {
      new float:v = (float(col) - center) * SLOT_SPACING
      if(sqrt(u*u + v*v) < LEADER_CLEARANCE)
        continue

      if(count == rank) {
        slotU = u
        slotV = v
        return true
      }
      ++count
    }
  }

  return false
}

stock pollLeaderRadio() {
  new word
  new id

  if(listen(RADIO_CHANNEL_LEADER, word, id)) {
    if(word == WORD_LEADER_ANNOUNCE || word == WORD_LEADER_READY) {
      leaderId = id
      leaderKnown = true
      if(word == WORD_LEADER_READY)
        leaderReady = true
    }
  }
}

stock bool:getLeaderVector(&float:dist, &float:absDir) {
  new item = ITEM_FRIEND|ITEM_WARRIOR
  new float:yaw
  new float:pitch
  new id

  dist = 0.0
  watch(item, dist, yaw, pitch, id)
  if(isFriendWarrior(item) && ((leaderKnown && id == leaderId) || (!leaderKnown && id == LEADER_ID))) {
    leaderId = id
    leaderKnown = true
    absDir = getDirection() + getTorsoYaw() + getHeadYaw() + yaw
    return true
  }

  new sound
  item = 0
  dist = hear(item, sound, yaw, pitch, id)
  if(isFriendWarrior(item) && sound == WORD_LEADER_PING && ((leaderKnown && id == leaderId) || (!leaderKnown && id == LEADER_ID))) {
    leaderId = id
    leaderKnown = true
    absDir = getDirection() + getTorsoYaw() + getHeadYaw() + yaw
    return true
  }

  return false
}

stock bool:getBlockingFriend(&float:blockYaw, &float:blockDist, &blockId) {
  new item = ITEM_FRIEND|ITEM_WARRIOR
  new float:yaw
  new float:pitch
  new id

  blockId = -1
  blockDist = 0.0
  watch(item, blockDist, yaw, pitch, id)
  if(isFriendWarrior(item) && blockDist < BLOCK_DIST && abs(yaw) < BLOCK_YAW) {
    blockYaw = yaw
    blockId = id
    return true
  }

  return false
}

stock bool:watchFriendById(targetId, &float:dist, &float:yaw) {
  new item
  new float:pitch
  new id
  new float:minDist = 0.0

  for(new tries = 0; tries < 5; ++tries) {
    item = ITEM_FRIEND|ITEM_WARRIOR
    dist = minDist
    watch(item, dist, yaw, pitch, id)
    if(item == ITEM_NONE)
      return false

    if(isFriendWarrior(item) && id == targetId)
      return true

    minDist = dist + 0.6
  }

  return false
}

leader() {
  new float:centerX
  new float:centerY
  new bool:haveCenter = getArenaCenter(centerX, centerY)
  new float:relocateUntil = getTime() + LEADER_RELOCATE_TIME

  new bool:readySpoken = false
  new bool:placed[MAX_TRACKED_BOTS]
  for(new i = 0; i < MAX_TRACKED_BOTS; ++i)
    placed[i] = false

  new followers = getMates() - 1
  if(followers < 0) followers = 0
  if(followers >= MAX_TRACKED_BOTS) followers = MAX_TRACKED_BOTS - 1

  new placedCount = 0
  new activeBot = -1
  new float:lastSeqCallTime = -1000.0
  new float:lastSeqAssignTime = -1000.0
  new float:activeSince = -1000.0

  walk()

  for(;;) {
    new float:now = getTime()

    if(now - lastSayTime >= getTimeNeededFor(ACTION_SAY)) {
      if(say(WORD_LEADER_PING))
        lastSayTime = now
    }

    if(!leaderReady && now - lastLeaderSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
      if(speak(RADIO_CHANNEL_LEADER, WORD_LEADER_ANNOUNCE))
        lastLeaderSpeakTime = now
    }

    if(!leaderReady) {
      if(haveCenter) {
        new float:x
        new float:y
        new float:z
        getLocation(x, y, z)

        new float:dx = centerX - x
        new float:dy = centerY - y
        new float:d = sqrt(dx*dx + dy*dy)
        new nearEnough = (d <= LEADER_CENTER_REACHED)
        new timeoutNear = (now >= relocateUntil && d <= LEADER_CENTER_REACHED + 2.4)

        if(nearEnough || timeoutNear) {
          if(nearEnough)
            leaderArrived = true
          leaderReady = true
          if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
            stand()
        } else {
          if(sight() < WALL_AVOID_DIST)
            rotateTo(getDirection() + (random(2) == 0 ? PI/4.0 : -PI/4.0))
          else
            rotateTo(atan2(dy, dx))

          if(isStanding())
            walk()
        }
      } else {
        leaderReady = true
      }

      wait(LOOP_DT)
      continue
    }

    if(!readySpoken && now - lastLeaderSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
      if(speak(RADIO_CHANNEL_LEADER, WORD_LEADER_READY)) {
        readySpoken = true
        lastLeaderSpeakTime = now
      }
    }

    if(leaderArrived && !leaderMsgPrinted) {
      printf("lider-,llegue a deestino^n")
      leaderMsgPrinted = true
    }

    new seqWord
    new seqId
    for(new tries = 0; tries < 8; ++tries) {
      if(!listen(RADIO_CHANNEL_SEQ, seqWord, seqId))
        break

      if(seqWord == WORD_SEQ_CLAIM &&
         activeBot < 0 &&
         seqId > LEADER_ID &&
         seqId < MAX_TRACKED_BOTS &&
         !placed[seqId]) {
        activeBot = seqId
        activeSince = now
        lastSeqAssignTime = -1000.0
      } else if(seqWord == WORD_SEQ_DONE && seqId > LEADER_ID && seqId < MAX_TRACKED_BOTS) {
        if(!placed[seqId]) {
          placed[seqId] = true
          ++placedCount
        }

        if(seqId == activeBot) {
          activeBot = -1
          activeSince = -1000.0
          lastSeqAssignTime = -1000.0
        }
      }
    }

    if(placedCount < followers) {
      if(activeBot < 0) {
        if(now - lastSeqCallTime >= SEQ_CALL_PERIOD && now - lastLeaderSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
          if(speak(RADIO_CHANNEL_SEQ, WORD_SEQ_CALL)) {
            lastSeqCallTime = now
            lastLeaderSpeakTime = now
          }
        }
      } else {
        if((lastSeqAssignTime < 0.0 || now - lastSeqAssignTime >= SEQ_ASSIGN_REPEAT) && now - lastLeaderSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
          if(speak(RADIO_CHANNEL_SEQ, WORD_SEQ_ASSIGN_BASE + activeBot)) {
            lastSeqAssignTime = now
            lastLeaderSpeakTime = now
          }
        }

        if(activeSince > 0.0 && now - activeSince > SEQ_ACTIVE_TIMEOUT) {
          activeBot = -1
          activeSince = -1000.0
          lastSeqAssignTime = -1000.0
        }
      }
    }

    if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
      stand()

    if(now - lastLeaderJumpTime >= JUMP_DT) {
      if(leaderJumpCrouched) {
        if(stand()) {
          leaderJumpCrouched = false
          lastLeaderJumpTime = now
        }
      } else {
        if(crouch()) {
          leaderJumpCrouched = true
          lastLeaderJumpTime = now
        }
      }
    }

    if(sight() < WALL_AVOID_DIST)
      rotateTo(getDirection() + (random(2) == 0 ? PI/3.0 : -PI/3.0))

    wait(LOOP_DT)
  }
}

follower() {
  new float:slotU = 0.0
  new float:slotV = 0.0
  new bool:slotReady = false
  new bool:selfReadyPrinted = false

  new rank = getID() - 1
  if(rank < 0) rank = 0

  new bool:myActive = false
  new bool:myDone = false
  new bool:doneSent = false
  new activeBotId = -1

  new float:lastCtrlSpeakTime = -1000.0
  new float:lastPassSpeakTime = -1000.0
  new float:lastSelfJumpTime = -1000.0
  new bool:selfJumpCrouched = false
  new float:diagUntil = -1000.0
  new float:diagSide = (getID()%2 == 0 ? 1.0 : -1.0)
  new float:lastErrCheckTime = -1000.0
  new float:lastErr = 999999.0
  new stuckCount = 0

  new float:yieldStepUntil = -1000.0
  new float:yieldHoldUntil = -1000.0
  new float:yieldSide = 1.0

  if(getSlotForRank(rank, slotU, slotV)) {
    slotReady = true
  } else {
    slotU = -4.8 - float(rank) * 0.55
    slotV = (rank%2 == 0 ? 1.3 : -1.3)
    slotReady = true
  }

  walk()

  for(;;) {
    new float:now = getTime()

    pollLeaderRadio()

    new seqWord
    new seqId
    for(new tries = 0; tries < 6; ++tries) {
      if(!listen(RADIO_CHANNEL_SEQ, seqWord, seqId))
        break

      if(seqWord == WORD_SEQ_CALL && !myDone && !myActive) {
        if(now - lastCtrlSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
          if(speak(RADIO_CHANNEL_SEQ, WORD_SEQ_CLAIM))
            lastCtrlSpeakTime = now
        }
      } else if(seqWord >= WORD_SEQ_ASSIGN_BASE && seqWord < WORD_SEQ_ASSIGN_BASE + MAX_TRACKED_BOTS) {
        activeBotId = seqWord - WORD_SEQ_ASSIGN_BASE
        if(activeBotId == getID())
          myActive = true
        else
          myActive = false
      } else if(seqWord == WORD_SEQ_DONE) {
        if(seqId == activeBotId)
          activeBotId = -1
      }
    }

    new passWord
    new passId
    for(new tries = 0; tries < 4; ++tries) {
      if(!listen(RADIO_CHANNEL_PASS, passWord, passId))
        break

      if(!myActive && !myDone && activeBotId > 0 && passId == activeBotId && (passWord == WORD_PASS_LEFT || passWord == WORD_PASS_RIGHT)) {
        yieldSide = (passWord == WORD_PASS_LEFT ? 1.0 : -1.0)
        yieldStepUntil = now + PASS_STEP_TIME
        yieldHoldUntil = yieldStepUntil + PASS_HOLD_TIME
      }
    }

    if(!myActive && !myDone && activeBotId > 0 && now >= yieldHoldUntil) {
      new float:reqDist
      new float:reqYaw
      if(watchFriendById(activeBotId, reqDist, reqYaw) && reqDist < PASS_TRIGGER_DIST && abs(reqYaw) < PASS_FRONT_YAW) {
        yieldSide = (reqYaw > 0.0 ? -1.0 : 1.0)
        yieldStepUntil = now + PASS_STEP_TIME
        yieldHoldUntil = yieldStepUntil + PASS_HOLD_TIME
      }
    }

    if(myDone) {
      if(!doneSent && now - lastCtrlSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
        if(speak(RADIO_CHANNEL_SEQ, WORD_SEQ_DONE)) {
          lastCtrlSpeakTime = now
          doneSent = true
        }
      }

      if(now - lastSelfJumpTime >= JUMP_DT) {
        if(selfJumpCrouched) {
          if(stand()) {
            selfJumpCrouched = false
            lastSelfJumpTime = now
          }
        } else {
          if(crouch()) {
            selfJumpCrouched = true
            lastSelfJumpTime = now
          }
        }
      }

      wait(LOOP_DT)
      continue
    }

    if(now < yieldStepUntil) {
      rotateTo(getDirection() + yieldSide * PASS_SIDE_ANGLE)
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - yieldSide * PI/4.0)

      if(isStanding())
        walk()

      wait(LOOP_DT)
      continue
    }

    if(now < yieldHoldUntil) {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()

      wait(LOOP_DT)
      continue
    }

    if(now < diagUntil) {
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - diagSide * PI/4.0)

      if(isStanding())
        walk()

      wait(LOOP_DT)
      continue
    }

    if(!myActive) {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()

      wait(LOOP_DT)
      continue
    }

    if(!leaderReady && now >= READY_FAILSAFE_DELAY)
      leaderReady = true

    if(!slotReady) {
      if(isStanding())
        walk()
      wait(LOOP_DT)
      continue
    }

    new float:d
    new float:adir
    new bool:haveLeader = getLeaderVector(d, adir)

    if(!haveLeader) {
      rotateTo(getDirection() + (getID()%2 == 0 ? 0.18 : -0.18))
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() + (getID()%2 == 0 ? PI/4.0 : -PI/4.0))
      if(isStanding())
        walk()

      wait(LOOP_DT)
      continue
    }

    new float:lx = d * cos(adir)
    new float:ly = d * sin(adir)
    new float:tx = lx + slotU
    new float:ty = ly + slotV
    new float:err = sqrt(tx*tx + ty*ty)

    new bool:doDiag = false
    new touchedNow = getTouched()
    if(touchedNow) {
      raise(touchedNow)
      doDiag = true
      diagSide = -diagSide
    }

    if(now - lastErrCheckTime >= STUCK_CHECK_DT) {
      if(err > HOLD_RADIUS && lastErr < 900000.0 && abs(lastErr - err) < STUCK_ERR_EPS)
        ++stuckCount
      else
        stuckCount = 0

      lastErr = err
      lastErrCheckTime = now
    }

    if(stuckCount >= STUCK_MAX) {
      doDiag = true
      stuckCount = 0
      diagSide = (random(2) == 0 ? 1.0 : -1.0)
    }

    if(doDiag) {
      diagUntil = now + DIAG_ESCAPE_TIME
      rotateTo(getDirection() + diagSide * DIAG_ESCAPE_ANGLE)
      if(isStanding())
        walk()

      wait(LOOP_DT)
      continue
    }

    if(err <= HOLD_RADIUS) {
      if(leaderReady && !selfReadyPrinted) {
        printf("LISTO-BOT-%d^n", getID())
        selfReadyPrinted = true
      }

      myDone = true
      myActive = false
      doneSent = false

      if(now - lastCtrlSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
        if(speak(RADIO_CHANNEL_SEQ, WORD_SEQ_DONE)) {
          lastCtrlSpeakTime = now
          doneSent = true
        }
      }

      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()

      wait(LOOP_DT)
      continue
    }

    new float:blockYaw
    new float:blockDist
    new blockId

    if(getBlockingFriend(blockYaw, blockDist, blockId)) {
      rotateTo(getDirection() + (blockYaw > 0.0 ? -PI/5.0 : PI/5.0))

      if(now - lastPassSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
        new passWordOut = (blockYaw > 0.0 ? WORD_PASS_RIGHT : WORD_PASS_LEFT)
        if(speak(RADIO_CHANNEL_PASS, passWordOut))
          lastPassSpeakTime = now
      }
    } else {
      rotateTo(atan2(ty, tx))
    }

    if(sight() < WALL_AVOID_DIST) {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()
      rotateTo(getDirection() + (getID()%2 == 0 ? PI/4.0 : -PI/4.0))
    }

    if(isStanding())
      walk()

    new touched = getTouched()
    if(touched)
      raise(touched)

    wait(LOOP_DT)
  }
}

fight() {
  if(getID() == LEADER_ID)
    leader()
  else
    follower()
}

main() {
  switch(getPlay()) {
    case PLAY_FIGHT: fight()
    case PLAY_SOCCER: fight()
    case PLAY_RACE: fight()
  }
}
