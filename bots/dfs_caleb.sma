// dfs_caleb.sma  —  Estrategia Caleb (DFS Iterativo)
// Estrategia:
// - Exploración completa del mapa usando DFS iterativo (no recursivo).
// - Uso de una grilla discreta para representar el entorno.
// - Uso de un stack manual para evitar overflow de memoria.
// - Integración con sistema IPC para reportar enemigos.
//
// Decisiones clave:
// - DFS iterativo evita consumo excesivo de stack.
// - Bitfield compacto para celdas visitadas.
// - Separación clara entre navegación, combate e IPC.

#include "core"
#include "math"
#include "bots"
#include "ipc_contract"

// -----------------------------------------------------------------------------
// CONSTANTES GENERALES

new const float:PI     = 3.1415
new const float:TWO_PI = 6.2830

// Parámetros de la grilla
new const float:CELL_SIZE   = 10.0
new const float:MAP_OFFSET  = 65.0
new const GRID_W            = 14
new const GRID_TOTAL        = 196
new const DFS_STACK_SIZE    = 64
new const VISITED_BYTES     = 25

// Navegación
new const float:STEP_ARRIVE = 3.0
new const float:ARRIVE_SQ   = 9.0
new const float:WALL_DIST   = 4.0

// Enemigos
new const float:REPORT_INTERVAL     = 1.0
new const float:SAFE_ENEMY_DISTANCE = 25.0
new const float:FLEE_DISTANCE       = 10.0
new const float:ENEMY_DATA_TTL      = 3.0
new const float:SCAN_HEAD_LIMIT     = 1.047

new const ENEMY_WARRIOR  = ITEM_ENEMY | ITEM_WARRIOR

// -----------------------------------------------------------------------------
// MEMORIA LOCAL DEL BOT

// DFS
new g_visited[VISITED_BYTES]
new g_dfsStack[DFS_STACK_SIZE]
new g_dfsStackTop = 0
new bool:g_dfsExhausted = false

new float:g_targetX = 0.0
new float:g_targetY = 0.0
new bool:g_hasTarget = false

// Enemigo
new bool:g_enemyKnown = false
new float:g_enemyYawRel = 0.0
new float:g_enemyPitchRel = 0.0
new float:g_enemyDist = 0.0
new float:g_enemySeenAt = -999.0

// IPC
new bool:g_ipcEnemyPending = false
new g_ipcEnemyStep = 0
new g_ipcEnemyYawEncoded = 0
new g_ipcEnemyDistEncoded = 0
new float:g_lastReportTime = 0.0

new bool:g_calebKiaReported = false

// Exploración visual
new float:g_headScanDir = 0.0

// Posición cacheada
new float:g_myX = 0.0
new float:g_myY = 0.0
new float:g_myZ = 0.0

// -----------------------------------------------------------------------------
// FUNCIONES DE GRILLA

stock worldToCell(float:wx, float:wy, &col, &row) {
  col = floatround((wx + MAP_OFFSET) / CELL_SIZE, floatround_floor)
  row = floatround((wy + MAP_OFFSET) / CELL_SIZE, floatround_floor)
  col = clamp(col, 0, GRID_W - 1)
  row = clamp(row, 0, GRID_W - 1)
}

stock cellToWorld(col, row, &float:wx, &float:wy) {
  wx = float(col) * CELL_SIZE + CELL_SIZE * 0.5 - MAP_OFFSET
  wy = float(row) * CELL_SIZE + CELL_SIZE * 0.5 - MAP_OFFSET
}

stock cellIndex(col, row) {
  return row * GRID_W + col
}

stock bool:isVisited(idx) {
  if(idx < 0 || idx >= GRID_TOTAL) return true
  new byteIdx = idx / 8
  new bitIdx  = idx % 8
  return bool:((g_visited[byteIdx] >> bitIdx) & 1)
}

stock markVisited(idx) {
  if(idx < 0 || idx >= GRID_TOTAL) return
  new byteIdx = idx / 8
  new bitIdx  = idx % 8
  g_visited[byteIdx] |= (1 << bitIdx)
}

// -----------------------------------------------------------------------------
// DFS

stock dfsPush(idx) {
  if(g_dfsStackTop >= DFS_STACK_SIZE) return
  if(isVisited(idx)) return
  g_dfsStack[g_dfsStackTop] = idx
  g_dfsStackTop++
}

stock dfsPop() {
  if(g_dfsStackTop <= 0) return -1
  g_dfsStackTop--
  return g_dfsStack[g_dfsStackTop]
}

stock dfsPushNeighbors(col, row) {
  if(row > 0)          dfsPush(cellIndex(col,   row-1))
  if(col > 0)          dfsPush(cellIndex(col-1, row))
  if(row < GRID_W-1)   dfsPush(cellIndex(col,   row+1))
  if(col < GRID_W-1)   dfsPush(cellIndex(col+1, row))
}

stock dfsInit() {
  new startCol
  new startRow
  worldToCell(g_myX, g_myY, startCol, startRow)

  new startIdx = cellIndex(startCol, startRow)
  markVisited(startIdx)
  dfsPushNeighbors(startCol, startRow)

  new nextIdx = dfsPop()
  if(nextIdx >= 0) {
    new col = nextIdx % GRID_W
    new row = nextIdx / GRID_W
    cellToWorld(col, row, g_targetX, g_targetY)
    markVisited(nextIdx)
    dfsPushNeighbors(col, row)
    g_hasTarget = true
  }
}

stock dfsAdvance() {
  new nextIdx = -1

  while(g_dfsStackTop > 0) {
    nextIdx = dfsPop()
    if(nextIdx >= 0 && !isVisited(nextIdx)) break
    nextIdx = -1
  }

  if(nextIdx < 0) {
    g_dfsExhausted = true
    g_hasTarget    = false
    return
  }

  new col = nextIdx % GRID_W
  new row = nextIdx / GRID_W
  cellToWorld(col, row, g_targetX, g_targetY)
  markVisited(nextIdx)
  dfsPushNeighbors(col, row)
  g_hasTarget = true
}

// -----------------------------------------------------------------------------
// MATEMATICA

stock float:wrapPi(float:angle) {
  angle = mod(angle + PI, TWO_PI)
  if(angle < 0.0) angle += TWO_PI
  return angle - PI
}

stock float:calcAngle2D(float:y, float:x) {
  new const float:EPS = 0.00001
  if(abs(x) < EPS) {
    if(y > 0.0) return  PI / 2.0
    if(y < 0.0) return -PI / 2.0
    return 0.0
  }
  new float:a = atan(y / x)
  if(x < 0.0) {
    if(y >= 0.0) a += PI
    else         a -= PI
  }
  return a
}

// -----------------------------------------------------------------------------
// MOVIMIENTO

stock refreshPosition() {
  getLocation(g_myX, g_myY, g_myZ)
}

stock bool:arrivedAtTarget() {
  new float:dx = g_targetX - g_myX
  new float:dy = g_targetY - g_myY
  return (dx*dx + dy*dy) < ARRIVE_SQ
}

stock scanWithHead() {
  rotateHead(g_headScanDir)
  if(getHeadYaw() == g_headScanDir)
    g_headScanDir = -g_headScanDir
}

stock moveToward(float:tx, float:ty) {
  new float:dx          = tx - g_myX
  new float:dy          = ty - g_myY
  new float:targetAngle = calcAngle2D(dy, dx)
  new float:turn        = wrapPi(targetAngle - getDirection())

  rotate(getDirection() + turn)

  if(abs(turn) < 0.35 && getEnergy() > 20.0) run()
  else walk()
}

stock collectPowerup() {
  new touched = getTouched()
  if(touched) raise(touched)
}

// -----------------------------------------------------------------------------
// DETECCION DE ENEMIGOS

stock bool:detectEnemy() {
  new item      = ENEMY_WARRIOR
  new float:dist  = 0.0
  new float:yaw   = 0.0
  new float:pitch = 0.0

  watch(item, dist, yaw, pitch)

  if(item == ENEMY_WARRIOR) {
    g_enemyYawRel   = yaw
    g_enemyPitchRel = pitch
    g_enemyDist     = dist
    g_enemyKnown    = true
    g_enemySeenAt   = getTime()

    new float:absAngle = getDirection() + getTorsoYaw() + getHeadYaw() + yaw
    rotate(absAngle)
    bendTorso(pitch)
    bendHead(-pitch)
    rotateHead(0.0)

    return true
  }

  if(g_enemyKnown && (getTime() - g_enemySeenAt) > ENEMY_DATA_TTL)
    g_enemyKnown = false

  return false
}

// -----------------------------------------------------------------------------
// IPC

stock ipcPrepareEnemyReport() {
  if(!g_enemyKnown) return
  g_ipcEnemyYawEncoded  = floatround(g_enemyYawRel * YAW_SCALE)
  g_ipcEnemyDistEncoded = clamp(floatround(g_enemyDist), 0, MAX_ENCODED_DIST)
  g_ipcEnemyStep        = 0
  g_ipcEnemyPending     = true
}

stock ipcTickTransmit() {
  if(!g_ipcEnemyPending) return
  if(g_ipcEnemyStep == 0) {
    if(speak(CH_ENEMY_SPOTTED, MSG_ENEMY_CONTACT))
      g_ipcEnemyStep = 1
  } else if(g_ipcEnemyStep == 1) {
    if(speak(CH_ENEMY_SPOTTED, g_ipcEnemyYawEncoded))
      g_ipcEnemyStep = 2
  } else if(g_ipcEnemyStep == 2) {
    if(speak(CH_ENEMY_SPOTTED, g_ipcEnemyDistEncoded)) {
      g_ipcEnemyStep    = 0
      g_ipcEnemyPending = false
      g_lastReportTime  = getTime()
    }
  }
}

stock ipcReportKIA() {
  if(g_calebKiaReported) return
  if(getHealth() > HEALTH_LOW_THRESHOLD) return
  if(speak(CH_CALEB_DOWN, MSG_CALEB_KIA))
    g_calebKiaReported = true
}

stock ipcPollAck() {
  new word
  listen(CH_RAMBO_ACTIVE, word)
}

// -----------------------------------------------------------------------------
// COMPORTAMIENTO

stock fleeFromEnemy() {
  new float:absAngle = getDirection() + getTorsoYaw() + getHeadYaw() + g_enemyYawRel
  new float:enemyX   = g_myX + g_enemyDist * cos(absAngle)
  new float:enemyY   = g_myY + g_enemyDist * sin(absAngle)
  new float:escape   = calcAngle2D(g_myY - enemyY, g_myX - enemyX)

  g_targetX = g_myX + FLEE_DISTANCE * cos(escape)
  g_targetY = g_myY + FLEE_DISTANCE * sin(escape)

  rotate(escape)
  if(getEnergy() > 20.0) run()
  else walk()

  scanWithHead()
}

stock doDFSExplore() {
  if(!g_hasTarget) {
    scanWithHead()
    if(isRunning()) walk()
    return
  }

  if(sight() < WALL_DIST) {
    dfsAdvance()
    return
  }

  if(arrivedAtTarget()) {
    dfsAdvance()
  } else {
    moveToward(g_targetX, g_targetY)
    scanWithHead()
  }
}

// -----------------------------------------------------------------------------
// LOOP PRINCIPAL

runCalebDFS() {
  g_headScanDir = SCAN_HEAD_LIMIT

  refreshPosition()
  dfsInit()
  walk()

  for(;;) {
    wait(0.05)

    refreshPosition()
    collectPowerup()

    if(detectEnemy()) {
      if(!g_ipcEnemyPending && (getTime() - g_lastReportTime) > REPORT_INTERVAL)
        ipcPrepareEnemyReport()

      if(g_enemyDist < SAFE_ENEMY_DISTANCE) {
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
    ipcPollAck()
  }
}

fight() {
  if(getID() == CALEB_ID) {
    runCalebDFS()
  }
}

main() {
  switch(getPlay()) {
    case PLAY_FIGHT: fight()
    case PLAY_RACE:  fight()
  }
}
