# Contrato de Integración — Estrategia Caleb × Estrategia Rambo

> **Versión:** 1.0
> **Motor:** GUN-TACTYX build 1.1.5
> **Archivo de contrato compartido:** `ipc_contract.inc`
> **Audiencia:** Equipo de desarrollo de `bots_caleb.sma`

## 1. Análisis de Viabilidad: Desacoplamiento en Pawn/AMX

### 1.1 ¿Puede Pawn soportar una "Interfaz" o "Clase Abstracta"?

**Respuesta directa: No en el sentido POO clásico.** Pawn es un lenguaje procedural sin herencia, sin vtables y sin tipos de objeto. Sin embargo, el desacoplamiento real se logra mediante tres mecanismos que el motor sí soporta:

| Mecanismo POO equivalente | Implementación en Pawn/GUN-TACTYX |
|---|---|
| Interfaz / Contrato | Archivo `ipc_contract.inc` con `#define` compartidos (canales, mensajes, constantes de escala) |
| Método abstracto | Convención documentada: funciones `stock` con firma específica que cada equipo implementa |
| Canal de mensajes | `speak(channel, word)` / `listen(channel, word)` — el único IPC nativo del motor |
| Evento / Callback | Protocolo de mensajes secuenciales sobre canales de radio reservados |

### 1.2 Limitación crítica del IPC nativo

`speak()` y `listen()` transmiten **un único entero por llamada**. No existe paso de structs, arrays o floats directos. El protocolo de 3 mensajes definido en `ipc_contract.inc` es la solución canónica para transmitir un par `(yaw, distancia)`.

### 1.3 Conclusión de viabilidad

El desacoplamiento **es plenamente viable** si ambos equipos:
1. Incluyen `ipc_contract.inc` sin modificarlo unilateralmente.
2. Respetan la secuencia y el timing del protocolo de mensajes.
3. No asumen nada del estado interno del script del otro equipo.

---

## 2. Mapa de Comunicación

```
┌─────────────────────────────────────────────────────────────┐
│                    ipc_contract.inc                         │
│  (Verdad única — nunca modificar sin coordinación mutua)    │
└────────────────────┬────────────────────────────────────────┘
                     │ #include en ambos scripts
         ┌───────────┴───────────┐
         ▼                       ▼
┌─────────────────┐     ┌─────────────────────┐
│  bots_caleb.sma │     │   bots_rambo.sma     │
│  (Exploración)  │     │   (Asalto Táctico)   │
└────────┬────────┘     └──────────┬───────────┘
         │                         │
         │  speak(CH_ENEMY_SPOTTED, MSG_ENEMY_CONTACT)
         │  speak(CH_ENEMY_SPOTTED, yaw_encoded)
         │  speak(CH_ENEMY_SPOTTED, dist_encoded)
         ├────────────────────────►│  ipc_pollIncoming()
         │                         │  reconstruye (yaw, dist)
         │                         │
         │  speak(CH_CALEB_DOWN, MSG_CALEB_KIA)
         ├────────────────────────►│  g_calebKIA = true
         │                         │  → runAssaultCycle()
         │                         │
         │                        ◄│  speak(CH_RAMBO_ACTIVE, MSG_RAMBO_ACK)
         │  (ACK opcional)         │
         │                         │
```

---

## 3. Reglas Obligatorias para el Equipo Caleb

### REGLA 1 — Incluir el contrato sin modificarlo

```pawn
// OBLIGATORIO como primera línea de includes
#include "ipc_contract"
```

Nunca redefinir `CH_ENEMY_SPOTTED`, `CH_CALEB_DOWN`, `CH_RAMBO_ACTIVE` ni los `MSG_*` localmente. Si se requiere un cambio, coordinar con ambos equipos y actualizar la versión del contrato.

### REGLA 2 — Protocolo de reporte de contacto enemigo (3 mensajes en orden)

Cuando Caleb detecta un enemigo, **debe emitir exactamente esta secuencia** en el canal `CH_ENEMY_SPOTTED`:

```pawn
// Paso 1: señal de inicio de secuencia
speak(CH_ENEMY_SPOTTED, MSG_ENEMY_CONTACT)

// Paso 2: yaw codificado en miliradianes (entero)
// yaw es el ángulo relativo a la cabeza de Caleb (float, en radianes)
new encodedYaw = floatround(yaw * YAW_SCALE)
speak(CH_ENEMY_SPOTTED, encodedYaw)

// Paso 3: distancia al enemigo (metros, truncada a entero)
new encodedDist = clamp(floatround(dist), 0, MAX_ENCODED_DIST)
speak(CH_ENEMY_SPOTTED, encodedDist)
```

**Restricciones de timing:**
- Los 3 mensajes deben emitirse en la **misma iteración de bucle** o en iteraciones consecutivas sin `wait()` mayor a `IPC_POLL_WAIT` (0.1s) entre ellos.
- Si el cooldown de `speak()` impide la emisión inmediata, reintentar en la siguiente iteración. **No fragmentar la secuencia con waits largos**.
- El valor de `yaw` debe ser el valor **directo** retornado por `watch()`, sin convertirlo a ángulo absoluto (Rambo realiza su propia conversión).

### REGLA 3 — Evento de muerte de Caleb

Cuando la salud de Caleb llegue a 0 (o sea inminente), emitir **antes de morir**:

```pawn
if(getHealth() <= HEALTH_LOW_THRESHOLD) {
  // Emitir en el canal de relevo de emergencia
  speak(CH_CALEB_DOWN, MSG_CALEB_KIA)
  // Continuar lógica local (el motor determina la muerte efectiva)
}
```


> [!IMPORTANT]
> El motor no garantiza ejecución de código tras la muerte. Emitir el evento al cruzar el umbral `HEALTH_LOW_THRESHOLD` (25.0 HP), **no** esperar a llegar a 0.

### REGLA 4 — Escuchar el ACK de Rambo (opcional pero recomendado)

Para confirmar que el relevo fue exitoso:

```pawn
new ackWord
if(listen(CH_RAMBO_ACTIVE, ackWord)) {
  if(ackWord == MSG_RAMBO_ACK) {
    // Rambo confirmó activación. Caleb puede ajustar su comportamiento.
  }
}
```

Esta escucha es **no bloqueante** (nunca hacer `do-while` esperando este ACK).

### REGLA 5 — Formato de datos del protocolo

| Dato | Tipo en Pawn | Rango válido | Fórmula de encoding |
|---|---|---|---|
| `yaw` | `float` (radianes) | `[-π, π]` | `floatround(yaw * 1000)` → entero `[-3142, 3142]` |
| `dist` | `float` (metros) | `[0.0, 200.0]` | `clamp(floatround(dist), 0, 200)` → entero `[0, 200]` |
| `MSG_*` | `int` constante | Ver `ipc_contract.inc` | Sin transformación |

El decoding en Rambo usa: `yaw_float = float(encodedYaw) / 1000.0`

### REGLA 6 — NO escribir en los canales de Rambo

Caleb **solo emite** en `CH_ENEMY_SPOTTED` y `CH_CALEB_DOWN`.
Caleb **solo escucha** en `CH_RAMBO_ACTIVE`.

Escribir en `CH_RAMBO_ACTIVE` desde Caleb corrompería el protocolo de relevo de Rambo.

### REGLA 7 — Prevención de desbordamiento en DFS

El DFS implementado por Caleb debe **nunca ser recursivo puro**. Dado que el motor asigna stack fijo por bot (`BOT_MEMORY_SIZE = 32768` bytes por defecto), una recursión profunda producirá stack overflow.

**Patrón obligatorio:** DFS iterativo con stack explícito en array local:

```pawn
// Ejemplo de estructura DFS iterativa segura
new stack[MAX_DFS_DEPTH]    // array de sectores/nodos pendientes
new stackTop = 0            // índice del tope del stack

// Push inicial
stack[stackTop++] = SECTOR_INICIAL

while(stackTop > 0) {
  wait(0.05)  // yield crítico en cada iteración del DFS
  new sector = stack[--stackTop]
  // ... procesar sector ...
  // Push vecinos no visitados
  if(stackTop < MAX_DFS_DEPTH - 1)
    stack[stackTop++] = vecino
}
```

`MAX_DFS_DEPTH` debe ser conservador. Con `BOT_MEMORY_SIZE = 32768` y overhead del runtime, no superar **64 nodos de profundidad**.

## 4. Checklist de Verificación Pre-Integración

Antes de entregar la estrategia Caleb para integración con estrategia Rambo, verificar:

- [ ] `#include "ipc_contract"` está presente y no redefinido localmente.
- [ ] La secuencia de 3 `speak()` se emite completa y en orden en `CH_ENEMY_SPOTTED`.
- [ ] El encoding de `yaw` usa `floatround(yaw * YAW_SCALE)` (1000).
- [ ] El encoding de `dist` usa `clamp(floatround(dist), 0, MAX_ENCODED_DIST)`.
- [ ] El evento `MSG_CALEB_KIA` se emite en `CH_CALEB_DOWN` al cruzar `HEALTH_LOW_THRESHOLD`.
- [ ] No se escribe en `CH_RAMBO_ACTIVE`.
- [ ] El DFS es iterativo (no recursivo) con `wait(0.05)` dentro del bucle.
- [ ] Todos los `do-while` de espera tienen contador de guardia y `wait()` interno.
- [ ] Las variables de estado del DFS están declaradas **fuera** del bucle principal.

## 5. Tabla de Referencia Rápida — Constantes del Contrato

| Constante | Valor | Uso |
|---|---|---|
| `CH_ENEMY_SPOTTED` | `0` | Canal Caleb→Rambo: contacto enemigo |
| `CH_CALEB_DOWN` | `1` | Canal Caleb→Rambo: evento de muerte |
| `CH_RAMBO_ACTIVE` | `2` | Canal Rambo→Caleb: ACK de activación |
| `MSG_ENEMY_CONTACT` | `1` | Word: inicio de secuencia de coords |
| `MSG_SECTOR_CLEAR` | `2` | Word: sector explorado sin enemigos |
| `MSG_CALEB_KIA` | `3` | Word: Caleb eliminado |
| `MSG_RAMBO_ACK` | `4` | Word: Rambo confirmó activación |
| `YAW_SCALE` | `1000` | Factor de encoding para yaw |
| `YAW_UNSCALE` | `1000.0` | Factor de decoding para yaw |
| `MAX_ENCODED_DIST` | `200` | Techo de distancia codificada (metros) |
| `IPC_RECV_MAX_TRIES` | `50` | Reintentos máx. en espera de secuencia |
| `IPC_POLL_WAIT` | `0.1` | Yield (s) entre reintentos IPC |
| `CALEB_ID` | `1` | ID reservado para el explorador |
| `RAMBO_INITIAL_ID` | `2` | ID del primer Rambo al iniciar |
| `HEALTH_LOW_THRESHOLD` | `25.0` | HP mínimo antes de emitir KIA |
| `GRENADE_MIN_RANGE` | `30.0` | Distancia mínima para granada |
| `GRENADE_MAX_RANGE` | `60.0` | Distancia máxima para granada |


*Contrato generado bajo marco técnico `BOTS_API_ENCICLOPEDIA.md` build 1.1.5.*
*Cambios a este documento requieren aprobación de ambos equipos.*
