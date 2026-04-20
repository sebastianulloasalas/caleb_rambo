// paso_simple.sma - ACTUAL
//
// Objetivo de este bot demo:
// 1) Un solo bot (ID 0) va de punto A a punto B y vuelve.
// 2) Si se bloquea con otro bot, pide paso por radio.
// 3) Los otros bots se apartan temporalmente y luego regresan a su sitio.
// 4) Si el bot activo se atasca, fuerza una salida diagonal.

#include "core"
#include "math"
#include "bots"

// Bot que hace el recorrido A <-> B.
new const RUNNER_ID = 0

// Canal y palabras para protocolo de "dar paso".
new const PASS_BASE_CHANNEL = 40
new const WORD_PASS_LEFT = 7001
new const WORD_PASS_RIGHT = 7002

// Constantes matematicas basicas.
new const float:PI = 3.1415
new const float:TWO_PI = 6.2830

// Distancias y angulos de movimiento.
new const float:ARRIVE_RADIUS = 1.0
new const float:ARRIVE_RADIUS_HOME = 0.70
new const float:ARRIVE_RESET_RADIUS = 2.20
new const float:WALL_AVOID_DIST = 2.2
new const float:BLOCK_DIST = 2.5
new const float:BLOCK_YAW = 0.785
new const float:BLOCK_YAW_125 = 1.09
new const float:BLOCK_YAW_180 = 1.57
new const float:BLOCK_ESCALATE_125_DT = 0.70
new const float:BLOCK_ESCALATE_180_DT = 1.35
new const float:RUNNER_HEAD_SWEEP = 0.70
new const float:RUNNER_SCAN_DT = 0.45
new const float:RUNNER_SCAN_FREEZE_DT = 0.00
new const float:RUNNER_BLOCK_GRACE_DT = 0.10
new const float:RUNNER_BLOCK_PERSIST_DT = 1.40
new const float:RUNNER_SPACE_BACKOFF_DT = 0.45
new const float:RUNNER_SPACE_BACKOFF_ANGLE = 0.70
new const RUNNER_USE_ABS_TARGET = 1
new const float:RUNNER_TARGET_ABS_X = 24.0
new const float:RUNNER_TARGET_ABS_Y = -24.0
new const float:RUNNER_MIN_ROUTE_DIST = 14.0
new const RUNNER_REPEAT_CYCLE = 0

// Parametros de ceder paso (solo bot objetivo).
new const float:PASS_STEP_TIME = 1.80
new const float:PASS_HOLD_TIME = 0.12
new const float:PASS_SIDE_ANGLE = 1.05
new const float:PASS_BACK_BIAS = 0.35
new const float:PASS_TRIGGER_DIST = 3.2
new const float:PASS_FRONT_YAW = 0.85
new const float:PASS_RESEND_SAME_TARGET_DT = 1.20
new const float:YIELD_TASK_MAX_DT = 5.00
new const float:YIELD_STUCK_CHECK_DT = 0.25
new const float:YIELD_MIN_MOVE = 0.18
new const float:YIELD_AWAY_RADIUS = 1.25
new const float:YIELD_MIN_TASK_TIME = 0.90
new const float:YIELD_RETRY_STEP_DT = 0.65
new const float:YIELD_BOOST_ANGLE = 0.80
new const float:YIELD_BACK_MODE_ERR = 1.20

// Distancia para considerar que el bot regreso a su base.
new const float:HOME_RADIUS = 0.90

// Deteccion de atasco (no progreso real hacia el objetivo).
new const float:STUCK_CHECK_DT = 0.45
new const float:STUCK_ERR_EPS = 0.08
new const float:STUCK_MOVE_EPS = 0.07
new const STUCK_MAX = 2

// Escape diagonal cuando hay choque o atasco.
new const float:DIAG_ESCAPE_TIME = 0.65
new const float:DIAG_ESCAPE_ANGLE = 0.95

// Periodo principal de actualizacion (mas rapido = info mas fresca).
new const float:LOOP_DT = 0.04

// Control de cooldown para speak().
new float:lastSpeakTime = -1000.0
new lastPassTarget = -1
new float:lastPassTargetTime = -1000.0

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

// Rota al angulo absoluto pedido usando el delta minimo.
stock rotateTo(float:absAngle) {
  new float:cur = getDirection()
  rotate(cur + wrapPi(absAngle - cur))
}

// Estima centro del mapa promediando goals.
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

// Detecta si hay un companero bloqueando justo al frente.
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

  // watch() no siempre devuelve el mas cercano: escanea todos los candidatos visibles.
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

// Canal privado para enviar orden de paso a un bot especifico.
stock getPassChannelFor(botId) {
  if(botId < 0)
    botId = 0
  return PASS_BASE_CHANNEL + botId
}

// Busca un bot amigo concreto por ID y devuelve distancia/yaw relativo.
stock bool:watchFriendById(targetId, &float:dist, &float:yaw) {
  new item
  new float:pitch
  new id
  new float:minDist = 0.0

  for(new tries = 0; tries < 6; ++tries) {
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

// Bot activo: va de A a B, pide paso si se bloquea y usa diagonal si se atasca.
runner() {
  // Punto A = posicion inicial del bot activo.
  new float:ax
  new float:ay
  new float:az
  getLocation(ax, ay, az)

  // Punto B = centro estimado del mapa (fallback si no existe).
  new float:bx
  new float:by
  new bool:haveB = getArenaCenter(bx, by)
  if(RUNNER_USE_ABS_TARGET) {
    // Destino absoluto configurable (coordenadas del mapa).
    bx = RUNNER_TARGET_ABS_X
    by = RUNNER_TARGET_ABS_Y

    // Si cae demasiado cerca del origen, prueba opuesto y luego fallback.
    new float:dAbs = sqrt((bx-ax)*(bx-ax) + (by-ay)*(by-ay))
    if(dAbs < RUNNER_MIN_ROUTE_DIST) {
      bx = -RUNNER_TARGET_ABS_X
      by = -RUNNER_TARGET_ABS_Y
      dAbs = sqrt((bx-ax)*(bx-ax) + (by-ay)*(by-ay))
      if(dAbs < RUNNER_MIN_ROUTE_DIST) {
        bx = ax + RUNNER_MIN_ROUTE_DIST
        by = ay
      }
    }
  } else {
    if(!haveB) {
      bx = ax + 12.0
      by = ay
    }

    // Evita que centro y origen queden demasiado cerca.
    new float:dCenter = sqrt((bx-ax)*(bx-ax) + (by-ay)*(by-ay))
    if(dCenter < RUNNER_MIN_ROUTE_DIST) {
      bx = ax + RUNNER_MIN_ROUTE_DIST
      by = ay
    }
  }

  // Estado de ruta: origen -> centro -> origen (ciclico).
  new const RUN_TO_CENTER = 0
  new const RUN_TO_HOME = 1
  new runState = RUN_TO_CENTER

  // Variables de atasco.
  new float:lastErrCheckTime = -1000.0
  new float:lastErr = 999999.0
  new stuckCount = 0
  new float:lastPosX = ax
  new float:lastPosY = ay
  new float:diagUntil = -1000.0
  new float:diagSide = 1.0
  new float:scanHead = RUNNER_HEAD_SWEEP
  new float:lastScanTime = -1000.0
  new float:scanFreezeUntil = -1000.0
  new float:blockGraceUntil = -1000.0
  new lastBlockedId = -1
  new float:blockedSince = -1000.0
  new float:spaceUntil = -1000.0
  new float:spaceSide = 1.0
  new float:stuckSince = -1000.0
  new lastConeStage = -1
  new arriveLatched = 0
  new bool:runnerDone = false

  walk()
  printf("RUNNER-ID-%d EVENTO-INICIO HACIA-CENTRO^n", getID())

  for(;;) {
    new float:now = getTime()

    // Modo prueba de una sola vuelta: al terminar, se queda quieto en origen.
    if(runnerDone) {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()

      wait(LOOP_DT)
      continue
    }

    // Barrido de cabeza para cubrir 90 grados frontales con watch().
    if(!isHeadRotating() && now - lastScanTime >= RUNNER_SCAN_DT) {
      rotateHead(scanHead)
      scanHead = -scanHead
      lastScanTime = now
      scanFreezeUntil = now + RUNNER_SCAN_FREEZE_DT
    }

    // Pausa corta para estabilidad de escaneo (evita congelar al runner).
    if(now < scanFreezeUntil) {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()

      wait(LOOP_DT)
      continue
    }

    // Objetivo actual (A o B).
    new float:tx = (runState == RUN_TO_CENTER ? bx : ax)
    new float:ty = (runState == RUN_TO_CENTER ? by : ay)

    // Error al objetivo.
    new float:x
    new float:y
    new float:z
    getLocation(x, y, z)

    new float:dx = tx - x
    new float:dy = ty - y
    new float:err = sqrt(dx*dx + dy*dy)

    // Si esta en modo escape diagonal, prioriza salir del atasco.
    if(now < diagUntil) {
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() - diagSide * PI/4.0)

      if(isStanding())
        walk()

      wait(LOOP_DT)
      continue
    }

    // Si lleva tiempo bloqueado con el mismo bot, retrocede para abrir espacio.
    if(now < spaceUntil) {
      rotateTo(getDirection() + spaceSide * RUNNER_SPACE_BACKOFF_ANGLE)
      if(isStanding() || isWalking() || isRunning() || isWalkingcr())
        walkbk()

      wait(LOOP_DT)
      continue
    }

    // Bloqueo detectado recientemente: pausar un instante para dejar ceder al mate.
    if(now < blockGraceUntil) {
      if(isStanding())
        walk()

      wait(LOOP_DT)
      continue
    }

    // Eventos de llegada con histéresis para evitar spam por rebote.
    new float:arriveRadius = (runState == RUN_TO_HOME ? ARRIVE_RADIUS_HOME : ARRIVE_RADIUS)
    if(err <= arriveRadius) {
      if(!arriveLatched) {
        if(runState == RUN_TO_CENTER) {
          runState = RUN_TO_HOME
          printf("RUNNER-ID-%d EVENTO-LLEGO-CENTRO REGRESA-ORIGEN^n", getID())
        } else {
          if(RUNNER_REPEAT_CYCLE) {
            runState = RUN_TO_CENTER
            printf("RUNNER-ID-%d EVENTO-LLEGO-ORIGEN HACIA-CENTRO^n", getID())
          } else {
            runnerDone = true
            printf("RUNNER-ID-%d EVENTO-FIN-PRUEBA EN-ORIGEN^n", getID())
          }
        }

        arriveLatched = 1
        // Al cambiar tramo, limpia estado de atasco.
        stuckSince = -1000.0
        stuckCount = 0
        blockGraceUntil = now + RUNNER_BLOCK_GRACE_DT

        wait(LOOP_DT)
        continue
      }
    } else if(err >= ARRIVE_RESET_RADIUS) {
      arriveLatched = 0
    }

    // Si hay bloqueo frontal, pide paso y corrige rumbo.
    new float:blockYaw
    new float:blockDist
    new blockId
    new bool:doDiag = false
    new blockedNow = 0

    // Escalado de cono: 90 -> 125 -> 180 segun tiempo atascado.
    new float:blockYawNow = BLOCK_YAW
    new coneStage = 0
    if(stuckSince > -900.0) {
      new float:stuckDt = now - stuckSince
      if(stuckDt >= BLOCK_ESCALATE_180_DT) {
        blockYawNow = BLOCK_YAW_180
        coneStage = 2
      } else if(stuckDt >= BLOCK_ESCALATE_125_DT) {
        blockYawNow = BLOCK_YAW_125
        coneStage = 1
      }
    }

    if(coneStage != lastConeStage) {
      if(coneStage == 0)
        printf("RUNNER-CONE-90^n")
      else if(coneStage == 1)
        printf("RUNNER-CONE-125^n")
      else
        printf("RUNNER-CONE-180^n")
      lastConeStage = coneStage
    }

    if(getBlockingFriend(blockYaw, blockDist, blockId, blockYawNow)) {
      blockedNow = 1
      rotateTo(getDirection() + (blockYaw > 0.0 ? -PI/5.0 : PI/5.0))
      diagSide = (blockYaw > 0.0 ? -1.0 : 1.0)

      if(blockId == lastBlockedId) {
        if(blockedSince < -900.0)
          blockedSince = now
        else if(now - blockedSince >= RUNNER_BLOCK_PERSIST_DT) {
          spaceUntil = now + RUNNER_SPACE_BACKOFF_DT
          spaceSide = (blockYaw > 0.0 ? -1.0 : 1.0)
          blockedSince = now
          printf("RUNNER-ID-%d BACKOFF-SPACE TO-%d^n", getID(), blockId)
        }
      } else {
        lastBlockedId = blockId
        blockedSince = now
      }

      if(now - lastSpeakTime >= getTimeNeededFor(ACTION_SPEAK)) {
        new passWord = (blockYaw > 0.0 ? WORD_PASS_RIGHT : WORD_PASS_LEFT)
        if(blockId >= 0 && blockId != getID()) {
          if(blockId == lastPassTarget && now - lastPassTargetTime < PASS_RESEND_SAME_TARGET_DT) {
            // Evita reiniciar al mismo yielder por spam de mensajes.
          } else {
            new passChannel = getPassChannelFor(blockId)
            new bool:txOk = speak(passChannel, passWord)
            printf("TX-RUNNER-%d TO-%d CH-%d WORD-%d OK-%d^n", getID(), blockId, passChannel, passWord, txOk)
            lastSpeakTime = now
            if(txOk) {
              lastPassTarget = blockId
              lastPassTargetTime = now
            }
          }
        }
      }

      // Dar una ventana corta para que el yielder se aparte.
      blockGraceUntil = now + RUNNER_BLOCK_GRACE_DT
    } else {
      lastBlockedId = -1
      blockedSince = -1000.0

      // Ruta normal: directo al objetivo.
      rotateTo(atan2(dy, dx))
    }

    // Si esta muy cerca de pared, corrige fuerte.
    if(sight() < WALL_AVOID_DIST)
      rotateTo(getDirection() + (random(2) == 0 ? PI/4.0 : -PI/4.0))

    // Deteccion de atasco por falta de progreso.
    if(now - lastErrCheckTime >= STUCK_CHECK_DT) {
      new float:movedDx = x - lastPosX
      new float:movedDy = y - lastPosY
      new float:moved = sqrt(movedDx*movedDx + movedDy*movedDy)
      new isMovingNow = (isWalking() || isRunning() || isWalkingbk() || isWalkingcr())

      if(blockedNow) {
        // No contar atasco mientras estamos gestionando un bloqueo visible.
        stuckSince = -1000.0
        stuckCount = 0
      } else {
        if(err > ARRIVE_RADIUS && isMovingNow && moved < STUCK_MOVE_EPS) {
          if(stuckSince < -900.0)
            stuckSince = now
        } else {
          stuckSince = -1000.0
        }

        if(err > ARRIVE_RADIUS && isMovingNow &&
           (lastErr < 900000.0 && abs(lastErr - err) < STUCK_ERR_EPS) &&
           moved < STUCK_MOVE_EPS)
          ++stuckCount
        else
          stuckCount = 0
      }

      lastErr = err
      lastPosX = x
      lastPosY = y
      lastErrCheckTime = now
    }

    // Salida diagonal forzada si hay atasco repetido.
    if(stuckCount >= STUCK_MAX) {
      doDiag = true
      diagSide = (random(2) == 0 ? 1.0 : -1.0)
      stuckCount = 0
    }

    if(doDiag) {
      diagUntil = now + DIAG_ESCAPE_TIME
      rotateTo(getDirection() + diagSide * DIAG_ESCAPE_ANGLE)
      if(isStanding())
        walk()

      wait(LOOP_DT)
      continue
    }

    // Mantener movimiento.
    if(isStanding())
      walk()

    // Levantar objetos tocados para no trabarse encima.
    new touched = getTouched()
    if(touched)
      raise(touched)

    wait(LOOP_DT)
  }
}

// Bots de apoyo: dan paso cuando escuchan orden y luego vuelven a su posicion base.
yielder() {
  // Posicion base para volver luego de ceder paso.
  new float:homeX
  new float:homeY
  new float:homeZ
  getLocation(homeX, homeY, homeZ)

  // Ventanas de cesion temporal.
  new float:yieldStepUntil = -1000.0
  new float:yieldHoldUntil = -1000.0
  new float:yieldSide = (getID()%2 == 0 ? 1.0 : -1.0)
  new float:yieldDir = 0.0
  new bool:hasYieldDir = false
  new float:yieldStartX = homeX
  new float:yieldStartY = homeY
  new float:yieldCheckTime = -1000.0
  new yieldBoostCount = 0
  new bool:yieldBusy = false
  new float:yieldTaskDeadline = -1000.0
  new float:yieldTaskStart = -1000.0
  new bool:yieldMovedAway = false
  new float:lastRetryLog = -1000.0

  // Estrategia 3: canal privado por ID.
  new myPassChannel = getPassChannelFor(getID())
  printf("YIELDER-INICIO ID-%d CH-%d^n", getID(), myPassChannel)

  for(;;) {
    new float:now = getTime()

    // Seguridad: si una tarea tarda demasiado, reabrir escucha.
    if(yieldBusy && now > yieldTaskDeadline) {
      yieldBusy = false
      hasYieldDir = false
      yieldStepUntil = -1000.0
      yieldHoldUntil = -1000.0
      yieldMovedAway = false
      printf("RX-ID-%d TAREA-TIMEOUT REABRE-ESCUCHA^n", getID())
    }

    // Escucha SOLO su canal privado cuando NO esta ocupado.
    new word
    new id
    if(!yieldBusy && listen(myPassChannel, word, id)) {
      if(id == RUNNER_ID && (word == WORD_PASS_LEFT || word == WORD_PASS_RIGHT)) {
        printf("RX-ID-%d RECIBIDO-RUNNER-%d CH-%d WORD-%d^n", getID(), id, myPassChannel, word)

        // Estrategia 4: filtro visual + proximidad + frente.
        new float:rDist
        new float:rYaw
        new bool:okWatch = watchFriendById(RUNNER_ID, rDist, rYaw)

        // Si llega mensaje privado del runner, calcula escape opuesto (180 grados).
        yieldSide = (word == WORD_PASS_LEFT ? 1.0 : -1.0)
        if(okWatch) {
          new float:runnerAbs = getDirection() + getTorsoYaw() + getHeadYaw() + rYaw
          yieldDir = runnerAbs + PI + yieldSide * PASS_BACK_BIAS
          hasYieldDir = true
        } else {
          // Fallback si no se logra ver al runner: alejarse hacia atras.
          yieldDir = getDirection() + PI + yieldSide * 0.90
          hasYieldDir = true
        }

        yieldStepUntil = now + PASS_STEP_TIME
        yieldHoldUntil = yieldStepUntil + PASS_HOLD_TIME

        // Referencia para detectar "gira pero no avanza".
        getLocation(yieldStartX, yieldStartY)
        yieldCheckTime = now + YIELD_STUCK_CHECK_DT
        yieldBoostCount = 0

        // Desde aqui queda ocupado hasta que vuelva a home tras haberse alejado.
        yieldBusy = true
        yieldTaskStart = now
        yieldMovedAway = false
        yieldTaskDeadline = now + PASS_STEP_TIME + PASS_HOLD_TIME + YIELD_TASK_MAX_DT

        if(okWatch && rDist < PASS_TRIGGER_DIST && abs(rYaw) < PASS_FRONT_YAW) {
          printf("RX-ID-%d FILTRO-OK CEDIENDO-180^n", getID())
        } else {
          printf("RX-ID-%d FILTRO-NO-OK CEDIENDO-FALLBACK^n", getID())
        }
      }
    }

    // Fase 1: apartarse lateralmente.
    if(now < yieldStepUntil) {
      if(hasYieldDir) {
        new float:dirErr = wrapPi(yieldDir - getDirection())
        rotateTo(yieldDir)

        // Si la desalineacion es grande, retrocede mientras gira.
        if(abs(dirErr) > YIELD_BACK_MODE_ERR) {
          if(isStanding() || isWalking() || isRunning() || isWalkingcr())
            walkbk()
        } else {
          if(isStanding() || isWalking() || isWalkingbk() || isWalkingcr()) {
            if(!run())
              walk()
          }
        }
      } else {
        rotateTo(getDirection() + yieldSide * PASS_SIDE_ANGLE)
        if(isStanding() || isWalking() || isWalkingbk() || isWalkingcr()) {
          if(!run())
            walk()
        }
      }

      if(sight() < WALL_AVOID_DIST)
        yieldDir = getDirection() - yieldSide * PI/2.2

      // Si no se desplaza en la fase de cesion, forzar empuje de salida.
      if(now >= yieldCheckTime) {
        new float:cx
        new float:cy
        new float:cz
        getLocation(cx, cy, cz)

        new float:mdx = cx - yieldStartX
        new float:mdy = cy - yieldStartY
        new float:moved = sqrt(mdx*mdx + mdy*mdy)
        new float:dFromHomeNow = sqrt((cx-homeX)*(cx-homeX) + (cy-homeY)*(cy-homeY))

        if(dFromHomeNow > YIELD_AWAY_RADIUS)
          yieldMovedAway = true

        if(moved < YIELD_MIN_MOVE) {
          ++yieldBoostCount
          new float:boostSign = (yieldBoostCount%2 == 0 ? -1.0 : 1.0)
          yieldDir = getDirection() + boostSign * yieldSide * (YIELD_BOOST_ANGLE + 0.15*float(yieldBoostCount%3))
          rotateTo(yieldDir)

          new float:dirErrBoost = abs(wrapPi(yieldDir - getDirection()))
          if(dirErrBoost > YIELD_BACK_MODE_ERR) {
            if(isStanding() || isWalking() || isRunning() || isWalkingcr())
              walkbk()
          } else if(!isRunning()) {
            run()
          }

          printf("RX-ID-%d BOOST-MOVE-%d^n", getID(), yieldBoostCount)
        }

        // Repetir chequeo durante la cesion hasta que realmente se desplace.
        yieldStartX = cx
        yieldStartY = cy
        yieldCheckTime = now + YIELD_STUCK_CHECK_DT
      }

      wait(LOOP_DT)
      continue
    }

    // Fase 2: quedarse quieto para dejar pasar.
    if(now < yieldHoldUntil) {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()

      wait(LOOP_DT)
      continue
    }

    // Termino la cesion: limpiar direccion de escape.
    hasYieldDir = false

    // Fase 3: regresar a posicion base.
    new float:x
    new float:y
    new float:z
    getLocation(x, y, z)

    new float:dx = homeX - x
    new float:dy = homeY - y
    new float:dHome = sqrt(dx*dx + dy*dy)

    if(dHome > HOME_RADIUS) {
      if(dHome > YIELD_AWAY_RADIUS)
        yieldMovedAway = true

      rotateTo(atan2(dy, dx))
      if(sight() < WALL_AVOID_DIST)
        rotateTo(getDirection() + (getID()%2 == 0 ? PI/4.0 : -PI/4.0))

      if(isStanding())
        walk()
    } else {
      if(isWalking() || isRunning() || isWalkingbk() || isWalkingcr())
        stand()

      if(yieldBusy) {
        if(yieldMovedAway && now - yieldTaskStart >= YIELD_MIN_TASK_TIME) {
          yieldBusy = false
          yieldMovedAway = false
          printf("RX-ID-%d TAREA-COMPLETA ESCUCHA-OK^n", getID())
        } else {
          // Si aun no logro una salida real, reintentar alejamiento sin reabrir escucha.
          hasYieldDir = true
          yieldDir = getDirection() + yieldSide * PASS_SIDE_ANGLE
          yieldStepUntil = now + YIELD_RETRY_STEP_DT
          yieldHoldUntil = -1000.0
          yieldCheckTime = now + YIELD_STUCK_CHECK_DT
          if(now - lastRetryLog > 0.8) {
            printf("RX-ID-%d REINTENTA-SALIDA^n", getID())
            lastRetryLog = now
          }
        }
      }
    }

    new touched = getTouched()
    if(touched)
      raise(touched)

    wait(LOOP_DT)
  }
}

fight() {
  if(getID() == RUNNER_ID)
    runner()
  else
    yielder()
}

main() {
  switch(getPlay()) {
    case PLAY_FIGHT: fight()
    case PLAY_SOCCER: fight()
    case PLAY_RACE: fight()
  }
}
