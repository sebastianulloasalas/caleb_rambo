// Contrato de Comunicación Inter-Script
// 
// Define los canales de radio, códigos de mensaje (words) y la estructura
// lógica del protocolo Caleb <-> Rambo.

#if defined _ipc_contract_included
  #endinput
#endif
#define _ipc_contract_included

// -----------------------------------------------------------------------------
// Canales de radio

// Canal usado por Caleb para reportar contacto con enemigo.
// Caleb habla y Rambo escucha.
#define CH_ENEMY_SPOTTED    0

// Canal usado por Caleb para reportar su propia muerte (evento de relevo).
// Caleb habla y Rambo escucha.
#define CH_CALEB_DOWN       1

// Canal usado por Rambo para confirmar que tomó el control (ACK).
// Rambo habla y Caleb escucha (útil para coordinación).
#define CH_RAMBO_ACTIVE     2

// -----------------------------------------------------------------------------
// Códigos de mensaje (words)
// El parámetro `word` de speak/listen/say/hear es un entero.
// Definimos constantes semánticas para evitar "magic numbers".

// Caleb detectó al menos un enemigo. Rambo debe leer las coordenadas
// publicadas via CH_ENEMY_SPOTTED en los mensajes siguientes.
#define MSG_ENEMY_CONTACT   1

// Caleb no detecta enemigos en su sector actual.
#define MSG_SECTOR_CLEAR    2

// Caleb fue eliminado. Rambo debe asumir control ofensivo inmediato.
#define MSG_CALEB_KIA       3

// Rambo confirmó activación tras MSG_CALEB_KIA.
#define MSG_RAMBO_ACK       4

// -----------------------------------------------------------------------------
// Protocolo de coordenadas
// LIMITACIÓN CRÍTICA del motor: speak(channel, word) y listen() solo
// transmiten UN entero por llamada. No existe un tipo de mensaje compuesto.
//
// SOLUCIÓN: Protocolo de 3 mensajes secuenciales para transmitir (yaw, dist):
//
//   Mensaje 1: MSG_ENEMY_CONTACT          señal de inicio de secuencia
//   Mensaje 2: floatround(yaw * 1000)     yaw codificado en miliradianes
//   Mensaje 3: floatround(dist)           distancia en metros (entero)
//
// El receptor (Rambo) debe consumir los 3 mensajes en orden para reconstruir
// la información. Si falta alguno, Rambo descarta la secuencia incompleta.
//
// Constantes de codificación:

// Factor de escala para codificar float yaw a int (miliradianes).
// yaw ∈ [-π, π] entonces encode: floatround(yaw * YAW_SCALE) ∈ [-3142, 3142]
#define YAW_SCALE           1000

// Factor de escala inverso para decodificar int a float yaw.
// yaw_float = float(encoded_yaw) / YAW_UNSCALE
#define YAW_UNSCALE         1000.0

// Distancia máxima esperada (metros). Valor mayor se trunca a este límite.
#define MAX_ENCODED_DIST    200

// -----------------------------------------------------------------------------
// Constantes de identificación de rol
//
// El ID 0 es reservado para el Jefe del equipo (Chief). Entonces:
//   - Bot ID 0 es Chief (no asignado a Caleb ni Rambo como rol fijo)
//   - Bot ID 1 es Caleb inicial (explorador)
//   - Bot IDs 2+ es Candidatos a Rambo
//
// El rol de "Rambo activo" es dinámico: se transfiere al bot más cercano
// al último contacto enemigo cuando el Rambo actual muere.

#define CALEB_ID            1
#define RAMBO_INITIAL_ID    2

// Umbral de salud para considerar un bot "en peligro" y priorizar su relevo.
// Valor en puntos de salud (default max = 100.0).
#define HEALTH_LOW_THRESHOLD  25.0

// Distancia máxima (metros) dentro de la cual Rambo considera atacar con
// granada en lugar de bala (debe coincidir con la lógica de Caleb si aplica).
#define GRENADE_MIN_RANGE   30.0
#define GRENADE_MAX_RANGE   60.0

// -----------------------------------------------------------------------------
// Timeouts y wait
//
// Tiempos máximos de espera en bucles de comunicación.
// Previenen bloqueos si el script remoto no responde.

// Máximo de iteraciones esperando la secuencia de coordenadas de Caleb.
// A ~10Hz de CPU: 50 iteraciones ≈ 5 segundos de espera máxima.
#define IPC_RECV_MAX_TRIES  50

// Tiempo de yield dentro de bucles de espera IPC (segundos).
#define IPC_POLL_WAIT       0.1
