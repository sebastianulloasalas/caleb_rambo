// master_platoon.sma — Integración Caleb (Exploración) + Rambo (Asalto)
// Descripción: 
// 1 Caleb explora el mapa de forma autónoma usando DFS.
// N Rambos patrullan pasivamente hasta que Caleb emite contacto enemigo vía IPC.
// Contrato estricto IPC de reemplazos dinámicos en caso de muerte de Caleb o Rambo.

#include "core"
#include "math"
#include "bots"
#include "ipc_contract"

// =============================================================================
// CONSTANTES GLOBALES (Macros enteras seguras)
// =============================================================================

#define GRID_W              14
#define GRID_TOTAL          196
#define DFS_STACK_SIZE      64
#define VISITED_CELLS       7 
#define ENEMY_WARRIOR       (ITEM_ENEMY | ITEM_WARRIOR)
#define ANY_WARRIOR         (ITEM_WARRIOR | ITEM_FRIEND | ITEM_ENEMY)
#define MSG_STUCK           911 

// =============================================================================
// CONSTANTES FLOTANTES GLOBALES (Protección estricta contra Warning 213)
// =============================================================================

new float:PI_F                  = 3.1415
new float:TWO_PI_F              = 6.2830
new float:PI_OVER_TWO_F         = 1.5707
new float:PI_OVER_TEN_F         = 0.3141

new float:CELL_SIZE_F           = 10.0
new float:MAP_OFFSET_F          = 65.0
new float:ARRIVE_SQ_F           = 9.0
new float:WALL_DIST_F           = 4.0
new float:STUCK_TIME_LIMIT_F    = 3.0
new float:REPORT_INTERVAL_F     = 1.0
new float:SAFE_ENEMY_DISTANCE_F = 25.0
new float:FLEE_DISTANCE_F       = 10.0
new float:ENEMY_DATA_TTL_F      = 3.0
new float:SCAN_HEAD_LIMIT_F     = 1.047
new float:EPS_F                 = 0.00001
new float:TURN_TOLERANCE_F      = 0.35
new float:FRONT_TOLERANCE_F     = 0.5
new float:ENERGY_RUN_F          = 20.0
new float:DIST_TWO_F            = 2.0

new float:PATROL_DIR_CHANGE_F   = 15.0
new float:WALL_AVOID_DIST_F     = 5.0
new float:ASSAULT_LOOP_WAIT_F   = 0.05
new float:STANDBY_LOOP_WAIT_F   = 0.1
new float:GRENADE_MIN_F         = 30.0
new float:GRENADE_MAX_F         = 60.0
new float:HEALTH_LOW_F          = 25.0
new float:YAW_UNSCALE_F         = 1000.0
new float:YAW_SCALE_F           = 1000.0
new float:IPC_POLL_WAIT_F       = 0.1
new float:WAIT_HALF_F           = 0.5
new float:WAIT_SHORT_F          = 0.3

// =============================================================================
// MEMORIA LOCAL DE CALEB (DFS)
// =============================================================================

new g_visited[VISITED_CELLS]
new g_dfsStack[DFS_STACK_SIZE]
new g_dfsStackTop = 0
new bool:g_dfsExhausted = false

new float:g_targetX = 0.0, float:g_targetY = 0.0
new bool:g_hasTarget = false
new float:g_myX = 0.0, float:g_myY = 0.0, float:g_myZ = 0.0

new float:g_stuckLastX = 0.0, float:g_stuckLastY = 0.0, float:g_stuckTime = 0.0
new bool:g_enemyKnown = false
new float:g_enemyYawRel = 0.0, float:g_enemyDist = 0.0, float:g_enemySeenAt = -999.0

new bool:g_ipcEnemyPending = false
new g_ipcEnemyStep = 0, g_ipcEnemyYawEncoded = 0, g_ipcEnemyDistEncoded = 0
new float:g_lastReportTime = 0.0
new bool:g_calebKiaReported = false
new float:g_headScanDir = 0.0

// =============================================================================
// MEMORIA LOCAL DE RAMBOS (Combate)
// =============================================================================

new g_ramboID = RAMBO_INITIAL_ID
new float:g_lastEnemyYaw = 0.0
new float:g_lastEnemyDist = 0.0
new bool:g_enemyContactActive = false
new bool:g_calebKIA = false

// =============================================================================
// UTILIDADES COMPARTIDAS (Matemática y Grilla)
// =============================================================================

stock worldToCell(float:wx, float:wy, &col, &row) {
  col = floatround((wx + MAP_OFFSET_F) / CELL_SIZE_F, floatround_floor)
  row = floatround((wy + MAP_OFFSET_F) / CELL_SIZE_F, floatround_floor)
  col = clamp(col, 0, GRID_W - 1)
  row = clamp(row, 0, GRID_W - 1)
}

stock cellToWorld(col, row, &float:wx, &float:wy) {
  wx = float(col) * CELL_SIZE_F + CELL_SIZE_F * 0.5 - MAP_OFFSET_F
  wy = float(row) * CELL_SIZE_F + CELL_SIZE_F * 0.5 - MAP_OFFSET_F
}

stock cellIndex(col, row) { return row * GRID_W + col; }

stock float:wrapPi(float:angle) {
  while (angle > PI_F) angle -= TWO_PI_F
  while (angle < -PI_F) angle += TWO_PI_F
  return angle
}

stock float:calcAngle2D(float:y, float:x) {
  if(abs(x) < EPS_F) {
    if(y > 0.0) return PI_OVER_TWO_F
    if(y < 0.0) return -PI_OVER_TWO_F
    return 0.0
  }
  new float:a = atan(y / x)
  if(x < 0.0) {
    if(y >= 0.0) a += PI_F
    else         a -= PI_F
  }
  return a
}

stock refreshPosition() { getLocation(g_myX, g_myY, g_myZ); }
stock collectPowerup() { new touched = getTouched(); if(touched) raise(touched); }

// =============================================================================
// MÓDULO 1: CALEB (Exploración Autónoma)
// =============================================================================

stock bool:isVisited(idx) {
  if(idx < 0 || idx >= GRID_TOTAL) return true
  return bool:((g_visited[idx / 32] >> (idx % 32)) & 1)
}

stock markVisited(idx) {
  if(idx < 0 || idx >= GRID_TOTAL) return
  g_visited[idx / 32] |= (1 << (idx % 32))
}

stock dfsPush(idx) {
  if(g_dfsStackTop >= DFS_STACK_SIZE || isVisited(idx)) return
  markVisited(idx)
  g_dfsStack[g_dfsStackTop++] = idx
}

stock dfsPop() {
  if(g_dfsStackTop <= 0) return -1
  return g_dfsStack[--g_dfsStackTop]
}

stock dfsPushNeighbors(col, row) {
  new dirs[4], count = 0
  if(row > 0)          dirs[count++] = cellIndex(col,   row-1)
  if(col > 0)          dirs[count++] = cellIndex(col-1, row)
  if(row < GRID_W-1)   dirs[count++] = cellIndex(col,   row+1)
  if(col < GRID_W-1)   dirs[count++] = cellIndex(col+1, row)

  for(new i = 0; i < count; i++) {
    new r = random(count)
    new temp = dirs[i]
    dirs[i] = dirs[r]
    dirs[r] = temp
  }
  for(new i = 0; i < count; i++) dfsPush(dirs[i])
}

stock dfsAdvance() {
  new nextIdx = -1
  while(g_dfsStackTop > 0) {
    nextIdx = dfsPop()
    if(nextIdx >= 0) break
  }
  if(nextIdx < 0) {
    g_dfsExhausted = true
    g_hasTarget    = false
    return
  }
  new col = nextIdx % GRID_W
  new row = nextIdx / GRID_W
  cellToWorld(col, row, g_targetX, g_targetY)
  g_hasTarget = true
  g_stuckTime = getTime()
}

stock dfsInit() {
  new startCol, startRow
  worldToCell(g_myX, g_myY, startCol, startRow)
  markVisited(cellIndex(startCol, startRow))
  dfsPushNeighbors(startCol, startRow)
  dfsAdvance()
}

stock bool:arrivedAtTarget() {
  new float:dx = g_targetX - g_myX
  new float:dy = g_targetY - g_myY
  return (dx*dx + dy*dy) < ARRIVE_SQ_F
}

stock scanWithHead() {
  rotateHead(g_headScanDir)
  if(getHeadYaw() == g_headScanDir) g_headScanDir = -g_headScanDir
}

stock moveToward(float:tx, float:ty) {
  new float:dx          = tx - g_myX
  new float:dy          = ty - g_myY
  new float:targetAngle = calcAngle2D(dy, dx)
  new float:turn        = wrapPi(targetAngle - getDirection())

  rotate(getDirection() + turn)
  rotateTorso(0.0)

  if(abs(turn) < TURN_TOLERANCE_F && getEnergy() > ENERGY_RUN_F) {
    run()
  } else {
    walk()
  }
}

stock checkAntiStuck() {
  if(getTime() - g_stuckTime > STUCK_TIME_LIMIT_F) {
    new float:dx = g_myX - g_stuckLastX
    new float:dy = g_myY - g_stuckLastY
    if(dx*dx + dy*dy < DIST_TWO_F && g_hasTarget) {
      speak(CH_RAMBO_ACTIVE, MSG_STUCK)
      walkbk() 
      dfsAdvance()
    }
    g_stuckLastX = g_myX
    g_stuckLastY = g_myY
    g_stuckTime = getTime()
  }
}

stock doDFSExplore() {
  if(g_dfsExhausted || !g_hasTarget) {
    scanWithHead()
    if(isRunning()) walk()
    return
  }

  checkAntiStuck()
  moveToward(g_targetX, g_targetY)
  scanWithHead()

  new float:dx = g_targetX - g_myX
  new float:dy = g_targetY - g_myY
  new float:turn = wrapPi(calcAngle2D(dy, dx) - getDirection())

  if(abs(turn) < FRONT_TOLERANCE_F) {
    new item = ANY_WARRIOR
    new float:frontDist = aim(item)
    if(frontDist < WALL_DIST_F) {
      if(item != ITEM_NONE) {
        walkbk() 
      } else {
        dfsAdvance() 
      }
      return
    }
  }

  if(arrivedAtTarget()) {
    new col, row
    worldToCell(g_targetX, g_targetY, col, row)
    dfsPushNeighbors(col, row)
    dfsAdvance()
  }
}

stock bool:detectEnemy() {
  new item = ENEMY_WARRIOR, float:dist = 0.0, float:yaw = 0.0, float:pitch = 0.0
  watch(item, dist, yaw, pitch)

  if(item == ENEMY_WARRIOR) {
    g_enemyYawRel = yaw
    g_enemyDist   = dist
    g_enemyKnown  = true
    g_enemySeenAt = getTime()
    
    new float:absAngle = getDirection() + getTorsoYaw() + getHeadYaw() + yaw
    rotate(absAngle)
    bendTorso(pitch)
    bendHead(-pitch)
    rotateHead(0.0)
    return true
  }
  if(g_enemyKnown && (getTime() - g_enemySeenAt) > ENEMY_DATA_TTL_F) {
    g_enemyKnown = false
  }
  return false
}

stock fleeFromEnemy() {
  new float:absAngle = getDirection() + getTorsoYaw() + getHeadYaw() + g_enemyYawRel
  new float:enemyX   = g_myX + g_enemyDist * cos(absAngle)
  new float:enemyY   = g_myY + g_enemyDist * sin(absAngle)
  new float:escape   = calcAngle2D(g_myY - enemyY, g_myX - enemyX)

  g_targetX = g_myX + FLEE_DISTANCE_F * cos(escape)
  g_targetY = g_myY + FLEE_DISTANCE_F * sin(escape)

  rotate(escape)
  if(getEnergy() > ENERGY_RUN_F) {
    run()
  } else {
    walk()
  }
  scanWithHead()
}

stock ipcPrepareEnemyReport() {
  if(!g_enemyKnown) return
  g_ipcEnemyYawEncoded  = floatround(g_enemyYawRel * YAW_SCALE_F)
  g_ipcEnemyDistEncoded = clamp(floatround(g_enemyDist), 0, MAX_ENCODED_DIST)
  g_ipcEnemyStep        = 0
  g_ipcEnemyPending     = true
}

stock ipcTickTransmit() {
  if(!g_ipcEnemyPending) return
  if(g_ipcEnemyStep == 0) {
    if(speak(CH_ENEMY_SPOTTED, MSG_ENEMY_CONTACT)) g_ipcEnemyStep = 1
  } else if(g_ipcEnemyStep == 1) {
    if(speak(CH_ENEMY_SPOTTED, g_ipcEnemyYawEncoded)) g_ipcEnemyStep = 2
  } else if(g_ipcEnemyStep == 2) {
    if(speak(CH_ENEMY_SPOTTED, g_ipcEnemyDistEncoded)) {
      g_ipcEnemyStep = 0
      g_ipcEnemyPending = false
      g_lastReportTime = getTime()
    }
  }
}

stock ipcReportKIA() {
  if(g_calebKiaReported || getHealth() > HEALTH_LOW_F) return
  if(speak(CH_CALEB_DOWN, MSG_CALEB_KIA)) g_calebKiaReported = true
}

stock caleb_ipcPollAck() {
  new word
  listen(CH_RAMBO_ACTIVE, word)
}

runCalebDFS() {
  g_headScanDir = SCAN_HEAD_LIMIT_F
  refreshPosition()
  dfsInit()
  walk()
  g_stuckTime = getTime()

  for(;;) {
    wait(ASSAULT_LOOP_WAIT_F)
    refreshPosition()
    collectPowerup()

    if(detectEnemy()) {
      if(!g_ipcEnemyPending && (getTime() - g_lastReportTime) > REPORT_INTERVAL_F) {
        ipcPrepareEnemyReport()
      }
      if(g_enemyDist < SAFE_ENEMY_DISTANCE_F) {
        fleeFromEnemy()
      } else { 
        walk()
        scanWithHead() 
      }
    } else {
      doDFSExplore()
    }

    ipcTickTransmit()
    ipcReportKIA()
    caleb_ipcPollAck()
  }
}


// =============================================================================
// MÓDULO 2: RAMBO (Asalto Táctico & Combate)
// =============================================================================

stock bool:ipc_pollIncoming() {
  new word
  new bool:hadMessage = false

  if(listen(CH_CALEB_DOWN, word)) {
    if(word == MSG_CALEB_KIA) {
      g_calebKIA = true
      hadMessage = true
    }
  }

  if(listen(CH_ENEMY_SPOTTED, word)) {
    if(word == MSG_ENEMY_CONTACT) {
      new yawEncoded = 0
      new distEncoded = 0
      new tries = 0
      new bool:seqOK = false

      while(tries < IPC_RECV_MAX_TRIES) {
        wait(IPC_POLL_WAIT_F) 
        if(listen(CH_ENEMY_SPOTTED, yawEncoded)) {
          tries = 0
          while(tries < IPC_RECV_MAX_TRIES) {
            wait(IPC_POLL_WAIT_F)
            if(listen(CH_ENEMY_SPOTTED, distEncoded)) {
              seqOK = true
              break
            }
            tries++
          }
          break
        }
        tries++
      }

      if(seqOK) {
        g_lastEnemyYaw    = float(yawEncoded) / YAW_UNSCALE_F
        g_lastEnemyDist   = float(distEncoded)
        g_enemyContactActive = true
        hadMessage = true
      }
    }
  }
  return hadMessage
}

stock ipc_sendAck() {
  speak(CH_RAMBO_ACTIVE, MSG_RAMBO_ACK)
}

stock selectNextRamboID() {
  new totalMates = getMates()
  new candidate  = g_ramboID + 1
  new iterations = 0

  while(iterations < totalMates) {
    if(candidate >= totalMates) candidate = 0
    if(candidate != 0 && candidate != CALEB_ID) {
      return candidate
    }
    candidate++
    iterations++
  }
  return 0
}

stock bool:chooseWeapon(float:dist) {
  new const FRIEND_W = ITEM_FRIEND|ITEM_WARRIOR
  new aimTarget

  if(getGrenadeLoad() > 0 && dist > GRENADE_MIN_F && dist < GRENADE_MAX_F) {
    aim(aimTarget)
    if(aimTarget != FRIEND_W) {
      launchGrenade()
      return true
    }
  }

  aim(aimTarget)
  if(aimTarget != FRIEND_W) {
    shootBullet()
    return true
  }
  return false
}

stock doPatrolMovement(&float:lastTime, &float:headDir, float:avoidDir) {
  new float:now = getTime()

  if(now - lastTime > PATROL_DIR_CHANGE_F) {
    lastTime = now
    new float:angle = float(random(3) - 1) * PI_OVER_TWO_F
    rotate(getDirection() + angle)
  } else if(isStanding()) {
    rotate(getDirection() + PI_OVER_TWO_F)
    wait(WAIT_HALF_F)
    walk()
  } else if(sight() < WALL_AVOID_DIST_F) {
    rotate(getDirection() + avoidDir)
  }
}

runAssaultCycle() {
  new const ENEMY_W = ITEM_ENEMY|ITEM_WARRIOR
  new const ENEMY_G = ITEM_ENEMY|ITEM_GUN

  new float:headDir     = SCAN_HEAD_LIMIT_F
  new float:lastTime    = getTime()
  new float:avoidDir    = (getID() % 2 == 0) ? PI_OVER_TEN_F : -PI_OVER_TEN_F

  ipc_sendAck()

  if(g_enemyContactActive) {
    rotate(getDirection() + g_lastEnemyYaw)
    run()
  } else {
    walk()
  }

  for(;;) {
    wait(ASSAULT_LOOP_WAIT_F) 

    if(getHealth() <= 0.0) {
      g_ramboID = selectNextRamboID()
      speak(CH_RAMBO_ACTIVE, g_ramboID)
      return 
    }

    ipc_pollIncoming()
    collectPowerup()

    new item      = ENEMY_W
    new float:dist  = 0.0
    new float:yaw   = 0.0
    new float:pitch = 0.0
    watch(item, dist, yaw, pitch)

    if(item == ENEMY_W) {
      g_lastEnemyYaw    = yaw
      g_lastEnemyDist   = dist
      g_enemyContactActive = true

      rotate(yaw + getDirection())
      bendTorso(pitch)
      bendHead(-pitch)
      rotateHead(0.0)

      if(isWalking() || isStanding()) {
        run()
      }
      chooseWeapon(dist)

    } else {
      if(isRunning()) {
        walk()
      }
      if(g_enemyContactActive) {
        rotate(getDirection() + g_lastEnemyYaw)
        g_enemyContactActive = false 
      }

      new sound
      dist = hear(item, sound, yaw)
      if(item == ENEMY_G) {
        run()
        rotate(yaw + getDirection())
        wait(WAIT_SHORT_F) 
      } else {
        doPatrolMovement(lastTime, headDir, avoidDir)
        rotateHead(headDir)
        if(getHeadYaw() == headDir) headDir = -headDir
      }
    }

    new newRamboWord
    if(listen(CH_RAMBO_ACTIVE, newRamboWord)) {
      // Prevención de Bug IPC: MSG_STUCK no es un nuevo Rambo ID
      if(newRamboWord != MSG_RAMBO_ACK && newRamboWord != MSG_STUCK) {
        g_ramboID = newRamboWord
        if(g_ramboID != getID()) return
      }
    }
  }
}

standbyLoop() {
  new float:lastTime  = getTime()
  new float:headDir   = SCAN_HEAD_LIMIT_F
  new float:avoidDir  = (getID() % 2 == 0) ? PI_OVER_TEN_F : -PI_OVER_TEN_F

  walk()
  wait(ASSAULT_LOOP_WAIT_F) 

  for(;;) {
    wait(STANDBY_LOOP_WAIT_F) 

    new newRamboWord
    if(listen(CH_RAMBO_ACTIVE, newRamboWord)) {
      if(newRamboWord != MSG_RAMBO_ACK && newRamboWord != MSG_STUCK) {
        g_ramboID = newRamboWord
      }
    }

    if(g_ramboID == getID()) {
      return 
    }

    ipc_pollIncoming()
    collectPowerup()
    doPatrolMovement(lastTime, headDir, avoidDir)

    rotateHead(headDir)
    if(getHeadYaw() == headDir) {
      headDir = -headDir
    }
  }
}

// =============================================================================
// DISPATCHER MAESTRO & MAIN
// =============================================================================

fight() {
  // Sincronización pasiva de todo el pelotón
  rotate(PI_F)
  wait(DIST_TWO_F) 

  if(getID() == CALEB_ID) {
    // Orquestación: Solo Caleb entra al bucle ciego de DFS
    runCalebDFS()
  } else {
    // Orquestación: Lógica de Rambos y Cadetes en Espera
    if(getID() == RAMBO_INITIAL_ID) {
      walk()
      wait(ASSAULT_LOOP_WAIT_F)
    } else {
      walk()
      wait(ASSAULT_LOOP_WAIT_F)
      new word
      listen(CH_RAMBO_ACTIVE, word) 
    }

    // Máquina de estados dinámica de Roles Secundarios
    for(;;) {
      wait(ASSAULT_LOOP_WAIT_F) 
      if(g_ramboID == getID()) {
        runAssaultCycle() // Rambo Activo: Inicia Modo Combate
      } else {
        standbyLoop()     // Rambo Suplente: Patrulla pasiva
      }
    }
  }
}

soccer() {
  new float:AVOID_WALL_DIR = (getID()%2 == 0 ? PI_OVER_TEN_F : -PI_OVER_TEN_F)
  new float:lastTime = getTime()

  rotate(getDirection() + TWO_PI_F)
  new float:dist, float:yaw, item

  do {
    item = ITEM_TARGET
    dist = 0.0
    watch(item, dist, yaw)
    wait(ASSAULT_LOOP_WAIT_F) 
  } while(item != ITEM_TARGET)

  rotate(getDirection() + yaw)
  setKickSpeed(getMaxKickSpeed())
  bendTorso(WAIT_SHORT_F)
  bendHead(-WAIT_SHORT_F)

  new float:waitTime = STUCK_TIME_LIMIT_F - getTime() + lastTime 
  if(waitTime > 0.0) wait(waitTime)
  
  walk()
  wait(IPC_POLL_WAIT_F)

  for(;;) {
    wait(ASSAULT_LOOP_WAIT_F) 
    new float:now = getTime()
    
    if(now - lastTime > PATROL_DIR_CHANGE_F) { 
      lastTime = now
      rotate(getDirection() + (float(random(2)) - 0.5) * PI_F)
    } else if(isStanding()) {
      rotate(getDirection() + (float(random(2)) - 0.5) * PI_F)
      wait(REPORT_INTERVAL_F) 
      walk()
    } else if(sight() < DIST_TWO_F) {
      rotate(getDirection() + AVOID_WALL_DIR)
    }
    collectPowerup()
    item = ITEM_TARGET
    dist = 0.0
    watch(item, dist, yaw)
    if(item == ITEM_TARGET) {
      rotate(yaw + getDirection())
      if(isWalking()) run()
    }
  }
}

main() {
  new botId = getID()
  seed(botId * 1024) 
  
  new playMode = getPlay()
  if(playMode == PLAY_FIGHT || playMode == PLAY_RACE) {
    fight()
  } else if(playMode == PLAY_SOCCER) {
    soccer()
  }
}
