# Auditoría Técnica: Directorio `/bots` — GUN-TACTYX

## 1. Análisis Individual de Scripts

### Script 1: `bots_recruit.sma`

**Nombre del Script:** `bots_recruit.sma`

**Propósito:** Bot de nivel básico que patrulla aleatoriamente y dispara a cualquier enemigo visible, sin capacidad auditiva.

**Lógica Detallada:**

El script define dos funciones de comportamiento: `fight()` y `soccer()`, seleccionadas en `main()` mediante `getPlay()`.

**`fight()` — Ciclo de combate:**

1. **Inicialización:** Llama a `walk()` para comenzar el desplazamiento. Define constantes bitmask: `FRIEND_WARRIOR = ITEM_FRIEND|ITEM_WARRIOR` y `ENEMY_WARRIOR = ITEM_ENEMY|ITEM_WARRIOR`.
2. **Bucle `for(;;)` principal:**
   - **Gestión de dirección:** Cada `CHANGE_DIR_TIME = 10.0s` (medido con `getTime()`), rota a un ángulo aleatorio usando `random(3)` escalado a radianes. Si `isStanding()` (colisión con pared u otro bot), rota 90° (`1.5708 rad`) y llama `wait(1.0)` antes de reanudar `walk()`. Si `sight() < 5.0m`, gira `AVOID_WALL_DIR` (alternado por paridad de `getID()`).
   - **Recolección:** `getTouched()` → `raise(touched)` para powerups.
   - **Percepción visual:** `watch(item, dist, yaw, pitch)` con filtro `ENEMY_WARRIOR`. Si detecta enemigo: rota cuerpo (`rotate`), inclina torso y cabeza (`bendTorso`/`bendHead`) hacia el pitch del objetivo, fuerza cabeza al frente (`rotateHead(0.0)`). Acelera a `run()`.
   - **Selección de arma:** Si `getGrenadeLoad() > 0` y `30 < dist < 60`: llama `aim(item)` y si no hay amigo en línea de fuego, `launchGrenade()`. En otro caso: `aim(item)` → `shootBullet()`.
   - **Sin enemigo visible:** Desacelera a `walk()`. Oscila la cabeza con `rotateHead(headDir)`, alternando entre `+1.047` y `-1.047 rad` cuando `getHeadYaw() == headDir`. **No usa `hear()`** — es su limitación definitoria.

**`soccer()` — Comportamiento en modo fútbol:** Localiza el `ITEM_TARGET` (balón) con `watch()`, apunta con `rotate()` y corre hacia él, reorientándose cada `10s` o al detectar pared/colisión.

**Dependencias:**
- `core.inc`: `random()`, `getTime()`
- `math.inc`: Operadores float (`>`, `<`, `-`)
- `bots.inc`: `walk()`, `run()`, `rotate()`, `wait()`, `sight()`, `watch()`, `aim()`, `shootBullet()`, `launchGrenade()`, `isStanding()`, `isWalking()`, `isRunning()`, `getID()`, `getGrenadeLoad()`, `getTouched()`, `raise()`, `bendTorso()`, `bendHead()`, `rotateHead()`, `getHeadYaw()`, `getPlay()`

### Script 2: `bots_rookie.sma`

**Nombre del Script:** `bots_rookie.sma`

**Propósito:** Bot intermedio que añade percepción auditiva y coordinación vocal de escuadrón en la fase de despliegue inicial.

**Lógica Detallada:**

**`fight()` — Fase de despliegue inicial (pre-bucle):**

Este es el diferenciador clave de Rookie respecto a Recruit:
- **Jefe (`getID() == 0`):** Llama `say(1)` para emitir una orden vocal por aire.
- **Subordinados (`getID() != 0`):** Entran en un bucle `do-while` escuchando con `hear(item, sound, yaw)` hasta detectar a un amigo (`ITEM_WARRIOR | ITEM_FRIEND`). Luego rotan 180° respecto a la dirección de llegada de la señal (`rotate(getDirection() + yaw + halfTurn)`), colocándose "de espaldas" al jefe. Esto forma una formación radial explosiva.
- Todos esperan `wait(1.5)` para sincronizar la rotación antes de `walk()`.

**Bucle `for(;;)` — Combate:**

Idéntico a Recruit en navegación. Las mejoras son:
1. **Granadas lanzadas en arco alto:** Antes de `launchGrenade()`, usa `bendTorso(0.5236)` (~30°) y `wait(0.5)` para dar ángulo de elevación, evitando impactar aliados. Restaura el pitch con `bendTorso(pitch)`.
2. **Percepción auditiva:** Cuando no hay enemigo visible, llama `hear(item, sound, yaw)` con filtro `ITEM_GUN`. Si escucha un disparo enemigo (`ENEMY_GUN`), activa `run()` y rota hacia la fuente. Esto llena el vacío de Recruit ante enemigos fuera del campo visual.

**Dependencias:**
- Todo lo de Recruit.
- Adicionalmente: `say()`, `hear()` de `bots.inc`.

### Script 3: `bots_trooper.txt`

**Nombre del Script:** `bots_trooper` (extensión `.txt`, probablemente `.sma`)

**Propósito:** Bot de combate coordinado que aprovecha la formación orientada en bloque para maximizar potencia de fuego simultáneo, con detección de segundo objetivo para cobertura múltiple.

**Lógica Detallada:**

**`fight()` — Fase de despliegue inicial:**

En lugar de la comunicación vocal de Rookie, Trooper usa una táctica de orientación pasiva masiva:
- `rotate(3.1415)` — Todos los bots del equipo rotan exactamente 180°, apuntando en la misma dirección.
- `wait(2.0)` — Espera mayor que Rookie para asegurar sincronía completa del equipo.
- Luego `walk()` + `wait(0.02)`.

**Bucle `for(;;)` — Combate:**

`CHANGE_DIR_TIME = 20.0s` (el doble de Recruit/Rookie), manteniendo la formación más tiempo.

La mejora táctica principal:
- **Targeting dual:** Los bots con `getID() % 2 == 0` (IDs pares) llaman `watch()` dos veces. La segunda llamada usa la distancia del primer target como umbral mínimo (`dist`), forzando a `watch()` a buscar el **siguiente** enemigo más cercano. Si no hay segundo, restaura el primer target. Esto distribuye el fuego entre múltiples enemigos.
- **Granadas sin elevación:** A diferencia de Rookie, lanza granadas directamente sin `bendTorso()` extra — el torso ya apunta al enemigo por `pitch`.
- **Percepción auditiva:** Reactiva a disparos (`ENEMY_GUN`) con `run()` y reorientación. Sin enemigo y sin sonido: `walk()` y oscilación de cabeza.

**`AVOID_WALL_DIR = 0.31415`** — Constante fija (no alternada por ID como en Recruit/Rookie), ya que todos orientados igual hace redundante la alternancia.

**Dependencias:** Idénticas a Rookie excepto que **no usa** `say()` ni `speak()`.

### Script 4: `bots_platoon.sma`

**Nombre del Script:** `bots_platoon.sma`

**Propósito:** Variante táctica de Trooper que sacrifica movilidad por potencia de fuego máxima, alternando bots de pie y agachados para crear líneas de fuego escalonadas.

**Lógica Detallada:**

**`fight()` — Fase de despliegue inicial:**

- `rotate(3.1415)` + `wait(2.0)` — igual que Trooper.
- **Formación escalonada:** `if(getID() % 2 == 0)` → `crouch()` + `wait(1.0)` (espera obligatoria post-`crouch()`, documentada en la API) → `walkcr()`. Los IDs impares hacen `walk()` normal.
- El `wait(1.0)` post-`crouch()` es crítico: la API establece que tras `crouch()` el bot necesita 1 segundo antes de poder iniciar `walkcr()`.

**Bucle `for(;;)` — Combate:**

La diferencia clave respecto a Trooper:
- **Sin `run()`:** Al detectar un enemigo, Platoon **no** acelera. Mantiene `walkcr()` o `walk()` para preservar la formación escalonada.
- **Gestión de postura en colisión:** Si `isStanding()`, rota 45° (`0.7854 rad`, la mitad que Trooper). Los bots pares vuelven a `crouch()` → `wait(1.0)` → `walkcr()` antes de reanudar el movimiento.
- **Targeting dual:** Idéntico a Trooper — IDs pares buscan segundo objetivo con `watch()` doble.
- **No modifica `headDir`** en la rama sin enemigo auditivo (código sin `walk()`/`run()` explícito allí, dependiendo del estado previo).

**Análisis de la postura:** Los bots agachados reducen su altura (`getHeight()` menor), liberando la línea de fuego a los bots de pie detrás. Esto maximiza el número de armas disparando simultáneamente, compensando la pérdida de movilidad.

**Dependencias:**
- Todo lo de Trooper.
- Adicionalmente: `crouch()`, `walkcr()`, `isCrouched()` de `bots.inc`.

## 2. Análisis de Interacción entre Scripts

Los scripts de `/bots` **no comparten estado global ni se llaman entre sí directamente**. La arquitectura de GUN-TACTYX aísla cada instancia de bot. La comunicación es exclusivamente a través de la API del motor:

| Mecanismo | Scripts que lo usan | Descripción |
|---|---|---|
| `say(word)` / `hear()` por aire | Rookie (jefe→subordinados) | Canal de voz local para la formación inicial |
| `watch()` con `dist` como umbral | Trooper, Platoon | "Protocolo implícito" de targeting dual en IDs pares |
| `getID() % 2` | Todos | Diferenciación de roles sin comunicación directa |
| `getPlay()` en `main()` | Todos | Selección de comportamiento según modo de partida |

El único momento de **coordinación real** es el `say()/hear()` de Rookie. El resto son estrategias emergentes por convención de ID.

## 3. Ciclo de Vida del Bot

```
╔══════════════════════════════════════════════════════════════╗
║                    CICLO DE VIDA DEL BOT                     ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  [INSTANCIACIÓN]                                             ║
║       │                                                      ║
║       ▼                                                      ║
║  main() → getPlay()                                          ║
║       │                                                      ║
║       ├─ PLAY_FIGHT  → fight()                               ║
║       ├─ PLAY_SOCCER → soccer()                              ║
║       └─ PLAY_RACE   → fight() (sin código específico)       ║
║                                                              ║
║  [FASE DE DESPLIEGUE — pre-bucle]                            ║
║       │                                                      ║
║       ▼                                                      ║
║  Recruit:  walk()  →  inicio inmediato                       ║
║  Rookie:   say()/hear() → formación radial → wait(1.5)       ║
║  Trooper:  rotate(π) → wait(2.0) → walk()                   ║
║  Platoon:  rotate(π) → wait(2.0) → crouch()/walk() bifurcado ║
║                                                              ║
║  [BUCLE PRINCIPAL — for(;;)]                                 ║
║       │                                                      ║
║       ▼                                                      ║
║  ┌─────────────────────────────────────────┐                 ║
║  │  1. GESTIÓN DE MOVIMIENTO               │                 ║
║  │     ├─ Timer expirado → rotate aleatoria│                 ║
║  │     ├─ isStanding() → rotate + walk     │                 ║
║  │     └─ sight() < umbral → evasión       │                 ║
║  │                                         │                 ║
║  │  2. RECOLECCIÓN                         │                 ║
║  │     └─ getTouched() → raise()           │                 ║
║  │                                         │                 ║
║  │  3. PERCEPCIÓN VISUAL                   │                 ║
║  │     └─ watch(ENEMY_WARRIOR, dist, ...)  │                 ║
║  │                                         │                 ║
║  │  4a. ENEMIGO DETECTADO                  │                 ║
║  │     ├─ rotate(yaw + getDirection())     │                 ║
║  │     ├─ bendTorso/bendHead (pitch)       │                 ║
║  │     ├─ run() [excepto Platoon]          │                 ║
║  │     └─ aim() → shoot/launchGrenade      │                 ║
║  │                                         │                 ║
║  │  4b. SIN ENEMIGO VISIBLE                │                 ║
║  │     ├─ hear(ENEMY_GUN) [Rookie/Trooper] │                 ║
║  │     │   ├─ Disparo oído → run+rotate    │                 ║
║  │     │   └─ Silencio → walk+rotateHead   │                 ║
║  │     └─ [Recruit] → walk + rotateHead    │                 ║
║  └─────────────────────────────────────────┘                 ║
║       │                                                      ║
║       └─ (sin condición de salida — loop infinito)           ║
╚══════════════════════════════════════════════════════════════╝
```


## 4. Contexto Técnico: Bucles, Stack y el Método `wait()`

### 4.1 Bucles de ejecución y agotamiento de stack

En el lenguaje de scripting de GUN-TACTYX (basado en Pawn/AMX), cada bot ejecuta su script en un **hilo virtual de CPU** con memoria limitada (configurable via `BOT_MEMORY_SIZE`). El stack crece con cada llamada a función y con cada variable local declarada dentro de un frame de llamada.

Un bucle `for(;;)` sin ningún punto de salida o espera es **atómico desde la perspectiva del scheduler del motor**: el motor no puede interrumpirlo. Esto significa:

- El script **monopoliza el hilo** hasta que el bucle termine o ceda el control.
- Si el bucle es infinito y no cede, el motor no puede avanzar la simulación para ese bot.
- Variables locales declaradas dentro del bucle **se acumulan en el stack** si el compilador no puede optimizarlas — en entornos de ejecución cíclica ajustada, esto puede provocar stack overflow.
- El heap también puede agotarse si el bucle hace llamadas que reservan memoria temporal sin liberarla.

### 4.2 El método `wait(float:time)` — yielding y prevención de desbordamiento

`wait(time)` es el **único mecanismo documentado de yielding** en esta API. Su firma es `native bool:wait(float:time)`.

Cuando un bot llama `wait(t)`:
1. El motor **suspende la ejecución del script** por `t` segundos de simulación.
2. El hilo virtual **devuelve el control al scheduler del motor**, que puede avanzar la física, procesar otros bots y actualizar el estado global.
3. Al expirar el tiempo, el script **reanuda desde la instrucción siguiente a `wait()`**, con el stack intacto pero el estado del mundo actualizado.

Por qué previene el desbordamiento:
- Al ceder el control, el motor puede **compactar o limpiar recursos temporales** del hilo.
- El frame actual del bucle **permanece en el stack** pero no crece, ya que no se están apilando nuevas llamadas.
- Evita que el scheduler marque el script como "colgado" y lo termine forzosamente.
- Permite que la lógica de percepción (`watch`, `hear`, `sight`) tenga tiempo para actualizarse entre iteraciones, evitando polling busy que consume ciclos de CPU virtual sin resultado.

**Regla de oro:** Todo bucle `for(;;)` o `while(...)` en estos scripts debe contener al menos un `wait()` o una llamada a sensor (`watch`, `hear`, `sight`) que implique `getTimeLostTo(...)`, ya que estas llamadas también introducen latencia controlada.

---

*Auditoría generada bajo marco técnico `BOTS_API_ENCICLOPEDIA.md` build 1.1.5.*
