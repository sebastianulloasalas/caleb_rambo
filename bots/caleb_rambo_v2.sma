// caleb_rambo.sma
// Primera version: estrategia Caleb + estructura preparada para Rambo.
//
// Objetivo actual:
// - Caleb explora el mapa.
// - Si Caleb ve un enemigo, calcula una posicion aproximada del enemigo.
// - Caleb informa por radio una ubicacion simplificada en forma de celda.
// - Los demas bots escuchan y guardan la informacion recibida.
// - La funcion de Rambo queda preparada para implementarla despues.

#include "core"
#include "math"
#include "bots"

// ================================================================
// CONSTANTES GENERALES
// ================================================================

new const CALEB_ID = 0              // Por ahora Caleb sera el bot con ID 0.
new const RAMBO_ID_INICIAL = 1      // Reservado para la siguiente etapa.

new const RADIO_CANAL_EQUIPO = 1
new const MSG_ENEMY_BASE = 10000    // Todo mensaje >= 10000 sera tratado como enemigo detectado.
new const MSG_CALEB_ALIVE = 9001    // Mensaje simple para indicar que Caleb sigue activo.

new const float:PI = 3.1415
new const float:TWO_PI = 6.2830

new const float:MAP_OFFSET = 70.0   // Desplaza coordenadas negativas a positivas para codificar celdas.
new const float:CELL_SIZE = 10.0    // Tamano aproximado de cada celda de exploracion/reporte.
new const float:STEP_DFS = 12.0     // Distancia entre puntos de exploracion de Caleb.

new const float:ARRIVE_DIST = 2.0   // Distancia para considerar que Caleb llego a un punto.
new const float:WALL_DIST = 4.0     // Si hay pared cerca, Caleb cambia de rama.
new const float:REPORT_INTERVAL = 1.0
new const float:SCAN_HEAD_LIMIT = 1.047
new const float:SAFE_ENEMY_DISTANCE = 25.0   // Distancia minima que Caleb intenta mantener frente al enemigo.
new const float:FLEE_DISTANCE = 10.0         // Distancia del punto de escape cuando Caleb ve un enemigo.

// Filtros de objetos usados por sensores.
// Reservado para la siguiente etapa, cuando los bots deban ubicar aliados.
// new const FRIEND_WARRIOR = ITEM_FRIEND | ITEM_WARRIOR
new const ENEMY_WARRIOR = ITEM_ENEMY | ITEM_WARRIOR

// ================================================================
// MEMORIA LOCAL DEL BOT
// Nota: cada bot ejecuta su propio script; por eso estas variables
// no son memoria global compartida real. La informacion entre bots
// se pasa mediante speak()/listen().
// ================================================================

new bool:g_enemyKnown = false
new float:g_enemyX = 0.0
new float:g_enemyY = 0.0
new float:g_enemyZ = 0.0
new float:g_enemyDist = 0.0
new g_enemyCellX = 0
new g_enemyCellY = 0
new float:g_lastEnemyTime = 0.0

new bool:g_calebDetectedEnemy = false
new float:g_lastReportTime = 0.0

// Estado de exploracion tipo DFS simplificado.
new float:g_targetX = 0.0
new float:g_targetY = 0.0
new g_dfsDirection = 0
new float:g_headScanDir = 0.0        // Se inicializa en ejecutar_estrategia_caleb().

// ================================================================
// FUNCIONES MATEMATICAS AUXILIARES
// ================================================================

//Normalizar un ángulo para que esté dentro del rango:
//Si el ángulo es muy grande (por ejemplo 4pi), se le resta 2pi repetidamente.
//Si es muy negativo (por ejemplo -5π), se le suma 2π.
stock float:wrapPi(float:angle) {
  while(angle > PI) angle -= TWO_PI
  while(angle < -PI) angle += TWO_PI
  return angle
}

//Calcular el ángulo (dirección) hacia un punto (x, y)
stock float:atan2(float:y, float:x) {
  new const float:EPS = 0.00001

  if(abs(x) < EPS) {
    if(y > 0.0) return PI / 2.0
    if(y < 0.0) return -PI / 2.0
    return 0.0
  }

  new float:a = atan(y / x)

  if(x < 0.0) {
    if(y >= 0.0) a += PI
    else a -= PI
  }

  return a
}

//Calcular la distancia entre dos puntos en 2D
stock float:dist2D(float:x1, float:y1, float:x2, float:y2) {
  new float:dx = x2 - x1
  new float:dy = y2 - y1
  return sqrt(dx * dx + dy * dy)
}

// Convierte una coordenada real del mapa a una celda entera.
// Ejemplo: coordenadas cercanas se agrupan en la misma celda.
stock coordToCell(float:value) {
  return floatround((value + MAP_OFFSET) / CELL_SIZE, floatround_floor)
}

// Codifica dos celdas en un solo entero para enviarlo por radio.
// Formato: 10000 + cellX*100 + cellY
stock encodeEnemyCell(cellX, cellY) {
  return MSG_ENEMY_BASE + cellX * 100 + cellY
}

// Decodifica el mensaje de radio recibido.
stock decodeEnemyCell(word, &cellX, &cellY) {
  new data = word - MSG_ENEMY_BASE
  cellX = data / 100
  cellY = data % 100
}

// Convierte una celda reportada nuevamente a una posicion aproximada.
stock float:cellToCoord(cell) {
  return float(cell) * CELL_SIZE - MAP_OFFSET + CELL_SIZE / 2.0
}

// ================================================================
// DETECCION Y MOVIMIENTO BASICO
// ================================================================

stock mirarAlrededor() {
  // Caleb mueve la cabeza de izquierda a derecha para aumentar la probabilidad
  // de detectar enemigos con watch().
  rotateHead(g_headScanDir)

  if(getHeadYaw() == g_headScanDir) {
    g_headScanDir = -g_headScanDir
  }
}

stock moverHacia(float:tx, float:ty) {
  new float:x
  new float:y
  new float:z
  getLocation(x, y, z)

  new float:dx = tx - x
  new float:dy = ty - y
  new float:targetAngle = atan2(dy, dx)
  new float:turn = wrapPi(targetAngle - getDirection())

  rotate(getDirection() + turn)

  // Si esta muy desalineado, caminar es mas estable que correr.
  if(abs(turn) < 0.35) {
    if(getEnergy() > 20.0) run()
    else walk()
  } else {
    walk()
  }
}

stock bool:llegoA(float:tx, float:ty) {
  new float:x
  new float:y
  new float:z
  getLocation(x, y, z)
  return dist2D(x, y, tx, ty) < ARRIVE_DIST
}

stock elegirSiguientePuntoDFS() {
  // DFS simplificado:
  // No tenemos una matriz real del mapa, asi que Caleb avanza por ramas
  // cardinales alrededor de su posicion actual. Si una rama se bloquea,
  // pasa a la siguiente direccion.
  new float:x
  new float:y
  new float:z
  getLocation(x, y, z)

  if(g_dfsDirection == 0) {        // Este
    g_targetX = x + STEP_DFS
    g_targetY = y
  } else if(g_dfsDirection == 1) { // Norte
    g_targetX = x
    g_targetY = y + STEP_DFS
  } else if(g_dfsDirection == 2) { // Oeste
    g_targetX = x - STEP_DFS
    g_targetY = y
  } else {                        // Sur
    g_targetX = x
    g_targetY = y - STEP_DFS
  }

  g_dfsDirection++
  if(g_dfsDirection > 3) g_dfsDirection = 0
}

stock evitarParedes() {
  // Si Caleb detecta una pared cerca, cambia su objetivo de exploracion.
  if(sight() < WALL_DIST) {
    rotate(getDirection() + PI / 2.0)
    elegirSiguientePuntoDFS()
    walk()
  }
}

stock recogerObjetos() {
  // Si pisa un objeto util, intenta recogerlo.
  new touched = getTouched()
  if(touched) raise(touched)
}

// ================================================================
// CALEB: EXPLORADOR
// ================================================================

stock bool:calebBuscarEnemigo() {
  new item = ENEMY_WARRIOR
  new float:dist = 0.0
  new float:yaw = 0.0
  new float:pitch = 0.0
  new id = 0

  watch(item, dist, yaw, pitch, id)

  if(item == ENEMY_WARRIOR) {
    new float:x
    new float:y
    new float:z
    getLocation(x, y, z)

    // watch() devuelve distancia y angulo relativo.
    // Con eso aproximamos la posicion global del enemigo.
    new float:enemyAngle = getDirection() + yaw

    g_enemyX = x + dist * cos(enemyAngle)
    g_enemyY = y + dist * sin(enemyAngle)
    g_enemyZ = z
    g_enemyDist = dist

    g_enemyCellX = coordToCell(g_enemyX)
    g_enemyCellY = coordToCell(g_enemyY)

    g_enemyKnown = true
    g_calebDetectedEnemy = true
    g_lastEnemyTime = getTime()

    // Caleb solo mira al enemigo para confirmar deteccion.
    // No debe perseguirlo ni acercarse.
    rotate(enemyAngle)
    bendTorso(pitch)
    bendHead(-pitch)
    rotateHead(0.0)

    return true
  }

  return false
}

stock calebReportarEnemigo() {
  // Radio limitada: speak() solo envia enteros, no textos ni estructuras.
  // Por eso enviamos una celda codificada.
  new float:t = getTime()

  if(g_enemyKnown && t - g_lastReportTime > REPORT_INTERVAL) {
    new word = encodeEnemyCell(g_enemyCellX, g_enemyCellY)
    speak(RADIO_CANAL_EQUIPO, word)
    g_lastReportTime = t
  }
}

stock calebAlejarseDelEnemigo() {
  new float:x
  new float:y
  new float:z
  getLocation(x, y, z)

  // Calcula la direccion desde el enemigo hacia Caleb.
  // Es decir, el sentido contrario al enemigo.
  new float:escapeAngle = atan2(y - g_enemyY, x - g_enemyX)

  // Define un punto de escape varios metros lejos del enemigo.
  g_targetX = x + FLEE_DISTANCE * cos(escapeAngle)
  g_targetY = y + FLEE_DISTANCE * sin(escapeAngle)

  rotate(escapeAngle)

  if(getEnergy() > 20.0) run()
  else walk()

  mirarAlrededor()
}

stock calebExplorar() {
  if(llegoA(g_targetX, g_targetY)) {
    elegirSiguientePuntoDFS()
  }

  evitarParedes()
  moverHacia(g_targetX, g_targetY)
  mirarAlrededor()
}

stock ejecutar_estrategia_caleb() {
  // Inicializa variables que no conviene asignar con constantes float en memoria global.
  // El compilador SMALL 1.8 exige expresiones constantes muy estrictas en variables globales.
  g_headScanDir = SCAN_HEAD_LIMIT

  // Inicializa el primer objetivo de exploracion desde su posicion inicial.
  elegirSiguientePuntoDFS()
  walk()

  for(;;) {
    recogerObjetos()

    if(calebBuscarEnemigo()) {
        calebReportarEnemigo()

        // Caleb no debe chocar con el enemigo.
        // Si el enemigo esta cerca, se aleja inmediatamente.
        if(g_enemyDist < SAFE_ENEMY_DISTANCE) {
            calebAlejarseDelEnemigo()
        } else {
            // Si el enemigo esta lejos, solo informa y continua explorando.
            walk()
            mirarAlrededor()
        }
    } else {
    calebExplorar()
    }

    // Mensaje opcional de vida. Sirve para que luego el equipo detecte
    // ausencia de Caleb y active Rambo.
    if(getTime() - g_lastReportTime > 3.0) {
      speak(RADIO_CANAL_EQUIPO, MSG_CALEB_ALIVE)
    }
  }
}

// ================================================================
// RAMBO: PENDIENTE PARA LA SIGUIENTE ETAPA
// ================================================================

stock ejecutar_estrategia_rambo() {
  // Por ahora Rambo solo escucha informacion de Caleb.
  // Luego se implementara: seleccionar enemigo objetivo y atacarlo.
  for(;;) {
    esperar_informacion_o_apoyar()
  }
}

// ================================================================
// BOTS NORMALES: ESCUCHAN Y GUARDAN INFORMACION
// ================================================================

stock escucharRadioEquipo() {
  new word = 0
  new speakerID = 0

  if(listen(RADIO_CANAL_EQUIPO, word, speakerID)) {
    if(word >= MSG_ENEMY_BASE) {
      decodeEnemyCell(word, g_enemyCellX, g_enemyCellY)

      g_enemyX = cellToCoord(g_enemyCellX)
      g_enemyY = cellToCoord(g_enemyCellY)
      g_enemyZ = 0.0
      g_enemyKnown = true
      g_lastEnemyTime = getTime()
    }
  }
}

stock esperar_informacion_o_apoyar() {
  escucharRadioEquipo()
  recogerObjetos()
  // Por ahora los bots que no son Caleb solo esperan.
  // Esto permite observar claramente el comportamiento de Caleb.
  rotateHead(g_headScanDir)

  if(getHeadYaw() == g_headScanDir) {
    g_headScanDir = -g_headScanDir
  }
}

// ================================================================
// DETECCION DE ESTADO / ASIGNACION DE ROLES
// ================================================================

stock detectar_estado_del_bot() {
  // Referencias minimas para evitar warnings mientras algunas variables quedan preparadas
  // para la siguiente etapa de la estrategia.
  if(g_calebDetectedEnemy) {
    g_lastEnemyTime = g_lastEnemyTime
    g_enemyZ = g_enemyZ
  }

  // En esta primera version no hay mucho que detectar.
  // La funcion queda separada porque luego aqui puede agregarse:
  // - verificar si Caleb dejo de reportar;
  // - verificar si Rambo murio;
  // - reasignar roles;
  // - decidir si un bot debe atacar o apoyar.
}

fight() {
  g_headScanDir = SCAN_HEAD_LIMIT

  detectar_estado_del_bot()

  if(getID() == CALEB_ID) {
    ejecutar_estrategia_caleb()
  } else if(getID() == RAMBO_ID_INICIAL) {
    ejecutar_estrategia_rambo()
  } else {
    for(;;) {
      esperar_informacion_o_apoyar()
    }
  }
}

soccer() {
  // No utilizada
}

main() {
  switch(getPlay()) {
    case PLAY_FIGHT: fight()
    case PLAY_SOCCER: soccer()
    case PLAY_RACE: fight()
  }
}
