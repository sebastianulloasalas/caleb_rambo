#if defined _ipc_contract_included
  #endinput
#endif
#define _ipc_contract_included

// =============================================================================
// CANALES DE RADIO

// Canal de Mando: Sólo el Jefe (ID 0) transmite aquí. El resto del equipo escucha.
#define CH_CHIEF_TX          0

// Canal de Reportes: Caleb y Rambos transmiten aquí. Sólo el Jefe (ID 0) escucha.
#define CH_CHIEF_RX          1

// =============================================================================
// CÓDIGOS DE MENSAJES (words)
//
// El parámetro `word` de speak/listen/say/hear es un entero.
// Definimos constantes semánticas para evitar "magic numbers".

// Comando atómico del Jefe ordenando a Caleb que inicie su DFS
#define CMD_START_EXPLORE    999

// Comando de asignación de rol. El Jefe suma el ID del bot a este valor.
#define CMD_WAKE_RAMBO_BASE  1000

// Caleb detectó al menos un enemigo. Rambo debe leer las coordenadas
// publicadas via CH_ENEMY_SPOTTED en los mensajes siguientes.
#define MSG_ENEMY_CONTACT   1

// Caleb no detecta enemigos en su sector actual.
#define MSG_SECTOR_CLEAR    2

// Caleb notifica su eliminación
#define MSG_CALEB_KIA       3

// Rambo activo notifica su eliminación
#define MSG_RAMBO_KIA       12

// =============================================================================
// PROTOCOLO DE COORDENADAS
//
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

// Factor de escala para codificar float yaw a int (miliradianes).
// yaw ∈ [-π, π] entonces encode: floatround(yaw * YAW_SCALE) ∈ [-3142, 3142]
#define YAW_SCALE           1000

// Factor de escala inverso para decodificar int a float yaw.
// yaw_float = float(encoded_yaw) / YAW_UNSCALE
#define YAW_UNSCALE         1000.0

// Distancia máxima esperada (metros). Valor mayor se trunca a este límite.
#define MAX_ENCODED_DIST    200

// =============================================================================
// CONSTANTES DE IDENTIFICACIÓN DE ROL ESTÁTICOS
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

// =============================================================================
// UMBRALES TÁCTICOS Y BALÍSTICOS

// Umbral de salud para considerar un bot "en peligro" y priorizar su relevo.
// Valor en puntos de salud (default max = 100.0).
#define HEALTH_LOW_THRESHOLD  25.0

// Distancia máxima (metros) dentro de la cual Rambo considera atacar con
// granada en lugar de bala (debe coincidir con la lógica de Caleb si aplica).
#define GRENADE_MIN_RANGE   30.0
#define GRENADE_MAX_RANGE   60.0

// =============================================================================
// TIEMPOS MÁXIMOS DE ESPERA DE COMUNICACIÓN
//
// Tiempos máximos de espera en bucles de comunicación.
// Previenen bloqueos si el script remoto no responde.

// Máximo de iteraciones esperando la secuencia de coordenadas de Caleb.
// A ~10Hz de CPU: 50 iteraciones ≈ 5 segundos de espera máxima.
#define IPC_RECV_MAX_TRIES  50

// Tiempo de yield dentro de bucles de espera IPC (segundos).
#define IPC_POLL_WAIT       0.1
