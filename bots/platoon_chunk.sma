// caleb_rambo_v3.sma
// Version final: estrategia Caleb integrada con ipc_contract.inc.
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

// bots_rambo.sma: Estrategia Rambo (Asalto Táctico)
//
// Propósito: Recibir inteligencia de Caleb y ejecutar ataques coordinados.
//            Gestiona su propio ciclo de reemplazo si el Rambo activo muere.
//
// Dependencias: core.inc, math.inc, bots.inc (API GUN-TACTYX 1.1.5)
//               ipc_contract.inc (Contrato de comunicación Caleb <-> Rambo)
//
// Arquitectura: Cada instancia del bot corre este script. El rol "Rambo activo"
//               es dinámico: solo el bot cuyo ID coincide con `g_ramboID`
//               ejecuta el ciclo de asalto. Los demás hacen patrulla de espera.

// -----------------------------------------------------------------------------
// CONSTANTES LOCALES

// Ángulo de rotación de cabeza para escaneo visual (radianes).
new const float:HEAD_SCAN_ANGLE    = 1.047

// Intervalo de cambio de dirección en patrulla (segundos).
new const float:PATROL_DIR_CHANGE  = 15.0

// Distancia mínima a pared para evasión en patrulla (metros).
new const float:WALL_AVOID_DIST    = 5.0

// Ángulo de evasión de pared (alternado por ID para evitar convoyes).
// Calcula una vez, basada en paridad del ID local.
// (No puede ser `new const` con getID(), se inicializa en setup.)

// Tiempo de yield en el bucle principal de asalto (segundos).
// Previene monopolización del hilo de CPU virtual.
new const float:ASSAULT_LOOP_WAIT  = 0.05

// Tiempo de yield en el bucle de patrulla de espera (segundos).
new const float:STANDBY_LOOP_WAIT  = 0.1

// -----------------------------------------------------------------------------
// ESTADO GLOBAL DEL SCRIPT
// (Cada instancia tiene su propia copia; no son compartidas entre bots.)

// ID del bot que actualmente ejerce el rol Rambo.
// Todos los bots mantienen esta variable sincronizada via radio.
new g_ramboID = RAMBO_INITIAL_ID

// Último yaw conocido al enemigo (radianes, relativo a cabeza de Caleb).
// Rambo lo usa para orientarse al iniciar el asalto.
new float:g_lastEnemyYaw  = 0.0

// Última distancia conocida al enemigo (metros).
new float:g_lastEnemyDist = 0.0

// Flag: Caleb reportó contacto enemigo activo.
new bool:g_enemyContactActive = false

// Flag: Caleb fue eliminado, Rambo debe asumir inmediatamente.
new bool:g_calebKIA = false

// -----------------------------------------------------------------------------
// FUNCIONES AUXILIARES

// Consume todos los mensajes pendientes en los canales IPC. Actualiza el estado
// global del script (g_*). Debe llamarse al inicio de cada iteración
// del bucle principal.
// @return true si hubo al menos un mensaje nuevo, false si no.
stock bool:ipc_pollIncoming() {
  new word
  new bool:hadMessage = false

  // Canal CH_CALEB_DOWN: relevo de emergencia
  if(listen(CH_CALEB_DOWN, word)) {
    if(word == MSG_CALEB_KIA) {
      g_calebKIA = true
      hadMessage = true
    }
  }

  // Canal CH_ENEMY_SPOTTED: secuencia de coordenadas
  // Protocolo de 3 mensajes: MSG_ENEMY_CONTACT | yaw_encoded | dist_encoded
  if(listen(CH_ENEMY_SPOTTED, word)) {
    if(word == MSG_ENEMY_CONTACT) {
      // Esperar mensaje 2: yaw codificado
      new yawEncoded = 0
      new distEncoded = 0
      new tries = 0
      new bool:seqOK = false

      while(tries < IPC_RECV_MAX_TRIES) {
        wait(IPC_POLL_WAIT) // yield: no bloquear el scheduler
        if(listen(CH_ENEMY_SPOTTED, yawEncoded)) {
          // Esperar mensaje 3: distancia
          tries = 0
          while(tries < IPC_RECV_MAX_TRIES) {
            wait(IPC_POLL_WAIT)
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
        g_lastEnemyYaw    = float(yawEncoded) / YAW_UNSCALE
        g_lastEnemyDist   = float(distEncoded)
        g_enemyContactActive = true
        hadMessage = true
      }
    }
  }

  return hadMessage
}

// Notifica a Caleb (y al equipo) que Rambo está activo.
// Se llama una sola vez al asumir el rol de Rambo.
stock ipc_sendAck() {
  speak(CH_RAMBO_ACTIVE, MSG_RAMBO_ACK)
}

// Determina el ID del próximo bot que asumirá el rol Rambo.
// Criterio: el bot con ID inmediatamente superior al actual,
//           con wrap-around. Evita asignar el rol al Chief (ID 0) y a
//           Caleb (ID CALEB_ID).
//
// Limitación del motor: No hay acceso al estado de salud de otros bots.
//             El criterio es puramente por ID (round-robin). Si se requiere
//             selección por cercanía, Caleb debe reportar posiciones via IPC.
// @return Nuevo ID de Rambo.
stock selectNextRamboID() {
  new totalMates = getMates()
  new candidate  = g_ramboID + 1

  // Wrap-around circular por el equipo
  new iterations = 0
  while(iterations < totalMates) {
    if(candidate >= totalMates)
      candidate = 0

    // Saltar Chief (ID 0) y Caleb (CALEB_ID)
    if(candidate != 0 && candidate != CALEB_ID) {
      return candidate
    }
    candidate++
    iterations++
  }

  // Fallback: si todos los IDs están excluidos, usar el Chief
  return 0
}

// Decide si lanzar granada o disparar bala según distancia.
// Centraliza la lógica de selección de arma para evitar
// duplicación entre el bloque de contacto visual y el de reacción auditiva.
// @param dist distancia al objetivo (metros).
// @return true si disparó (cualquier arma), false si no pudo.
stock bool:chooseWeapon(float:dist) {
  new const FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR
  new aimTarget

  if(getGrenadeLoad() > 0 && dist > GRENADE_MIN_RANGE && dist < GRENADE_MAX_RANGE) {
    aim(aimTarget)
    if(aimTarget != FRIEND_WARRIOR) {
      launchGrenade()
      return true
    }
  }

  aim(aimTarget)
  if(aimTarget != FRIEND_WARRIOR) {
    shootBullet()
    return true
  }

  return false
}

// Lógica de patrulla reutilizable. Gestiona cambio de dirección periódico,
// evasión de paredes y colisiones. Sigue el patrón canónico de los
// scripts de referencia.
// @param lastTime referencia al timestamp del último cambio de dir.
// @param headDir referencia al ángulo de scan de cabeza.
// @param avoidDir ángulo de evasión fijo (calculado por el llamador).
stock doPatrolMovement(&float:lastTime, &float:headDir, float:avoidDir) {
  new float:now = getTime()

  if(now - lastTime > PATROL_DIR_CHANGE) {
    lastTime = now
    // Girar aleatoriamente ±90° o ±45° para variar la patrulla
    new float:angle = float(random(3) - 1) * 1.5708
    rotate(getDirection() + angle)

  } else if(isStanding()) {
    // Colisión con bot u obstáculo: girar 90° y retomar marcha
    rotate(getDirection() + 1.5708)
    wait(0.5) // yield post-rotación
    walk()

  } else if(sight() < WALL_AVOID_DIST) {
    // Pared cercana: evasión suave
    rotate(getDirection() + avoidDir)
  }
}


// -----------------------------------------------------------------------------
// COMPORTAMIENTO PRINCIPAL: ASALTO TÁCTICO

// Bucle de asalto ejecutado únicamente por el bot con ID == g_ramboID.
//  1. Recibe inteligencia de Caleb via IPC.
//  2. Busca el mejor objetivo visual.
//  3. Ataca con la mejor arma disponible.
//  4. Detecta su propia muerte y cede el rol al siguiente candidato.
runAssaultCycle() {
  new const ENEMY_WARRIOR_LOCAL = ITEM_ENEMY|ITEM_WARRIOR
  new const ENEMY_GUN     = ITEM_ENEMY|ITEM_GUN

  // Variables de estado del bucle de asalto: declaradas FUERA del for(;;)
  // para no crecer el stack por iteración.
  new float:headDir     = HEAD_SCAN_ANGLE
  new float:lastTime    = getTime()
  new float:avoidDir    = (getID() % 2 == 0) ? 0.31415 : -0.31415

  // Confirmar rol activo a Caleb
  ipc_sendAck()

  // Orientarse hacia el último contacto conocido de Caleb (si existe)
  if(g_enemyContactActive) {
    rotate(getDirection() + g_lastEnemyYaw)
    run()
  } else {
    walk()
  }

  // Bucle principal de asalto
  for(;;) {
    wait(ASSAULT_LOOP_WAIT) // yield crítico: previene monopolización del hilo

    // Verificar si este bot sigue vivo
    // El motor no notifica la muerte directamente; se infiere por salud.
    if(getHealth() <= 0.0) {
      // Este Rambo ha muerto: elegir sucesor y salir del bucle
      g_ramboID = selectNextRamboID()
      // Publicar nuevo ID por radio para sincronizar al resto del equipo.
      // Nota: speak solo envía un entero; el nuevo Rambo escucha CH_RAMBO_ACTIVE
      // y compara el word (MSG_RAMBO_ACK) + su propio ID en el siguiente ciclo.
      speak(CH_RAMBO_ACTIVE, g_ramboID)
      return // Abandona runAssaultCycle; el script entra a standbyLoop
    }

    // Consumir mensajes IPC de Caleb
    ipc_pollIncoming()

    // Recolección de powerups
    new touched = getTouched()
    if(touched) raise(touched)

    // Percepción visual: buscar enemigo
    new item      = ENEMY_WARRIOR_LOCAL
    new float:dist  = 0.0
    new float:yaw   = 0.0
    new float:pitch = 0.0
    watch(item, dist, yaw, pitch)

    // Rama A: Enemigo visible
    if(item == ENEMY_WARRIOR_LOCAL) {
      // Actualizar estado de contacto global
      g_lastEnemyYaw    = yaw
      g_lastEnemyDist   = dist
      g_enemyContactActive = true

      // Orientar cuerpo y torso al objetivo
      rotate(yaw + getDirection())
      bendTorso(pitch)
      bendHead(-pitch)
      rotateHead(0.0)

      // Maximizar movilidad ofensiva
      if(isWalking() || isStanding())
        run()

      // Selección y disparo de arma
      chooseWeapon(dist)

    // Rama B: Sin enemigo visible
    } else {
      // Reducir velocidad para conservar energía
      if(isRunning())
        walk()

      // Usar última inteligencia de Caleb para orientarse
      if(g_enemyContactActive) {
        rotate(getDirection() + g_lastEnemyYaw)
        g_enemyContactActive = false // consumir el dato; esperar siguiente reporte
      }

      // Escuchar disparos enemigos como fallback perceptivo
      new sound
      dist = hear(item, sound, yaw)
      if(item == ENEMY_GUN) {
        run()
        rotate(yaw + getDirection())
        wait(0.3) // yield post-rotación reactiva

      } else {
        // Sin información: patrullar y escanear con cabeza
        doPatrolMovement(lastTime, headDir, avoidDir)
        rotateHead(headDir)
        if(getHeadYaw() == headDir)
          headDir = -headDir
      }
    }

    // Verificar si otro Rambo fue asignado por relevo externo
    // (caso: el Chief u otro bot emitió un nuevo g_ramboID)
    // Escuchar CH_RAMBO_ACTIVE para recibir el ID del nuevo Rambo
    new newRamboWord
    if(listen(CH_RAMBO_ACTIVE, newRamboWord)) {
      // El word aquí es el nuevo ID (ver selectNextRamboID + speak)
      if(newRamboWord != MSG_RAMBO_ACK) {
        g_ramboID = newRamboWord
        // Si este bot ya no es Rambo, salir del ciclo de asalto
        if(g_ramboID != getID())
          return
      }
    }
  }
}

// -----------------------------------------------------------------------------
// COMPORTAMIENTO SECUNDARIO: ESPERA / PATRULLA

// Bucle ejecutado por bots que NO son el Rambo activo en este tick.
// Mantienen una patrulla defensiva y escuchan si son promovidos
// a Rambo (por relevo tras muerte del Rambo actual).
standbyLoop() {
  new float:lastTime  = getTime()
  new float:headDir   = HEAD_SCAN_ANGLE
  new float:avoidDir  = (getID() % 2 == 0) ? 0.31415 : -0.31415

  walk()
  wait(0.05) // yield: asegurar estado walking antes del bucle

  for(;;) {
    wait(STANDBY_LOOP_WAIT) // yield: bucle de espera menos urgente

    // Verificar si este bot fue promovido a Rambo
    new newRamboWord
    if(listen(CH_RAMBO_ACTIVE, newRamboWord)) {
      // Actualizar g_ramboID si el word es un ID (no un ACK)
      if(newRamboWord != MSG_RAMBO_ACK)
        g_ramboID = newRamboWord
    }

    // Si fui promovido, salir de standby y asumir el asalto
    if(g_ramboID == getID()) {
      return // standbyLoop retorna a fight() vuelve al switch
    }

    // Consumir mensajes de Caleb para mantener estado actualizado
    ipc_pollIncoming()

    // Verificar relevo por muerte de Caleb
    // Si Caleb cayó y este bot es el candidato más cercano disponible,
    // el Chief (u otro mecanismo) habrá asignado el nuevo g_ramboID via radio.
    // Este bot simplemente espera la confirmación de su ID.

    // Patrulla defensiva de espera
    new touched = getTouched()
    if(touched) raise(touched)

    doPatrolMovement(lastTime, headDir, avoidDir)

    // Escaneo visual pasivo (no reacciona, solo actualiza headDir)
    rotateHead(headDir)
    if(getHeadYaw() == headDir)
      headDir = -headDir
  }
}

// -----------------------------------------------------------------------------
// DISPATCHER PRINCIPAL

// Determina el rol de este bot (Rambo activo vs en espera) y
// dirige la ejecución al bucle correspondiente.
// El loop es:
// standbyLoop() hasta ser promovido, luego runAssaultCycle(),
// luuego al morir, selectNextRamboID() luego volver a standbyLoop().
fight() {
  if(getID() == CALEB_ID) {
    ejecutar_estrategia_caleb()
  } else {
    // Todos los bots arrancan en formación similar a Trooper (sincronización
    // pasiva por rotación). El Rambo inicial comienza inmediatamente el asalto.
    rotate(3.1415)
    wait(2.0) // yield: sincronización de equipo

    // El bot con RAMBO_INITIAL_ID lidera desde el inicio
    if(getID() == RAMBO_INITIAL_ID) {
      walk()
      wait(0.05)
    } else {
      walk()
      wait(0.05)
      // Esperar a escuchar si ya hay un Rambo activo antes de decidir
      new word
      listen(CH_RAMBO_ACTIVE, word) // no-blocking; descarta si no hay mensaje
    }

    // Loop de vida del bot
    // standby, asalto, muerte, de nuevo standby con nuevo ID
    for(;;) {
      wait(0.05) // yield de seguridad entre transiciones de rol

      if(g_ramboID == getID()) {
        // Este bot es el Rambo activo: ejecutar ciclo de asalto
        runAssaultCycle()
        // Si runAssaultCycle retorna, este bot murió o cedió el rol:
        // volver a standby con el nuevo g_ramboID
      } else {
        // Este bot espera: patrullar y escuchar promoción
        standbyLoop()
        // Si standbyLoop retorna, este bot fue promovido: volver al inicio
      }
    }
  }
}

// -----------------------------------------------------------------------------
// COMPORTAMIENTO SOCCER (estándar)

soccer() {
  // No utilizada
}

main() {
  switch(getPlay()) {
    case PLAY_FIGHT:  fight()
    case PLAY_SOCCER: soccer()
    case PLAY_RACE:   fight() // Sin código específico para RACE aún
  }
}
