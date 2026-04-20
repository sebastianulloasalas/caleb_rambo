// mov_inteligente.sma
//
// Todos los bots:
// 1) Van de su punto inicial A a un punto B y regresan.
// 2) Pueden pedir paso por radio si otro companero bloquea.
// 3) Pueden ceder el paso cuando reciben peticion privada.

#include "core"
#include "math"
#include "bots"

new const float:PI = 3.1415
new const float:TWO_PI = 6.2830

// Ruta A <-> B.
new const float:ROUTE_ARRIVE_RADIUS = 1.0
new const float:ROUTE_RESET_RADIUS = 2.2
new const float:MIN_ROUTE_DIST = 12.0
new const float:TARGET_RING_RADIUS = 18.0

// Navegacion general.
new const float:LOOP_DT = 0.04
new const float:WALL_AVOID_DIST = 2.2

// Deteccion de bloqueo frontal.
new const float:BLOCK_DIST = 2.4
new const float:BLOCK_YAW = 0.80
new const float:SCAN_HEAD_SWEEP = 0.52
new const float:SCAN_DT = 0.55

// Protocolo de radio privada por ID.
new const PASS_BASE_CHANNEL = 80
new const WORD_PASS_LEFT = 7101
new const WORD_PASS_RIGHT = 7102
new const float:PASS_RESEND_SAME_TARGET_DT = 1.00
new const float:PASS_SIDE_BIAS = 0.35

// Maniobra de cesion.
new const float:YIELD_STEP_TIME = 1.00
new const float:YIELD_HOLD_TIME = 0.15
new const float:YIELD_TASK_MAX_DT = 4.00
new const float:YIELD_CHECK_DT = 0.25
new const float:YIELD_MIN_MOVE = 0.16
new const float:YIELD_BOOST_ANGLE = 0.85
new const float:YIELD_BACK_MODE_ERR = 1.20

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

stock getPassChannelFor(botId) {
  if(botId < 0)
    botId = 0
  return PASS_BASE_CHANNEL + botId
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

stock bool:getBlockingFriend(&float:blockYaw, &float:blockDist, &blockId, float:maxYaw) {
  new item
  new float:yaw
  new float:pitch
  new id
  new float:minDist = 0.0
  new maxScans = getMates() + 2

  if(maxScans < 4)
    maxScans = 4
  if(maxScans > 20)
    maxScans = 20

  blockYaw = 0.0
  blockId = -1
  blockDist = 9999.0

  for(new tries = 0; tries < maxScans; ++tries) {
    item = ITEM_FRIEND|ITEM_WARRIOR
    new float:dist = minDist
    watch(item, dist, yaw, pitch, id)
    if(item == ITEM_NONE)
      break

    if(isFriendWarrior(item) && id != getID() && dist < BLOCK_DIST && abs(yaw) < maxYaw) {
      if(blockId < 0 || dist < blockDist) {
        blockYaw = yaw
        blockDist = dist
        blockId = id
      }
    }

    minDist = dist + 0.4
  }

  return (blockId >= 0)
}

stock bool:watchFriendById(targetId, &float:dist, &float:yaw) {
  new item
  new float:pitch
  new id
  new float:minDist = 0.0

  for(new tries = 0; tries < 8; ++tries) {
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

stock getBotTarget(float:homeX, float:homeY, &float:tx, &float:ty) {
  new float:cx
  new float:cy

  new mates = getMates()
  if(mates < 1)
    mates = 1

  new float:angle = TWO_PI * float(getID()) / float(mates)

  if(getArenaCenter(cx, cy)) {
    tx = cx + cos(angle) * TARGET_RING_RADIUS
    ty = cy + sin(angle) * TARGET_RING_RADIUS
  } else {
    tx = homeX + cos(angle) * TARGET_RING_RADIUS
    ty = homeY + sin(angle) * TARGET_RING_RADIUS
  }

  new float:d = sqrt((tx-homeX)*(tx-homeX) + (ty-homeY)*(ty-homeY))
  if(d < MIN_ROUTE_DIST) {
    tx = homeX + MIN_ROUTE_DIST * cos(angle)
    ty = homeY + MIN_ROUTE_DIST * sin(angle)
  }
}

smartBot() {
  // Punto A fijo del bot (origen exacto de referencia).
  new float:homeX
  new float:homeY
  new float:homeZ
  getLocation(homeX, homeY, homeZ)

  // Punto B absoluto calculado para este bot.
  new float:targetX
  new float:targetY
  getBotTarget(homeX, homeY, targetX, targetY)

  new const ROUTE_TO_B = 0
  new const ROUTE_TO_A = 1
  new routeState = ROUTE_TO_B
  new routeLatched = 0

  // Estado de radio/speak.
  new myPassChannel = getPassChannelFor(getID())
  new float:lastSpeakTime = -1000.0
  new lastPassTarget = -1
  new float:lastPassTargetTime = -1000.0

  // Estado de cesion.
  new bool:yieldBusy = false
  new float:yieldStepUntil = -1000.0
  new float:yieldHoldUntil = -1000.0
  new float:yieldDeadline = -1000.0
  new float:yieldDir = 0.0
  new float:yieldSide = (getID()%2 == 0 ? 1.0 : -1.0)
  new bool:hasYieldDir = false
  new float:yieldStartX = homeX
  new float:yieldStartY = homeY
  new float:yieldCheckTime = -1000.0
  new yieldBoostCount = 0

  // Escaneo de cabeza.
  new float:scanHead = SCAN_HEAD_SWEEP
  new float:lastScanTime = -1000.0

  walk()
  printf("BOT-ID-%d INICIO A(%.1f,%.1f) B(%.1f,%.1f)^n", getID(), homeX, homeY, targetX, targetY)

  for(;;) {
    new float:now = getTime()

    // Escaneo suave para ampliar deteccion sin parar movimiento.
    if(!isHeadRotating() && now - lastScanTime >= SCAN_DT) {
      rotateHead(scanHead)
      scanHead = -scanHead
      lastScanTime = now
    }

    // Seguridad: evita quedar ocupado infinito en cesion.
    if(yieldBusy && now > yieldDeadline) {
      yieldBusy = false
      hasYieldDir = false
      yieldStepUntil = -1000.0
      yieldHoldUntil = -1000.0
      printf("BOT-ID-%d YIELD-TIMEOUT^n", getID())
    }

    // Escucha peticiones solo cuando no esta cediendo.
    new word
    new senderId
    if(!yieldBusy && listen(myPassChannel, word, senderId)) {
      if(senderId != getID() && (word == WORD_PASS_LEFT || word == WORD_PASS_RIGHT)) {
        new float:rDist
        new float:rYaw
        new bool:okWatch = watchFriendById(senderId, rDist, rYaw)

        yieldSide = (word == WORD_PASS_LEFT ? 1.0 : -1.0)
        if(okWatch) {
          new float:senderAbs = getDirection() + getTorsoYaw() + getHeadYaw() + rYaw
          yieldDir = senderAbs + PI + yieldSide * PASS_SIDE_BIAS
          hasYieldDir = true
        } else {
          yieldDir = getDirection() + PI + yieldSide * 0.90
          hasYieldDir = true
        }

        yieldBusy = true
        yieldStepUntil = now + YIELD_STEP_TIME
        yieldHoldUntil = yieldStepUntil + YIELD_HOLD_TIME
        yieldDeadline = now + YIELD_TASK_MAX_DT
        getLocation(yieldStartX, yieldStartY)
        yieldCheckTime = now + YIELD_CHECK_DT
        yieldBoostCount = 0

        printf("BOT-ID-%d RX-PASS DE-%d CH-%d WORD-%d^n", getID(), senderId, myPassChannel, word)
      }
    }

    // Modo cesion: apartarse y sostener.
    if(yieldBusy) {
      if(now < yieldStepUntil) {
        if(hasYieldDir) {
          new float:dirErr = wrapPi(yieldDir - getDirection())
          rotateTo(yieldDir)

          if(abs(dirErr) > YIELD_BACK_MODE_ERR) {
            if(isStanding() || isWalking() || isRunning() || isWalkingcr())
              walkbk()
          } else {
            if(isStanding() || isWalking() || isWalkingbk() || isWalkingcr()) {
              if(!run())
                walk()
            }
          }
        }

        if(sight() < WALL_AVOID_DIST)
          yieldDir = getDirection() - yieldSide * PI/2.2

        if(now >= yieldCheckTime) {
          new float:cx
          new float:cy
          new float:cz
          getLocation(cx, cy, cz)

          new float:mdx = cx - yieldStartX
          new float:mdy = cy - yieldStartY
          new float:moved = sqrt(mdx*mdx + mdy*mdy)

          if(moved < YIELD_MIN_MOVE) {
            ++yieldBoostCount
            new float:boostSign = (yieldBoostCount%2 == 0 ? -1.0 : 1.0)
            yieldDir = getDirection() + boostSign * yieldSide * (YIELD_BOOST_ANGLE + 0.15*float(yieldBoostCount%3))
            rotateTo(yieldDir)
            if(!isRunning())
              run()
            printf("BOT-ID-%d BOOST-%d^n", getID(), yieldBoostCount)
          }

          yieldStartX = cx
          yieldStartY = cy
          yieldCheckTime = now + YIELD_CHECK_DT
        }

        wait(LOOP_DT)
        continue
      }

      if(now < yieldHoldUntil) {
        if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
          stand()

        wait(LOOP_DT)
        continue
      }

      yieldBusy = false
      hasYieldDir = false
      printf("BOT-ID-%d YIELD-COMPLETE^n", getID())
    }

    // Ruta normal A <-> B.
    new float:tx = (routeState == ROUTE_TO_B ? targetX : homeX)
    new float:ty = (routeState == ROUTE_TO_B ? targetY : homeY)

    new float:x
    new float:y
    new float:z
    getLocation(x, y, z)

    new float:dx = tx - x
    new float:dy = ty - y
    new float:err = sqrt(dx*dx + dy*dy)

    if(err <= ROUTE_ARRIVE_RADIUS) {
      if(!routeLatched) {
        if(routeState == ROUTE_TO_B) {
          routeState = ROUTE_TO_A
          printf("BOT-ID-%d LLEGO-B REGRESA-A^n", getID())
        } else {
          routeState = ROUTE_TO_B
          printf("BOT-ID-%d LLEGO-A VA-B^n", getID())
        }
        routeLatched = 1
      }
    } else if(err >= ROUTE_RESET_RADIUS) {
      routeLatched = 0
    }

    // Bloqueo frontal: pedir paso al bot objetivo.
    new float:blockYaw
    new float:blockDist
    new blockId
    if(getBlockingFriend(blockYaw, blockDist, blockId, BLOCK_YAW)) {
      rotateTo(getDirection() + (blockYaw > 0.0 ? -PI/6.0 : PI/6.0))

      if(now - lastSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
        if(blockId >= 0 && blockId != getID()) {
          if(!(blockId == lastPassTarget && now - lastPassTargetTime < PASS_RESEND_SAME_TARGET_DT)) {
            new passWord = (blockYaw > 0.0 ? WORD_PASS_RIGHT : WORD_PASS_LEFT)
            new passChannel = getPassChannelFor(blockId)
            if(speak(passChannel, passWord)) {
              lastSpeakTime = now
              lastPassTarget = blockId
              lastPassTargetTime = now
              printf("BOT-ID-%d TX-PASS TO-%d CH-%d WORD-%d^n", getID(), blockId, passChannel, passWord)
            }
          }
        }
      }
    } else {
      rotateTo(atan2(dy, dx))
    }

    if(sight() < WALL_AVOID_DIST)
      rotateTo(getDirection() + (random(2) == 0 ? PI/4.0 : -PI/4.0))

    if(isStanding())
      walk()

    new touched = getTouched()
    if(touched)
      raise(touched)

    wait(LOOP_DT)
  }
}

fight() {
  smartBot()
}

main() {
  switch(getPlay()) {
    case PLAY_FIGHT: fight()
    case PLAY_SOCCER: fight()
    case PLAY_RACE: fight()
  }
}
