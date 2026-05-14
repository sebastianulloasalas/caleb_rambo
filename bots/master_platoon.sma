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

#define GRID_W              14
#define GRID_TOTAL          196
#define DFS_STACK_SIZE      64
#define VISITED_CELLS       7 
#define ENEMY_WARRIOR       (ITEM_ENEMY | ITEM_WARRIOR)
#define ANY_WARRIOR         (ITEM_WARRIOR | ITEM_FRIEND | ITEM_ENEMY)
#define MSG_STUCK           911 

// =============================================================================
// CONSTANTES FLOTANTES GLOBALES

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

new g_ramboID = 0 // Ahora inicializado en 0. El Jefe dicta quién despierta.
new float:g_lastEnemyYaw = 0.0
new float:g_lastEnemyDist = 0.0
new bool:g_enemyContactActive = false
new bool:g_calebKIA = false

// =============================================================================
// UTILIDADES COMPARTIDAS (Matemática y Grilla)

/**
 * worldToCell: Convierte coordenadas espaciales continuas a índices discretos de una grilla.
 * Detalle extendido: Fundamental para el mapeo espacial del algoritmo DFS. Limita
 * los valores resultantes al tamaño máximo de la grilla para prevenir desbordes de memoria.
 * 
 * @param wx Coordenada X actual en el mundo (Float).
 * @param wy Coordenada Y actual en el mundo (Float).
 * @param col Referencia de memoria donde se almacenará el índice de columna resultante.
 * @param row Referencia de memoria donde se almacenará el índice de fila resultante.
 * @return void (Los resultados se devuelven por referencia).
 */
stock worldToCell(float:wx, float:wy, &col, &row) {
  col = floatround((wx + MAP_OFFSET_F) / CELL_SIZE_F, floatround_floor)
  row = floatround((wy + MAP_OFFSET_F) / CELL_SIZE_F, floatround_floor)
  col = clamp(col, 0, GRID_W - 1)
  row = clamp(row, 0, GRID_W - 1)
}

/**
 * cellToWorld: Transforma una coordenada discreta de grilla al centro físico del mundo.
 * Detalle extendido: Utilizada por Caleb para establecer su g_targetX/g_targetY de navegación
 * tras calcular el siguiente nodo óptimo en el DFS.
 * 
 * @param col Índice de la columna en la grilla.
 * @param row Índice de la fila en la grilla.
 * @param wx Referencia para almacenar la coordenada X real resultante.
 * @param wy Referencia para almacenar la coordenada Y real resultante.
 * @return void
 */
stock cellToWorld(col, row, &float:wx, &float:wy) {
  wx = float(col) * CELL_SIZE_F + CELL_SIZE_F * 0.5 - MAP_OFFSET_F
  wy = float(row) * CELL_SIZE_F + CELL_SIZE_F * 0.5 - MAP_OFFSET_F
}

/**
 * cellIndex: Aplana una coordenada bidimensional en un índice unidimensional.
 * Detalle extendido: Necesario para la manipulación en los arrays de bits (g_visited)
 * y la pila de exploración (g_dfsStack), optimizando el uso de RAM.
 * 
 * @param col Índice de columna (0 a GRID_W - 1).
 * @param row Índice de fila (0 a GRID_W - 1).
 * @return El índice lineal equivalente del nodo.
 */
stock cellIndex(col, row) { return row * GRID_W + col; }

/**
 * wrapPi: Normaliza un ángulo para mantenerlo dentro del rango de -PI a PI.
 * Detalle extendido: Evita el uso de la función mod() nativa que suele causar
 * desajustes de tags flotantes en el motor Small 1.8. Crucial para los giros sin fin.
 * 
 * @param angle El ángulo en radianes a normalizar.
 * @return Ángulo normalizado en el rango estricto circular.
 */
stock float:wrapPi(float:angle) {
  while (angle > PI_F) angle -= TWO_PI_F
  while (angle < -PI_F) angle += TWO_PI_F
  return angle
}

/**
 * calcAngle2D: Computa la dirección (Yaw) hacia un punto relativo 2D.
 * Detalle extendido: Implementa un arco-tangente a prueba de divisiones por cero (EPS_F).
 * Permite a cualquier bot apuntar hacia objetivos o moverse iterativamente nodo por nodo.
 * 
 * @param y Diferencia en el eje Y (targetY - currentY).
 * @param x Diferencia en el eje X (targetX - currentX).
 * @return Ángulo resultante en radianes.
 */
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

/**
 * refreshPosition: Actualiza la caché local de coordenadas espaciales del bot.
 * Detalle extendido: Centraliza la llamada nativa getLocation, manteniendo las
 * variables globales g_myX/Y/Z sincronizadas en cada ciclo (Tick).
 * 
 * @return void
 */
stock refreshPosition() { getLocation(g_myX, g_myY, g_myZ); }

/**
 * collectPowerup: Verifica e intenta recolectar un objeto (powerup) en los pies del bot.
 * Detalle extendido: Se integra en loops de espera pasiva y de exploración activa.
 * 
 * @return void
 */
stock collectPowerup() { new touched = getTouched(); if(touched) raise(touched); }

// =============================================================================
// MÓDULO 0: JEFE (Centralizado)

/**
 * selectNextRamboID: Lógica de sucesión movida exclusivamente al dominio del Jefe.
 */
stock selectNextRamboID(currentRambo) {
  new totalMates = getMates()
  new candidate  = currentRambo + 1
  new iterations = 0

  while(iterations < totalMates) {
    if(candidate >= totalMates) candidate = 0
    // Evitar asignar al Jefe (0) o a Caleb (1)
    if(candidate != 0 && candidate != CALEB_ID) {
      return candidate
    }
    candidate++
    iterations++
  }
  return 0
}

/**
 * receiveSequence: Utilidad del Jefe para re-ensamblar la telemetría de Caleb.
 */
stock bool:receiveSequence(channel, &part2, &part3) {
  new tries = 0
  new temp2, temp3
  while(tries < IPC_RECV_MAX_TRIES) {
    wait(IPC_POLL_WAIT_F)
    if(listen(channel, temp2)) {
      tries = 0
      while(tries < IPC_RECV_MAX_TRIES) {
        wait(IPC_POLL_WAIT_F)
        if(listen(channel, temp3)) {
          part2 = temp2
          part3 = temp3
          return true
        }
        tries++
      }
      return false
    }
    tries++
  }
  return false
}

/**
 * runChiefCycle: Cerebro Estratégico. El bot 0 nunca combate directamente.
 */
runChiefCycle() {
  new activeRambo = RAMBO_INITIAL_ID

  // Despliegue de Exploración
  speak(CH_CHIEF_TX, CMD_START_EXPLORE)
  wait(IPC_POLL_WAIT_F)

  // Nombramiento del Rambo Inicial
  speak(CH_CHIEF_TX, CMD_WAKE_RAMBO_BASE + activeRambo)

  // Loop Central de Enrutamiento y Mando
  for(;;) {
    wait(IPC_POLL_WAIT_F)
    new word
    
    // El Jefe escucha todo lo que sucede en el canal de reportes
    if(listen(CH_CHIEF_RX, word)) {
      
      // Caleb reporta un enemigo. El Jefe funciona como Router hacia los Rambos.
      if(word == MSG_ENEMY_CONTACT) {
        new yawEnc, distEnc
        if(receiveSequence(CH_CHIEF_RX, yawEnc, distEnc)) {
          speak(CH_CHIEF_TX, MSG_ENEMY_CONTACT)
          wait(IPC_POLL_WAIT_F)
          speak(CH_CHIEF_TX, yawEnc)
          wait(IPC_POLL_WAIT_F)
          speak(CH_CHIEF_TX, distEnc)
        }
      }
      
      // El Rambo Activo ha muerto en combate. El Jefe lo reemplaza.
      else if(word == MSG_RAMBO_KIA) {
        activeRambo = selectNextRamboID(activeRambo)
        speak(CH_CHIEF_TX, CMD_WAKE_RAMBO_BASE + activeRambo)
      }
      
      // Caleb ha caído. El Jefe alerta a la escuadra.
      else if(word == MSG_CALEB_KIA) {
        speak(CH_CHIEF_TX, MSG_CALEB_KIA)
      }
    }
  }
}

// =============================================================================
// MÓDULO 1: CALEB (Exploración Autónoma)

/**
 * isVisited: Verifica el estado de exploración de un nodo en el bitfield.
 * Detalle extendido: Utiliza operaciones de bit a nivel de enteros de 32-bits para comprimir
 * 196 celdas en sólo 7 bloques de memoria, maximizando el heap space libre para GunTactyx.
 * 
 * @param idx Índice lineal de la celda a consultar.
 * @return Verdadero si ya fue visitada o si el índice está fuera de los límites.
 */
stock bool:isVisited(idx) {
  if(idx < 0 || idx >= GRID_TOTAL) return true
  return bool:((g_visited[idx / 32] >> (idx % 32)) & 1)
}

/**
 * markVisited: Marca un nodo bidimensional como explorado en el bitfield.
 * Detalle extendido: Actualiza la representación binaria comprimida del mapa evitando
 * sobre-escrituras o desbordes en índices inexistentes.
 * 
 * @param idx Índice lineal de la celda a marcar.
 * @return void
 */
stock markVisited(idx) {
  if(idx < 0 || idx >= GRID_TOTAL) return
  g_visited[idx / 32] |= (1 << (idx % 32))
}

/**
 * dfsPush: Empuja de forma segura un nuevo nodo (índice) a la pila de exploración de Caleb.
 * Detalle extendido: Bloquea inserciones duplicadas evaluando isVisited(). Actúa como 
 * una barrera contra el desborde de memoria (Stack Overflow) en la pila manual DFS_STACK_SIZE.
 * 
 * @param idx Índice lineal de la celda candidata a explorar.
 * @return void
 */
stock dfsPush(idx) {
  if(g_dfsStackTop >= DFS_STACK_SIZE || isVisited(idx)) return
  markVisited(idx)
  g_dfsStack[g_dfsStackTop++] = idx
}

/**
 * dfsPop: Retira y devuelve el nodo más reciente (LIFO) de la pila de exploración manual.
 * Detalle extendido: Soporta el concepto de Backtracking en la estrategia DFS de Caleb.
 * 
 * @return El índice del nodo recuperado, o -1 si la pila está vacía (exploración agotada).
 */
stock dfsPop() {
  if(g_dfsStackTop <= 0) return -1
  return g_dfsStack[--g_dfsStackTop]
}

/**
 * dfsPushNeighbors: Localiza e inyecta nodos ortogonales vecinos no visitados a la pila.
 * Detalle extendido: Aplica un Shuffle (aleatorización) en el orden de las ramas. Esto 
 * inyecta variabilidad a la exploración en diferentes rondas evitando patrones muy predecibles.
 * 
 * @param col Columna actual del nodo base.
 * @param row Fila actual del nodo base.
 * @return void
 */
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

/**
 * dfsAdvance: Avanza el motor de exploración extrayendo el próximo destino válido.
 * Detalle extendido: Establece `g_targetX` y `g_targetY`. Si se agotan los nodos (-1),
 * activa la bandera global de finalización (g_dfsExhausted) cancelando los cálculos.
 * 
 * @return void
 */
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

/**
 * dfsInit: Semilla inicial para arrancar la exploración de Caleb.
 * Detalle extendido: Calcula su posición de aparición (spawn), marca la celda cero,
 * puebla sus ramas vecinas y da la orden inicial de arranque hacia su primer destino DFS.
 * 
 * @return void
 */
stock dfsInit() {
  new startCol, startRow
  worldToCell(g_myX, g_myY, startCol, startRow)
  markVisited(cellIndex(startCol, startRow))
  dfsPushNeighbors(startCol, startRow)
  dfsAdvance()
}

/**
 * arrivedAtTarget: Mide la proximidad física del bot al nodo de destino actual de la grilla.
 * Detalle extendido: Define el área de tolerancia de llegada evitando un temblor 
 * infinito intentando estar en la coordenada perfecta absoluta (usando ARRIVE_SQ_F).
 * 
 * @return Verdadero si la distancia al compás cuadrado es menor al umbral tolerado.
 */
stock bool:arrivedAtTarget() {
  new float:dx = g_targetX - g_myX
  new float:dy = g_targetY - g_myY
  return (dx*dx + dy*dy) < ARRIVE_SQ_F
}

/**
 * scanWithHead: Implementa el radar visual panorámico continuo del bot Caleb.
 * Detalle extendido: Hace oscilar la cabeza a SCAN_HEAD_LIMIT_F radianes izquierda/derecha,
 * multiplicando el área barrida por los sensores periféricos nativos.
 * 
 * @return void
 */
stock scanWithHead() {
  rotateHead(g_headScanDir)
  if(getHeadYaw() == g_headScanDir) g_headScanDir = -g_headScanDir
}

/**
 * moveToward: Calcula y ejecuta el impulso biomecánico hacia un objetivo coordenado.
 * Detalle extendido: Fija temporalmente la rotación del torso para sincronizar el raycast
 * visual frontal. Regula la estamina cambiando de correr a caminar basado en ENERGY_RUN_F.
 * 
 * @param tx Coordenada X del destino.
 * @param ty Coordenada Y del destino.
 * @return void
 */
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

/**
 * checkAntiStuck: Supervisor de inercia y atascos lógicos/físicos en el entorno 3D.
 * Detalle extendido: Si Caleb no ha recorrido más de DIST_TWO_F en STUCK_TIME_LIMIT_F segundos,
 * fuerza un retroceso mecánico, omite la rama actual del árbol DFS y notifica al grupo (MSG_STUCK).
 * 
 * @return void
 */
stock checkAntiStuck() {
  if(getTime() - g_stuckTime > STUCK_TIME_LIMIT_F) {
    new float:dx = g_myX - g_stuckLastX
    new float:dy = g_myY - g_stuckLastY
    if(dx*dx + dy*dy < DIST_TWO_F && g_hasTarget) {
      walkbk() 
      dfsAdvance()
    }
    g_stuckLastX = g_myX
    g_stuckLastY = g_myY
    g_stuckTime = getTime()
  }
}

/**
 * doDFSExplore: Máquina de estados de transición paso a paso para la estrategia Caleb.
 * Detalle extendido: Gestiona colisiones inminentes utilizando `aim()`. Activa rutinas de 
 * evasión (Backtracking), avance a nuevas celdas y propagación continua de las reglas DFS.
 * 
 * @return void
 */
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

/**
 * detectEnemy: Dispara la lectura cruda del sensor de visión para filtrar guerreros hostiles.
 * Detalle extendido: De encontrar a alguien, actualiza coordenadas relativas, encausa el 
 * cuerpo hacia la amenaza simulando una alerta física. Permite mantener caché temporal.
 * 
 * @return Verdadero si un enemigo está siendo vislumbrado en este frame/tick.
 */
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

/**
 * fleeFromEnemy: Táctica de supervivencia autónoma de Caleb.
 * Detalle extendido: Calcula el vector opuesto exacto a la posición visualizada
 * del enemigo y acelera para ganar distancia segura manteniendo el radar giratorio activo.
 * 
 * @return void
 */
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

/**
 * ipcPrepareEnemyReport: Codifica metadatos en enteros para evadir la limitación IPC del motor.
 * Detalle extendido: GunTactyx sólo transmite Words (Enteros). Esta rutina empaqueta la 
 * rotación y distancia flotante escalándolos y bloqueándolos listos para transmisión.
 * 
 * @return void
 */
stock ipcPrepareEnemyReport() {
  if(!g_enemyKnown) return
  g_ipcEnemyYawEncoded  = floatround(g_enemyYawRel * YAW_SCALE_F)
  g_ipcEnemyDistEncoded = clamp(floatround(g_enemyDist), 0, MAX_ENCODED_DIST)
  g_ipcEnemyStep        = 0
  g_ipcEnemyPending     = true
}

/**
 * ipcTickTransmit: Operador de antena para transmitir alertas fragmentadas.
 * Detalle extendido: Emite un protocolo ordenado a través de CH_CHIEF_RX.
 * Trasmite Alerta a Yaw (escalado) a Distancia. El receptor reconstruirá esto después.
 * 
 * @return void
 */
stock ipcTickTransmit() {
  if(!g_ipcEnemyPending) return
  if(g_ipcEnemyStep == 0) {
    if(speak(CH_CHIEF_RX, MSG_ENEMY_CONTACT)) g_ipcEnemyStep = 1
  } else if(g_ipcEnemyStep == 1) {
    if(speak(CH_CHIEF_RX, g_ipcEnemyYawEncoded)) g_ipcEnemyStep = 2
  } else if(g_ipcEnemyStep == 2) {
    if(speak(CH_CHIEF_RX, g_ipcEnemyDistEncoded)) {
      g_ipcEnemyStep = 0
      g_ipcEnemyPending = false
      g_lastReportTime = getTime()
    }
  }
}

/**
 * ipcReportKIA: Envía un aviso de emergencia en vísperas de destrucción.
 * Detalle extendido: Si la salud cae a umbrales inviables, alerta en CH_CHIEF_RX.
 * Esto es la médula del reemplazo táctico para que el escuadrón lo asista sin él saberlo.
 * 
 * @return void
 */
stock ipcReportKIA() {
  if(g_calebKiaReported || getHealth() > HEALTH_LOW_F) return
  if(speak(CH_CHIEF_RX, MSG_CALEB_KIA)) g_calebKiaReported = true
}

/**
 * caleb_flushChiefTx: Depura los buzones de confirmación remota vaciándolos rutinariamente.
 * Detalle extendido: El simulador apila mensajes internamente; esto "consume" los mensajes
 * del canal CH_CHIEF_TX para no interferir con el parseo asíncrono de Caleb.
 * 
 * @return void
 */
stock caleb_flushChiefTx() {
  new word
  listen(CH_CHIEF_TX, word)
}

/**
 * runCalebDFS: Ciclo de la entidad Exploradora (Caleb).
 * Detalle extendido: Fusiona las llamadas de supervivencia `detectEnemy` con el mapeo `doDFSExplore`.
 * Se asegura de invocar un `wait` preventivo en cada tick salvaguardando los hilos de CPU locales.
 * 
 * @return No retorna nunca por sí solo (for(;;)).
 */
runCalebDFS() {
  // Caleb ESPERA la orden explícita del Jefe para moverse.
  new bool:started = false
  while(!started) {
    new word
    if(listen(CH_CHIEF_TX, word) && word == CMD_START_EXPLORE) {
      started = true
    }
    wait(WAIT_SHORT_F)
  }

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
    caleb_flushChiefTx()
  }
}


// =============================================================================
// MÓDULO 2: RAMBO (Asalto Táctico & Combate)

/**
 * ipc_pollIncoming: Receptor síncrono para reconstruir transmisiones alienadas desde el Jefe.
 * Detalle extendido: Consume iterativamente las partes (Contacto->Yaw->Distancia). Si se
 * pierde una secuencia, la abandona. También audita caídas de aliados (CH_CHIEF_TX).
 * 
 * @return Verdadero si un bloque de inteligencia coherente fue parseado exitosamente.
 */
stock bool:ipc_pollIncoming() {
  new word
  new bool:hadMessage = false

  if(listen(CH_CHIEF_TX, word)) {
    // Manejo de nombramiento atómico
    if(word >= CMD_WAKE_RAMBO_BASE) {
      g_ramboID = word - CMD_WAKE_RAMBO_BASE
      hadMessage = true
    }

    // Muerte de Caleb
    else if(word == MSG_CALEB_KIA) {
      g_calebKIA = true
      hadMessage = true
    }

    // Recepción de coordenadas enrutadas por el Jefe
    else if(word == MSG_ENEMY_CONTACT) {
      new yawEncoded = 0
      new distEncoded = 0
      new tries = 0
      new bool:seqOK = false

      while(tries < IPC_RECV_MAX_TRIES) {
        wait(IPC_POLL_WAIT_F) 
        if(listen(CH_CHIEF_TX, yawEncoded)) {
          tries = 0
          while(tries < IPC_RECV_MAX_TRIES) {
            wait(IPC_POLL_WAIT_F)
            if(listen(CH_CHIEF_TX, distEncoded)) {
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

/**
 * chooseWeapon: Micro-orquestador armamentístico basado en la métrica espacial provista.
 * Detalle extendido: Previene Fuego Amigo comprobando la línea de tiro usando `aim`.
 * Desenfunda Granadas en zonas lejanas (GRENADE_MIN_F a GRENADE_MAX_F) o usa balas de otra forma.
 * 
 * @param dist Distancia reportada hacia el foco de atención hostil.
 * @return Verdadero si logró disparar algún armamento, falso de estar bloqueado/vacío.
 */
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

/**
 * doPatrolMovement: Inyecta un vector de caos estocástico al caminar impidiendo embotellamientos.
 * Detalle extendido: Funciona como un temporizador biológico para mirar y girar pseudo-aleatoriamente
 * durante las esperas (StandbyLoop) y bloqueos físicos contra paredes u aliados en el área.
 * 
 * @param lastTime Referencia al temporizador del último quiebre de trayectoria (actualizado in-place).
 * @param headDir  Referencia del pivote de la vista actual del bot (no modificado aquí directamente).
 * @param avoidDir Constante flotante de evasión rotacional exclusiva al ID local.
 * @return void
 */
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

/**
 * runAssaultCycle: El clímax combativo para la entidad designada como Rambo Actual.
 * Detalle extendido: Monopoliza sus acciones hacia una caza agresiva procesando coordenadas
 * enviadas por Caleb. Verifica constantemente su barra de vida para traspasar el título si cae (KIA).
 * 
 * @return void (Si retorna, implica que el bot murió o el rol fue despojado dinámicamente).
 */
runAssaultCycle() {
  new const ENEMY_W = ITEM_ENEMY|ITEM_WARRIOR
  new const ENEMY_G = ITEM_ENEMY|ITEM_GUN

  new float:headDir     = SCAN_HEAD_LIMIT_F
  new float:lastTime    = getTime()
  new float:avoidDir    = (getID() % 2 == 0) ? PI_OVER_TEN_F : -PI_OVER_TEN_F

  if(g_enemyContactActive) {
    rotate(getDirection() + g_lastEnemyYaw)
    run()
  } else {
    walk()
  }

  for(;;) {
    wait(ASSAULT_LOOP_WAIT_F) 

    // Si Rambo muere, reporta al Jefe y corta su proceso.
    if(getHealth() <= 0.0) {
      speak(CH_CHIEF_RX, MSG_RAMBO_KIA)
      return 
    }

    ipc_pollIncoming()

    // Si el Jefe designó a otro bot mientras este seguía vivo
    if(g_ramboID != getID()) {
      return 
    }

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
  }
}

/**
 * standbyLoop: Estado de vigilia pasivo para los componentes no protagónicos del pelotón.
 * Detalle extendido: Un bot en Standby patrulla áreas de bajo interés para no molestar la
 * triangulación de Caleb y escucha atentamente nombramientos directos en su ID para escalar al asalto.
 * 
 * @return void (Si retorna, implica un salto contextual al `runAssaultCycle` superior).
 */
standbyLoop() {
  new float:lastTime  = getTime()
  new float:headDir   = SCAN_HEAD_LIMIT_F
  new float:avoidDir  = (getID() % 2 == 0) ? PI_OVER_TEN_F : -PI_OVER_TEN_F

  walk()
  wait(ASSAULT_LOOP_WAIT_F) 

  for(;;) {
    wait(STANDBY_LOOP_WAIT_F) 

    ipc_pollIncoming() // Actualiza g_ramboID leyendo CH_CHIEF_TX

    // Si el Jefe lo invoca, sale del standby directo al asalto.
    if(g_ramboID == getID()) {
      return 
    }

    collectPowerup()
    doPatrolMovement(lastTime, headDir, avoidDir)

    rotateHead(headDir)
    if(getHeadYaw() == headDir) {
      headDir = -headDir
    }
  }
}

// =============================================================================
// DISPATCHER MAIN

/**
 * fight: Router supremo y árbitro de inicio contextual.
 * Detalle extendido: Evalúa el ID único del bot al momento del spawn y lo despacha
 * a la rama Caleb si es el número asignado, o lo condena a la máquina de roles de Rambo
 * para esperar ser el cazador primario o ser de reserva (standby).
 * 
 * @return void (Entra en bucles infinitos por defecto según su rol).
 */
fight() {
  // Sincronización pasiva de todo el pelotón
  rotate(PI_F)
  wait(DIST_TWO_F) 

  new myID = getID()

  // Orquestación: El Jefe (0) toma el mando en su thread exclusivo
  if(myID == 0) {
    runChiefCycle()
  } 

  // Orquestación: Caleb (1) queda pendiente de órdenes
  else if(myID == CALEB_ID) {
    runCalebDFS()
  } 

  // Orquestación: Resto de la infantería espera pasivamente su asignación
  else {
    stand()
    wait(1.0)

    for(;;) {
      wait(ASSAULT_LOOP_WAIT_F) 
      if(g_ramboID == myID) {
        runAssaultCycle() // Jefe lo nombró activo
      } else {
        standbyLoop()     // Jefe lo tiene en reserva
      }
    }
  }
}

soccer() { }

/**
 * main: Punto de entrada nativo predefinido por el motor GunTactyx.
 * Detalle extendido: Genera las semillas matemáticas de pseudo-azar basadas en el
 * identificador para forzar divergencia grupal. Cede el control al juego apropiado.
 * 
 * @return void (Nunca retorna).
 */
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
