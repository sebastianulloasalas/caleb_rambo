// caleb_rambo_v3.sma
// Version 3: estrategia Caleb integrada con ipc_contract.inc.
//
// Objetivo actual:
// - Caleb explora el mapa.
// - Si Caleb ve un enemigo, reporta yaw y distancia usando el contrato IPC.
// - Caleb no persigue al enemigo: informa y mantiene distancia.
// - Los demas bots escuchan la informacion recibida.
// - Rambo queda preparado para implementarse despues.

#include "core"
#include "math"
#include "bots"
#include "ipc_contract"

// -----------------------------------------------------------------------------
// CONSTANTES GENERALES

new const float:PI = 3.1415
new const float:TWO_PI = 6.2830

new const float:STEP_DFS = 12.0     // Distancia entre puntos de exploracion de Caleb.
new const float:ARRIVE_DIST = 2.0   // Distancia para considerar que Caleb llego a un punto.
new const float:WALL_DIST = 4.0     // Si hay pared cerca, Caleb cambia de rama.
new const float:REPORT_INTERVAL = 1.0
new const float:SCAN_HEAD_LIMIT = 1.047
new const float:SAFE_ENEMY_DISTANCE = 25.0  // Distancia minima que Caleb intenta mantener frente al enemigo.
new const float:FLEE_DISTANCE = 10.0        // Distancia del punto de escape cuando Caleb ve un enemigo.
new const float:FLOAT_EPSILON = 0.05        // Tolerancia para comparacion de floats

// Filtros de objetos usados por sensores.
new const ENEMY_WARRIOR = ITEM_ENEMY | ITEM_WARRIOR

// -----------------------------------------------------------------------------
// MEMORIA LOCAL DEL BOT

new bool:g_enemyKnown = false
new float:g_enemyX = 0.0
new float:g_enemyY = 0.0
new float:g_enemyZ = 0.0
new float:g_enemyDist = 0.0
new float:g_lastEnemyTime = 0.0

new bool:g_calebDetectedEnemy = false
new float:g_lastReportTime = 0.0

// Datos crudos devueltos por watch().
// El contrato exige enviar el yaw relativo directamente, no el angulo absoluto.
new float:g_enemyYawRel = 0.0
new float:g_enemyPitchRel = 0.0

// Cola simple para transmitir los 3 mensajes IPC sin romper el cooldown de speak().
new bool:g_ipcEnemyPending = false
new g_ipcEnemyStep = 0
new g_ipcEnemyYawEncoded = 0
new g_ipcEnemyDistEncoded = 0

// Evita repetir indefinidamente el aviso de Caleb en peligro.
new bool:g_calebKiaReported = false

// Estado de exploracion tipo DFS simplificado.
new float:g_targetX = 0.0
new float:g_targetY = 0.0
new g_dfsDirection = 0
new float:g_headScanDir = 0.0        // Se inicializa en ejecutar_estrategia_caleb().


// -----------------------------------------------------------------------------
// FUNCIONES MATEMATICAS AUXILIARES

// Normalizar un ángulo para que esté dentro del rango:
// Si el ángulo es muy grande (por ejemplo 4pi), se le resta 2pi repetidamente.
// Si es muy negativo (por ejemplo -5π), se le suma 2π.
stock float:wrapPi(float:angle) {
  while(angle > PI) angle -= TWO_PI
  while(angle < -PI) angle += TWO_PI
  return angle
}

// Calcular el ángulo (dirección) hacia un punto (x, y)
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

// Calcular la distancia entre dos puntos en 2D
stock float:dist2D(float:x1, float:y1, float:x2, float:y2) {
  new float:dx = x2 - x1
  new float:dy = y2 - y1
  return sqrt(dx * dx + dy * dy)
}

// -----------------------------------------------------------------------------
// DETECCION Y MOVIMIENTO BASICO

stock mirarAlrededor() {
  // Caleb mueve la cabeza de izquierda a derecha para aumentar la probabilidad
  // de detectar enemigos con watch().
  rotateHead(g_headScanDir)

  if(abs(getHeadYaw() - g_headScanDir) < FLOAT_EPSILON) {
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
  if(abs(turn) < 0.35 && getEnergy() > 20.0) run()
  else walk()
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

  g_dfsDirection = (g_dfsDirection + 1) % 4
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

// -----------------------------------------------------------------------------
// CALEB: EXPLORADOR

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

    // Guardamos el yaw y pitch relativos entregados directamente por watch().
    g_enemyYawRel = yaw
    g_enemyKnown = true
    g_lastEnemyTime = getTime()

    g_enemyPitchRel = pitch
    g_calebDetectedEnemy = true

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

stock ipcPrepararReporteEnemigo() {
  // Prepara la secuencia:
  //  1. MSG_ENEMY_CONTACT
  //  2. yaw relativo codificado
  //  3. distancia codificada

  if(!g_enemyKnown) return

  g_ipcEnemyYawEncoded = floatround(g_enemyYawRel * YAW_SCALE)
  g_ipcEnemyDistEncoded = clamp(floatround(g_enemyDist), 0, MAX_ENCODED_DIST)
  g_ipcEnemyStep = 0
  g_ipcEnemyPending = true
}

stock ipcTransmitirReporteEnemigo() {
  // speak() tiene cooldown. Por eso NO enviamos los 3 mensajes seguidos
  // en una sola llamada lógica. Esta función intenta avanzar un paso
  // por iteración.

  if(!g_ipcEnemyPending) return

  if(g_ipcEnemyStep == 0) {
    if(speak(CH_ENEMY_SPOTTED, MSG_ENEMY_CONTACT)) {
      g_ipcEnemyStep = 1
    }
  } else if(g_ipcEnemyStep == 1) {
    if(speak(CH_ENEMY_SPOTTED, g_ipcEnemyYawEncoded)) {
      g_ipcEnemyStep = 2
    }
  } else if(g_ipcEnemyStep == 2) {
    if(speak(CH_ENEMY_SPOTTED, g_ipcEnemyDistEncoded)) {
      g_ipcEnemyStep = 0
      g_ipcEnemyPending = false
      g_lastReportTime = getTime()
    }
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

stock ipcReportarCalebEnPeligro() {
  // El contrato indica no esperar a que Caleb muera.
  // Debe reportar KIA cuando cruza HEALTH_LOW_THRESHOLD.
  if(!g_calebKiaReported && getHealth() <= HEALTH_LOW_THRESHOLD) {
    if(speak(CH_CALEB_DOWN, MSG_CALEB_KIA)) {
      g_calebKiaReported = true
    }
  }
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
      if(getTime() - g_lastReportTime > REPORT_INTERVAL && !g_ipcEnemyPending) {
        ipcPrepararReporteEnemigo()
      }

      // Caleb no debe chocar con el enemigo.
      // Si el enemigo esta cerca, se aleja inmediatamente.
      if(g_enemyDist < SAFE_ENEMY_DISTANCE) {
        calebAlejarseDelEnemigo()
      } else {
        walk()
        mirarAlrededor()
      }
    } else {
      calebExplorar()
    }

    ipcTransmitirReporteEnemigo()

    ipcReportarCalebEnPeligro()

    wait(0.05)
  }
}

fight() {
  if(getID() == CALEB_ID) {
    ejecutar_estrategia_caleb()
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
