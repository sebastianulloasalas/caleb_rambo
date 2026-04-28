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

#include "core"
#include "math"
#include "bots"
#include "ipc_contract"

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
  new const ENEMY_WARRIOR = ITEM_ENEMY|ITEM_WARRIOR
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
    new item      = ENEMY_WARRIOR
    new float:dist  = 0.0
    new float:yaw   = 0.0
    new float:pitch = 0.0
    watch(item, dist, yaw, pitch)

    // Rama A: Enemigo visible
    if(item == ENEMY_WARRIOR) {
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

// -----------------------------------------------------------------------------
// COMPORTAMIENTO SOCCER (estándar)

soccer() {
  new const float:PI             = 3.1415
  new const float:AVOID_WALL_DIR = (getID()%2 == 0 ? PI/10.0 : -PI/10.0)
  new const float:CHANGE_DIR_TIME= 10.0
  new float:lastTime = getTime()

  rotate(getDirection() + PI * 2.0)

  new float:dist
  new float:yaw
  new item
  do {
    item = ITEM_TARGET
    dist = 0.0
    watch(item, dist, yaw)
    wait(0.05) // yield: do-while siempre debe ceder
  } while(item != ITEM_TARGET)

  rotate(getDirection() + yaw)
  setKickSpeed(getMaxKickSpeed())
  bendTorso(0.3)
  bendHead(-0.3)

  new float:waitTime = 3.0 - getTime() + lastTime
  if(waitTime > 0.0)
    wait(waitTime)
  walk()
  wait(0.1)

  for(;;) {
    wait(0.05) // yield: bucle principal soccer
    new float:now = getTime()
    if(now - lastTime > CHANGE_DIR_TIME) {
      lastTime = now
      rotate(getDirection() + (float(random(2)) - 0.5) * PI)
    } else if(isStanding()) {
      rotate(getDirection() + (float(random(2)) - 0.5) * PI)
      wait(1.0)
      walk()
    } else if(sight() < 2.0) {
      rotate(getDirection() + AVOID_WALL_DIR)
    }
    new touched = getTouched()
    if(touched) raise(touched)
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
  switch(getPlay()) {
    case PLAY_FIGHT:  fight()
    case PLAY_SOCCER: soccer()
    case PLAY_RACE:   fight() // Sin código específico para RACE aún
  }
}
