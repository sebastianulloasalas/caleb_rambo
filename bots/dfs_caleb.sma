// dfs_caleb.sma  —  Estrategia Caleb Refactorizada (DFS Iterativo Autónomo)
// Exclusividad: Solo el bot asignado como CALEB_ID ejecuta la exploración.

#include "core"
#include "math"
#include "bots"
#include "ipc_contract"

// -----------------------------------------------------------------------------
// CONSTANTES DE ENTEROS (Macros seguras)
#define GRID_W              14
#define GRID_TOTAL          196
#define DFS_STACK_SIZE      64
#define VISITED_CELLS       7 

#define ENEMY_WARRIOR       (ITEM_ENEMY | ITEM_WARRIOR)
#define ANY_WARRIOR         (ITEM_WARRIOR | ITEM_FRIEND | ITEM_ENEMY)

#define MSG_STUCK           911 // Reporte IPC para atascos

// Nota: CALEB_ID fue removido de aquí para evitar Warning 201. 
// Ya está definido dentro de "ipc_contract"

// -----------------------------------------------------------------------------
// CONSTANTES FLOTANTES GLOBALES (Previene Warning 213: Tag Mismatch)
new float:PI_F                  = 3.1415
new float:TWO_PI_F              = 6.2830
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

// -----------------------------------------------------------------------------
// MEMORIA LOCAL DEL BOT

new g_visited[VISITED_CELLS]
new g_dfsStack[DFS_STACK_SIZE]
new g_dfsStackTop = 0
new bool:g_dfsExhausted = false

new float:g_targetX = 0.0
new float:g_targetY = 0.0
new bool:g_hasTarget = false

new float:g_myX = 0.0, float:g_myY = 0.0, float:g_myZ = 0.0

// Variables Anti-Stuck
new float:g_stuckLastX = 0.0
new float:g_stuckLastY = 0.0
new float:g_stuckTime  = 0.0

new bool:g_enemyKnown = false
new float:g_enemyYawRel = 0.0
new float:g_enemyDist = 0.0
new float:g_enemySeenAt = -999.0

new bool:g_ipcEnemyPending = false
new g_ipcEnemyStep = 0
new g_ipcEnemyYawEncoded = 0
new g_ipcEnemyDistEncoded = 0
new float:g_lastReportTime = 0.0
new bool:g_calebKiaReported = false

new float:g_headScanDir = 0.0

// -----------------------------------------------------------------------------
// GRILLA
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

stock bool:isVisited(idx) {
  if(idx < 0 || idx >= GRID_TOTAL) return true
  return bool:((g_visited[idx / 32] >> (idx % 32)) & 1)
}

stock markVisited(idx) {
  if(idx < 0 || idx >= GRID_TOTAL) return
  g_visited[idx / 32] |= (1 << (idx % 32))
}

// -----------------------------------------------------------------------------
// DFS Y NAVEGACIÓN
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

// -----------------------------------------------------------------------------
// RUTINAS DE MOVIMIENTO Y MATEMÁTICAS

// Sin mod() para evadir de raíz el riesgo de warning de tag mismatch.
stock float:wrapPi(float:angle) {
  while (angle > PI_F) angle -= TWO_PI_F
  while (angle < -PI_F) angle += TWO_PI_F
  return angle
}

stock float:calcAngle2D(float:y, float:x) {
  if(abs(x) < EPS_F) {
    if(y > 0.0) return PI_F / 2.0
    if(y < 0.0) return -PI_F / 2.0
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

  if(abs(turn) < 0.35 && getEnergy() > 20.0) {
    run()
  } else {
    walk()
  }
}

stock collectPowerup() {
  new touched = getTouched()
  if(touched) raise(touched)
}

// -----------------------------------------------------------------------------
// LÓGICA ANTI-STUCK Y NAVEGACIÓN SEGURA

stock checkAntiStuck() {
  if(getTime() - g_stuckTime > STUCK_TIME_LIMIT_F) {
    new float:dx = g_myX - g_stuckLastX
    new float:dy = g_myY - g_stuckLastY
    if(dx*dx + dy*dy < 2.0 && g_hasTarget) {
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

  if(abs(turn) < 0.5) {
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

// -----------------------------------------------------------------------------
// DETECCIÓN DE ENEMIGOS E IPC
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

  if(g_enemyKnown && (getTime() - g_enemySeenAt) > ENEMY_DATA_TTL_F)
    g_enemyKnown = false
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
  
  if(getEnergy() > 20.0) {
    run()
  } else {
    walk()
  }
  
  scanWithHead()
}

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
  if(g_calebKiaReported || getHealth() > HEALTH_LOW_THRESHOLD) return
  if(speak(CH_CALEB_DOWN, MSG_CALEB_KIA)) g_calebKiaReported = true
}

stock ipcPollAck() {
  new word
  listen(CH_RAMBO_ACTIVE, word)
}

// -----------------------------------------------------------------------------
// LOOP PRINCIPAL
runCalebDFS() {
  g_headScanDir = SCAN_HEAD_LIMIT_F
  refreshPosition()
  dfsInit()
  walk()
  g_stuckTime = getTime()

  for(;;) {
    wait(0.05)
    refreshPosition()
    collectPowerup()

    if(detectEnemy()) {
      if(!g_ipcEnemyPending && (getTime() - g_lastReportTime) > REPORT_INTERVAL_F)
        ipcPrepareEnemyReport()

      if(g_enemyDist < SAFE_ENEMY_DISTANCE_F) fleeFromEnemy()
      else { walk(); scanWithHead(); }
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
  } else {
    for(;;) {
      wait(1.0)
    }
  }
}

main() {
  new botId = getID()
  seed(botId * 1024) 
  
  // Reemplazamos el "switch" que colapsaba el Parser, por if/else seguros.
  new playMode = getPlay()
  if(playMode == PLAY_FIGHT || playMode == PLAY_RACE) {
    fight()
  }
}
