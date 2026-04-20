// triangulo_equipo.sma
//
// Formacion triangular fija:
// - ID 0 (jefe) va al centro del mapa.
// - Los demas bots se distribuyen sobre el perimetro de un triangulo
//   segun getMates().

#include "core"
#include "math"
#include "bots"

new const float:PI = 3.1415
new const float:TWO_PI = 6.2830

new const float:ARRIVE_RADIUS = 0.38
new const float:ARRIVE_RESET_RADIUS = 1.10
new const float:FINAL_APPROACH_RADIUS = 1.10
new const float:FINAL_ALIGN_YAW = 0.18
new const float:NAV_TURN_DEADBAND = 0.10
new const float:WALL_AVOID_DIST = 2.2
new const float:BLOCK_DIST = 1.9
new const float:BLOCK_YAW = 0.65

new const float:TRI_BASE_RADIUS = 6.0
new const float:TRI_PER_BOT_RADIUS = 0.55
new const float:TRI_MIN_RADIUS = 5.0
new const float:TRI_MAX_RADIUS = 14.0
new const float:MAP_SAFE_HALF = 58.0
new const float:MAP_EDGE_MARGIN = 2.5

new const float:MOVE_CHECK_DT = 0.35
new const float:MOVE_EPS = 0.25
new const STUCK_MAX = 5 
new const float:BACKOFF_TIME = 0.50
new const float:BACKOFF_ANGLE = 0.90
new const float:WALL_TRAP_DIST = 1.20
new const float:WALL_ESCAPE_TIME = 0.75
new const float:WALL_ESCAPE_ANGLE = 1.05
new const float:WALL_ESCAPE_REARM_DT = 0.30
new const WALL_TRAP_COUNT_MAX = 8
new const float:WALL_TRAP_COUNT_DT = 0.20

new const float:BOT_BLOCK_REPEAT_DT = 0.20
new const BOT_BLOCK_REPEAT_MAX = 4
new const float:BOT_YIELD_TIME = 0.60
new const float:BOT_YIELD_ANGLE = 1.10
new const float:BOT_YIELD_EXTRA_TIME = 0.30
new const float:BOT_FORCE_BYPASS_TIME = 0.45
new const float:BOT_FORCE_BYPASS_ANGLE = 0.85
new const float:DEADLOCK_BACK_TIME = 1.10
new const float:DEADLOCK_SIDE_TIME = 0.62
new const float:DEADLOCK_SIDE_ANGLE = 1.28
new const float:DEADLOCK_COOLDOWN = 0.40
new const float:WALL_BREAK_BACK_TIME = 1.20
new const float:WALL_BREAK_SIDE_TIME = 0.85
new const float:WALL_BREAK_ANGLE = 1.45
new const float:WALL_BREAK_REARM_DT = 1.00
new const float:EDGE_NEAR_MARGIN = 1.8
new const float:TRI_BORDER_CLEARANCE = 9.5
new const float:TRI_TARGET_MARGIN = 1.2
new const float:TRI_FIT_MIN_RADIUS = 3.5
new const float:CENTER_PULL_TO_ORIGIN = 0.15

new const PASS_BASE_CHANNEL = 140
new const WORD_PASS_LEFT = 9101
new const WORD_PASS_RIGHT = 9102
new const float:PASS_RESEND_SAME_TARGET_DT = 0.90
new const float:YIELD_BACK_ONLY_TIME = 0.24
new const float:YIELD_SAME_SENDER_COOLDOWN = 0.55
new const float:YIELD_GLOBAL_REARM_DT = 0.25
new const float:BLOCK_SCAN_BACK_TIME = 0.20
new const float:BACK_PHASE_MIN_GAP = 2.20
new const float:MAX_CONTINUOUS_BACK_TIME = 0.72

new const float:LOOP_DT = 0.04

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

stock bool:isFriendWarrior(item) {
  if((item & ITEM_FRIEND) && (item & ITEM_WARRIOR))
    return true
  return false
}

stock bool:canIssueWalk() {
  if(isStanding() || isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
    return true
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

stock bool:getFrontBlockInfo(&float:blockYaw, &float:blockDist, &blockId) {
  new item
  new float:dist
  new float:yaw
  new float:pitch
  new id
  new float:minDist = 0.0

  blockYaw = 0.0
  blockDist = 0.0
  blockId = -1

  for(new tries = 0; tries < 8; ++tries) {
    item = ITEM_FRIEND|ITEM_WARRIOR
    dist = minDist
    watch(item, dist, yaw, pitch, id)
    if(item == ITEM_NONE)
      return false

    if(isFriendWarrior(item) && id != getID() && dist < BLOCK_DIST && abs(yaw) < BLOCK_YAW) {
      blockYaw = yaw
      blockDist = dist
      blockId = id
      return true
    }

    minDist = dist + 0.4
  }

  return false
}

stock bool:isInsideSafe(float:x, float:y, float:mapCx, float:mapCy, float:safeHalf) {
  if(abs(x - mapCx) <= safeHalf && abs(y - mapCy) <= safeHalf)
    return true
  return false
}

stock clampPointInsideSafe(&float:x, &float:y, float:mapCx, float:mapCy, float:safeHalf) {
  x = clampf(x, mapCx - safeHalf, mapCx + safeHalf)
  y = clampf(y, mapCy - safeHalf, mapCy + safeHalf)
}

stock float:getTriangleRadius() {
  new mates = getMates()
  if(mates < 1)
    mates = 1

  new float:r = TRI_BASE_RADIUS + TRI_PER_BOT_RADIUS * float(mates - 1)
  return clampf(r, TRI_MIN_RADIUS, TRI_MAX_RADIUS)
}

stock float:getPairSideSign(idA, idB) {
  if(((idA + idB) % 2) == 0)
    return 1.0
  return -1.0
}

stock getPassChannelFor(botId) {
  if(botId < 0)
    botId = 0
  return PASS_BASE_CHANNEL + botId
}

stock triangleVertices(float:cx, float:cy,
                       float:r,
                       &float:x0, &float:y0,
                       &float:x1, &float:y1,
                       &float:x2, &float:y2) {
  // Triangulo equilatero centrado en (cx,cy), vertice superior en +Y.
  x0 = cx
  y0 = cy + r

  x1 = cx - 0.8660 * r
  y1 = cy - 0.5000 * r

  x2 = cx + 0.8660 * r
  y2 = cy - 0.5000 * r
}

stock fitTriangleInsideMap(&float:cx, &float:cy, &float:r,
                           float:mapCx, float:mapCy, float:safeHalf) {
  for(new i = 0; i < 18; ++i) {
    new float:x0
    new float:y0
    new float:x1
    new float:y1
    new float:x2
    new float:y2
    triangleVertices(cx, cy, r, x0, y0, x1, y1, x2, y2)

    if(isInsideSafe(x0, y0, mapCx, mapCy, safeHalf) &&
       isInsideSafe(x1, y1, mapCx, mapCy, safeHalf) &&
       isInsideSafe(x2, y2, mapCx, mapCy, safeHalf))
      return

    // Si hay vertices fuera, acercar centro al centro del mapa y reducir radio.
    cx = mapCx + (cx - mapCx) * 0.78
    cy = mapCy + (cy - mapCy) * 0.78
    r *= 0.90
    r = clampf(r, TRI_FIT_MIN_RADIUS, TRI_MAX_RADIUS)
  }

  if(r > safeHalf * 0.95)
    r = safeHalf * 0.95
  if(r < TRI_FIT_MIN_RADIUS)
    r = TRI_FIT_MIN_RADIUS

  new float:centerHalf = safeHalf - r
  if(centerHalf < 0.0)
    centerHalf = 0.0
  clampPointInsideSafe(cx, cy, mapCx, mapCy, centerHalf)
}

stock edgePoint(float:ax, float:ay, float:bx, float:by, float:t, &float:ox, &float:oy) {
  ox = ax + (bx - ax) * t
  oy = ay + (by - ay) * t
}

stock assignTriangleTarget(float:cx, float:cy, float:r, &float:tx, &float:ty) {
  // Jefe al centro.
  if(getID() == 0) {
    tx = cx
    ty = cy
    return
  }

  new mates = getMates()
  new others = mates - 1
  if(others <= 0) {
    tx = cx
    ty = cy
    return
  }

  new rank = getID() - 1
  if(rank < 0)
    rank = 0
  if(rank >= others)
    rank = rank % others

  new float:x0
  new float:y0
  new float:x1
  new float:y1
  new float:x2
  new float:y2
  triangleVertices(cx, cy, r, x0, y0, x1, y1, x2, y2)

  // Distribucion uniforme a lo largo del perimetro.
  new float:u = float(rank) / float(others)
  if(u < 0.3333) {
    edgePoint(x0, y0, x1, y1, u * 3.0, tx, ty)
  } else if(u < 0.6666) {
    edgePoint(x1, y1, x2, y2, (u - 0.3333) * 3.0, tx, ty)
  } else {
    edgePoint(x2, y2, x0, y0, (u - 0.6666) * 3.0, tx, ty)
  }
}

formationBot() {
  // Centro real del mapa usado como referencia de limites.
  new float:mapCx
  new float:mapCy
  if(!getArenaCenter(mapCx, mapCy)) {
    mapCx = 0.0
    mapCy = 0.0
  }

  // En algunos mapas el promedio de goals queda sesgado; acercarlo al origen
  // mantiene la formacion mas centrada y lejos de paredes.
  mapCx *= (1.0 - CENTER_PULL_TO_ORIGIN)
  mapCy *= (1.0 - CENTER_PULL_TO_ORIGIN)

  // Centro de formacion (puede ajustarse hacia adentro).
  new float:cx = mapCx
  new float:cy = mapCy

  // Radio inicial y ajuste para garantizar vertices dentro del mapa.
  new float:triR = getTriangleRadius()
  new float:safeHalf = MAP_SAFE_HALF - TRI_BORDER_CLEARANCE
  if(safeHalf < TRI_FIT_MIN_RADIUS + 2.0)
    safeHalf = TRI_FIT_MIN_RADIUS + 2.0
  fitTriangleInsideMap(cx, cy, triR, mapCx, mapCy, safeHalf)

  new float:tx
  new float:ty
  assignTriangleTarget(cx, cy, triR, tx, ty)
  new float:extraMargin = TRI_TARGET_MARGIN
  if(MAP_EDGE_MARGIN > extraMargin)
    extraMargin = MAP_EDGE_MARGIN
  new float:targetSafeHalf = safeHalf - extraMargin
  if(targetSafeHalf < TRI_FIT_MIN_RADIUS + 1.0)
    targetSafeHalf = safeHalf
  clampPointInsideSafe(tx, ty, mapCx, mapCy, targetSafeHalf)

  // Fallback ligero: si un no-lider quedo en el centro, desplazarlo un poco.
  if(getID() != 0 && abs(tx - cx) < 0.05 && abs(ty - cy) < 0.05) {
    switch(getID() % 4) {
      case 0: tx += 1.0
      case 1: tx -= 1.0
      case 2: ty += 1.0
      default: ty -= 1.0
    }
    clampPointInsideSafe(tx, ty, mapCx, mapCy, targetSafeHalf)
  }


  new float:lastCheck = -1000.0
  new float:lastX = cx
  new float:lastY = cy
  new stuckCount = 0
  new float:backoffUntil = -1000.0
  new float:backoffSide = 1.0
  new float:wallEscapeUntil = -1000.0
  new float:wallEscapeRearmUntil = -1000.0
  new float:wallEscapeSide = 1.0
  new wallTrapCount = 0
  new float:lastWallTrapTick = -1000.0
  new float:yieldUntil = -1000.0
  new float:yieldDir = 0.0
  new float:yieldSide = 1.0
  new bool:yieldHardBack = false
  new frontBlockId = -1
  new frontBlockCount = 0
  new float:lastFrontBlockTick = -1000.0
  new float:forceBypassUntil = -1000.0
  new float:forceBypassSide = 1.0
  new float:deadlockBackUntil = -1000.0
  new float:deadlockSideUntil = -1000.0
  new float:deadlockSide = 1.0
  new float:deadlockCooldownUntil = -1000.0
  new float:wallBreakBackUntil = -1000.0
  new float:wallBreakSideUntil = -1000.0
  new float:wallBreakRearmUntil = -1000.0
  new float:wallBreakSide = 1.0
  new myPassChannel = getPassChannelFor(getID())
  new float:lastPassSent = -1000.0
  new lastPassTarget = -1
  new float:lastPassTargetTime = -1000.0
  new float:yieldBackUntil = -1000.0
  new float:yieldGlobalRearmUntil = -1000.0
  new lastYieldSender = -1
  new float:lastYieldRxTime = -1000.0
  new float:blockScanBackUntil = -1000.0
  new float:blockScanRearmUntil = -1000.0
  new float:blockScanSide = 1.0
  new float:noBackUntil = -1000.0
  new bool:arriveLogged = false
  new backoffChainCount = 0
  new float:backoffChainResetUntil = -1000.0
  new float:backMotionStart = -1000.0
  new float:stuckCycleSide = 1.0

  walk()

  for(;;) {
    new float:now = getTime()

    // Fase 2: Avance conjunto luego de formar el triangulo
    if(now >= 30.0) {
        if(sight() < 3.0)
            rotateTo(getDirection() + PI/3.0)
        else
            rotateTo(0.0)

        if(isStanding() || isWalkingbk() || isWalkingcr() || isRunning())
            walk()

        wait(LOOP_DT)
        continue
    }

    // Guard rail: nunca permitir retroceso continuo indefinido.
    if(isWalkingbk()) {
      if(backMotionStart < -999.0)
        backMotionStart = now

      if(now - backMotionStart >= MAX_CONTINUOUS_BACK_TIME) {
        backoffUntil = -1000.0
        blockScanRearmUntil = -1000.0
        yieldBackUntil = -1000.0
        deadlockBackUntil = -1000.0
        wallBreakBackUntil = -1000.0
        wallEscapeUntil = -1000.0
        noBackUntil = now + BACK_PHASE_MIN_GAP
        backoffChainCount = 0
        backoffChainResetUntil = -1000.0
        forceBypassSide = stuckCycleSide
        stuckCycleSide = -stuckCycleSide
        forceBypassUntil = now + BOT_FORCE_BYPASS_TIME + 0.22

        if(isWalkingbk() || isWalking() || isRunning() || isWalkingcr())
          stand()

        if(canIssueWalk())
          walk()

        wait(LOOP_DT)
        continue
      }
    } else {
      backMotionStart = -1000.0
    }

    new float:x
    new float:y
    new float:z
    getLocation(x, y, z)

    new float:dx = tx - x
    new float:dy = ty - y
    new float:err = sqrt(dx*dx + dy*dy)

    // Rehabilita el aviso de llegada si el bot se alejo del objetivo.
    if(err > ARRIVE_RESET_RADIUS)
      arriveLogged = false

    // Reset conservador: salir de walk-back si todas las fases de retroceso ya expiraron.
    if(isWalkingbk() && err > ARRIVE_RADIUS &&
       now >= yieldBackUntil &&
       now >= wallBreakBackUntil &&
       now >= deadlockBackUntil &&
       now >= backoffUntil) {
      walk()
    }

    // Ancla de destino: cerca del objetivo, cancelar maniobras transitorias
    // para evitar caminar en arco alrededor del punto final.
    if(arriveLogged && err <= ARRIVE_RESET_RADIUS) {
      yieldUntil = -1000.0
      yieldBackUntil = -1000.0
      blockScanBackUntil = -1000.0
      blockScanRearmUntil = -1000.0
      backoffUntil = -1000.0
      forceBypassUntil = -1000.0
      deadlockBackUntil = -1000.0
      deadlockSideUntil = -1000.0
      wallBreakBackUntil = -1000.0
      wallBreakSideUntil = -1000.0
      wallEscapeUntil = -1000.0

      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()

      wait(LOOP_DT)
      continue
    }

    if(err <= ARRIVE_RADIUS) {
      if(!arriveLogged) {
        printf("bot %d llego a destino %d,%d^n", getID(), floatround(tx), floatround(ty))
        arriveLogged = true
      }

      backoffChainCount = 0
      yieldUntil = -1000.0
      yieldBackUntil = -1000.0
      blockScanBackUntil = -1000.0
      blockScanRearmUntil = -1000.0
      backoffUntil = -1000.0
      forceBypassUntil = -1000.0
      deadlockBackUntil = -1000.0
      deadlockSideUntil = -1000.0
      wallBreakBackUntil = -1000.0
      wallBreakSideUntil = -1000.0
      wallEscapeUntil = -1000.0

      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()

      wait(LOOP_DT)
      continue
    }

    // Siempre escuchar pedidos de paso, incluso estando quieto en posicion.
    // No rearma while cede para evitar bucle de retroceso.
    new word
    new senderId
    if(now >= yieldUntil && now >= yieldGlobalRearmUntil && listen(myPassChannel, word, senderId)) {
      if(senderId != getID() && (word == WORD_PASS_LEFT || word == WORD_PASS_RIGHT)) {
        if(senderId == lastYieldSender && now - lastYieldRxTime < YIELD_SAME_SENDER_COOLDOWN) {
          // Ignorar spam de un mismo emisor sin bloquear la IA.
        } else {
          yieldSide = (word == WORD_PASS_LEFT ? 1.0 : -1.0)

          yieldDir = getDirection() + PI + yieldSide * BOT_YIELD_ANGLE

          // Si estaba quieto en su posicion, retrocede un poco para abrir paso visible.
          new allowYieldBack = 0
          if(now >= noBackUntil && isStanding())
            allowYieldBack = 1
          yieldHardBack = (allowYieldBack != 0)
          yieldBackUntil = now
          if(yieldHardBack) {
            yieldBackUntil = now + YIELD_BACK_ONLY_TIME
            noBackUntil = yieldBackUntil + BACK_PHASE_MIN_GAP
          }
          yieldUntil = now + BOT_YIELD_TIME + BOT_YIELD_EXTRA_TIME
          yieldGlobalRearmUntil = yieldUntil + YIELD_GLOBAL_REARM_DT
          lastYieldSender = senderId
          lastYieldRxTime = now
        }
      }
    }

    // Si este bot esta cediendo el paso, ejecutar maniobra temporal.
    if(now < yieldUntil) {
      rotateTo(yieldDir)

      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - yieldSide * PI/2.8)

      if(yieldHardBack && now < yieldBackUntil) {
        if(isStanding() || isWalking() || isRunning() || isWalkingcr())
          walkbk()
      } else {
        yieldHardBack = false
        if(canIssueWalk())
          walk()
      }

      wait(LOOP_DT)
      continue
    }

    // Paso lateral breve y aleatorio para romper choques bot-bot.
    if(now < blockScanBackUntil) {
      rotateTo(getDirection() + blockScanSide * PI/2.0)
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - blockScanSide * PI/2.4)

      if(canIssueWalk())
        walk()

      wait(LOOP_DT)
      continue
    }

    // Ruptura fuerte de estancamiento con paredes/borde: retrocede y luego sale lateral.
    if(now < wallBreakBackUntil) {
      rotateTo(getDirection() + wallBreakSide * PI/2.2)
      if(isStanding() || isWalking() || isRunning() || isWalkingcr())
        walkbk()

      wait(LOOP_DT)
      continue
    }

    if(now < wallBreakSideUntil) {
      rotateTo(getDirection() + wallBreakSide * WALL_BREAK_ANGLE)
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - wallBreakSide * PI/2.4)

      if(canIssueWalk())
        walk()

      wait(LOOP_DT)
      continue
    }

    // Ruptura de estancamiento entre bots: atras + lateral y luego vuelve a su objetivo.
    if(now < deadlockBackUntil) {
      rotateTo(getDirection() + deadlockSide * PI/2.4)
      if(isStanding() || isWalking() || isRunning() || isWalkingcr())
        walkbk()

      wait(LOOP_DT)
      continue
    }

    if(now < deadlockSideUntil) {
      rotateTo(getDirection() + deadlockSide * DEADLOCK_SIDE_ANGLE)
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - deadlockSide * PI/2.3)

      if(canIssueWalk())
        walk()

      wait(LOOP_DT)
      continue
    }

    // Escape fuerte de pared para no quedar empujando infinito.
    if(now < wallEscapeUntil) {
      rotateTo(getDirection() + wallEscapeSide * WALL_ESCAPE_ANGLE)

      if(canIssueWalk())
        walk()

      if(sight() < WALL_TRAP_DIST)
        wallEscapeSide = -wallEscapeSide

      wait(LOOP_DT)
      continue
    }

    if(now < backoffUntil) {
      rotateTo(getDirection() + backoffSide * BACKOFF_ANGLE)
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - backoffSide * PI/2.5)

      if(isStanding() || isWalking() || isRunning() || isWalkingcr())
        walkbk()

      wait(LOOP_DT)
      continue
    }

    // Tras retroceder, ejecutar un lateral corto para no volver al mismo choque.
    if(now >= backoffUntil && now < blockScanRearmUntil) {
      rotateTo(getDirection() + backoffSide * PI/2.0)
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - backoffSide * PI/2.4)

      if(canIssueWalk())
        walk()

      wait(LOOP_DT)
      continue
    }

    // Si tengo prioridad y aun asi sigo bloqueado, forzar bypass corto.
    if(now < forceBypassUntil) {
      rotateTo(getDirection() + forceBypassSide * BOT_FORCE_BYPASS_ANGLE)

      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - forceBypassSide * PI/2.6)

      if(canIssueWalk())
        walk()

      wait(LOOP_DT)
      continue
    }

    // Navegacion principal al objetivo.
    new nearFinalApproach = 0
    if(err <= FINAL_APPROACH_RADIUS)
      nearFinalApproach = 1

    new float:toTarget = atan2(dy, dx)
    new float:yawErrToTarget = wrapPi(toTarget - getDirection())
    if(abs(yawErrToTarget) > NAV_TURN_DEADBAND)
      rotateTo(toTarget)

    // Cerca del objetivo: primero alinear rumbo, luego avanzar corto para evitar orbitas.
    if(nearFinalApproach != 0 && abs(yawErrToTarget) > FINAL_ALIGN_YAW) {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()
    } else if(nearFinalApproach != 0) {
      if(canIssueWalk())
        walk()
    } else {
      // Evitar pared solo en navegacion normal (lejos del objetivo).
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() + (random(2) == 0 ? PI/4.0 : -PI/4.0))
    }

    if(sight() < WALL_TRAP_DIST) {
      if(now >= wallEscapeRearmUntil) {
        wallEscapeUntil = now + WALL_ESCAPE_TIME
        wallEscapeSide = (random(2) == 0 ? 1.0 : -1.0)
        wallEscapeRearmUntil = now + WALL_ESCAPE_REARM_DT
      }

      if(now - lastWallTrapTick >= WALL_TRAP_COUNT_DT) {
        ++wallTrapCount
        lastWallTrapTick = now
      }
    } else if(now - lastWallTrapTick >= WALL_TRAP_COUNT_DT && wallTrapCount > 0) {
      --wallTrapCount
      lastWallTrapTick = now
    }

    if(err > ARRIVE_RADIUS && wallTrapCount >= WALL_TRAP_COUNT_MAX) {
      wallEscapeUntil = now + WALL_ESCAPE_TIME
      wallEscapeSide = (random(2) == 0 ? 1.0 : -1.0)
      wallEscapeRearmUntil = now + WALL_ESCAPE_REARM_DT
      wallTrapCount = 0

      wait(LOOP_DT)
      continue
    }

    // Arbitraje anti-bloqueo entre bots: menor ID mantiene prioridad.
    new float:blockYaw
    new float:blockDist
    new blockId
    new bool:hasFrontBlock = getFrontBlockInfo(blockYaw, blockDist, blockId)

    if(hasFrontBlock) {

      if(blockId == frontBlockId && now - lastFrontBlockTick <= BOT_BLOCK_REPEAT_DT)
        ++frontBlockCount
      else
        frontBlockCount = 1

      frontBlockId = blockId
      lastFrontBlockTick = now

      // Solo el bot que efectivamente esta moviendose puede pedir paso.
      if(err > ARRIVE_RADIUS && now - lastPassSent >= getTimeNeededFor(ACTION_SPEAK)) {
        if(blockId >= 0 && blockId != getID()) {
          if(!(blockId == lastPassTarget && now - lastPassTargetTime < PASS_RESEND_SAME_TARGET_DT)) {
            new passWord = (blockYaw > 0.0 ? WORD_PASS_RIGHT : WORD_PASS_LEFT)
            new passChannel = getPassChannelFor(blockId)
            if(speak(passChannel, passWord)) {
              lastPassSent = now
              lastPassTarget = blockId
              lastPassTargetTime = now
            }
          }
        }
      }

      new severeBlock = (frontBlockCount >= BOT_BLOCK_REPEAT_MAX || blockDist < 1.05)

      // Si el bloqueo frontal persiste, forzar secuencia atras+lateral.
      if(severeBlock && now >= deadlockCooldownUntil) {
        new float:pairSide = getPairSideSign(getID(), blockId)
        deadlockSide = (getID() > blockId ? pairSide : -pairSide)
        new float:deadBack = 0.0
        if(now >= noBackUntil)
          deadBack = DEADLOCK_BACK_TIME

        deadlockBackUntil = now + deadBack
        deadlockSideUntil = deadlockBackUntil + DEADLOCK_SIDE_TIME
        deadlockCooldownUntil = deadlockSideUntil + DEADLOCK_COOLDOWN
        noBackUntil = deadlockBackUntil + BACK_PHASE_MIN_GAP
        yieldUntil = -1000.0
        yieldBackUntil = -1000.0
        forceBypassUntil = -1000.0

        wait(LOOP_DT)
        continue
      }

      // El ID mas alto cede para romper deadlocks de frente.
      if(getID() > blockId) {
        yieldSide = getPairSideSign(getID(), blockId)
        yieldDir = getDirection() + yieldSide * BOT_YIELD_ANGLE
        // Evitar bucle de retroceso: ceder por desplazamiento lateral/avance.
        yieldHardBack = false
        yieldUntil = now + BOT_YIELD_TIME
        yieldUntil += BOT_YIELD_EXTRA_TIME

        wait(LOOP_DT)
        continue
      }

      // El ID con prioridad intenta paso lateral; si persiste, bypass temporal.
      if(severeBlock) {
        forceBypassSide = (blockYaw > 0.0 ? -1.0 : 1.0)
        forceBypassUntil = now + BOT_FORCE_BYPASS_TIME
        wait(LOOP_DT)
        continue
      }

      rotateTo(getDirection() + (blockYaw > 0.0 ? -PI/6.0 : PI/6.0))
    } else {
      if(now - lastFrontBlockTick >= BOT_BLOCK_REPEAT_DT && frontBlockCount > 0) {
        --frontBlockCount
        lastFrontBlockTick = now
      }
    }

    if(nearFinalApproach == 0 && canIssueWalk())
      walk()

    // Deteccion de atasco local.
    if(now - lastCheck >= MOVE_CHECK_DT) {
      new float:mx = x - lastX
      new float:my = y - lastY
      new float:moved = sqrt(mx*mx + my*my)
      new float:edgeX = abs(x - mapCx)
      new float:edgeY = abs(y - mapCy)
      new nearEdge = 0
      if(edgeX >= targetSafeHalf - EDGE_NEAR_MARGIN ||
         edgeY >= targetSafeHalf - EDGE_NEAR_MARGIN)
        nearEdge = 1

      new stalled = 0
      if(err > ARRIVE_RADIUS) {
        if(isStanding() || moved < MOVE_EPS)
          stalled = 1
      }

      if(stalled != 0)
        ++stuckCount
      else if(stuckCount > 0)
        --stuckCount

      if(stalled == 0)
        backoffChainCount = 0

      new wallClose = 0
      if(sight() < WALL_TRAP_DIST)
        wallClose = 1
      new wallTrapPersistent = 0
      if(wallClose != 0 && stuckCount >= 2)
        wallTrapPersistent = 1

      // Si esta cerca de borde y no progresa, ejecutar ruptura fuerte de pared.
      if(err > ARRIVE_RADIUS &&
         now >= wallBreakRearmUntil &&
         ((nearEdge != 0 && (stalled != 0 || wallClose != 0)) || wallTrapPersistent != 0)) {
        if(abs(x - mapCx) >= abs(y - mapCy))
          wallBreakSide = (x >= mapCx ? -1.0 : 1.0)
        else
          wallBreakSide = (y >= mapCy ? -1.0 : 1.0)

        if(random(2) == 0)
          wallBreakSide = -wallBreakSide

        new float:wallBack = 0.0
        if(now >= noBackUntil)
          wallBack = WALL_BREAK_BACK_TIME

        wallBreakBackUntil = now + wallBack
        wallBreakSideUntil = wallBreakBackUntil + WALL_BREAK_SIDE_TIME
        wallBreakRearmUntil = wallBreakSideUntil + WALL_BREAK_REARM_DT
        noBackUntil = wallBreakBackUntil + BACK_PHASE_MIN_GAP
        wallEscapeUntil = -1000.0
        backoffUntil = -1000.0
        blockScanRearmUntil = -1000.0
        wallTrapCount = 0
        stuckCount = 0

        lastX = x
        lastY = y
        lastCheck = now

        wait(LOOP_DT)
        continue
      }

      lastX = x
      lastY = y
      lastCheck = now
    }

    if(stuckCount >= STUCK_MAX) {
      if(now > backoffChainResetUntil)
        backoffChainCount = 0

      ++backoffChainCount
      backoffChainResetUntil = now + 2.0

      // Patrón simple y cíclico: luego del retroceso lateraliza derecha, luego izquierda.
      new float:cycleSide = stuckCycleSide
      stuckCycleSide = -stuckCycleSide

      // Si encadena varios retrocesos, forzar salida por bypass adelante/lateral.
      if(backoffChainCount >= 3) {
        forceBypassSide = cycleSide
        forceBypassUntil = now + BOT_FORCE_BYPASS_TIME + 0.20
        noBackUntil = now + BACK_PHASE_MIN_GAP
        backoffUntil = -1000.0
        blockScanRearmUntil = -1000.0
        backoffChainCount = 0
      } else {
        // Si no se permite retroceso por cooldown, usar bypass y no rearmar backoff.
        if(now >= noBackUntil) {
          // ~1.5s+ inmovil -> retroceso corto para destrabar y reintentar ruta.
          backoffUntil = now + BACKOFF_TIME + 0.10
          blockScanRearmUntil = backoffUntil + BLOCK_SCAN_BACK_TIME
          backoffSide = cycleSide
        } else {
          forceBypassSide = cycleSide
          forceBypassUntil = now + BOT_FORCE_BYPASS_TIME
          backoffUntil = -1000.0
          blockScanRearmUntil = -1000.0
        }
      }

      stuckCount = 0
    }

    new touched = getTouched()
    if(touched)
      raise(touched)

    wait(LOOP_DT)
  }
}

fight() {
  formationBot()
}

main() {
  switch(getPlay()) {
    case PLAY_FIGHT: fight()
    case PLAY_SOCCER: fight()
    case PLAY_RACE: fight()
  }
}
