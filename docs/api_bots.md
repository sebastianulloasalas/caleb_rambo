# GunTactyx Bot API - Enciclopedia Completa

## 1) Alcance y fuentes

Este documento cubre **todas** las funciones disponibles para programar bots en esta build (1.1.5), tomando como fuente directa:

- `bots/bots.inc` (API especifica de bots)
- `bots/core.inc` (funciones base del lenguaje)
- `bots/math.inc` (funciones y operadores de punto flotante)
- `engine/engn.inc` (API de tuning global por script de engine)
- `GUN-TACTYX-manual.htm` (semantica y comportamiento esperado)

Cobertura validada por conteo real del codigo:

- `bots/bots.inc`: 109 funciones nativas
- `bots/core.inc`: 16 funciones nativas
- `bots/math.inc`: 25 funciones nativas + 26 operadores stock
- `engine/engn.inc`: 2 funciones nativas

## 2) Convenciones clave

- Unidad de distancia: metros.
- Unidad de tiempo: segundos.
- Angulos: radianes.
- Varios metodos devuelven informacion por referencia (`&param`) ademas del valor de retorno.
- Para tiempos de enfriamiento/latencia:
  - `getTimeNeededFor(...)`: cooldown entre acciones.
  - `getTimeLostTo(...)`: tiempo de CPU bloqueado por sensores.
- Defaults (si no modificas el tuning del motor): ver `engine/default.sma`.
  - Coste de sensores (CPU): `SIGHT=0.01`, `AIM/HEAR/WATCH/LISTEN=0.04`.
  - Cooldowns: `SAY=0.5`, `SPEAK=0.25`, `MOVE=1.0`, `DROP=0.5`, `SHOOT=0.5`.

## 3) Enums y constantes de `bots.inc`

### 3.1 Objetivo de partida

- `GOAL_TERMINATE_CHIEF = 0`
- `GOAL_TERMINATE_TEAM`
- `GOAL_CAPTURE_SIGN`

### 3.2 Tipo de partida

- `PLAY_FIGHT = 0`
- `PLAY_SOCCER`
- `PLAY_RACE`

### 3.3 Atributos de objeto observado

- `ATTRIBUTE_NONE = 0`
- `ATTRIBUTE_HAS_GUN`
- `ATTRIBUTE_HAS_SIGN`

### 3.4 Tipos de sonido

- `SOUND_NONE = 0`
- `SOUND_SHOT`
- `SOUND_LAUNCH`
- `SOUND_BOOM`

### 3.5 Tipos de accion (timings)

- `ACTION_MOVE = 0`
- `ACTION_DROP`
- `ACTION_SHOOT`
- `ACTION_SAY`
- `ACTION_HEAR`
- `ACTION_SIGHT`
- `ACTION_AIM`
- `ACTION_WATCH`
- `ACTION_SPEAK`
- `ACTION_LISTEN`

### 3.6 Tipos de item (bitmask)

- `ITEM_NONE = 0`
- `ITEM_FRIEND = 1`
- `ITEM_ENEMY = 2`
- `ITEM_WARRIOR = 4`
- `ITEM_GUN = 8`
- `ITEM_BULLET = 16`
- `ITEM_GRENADE = 32`
- `ITEM_MEDIKIT = 64`
- `ITEM_FOOD = 128`
- `ITEM_ARMOR = 256`
- `ITEM_BULLETS = 512`
- `ITEM_GRENADES = 1024`
- `ITEM_SIGN = 2048`
- `ITEM_TARGET = 4096`

## 4) API completa de `bots/bots.inc` (109 metodos)

## 4.1 Contexto de partida y simulacion

| Firma | Explicacion breve |
|---|---|
| `getGoal()` | Devuelve el objetivo activo (`GOAL_*`). |
| `getPlay()` | Devuelve el modo de juego (`PLAY_*`). |
| `getTeams()` | Numero de equipos en la partida. |
| `getMates()` | Numero de bots por equipo. |
| `getTimeout()` | Duracion de la partida. |
| `getKilledEnemies()` | Enemigos eliminados por este bot. |
| `getKilledFriends()` | Fuego amigo causado por este bot. |
| `bool:getGoalLocation(team,&float:x,&float:y,&float:z=0.0)` | Coordenadas del goal/spawn de un equipo cuando aplica. |
| `float:getGoalSize()` | Tamano del area de goal. |
| `float:getTargetSize()` | Tamano del target (balon en soccer). |
| `float:getTargetMaxSpeed()` | Velocidad maxima del target. |
| `float:getTime()` | Tiempo de simulacion transcurrido. |
| `getTicksCount()` | Ticks de CPU virtual transcurridos. |
| `float:getSimulationStep()` | Paso fijo del simulador (dt). |
| `float:getCPUPeriod()` | Periodo del tick de CPU virtual. |
| `float:getTimeNeededFor(action)` | Cooldown de una accion (`ACTION_*`). |
| `float:getTimeForRespawn(item)` | Tiempo de respawn de powerup por item. |
| `float:getTimeLostTo(action)` | Latencia de CPU al llamar sensores/escucha. |
| `float:getGravity()` | Gravedad global. |
| `float:getGroundElasticity()` | Restitucion del suelo (rebotes). |

## 4.2 Identidad, posicion y estado corporal

| Firma | Explicacion breve |
|---|---|
| `getMemorySize()` | RAM virtual asignada al bot. |
| `getID()` | ID del bot dentro del equipo (chief suele ser 0). |
| `getLocation(&float:x,&float:y,&float:z=0.0)` | Posicion absoluta del bot. |
| `float:getSize()` | Tamano horizontal del bot (collision box). |
| `float:getHeight()` | Altura actual del bot (de pie/agachado). |
| `float:getWeaponHeight()` | Altura de referencia del arma/sensor de apuntado. |
| `float:getWeaponLength()` | Longitud de referencia del arma. |
| `bool:isStanding()` | Esta de pie. |
| `bool:isCrouched()` | Esta agachado. |
| `bool:isWalking()` | Camina hacia adelante. |
| `bool:isWalkingcr()` | Camina agachado. |
| `bool:isWalkingbk()` | Camina hacia atras. |
| `bool:isRunning()` | Esta corriendo. |
| `bool:isRotating()` | Sigue rotando cuerpo (yaw de piernas) hacia objetivo. |
| `bool:isTorsoRotating()` | Sigue rotando torso. |
| `bool:isHeadRotating()` | Sigue rotando cabeza. |
| `bool:isTorsoBending()` | Sigue inclinando torso (pitch). |
| `bool:isHeadBending()` | Sigue inclinando cabeza (pitch). |

## 4.3 Acciones de movimiento y orientacion

| Firma | Explicacion breve |
|---|---|
| `bool:stand()` | Cambia a estado de pie si cooldown lo permite. |
| `bool:crouch()` | Cambia a estado agachado si procede. |
| `bool:walk()` | Caminar hacia adelante. |
| `bool:walkcr()` | Caminar agachado. |
| `bool:walkbk()` | Caminar hacia atras. |
| `bool:run()` | Correr (requiere energia). |
| `bool:rotate(float:angle)` | Orienta piernas/cuerpo a un angulo absoluto. |
| `bool:rotateTorso(float:angle)` | Orienta torso relativo a piernas. |
| `bool:rotateHead(float:angle)` | Orienta cabeza relativo a torso. |
| `bool:bendTorso(float:angle)` | Inclina torso (pitch). |
| `bool:bendHead(float:angle)` | Inclina cabeza (pitch). |
| `bool:wait(float:time)` | Suspende ejecucion del script por tiempo dado. |
| `float:getDirection()` | Yaw absoluto de marcha (piernas). |
| `float:getRotSpeed()` | Velocidad de giro del cuerpo. |
| `float:getTorsoYaw()` | Yaw relativo del torso. |
| `float:getTorsoMinYaw()` | Limite minimo de yaw de torso. |
| `float:getTorsoMaxYaw()` | Limite maximo de yaw de torso. |
| `float:getTorsoPitch()` | Pitch actual del torso. |
| `float:getTorsoMinPitch()` | Limite minimo de pitch de torso. |
| `float:getTorsoMaxPitch()` | Limite maximo de pitch de torso. |
| `float:getTorsoRotSpeed()` | Velocidad de rotacion del torso. |
| `float:getHeadYaw()` | Yaw relativo de la cabeza. |
| `float:getHeadMinYaw()` | Limite minimo de yaw de cabeza. |
| `float:getHeadMaxYaw()` | Limite maximo de yaw de cabeza. |
| `float:getHeadPitch()` | Pitch actual de la cabeza. |
| `float:getHeadMinPitch()` | Limite minimo de pitch de cabeza. |
| `float:getHeadMaxPitch()` | Limite maximo de pitch de cabeza. |
| `float:getHeadRotSpeed()` | Velocidad de rotacion de cabeza. |
| `float:getAngleOfView()` | Semiangulo de vision usado por `watch()`. |
| `float:getSensorsRange()` | Alcance maximo de sensores. |

## 4.4 Percepcion y comunicacion

| Firma | Explicacion breve |
|---|---|
| `bool:say(word)` | Comunica por voz local (aire), con cooldown. |
| `bool:speak(channel,word)` | Comunica por radio en canal especifico. |
| `bool:listen(channel,&word,&id=0)` | Lee palabra de radio en canal; devuelve emisor. |
| `float:hear(&item,&sound,&float:yaw=0.0,&float:pitch=0.0,&id=0)` | Oye evento mas cercano segun filtro, con direccion y distancia. |
| `watch(&item,&float:dist,&float:yaw=0.0,&float:pitch=0.0,&id=0)` | Ve objetos por filtro/campo visual; retorna atributo (`ATTRIBUTE_*`). |
| `float:sight()` | Distancia a pared frente a la cabeza. |
| `float:aim(&item)` | Distancia a objetivo en linea de mira del arma o pared. |

### 4.4.1 Detalles practicos (manual + defaults)

- `say(word)`
  - Transmite por aire (solo cercanos). Cooldown: `getTimeNeededFor(ACTION_SAY)` (default `0.5`).
  - Retorna `true` si pudo hablar; `false` si fue demasiado pronto.
- `speak(channel,word)`
  - Transmite por radio (no por aire). Cooldown: `getTimeNeededFor(ACTION_SPEAK)` (default `0.25`).
  - Puede fallar si el canal no esta libre.
- `listen(channel,&word,&id=0)`
  - Retorna `true` si alguien hablo en ese canal.
  - `id`: para amigos es el ID real; para enemigos es un entero aleatorio (no te da la identidad real).
  - Consume `getTimeLostTo(ACTION_LISTEN)` (default `0.04`).
- `hear(&item,&sound,&yaw=0.0,&pitch=0.0,&id=0)`
  - **`item` es filtro de entrada**: debe setearse antes de llamar.
    - `0`: reporta el sonido mas cercano entre voz, disparos y explosiones.
    - `ITEM_GUN`: descarta voz; reporta disparos/boom.
    - `ITEM_GRENADE`: solo explosiones.
  - Retorna la **distancia** al sonido y escribe:
    - `item`: `ITEM_GUN` / `ITEM_GRENADE` / `ITEM_WARRIOR`, OR con `ITEM_FRIEND` o `ITEM_ENEMY`; o `ITEM_NONE` si no se oye nada.
    - `sound`: `SOUND_SHOT` / `SOUND_LAUNCH` / `SOUND_BOOM` o la `word` si `item` es `ITEM_WARRIOR`.
    - `yaw/pitch`: direccion **relativa a la cabeza** (ver nota de rotacion abajo).
    - `id`: solo relevante si `item` es `ITEM_WARRIOR` (amigo real / enemigo aleatorio).
  - Consume `getTimeLostTo(ACTION_HEAR)` (default `0.04`). Si disparas/hablas durante el `hear()`, puedes oirte a ti mismo (si el filtro lo permite).
- `sight()`
  - Distancia a la pared mas cercana justo delante de la cabeza (torso + cabeza afectan el rayo).
  - Consume `getTimeLostTo(ACTION_SIGHT)` (default `0.01`).
- `aim(&item)`
  - Distancia al guerrero mas cercano delante del **laser de punteria** del arma (si no hay, devuelve pared).
  - `item`: `ITEM_WARRIOR|ITEM_FRIEND`, `ITEM_WARRIOR|ITEM_ENEMY` o `ITEM_NONE` (pared).
  - Consume `getTimeLostTo(ACTION_AIM)` (default `0.04`). Nota: la bala hereda velocidad del bot, asi que la trayectoria puede diferir del rayo.
- `watch(&item,&dist,&yaw=0.0,&pitch=0.0,&id=0)`
  - **`item` y `dist` son entrada/salida**: ambos deben setearse antes de llamar.
    - `item`: filtro (p.ej. `ITEM_WARRIOR`, `ITEM_GUN`, `ITEM_SIGN`, `ITEM_TARGET`...); `ITEM_FRIEND/ITEM_ENEMY` solo combinan con `WARRIOR/BULLET/GRENADE`.
    - `dist`: distancia minima (sirve para “saltar” el mas cercano y buscar el siguiente).
  - Retorna `ATTRIBUTE_*` solo si ve un guerrero (arma o sign); si no, `ATTRIBUTE_NONE`.
  - Si no ve nada, escribe `item = ITEM_NONE`.
  - Consume `getTimeLostTo(ACTION_WATCH)` (default `0.04`).
- Nota (rotacion absoluta): `yaw` de `hear/watch` es relativo a la cabeza. Para encarar el objetivo:
  - `rotate(getDirection()+getTorsoYaw()+getHeadYaw()+yaw)`

## 4.5 Movimiento especial de soccer

| Firma | Explicacion breve |
|---|---|
| `float:getMaxKickSpeed()` | Velocidad maxima transferible al target. |
| `float:getKickSpeed()` | Velocidad de patada configurada actual. |
| `float:setKickSpeed(float:speed)` | Ajusta y devuelve la velocidad efectiva de patada. |

## 4.6 Energia, salud, armadura e inventario

| Firma | Explicacion breve |
|---|---|
| `float:getWalkSpeed()` | Velocidad de caminar. |
| `float:getWalkcrSpeed()` | Velocidad de caminar agachado. |
| `float:getWalkbkSpeed()` | Velocidad de caminar hacia atras. |
| `float:getRunSpeed()` | Velocidad de correr. |
| `float:getFallMaxSpeed()` | Velocidad vertical maxima de caida sobrevivible. |
| `float:getEnergy()` | Energia actual. |
| `float:getMaxEnergy()` | Energia maxima. |
| `float:getRunEnergyLoss()` | Consumo de energia al correr. |
| `float:getStandEnergyGain()` | Regeneracion al estar de pie quieto. |
| `float:getHealth()` | Salud actual. |
| `float:getMaxHealth()` | Salud maxima. |
| `float:getBulletHealthLoss()` | Danio base de bala (antes de armadura). |
| `float:getGrenadeMaxDamage()` | Danio maximo de granada en proximidad. |
| `float:getArmor()` | Armadura actual. |
| `float:getMaxArmor()` | Armadura maxima. |
| `getOwned()` | Item sostenido por el bot (`ITEM_GUN`, `ITEM_SIGN`, `ITEM_NONE`). |
| `getTouched()` | Ultimo item/objeto tocado. |
| `float:getDropAmount(item)` | Cantidad minima o fija soltada por tipo de item. |
| `bool:drop(item)` | Suelta item/recurso si reglas y cooldown lo permiten. |
| `bool:raise(item)` | Recoge item tocado si procede. |

### 4.6.1 Detalles de `drop/raise/getTouched`

- `getTouched()` reporta el item tocado (base para decidir `raise(item)`).
- `raise(item)`
  - El `item` **debe** ser el mismo reportado por `getTouched()`.
  - Si levantas un `sign` o un arma, aplica un cooldown compartido: debe pasar al menos `getTimeNeededFor(ACTION_DROP)` antes de volver a `shoot/raise/drop`.
- `drop(item)`
  - Los chiefs no pueden soltar el `sign` cuando el goal es `GOAL_TERMINATE_CHIEF`.
  - Soltar `sign` o arma tambien activa el cooldown compartido con `shoot/raise/drop`.

## 4.7 Armas y municion

| Firma | Explicacion breve |
|---|---|
| `bool:shootBullet()` | Dispara bala si hay municion y cooldown. |
| `float:getBulletSpeed()` | Velocidad base de bala. |
| `getBulletLoad()` | Balas actuales. |
| `getBulletMaxLoad()` | Capacidad maxima de balas. |
| `bool:launchGrenade()` | Lanza granada si hay municion y cooldown. |
| `float:getGrenadeSpeed()` | Velocidad inicial de granada. |
| `getGrenadeLoad()` | Granadas actuales. |
| `getGrenadeMaxLoad()` | Capacidad maxima de granadas. |
| `getGrenadeMaxRange()` | Radio maximo de efecto de granada. |
| `getGrenadeDelay()` | Retardo de explosion de granada. |
| `getExplosionTimeLen()` | Duracion de evento sonoro de explosion. |

### 4.7.1 Detalles de `shootBullet/launchGrenade`

- Ambos requieren que haya pasado `getTimeNeededFor(ACTION_SHOOT)` desde el ultimo disparo (default `0.5`).
- `shootBullet()`
  - Direccion: piernas + torso (por la orientacion del arma).
  - La bala **no** cae por gravedad.
  - Velocidad efectiva: composicion de velocidad del arma + velocidad del bot.
- `launchGrenade()`
  - Direccion inicial: piernas + torso.
  - La granada **si** es afectada por gravedad.
  - Velocidad efectiva: composicion de velocidad del arma + velocidad del bot.

## 5) API base de `bots/core.inc` (16 metodos)

| Firma | Explicacion breve |
|---|---|
| `heapspace()` | Memoria libre de heap del bot/script. |
| `numargs()` | Numero de argumentos recibidos en funcion variadica. |
| `getarg(arg, index=0)` | Lee argumento variadico (o elemento de array). |
| `setarg(arg, index=0, value)` | Escribe argumento variadico por indice. |
| `strlen(const string[])` | Longitud de cadena en caracteres. |
| `strpack(dest[], const source[])` | Convierte/copia cadena a formato packed. |
| `strunpack(dest[], const source[])` | Convierte/copia cadena a formato unpacked. |
| `seed(value)` | Inicializa o reinicia semilla de random. |
| `random(max)` | Entero pseudoaleatorio en rango `[0, max-1]`. |
| `min(value1, value2)` | Minimo entero. |
| `max(value1, value2)` | Maximo entero. |
| `clamp(value, min=cellmin, max=cellmax)` | Acota valor a un rango. |
| `print(const string[])` | Imprime texto en consola del script. |
| `printint(value)` | Imprime entero. |
| `printflt(float:value)` | Imprime flotante. |
| `printf(const string[], ...)` | Formateo estilo C (`%c %d %f %s`). |

## 6) API matematica de `bots/math.inc`

### 6.1 Enum de redondeo

- `floatround_round`
- `floatround_floor`
- `floatround_ceil`

### 6.2 Nativas (25)

| Firma | Explicacion breve |
|---|---|
| `float:float(value)` | Convierte entero a float. |
| `float:floatstr(const string[])` | Convierte string a float. |
| `float:floatmul(float:oper1, float:oper2)` | Multiplicacion float. |
| `float:floatdiv(float:dividend, float:divisor)` | Division float. |
| `float:floatadd(float:dividend, float:divisor)` | Suma float. |
| `float:floatsub(float:oper1, float:oper2)` | Resta float. |
| `float:floatfract(float:value)` | Parte fraccionaria. |
| `floatround(float:value, floatround_method:method=floatround_round)` | Redondeo configurable. |
| `floatcmp(float:fOne, float:fTwo)` | Comparacion float (-1, 0, 1). |
| `float:operator*(float:oper1, float:oper2) = floatmul` | Operador `*` entre floats. |
| `float:operator/(float:oper1, float:oper2) = floatdiv` | Operador `/` entre floats. |
| `float:operator+(float:oper1, float:oper2) = floatadd` | Operador `+` entre floats. |
| `float:operator-(float:oper1, float:oper2) = floatsub` | Operador `-` binario entre floats. |
| `float:abs(float:value)` | Valor absoluto. |
| `float:acos(float:value)` | Arcocoseno. |
| `float:asin(float:value)` | Arcoseno. |
| `float:atan(float:value)` | Arcotangente. |
| `float:cos(float:value)` | Coseno. |
| `float:exp(float:value)` | Exponencial. |
| `float:log(float:value)` | Logaritmo natural. |
| `float:mod(float:oper1,float:oper2)` | Modulo en flotante. |
| `float:pow(float:base,float:exp)` | Potencia. |
| `float:sin(float:value)` | Seno. |
| `float:sqrt(float:value)` | Raiz cuadrada. |
| `float:tan(float:value)` | Tangente. |

### 6.3 Operadores stock incluidos (26)

Estos operadores ya vienen implementados en `math.inc` para simplificar expresiones mixtas int/float:

- `operator++(float:oper)`
- `operator--(float:oper)`
- `operator-(float:oper)` (unario)
- `operator*(float:oper1, oper2)`
- `operator/(float:oper1, oper2)`
- `operator/(oper1, float:oper2)`
- `operator+(float:oper1, oper2)`
- `operator-(float:oper1, oper2)`
- `operator-(oper1, float:oper2)`
- `operator==(float:oper1, float:oper2)`
- `operator==(float:oper1, oper2)`
- `operator!=(float:oper1, float:oper2)`
- `operator!=(float:oper1, oper2)`
- `operator>(float:oper1, float:oper2)`
- `operator>(float:oper1, oper2)`
- `operator>(oper1, float:oper2)`
- `operator>=(float:oper1, float:oper2)`
- `operator>=(float:oper1, oper2)`
- `operator>=(oper1, float:oper2)`
- `operator<(float:oper1, float:oper2)`
- `operator<(float:oper1, oper2)`
- `operator<(oper1, float:oper2)`
- `operator<=(float:oper1, float:oper2)`
- `operator<=(float:oper1, oper2)`
- `operator<=(oper1, float:oper2)`
- `operator!(float:oper)`

## 7) API de `engine/engn.inc` (scripts de tuning global)

Estos metodos no son para la IA individual de cada bot en combate, sino para scripts de configuracion del motor (carpeta `engine`).

| Firma | Explicacion breve |
|---|---|
| `setVariable(variable,float:value)` | Escribe una variable global del simulador. |
| `float:getVariable(variable)` | Lee una variable global del simulador. |

### 7.1 Indices de variables de engine (enum)

`engn.inc` define los indices para `setVariable/getVariable`.

- Memoria/CPU/simulacion: `BOT_MEMORY_SIZE`, `BOT_CPU_FREQUENCY`, `SIMULATION_TIME_STEP`.
- Powerups init/respawn: `POWERUP_*`.
- Tamano/espaciado bot: `BOT_SIZE_*`, `BOT_SPACING`.
- Costes de tiempo por accion: `BOT_TIME_LOST_TO_*`, `BOT_TIME_NEEDED_TO_*`.
- Cinematica bot: `BOT_SPEED_*`, `BOT_KICK_SPEED_MAX`, `BOT_SPEED_VERTICAL_MAX`.
- Energia/salud/armadura: `BOT_ENERGY_*`, `BOT_HEALTH_*`, `BOT_ARMOR_*`.
- Limites de torso/cabeza: `BOT_TORSO_*`, `BOT_HEAD_*`, `BOT_SENSORS_DISTANCE_MAX`.
- Arma: `WEAPON_*`.
- Mundo: `WORLD_GRAVITY`, `ARENA_SIZE`, `GOAL_SIZE`, `TARGET_SIZE`, `TARGET_MAX_SPEED`, `GROUND_RESTITUTION`.

Para defaults reales ver `engine/default.sma`.

## 8) Funciones especialmente interesantes (recomendadas)

- `watch(...)`: vision filtrada por tipo de item, distancia minima y direccion relativa.
- `hear(...)`: inteligencia reactiva por sonidos (disparo, lanzamiento, explosion, voz).
- `aim(&item)`: evita fuego amigo al comprobar si hay aliado en la linea de tiro.
- `getTimeNeededFor(...)` y `getTimeLostTo(...)`: base para controlar ritmo de decisiones y costo de sensores.
- `say/speak/listen`: coordinacion de escuadron (aire + radio por canal).
- `getGoal()/getPlay()`: permite adaptar estrategia segun objetivo y modo.
- `setKickSpeed(...)`: micro-control tactico del balon en soccer.
- `getOwned()/drop()/raise()`: logica de soporte y manejo de recursos/sign.

## 9) Notas de precision importantes

- **Fuente canonica de firma**: para compilar, manda lo que dicen los `.inc`.
- En el apendice A estan las firmas `native ...` copiadas verbatim para que puedas comparar/validar.
- En el manual aparecen nombres historicos como `getGunHeight/getGunLength`; en esta build los nombres exportados son `getWeaponHeight/getWeaponLength`.
- `watch(...)` retorna un `cell` (entero) que actua como `ATTRIBUTE_*`.
- El valor de `yaw` en `hear/watch` es relativo a cabeza (normalmente se convierte a angulo absoluto sumando direccion de piernas + torso + cabeza).

## 10) Cobertura final

Checklist de cobertura de este documento:

- API bot (`bots/bots.inc`): 109/109
- API core (`bots/core.inc`): 16/16
- API math nativa (`bots/math.inc`): 25/25
- Operadores stock (`bots/math.inc`): 26/26
- API engine (`engine/engn.inc`): 2/2

Total cubierto: **178 entradas** (152 nativas + 26 stock).

## 11) Apendice A — Firmas `native` exactas (copiadas de los `.inc`)

> Este apendice existe para tener una “fuente canonica” pegada en el mismo documento.
> Si tu objetivo es compilar o validar cobertura, estas lineas son las que deben coincidir.

### 11.1 `bots/core.inc` (nativas)

```pawn
native heapspace();

native numargs();
native getarg(arg, index=0);
native setarg(arg, index=0, value);

native strlen(const string[]);
native strpack(dest[], const source[]);
native strunpack(dest[], const source[]);

native seed(value);
native random(max);

native min(value1, value2);
native max(value1, value2);
native clamp(value, min=cellmin, max=cellmax);

native print(const string[]);
native printint(value);
native printflt(float:value);
native printf(const string[], ...);
```

### 11.2 `bots/math.inc` (nativas)

```pawn
native float:float(value);
native float:floatstr(const string[]);
native float:floatmul(float:oper1, float:oper2);
native float:floatdiv(float:dividend, float:divisor);
native float:floatadd(float:dividend, float:divisor);
native float:floatsub(float:oper1, float:oper2);
native float:floatfract(float:value);
native floatround(float:value, floatround_method:method=floatround_round);
native floatcmp(float:fOne, float:fTwo);

native float:operator*(float:oper1, float:oper2) = floatmul;
native float:operator/(float:oper1, float:oper2) = floatdiv;
native float:operator+(float:oper1, float:oper2) = floatadd;
native float:operator-(float:oper1, float:oper2) = floatsub;

native float:abs(float:value);
native float:acos(float:value);
native float:asin(float:value);
native float:atan(float:value);
native float:cos(float:value);
native float:exp(float:value);
native float:log(float:value);
native float:mod(float:oper1,float:oper2);
native float:pow(float:base,float:exp);
native float:sin(float:value);
native float:sqrt(float:value);
native float:tan(float:value);
```

### 11.3 `bots/bots.inc` (nativas)

```pawn
native getGoal();
native getPlay();
native getTeams();
native getMates();
native getTimeout();
native getKilledEnemies();
native getKilledFriends();
native bool:getGoalLocation(team,&float:x,&float:y,&float:z=0.0);
native float:getGoalSize();
native float:getTargetSize();
native float:getTargetMaxSpeed();
native float:getTime();
native getTicksCount();
native float:getSimulationStep();
native float:getCPUPeriod();
native float:getTimeNeededFor(action);
native float:getTimeForRespawn(item);
native float:getTimeLostTo(action);
native getMemorySize();
native getID();
native getLocation(&float:x,&float:y,&float:z=0.0);
native float:getSize();
native float:getHeight();
native float:getWeaponHeight();
native float:getWeaponLength();
native bool:isStanding();
native bool:isCrouched();
native bool:isWalking();
native bool:isWalkingcr();
native bool:isWalkingbk();
native bool:isRunning();
native bool:stand();
native bool:crouch();
native bool:walk();
native bool:walkcr();
native bool:walkbk();
native bool:run();
native bool:rotate(float:angle);
native bool:isRotating();
native bool:rotateTorso(float:angle);
native bool:isTorsoRotating();
native bool:rotateHead(float:angle);
native bool:isHeadRotating();
native bool:bendTorso(float:angle);
native bool:isTorsoBending();
native bool:bendHead(float:angle);
native bool:isHeadBending();
native bool:wait(float:time);
native bool:say(word);
native bool:speak(channel,word);
native bool:listen(channel,&word,&id=0);
native float:hear(&item,&sound,&float:yaw=0.0,&float:pitch=0.0,&id=0);
native float:getMaxKickSpeed();
native float:getKickSpeed();
native float:setKickSpeed(float:speed);
native float:getWalkSpeed();
native float:getWalkcrSpeed();
native float:getWalkbkSpeed();
native float:getRunSpeed();
native float:getFallMaxSpeed();
native watch(&item,&float:dist,&float:yaw=0.0,&float:pitch=0.0,&id=0);
native float:sight();
native float:aim(&item);
native float:getEnergy();
native float:getMaxEnergy();
native float:getRunEnergyLoss();
native float:getStandEnergyGain();
native float:getHealth();
native float:getMaxHealth();
native float:getBulletHealthLoss();
native float:getGrenadeMaxDamage();
native float:getArmor();
native float:getMaxArmor();
native getOwned();
native getTouched();
native float:getDropAmount(item)
native bool:drop(item);
native bool:raise(item);
native float:getDirection();
native float:getRotSpeed();
native float:getTorsoYaw();
native float:getTorsoMinYaw();
native float:getTorsoMaxYaw();
native float:getTorsoPitch();
native float:getTorsoMinPitch();
native float:getTorsoMaxPitch();
native float:getTorsoRotSpeed();
native float:getHeadYaw();
native float:getHeadMinYaw();
native float:getHeadMaxYaw();
native float:getHeadPitch();
native float:getHeadMinPitch();
native float:getHeadMaxPitch();
native float:getHeadRotSpeed();
native float:getAngleOfView();
native float:getSensorsRange();
native bool:shootBullet();
native float:getBulletSpeed();
native getBulletLoad();
native getBulletMaxLoad();
native bool:launchGrenade();
native float:getGrenadeSpeed();
native getGrenadeLoad();
native getGrenadeMaxLoad();
native getGrenadeMaxRange();
native getGrenadeDelay();
native getExplosionTimeLen();
native float:getGravity();
native float:getGroundElasticity();
```

### 11.4 `engine/engn.inc` (nativas)

```pawn
native setVariable(variable,float:value);
native float:getVariable(variable);
```
