# DOCUMENTO 2: Especificación Técnica - Estrategia Rambo (Combat & Pursuit)

Este documento especifica la rutina estocástica y balística de los bots asignados como ejecutores (Rambos). Estos operan como máquinas de estados finitos dependientes de la inteligencia externa (Caleb) y de la cadena de mando interna del escuadrón.

### 1. Escucha Activa y Trigger (Interrupción de Estado)
Los bots de combate operan predominantemente en `standbyLoop()`, ahorrando ciclos de CPU con `wait(STANDBY_LOOP_WAIT_F)`.
*   **Monitoreo (Polling):** La función central de extracción de red es `ipc_pollIncoming()`.
*   **Procesamiento Asíncrono:** La función bloquea brevemente su hilo con un `while` y sub-tiempos `wait(IPC_POLL_WAIT_F)` escuchando el canal `CH_ENEMY_SPOTTED` hasta conseguir las 3 piezas del paquete de datos de Caleb.
*   **Despertar (Trigger):** Al validar el paquete (`seqOK`), desencripta el `yaw` dividiendo por `YAW_UNSCALE_F` y activa la bandera global `g_enemyContactActive = true`. El bucle principal detecta este flag, rompe la pasividad, orienta el cuerpo hacia la posición inyectada (`rotate(getDirection() + g_lastEnemyYaw)`) y acelera con `run()`.

### 2. Lógica de Sucesión (Switching Activo)
El rol de "Rambo Activo" es exclusivo. Si el Rambo en curso (`runAssaultCycle()`) sufre daños críticos mortales, se activa el relevo automático:
*   **Detección:** En Pawn nativo no existen manejadores de eventos (event listeners) de muerte. Se utiliza el polling constante `if(getHealth() <= 0.0)` en cada ciclo de `runAssaultCycle()`.
*   **Cálculo del Sucesor (`selectNextRamboID`):** La función incrementa su propio ID (`g_ramboID + 1`). Utiliza un loop `while` sobre la cantidad de aliados (`getMates()`) evaluando un wrap-around circular `candidate >= totalMates`. Omite siempre por validación al ID `0` (Chief) y al `1` (Caleb).
*   **Transferencia (Context Switch):** 
    1. El moribundo emite el nuevo ID al aire: `speak(CH_RAMBO_ACTIVE, g_ramboID)`.
    2. Hace `return`, muriendo lógicamente en el script.
    3. Todos los bots en `standbyLoop()` están escuchando `CH_RAMBO_ACTIVE`. Reciben el nuevo ID y actualizan su variable local.
    4. El bot de reserva que evalúa `if(g_ramboID == getID())` aprueba la cláusula, sale del loop de reserva y sube un nivel de contexto en la función orquestadora `fight()`, que lo dirige inmediatamente a instanciar su propio `runAssaultCycle()`.

### 3. Algoritmo de Ataque y Persecución
Una vez en estado activo, el Rambo prioriza la letalidad intentando optimizar el tipo de arma usada en base a la trigonometría.
*   **Movimiento Biomecánico:** En `runAssaultCycle()`, extrae telemetría directa utilizando `watch()`. Si hay contacto (`ITEM_ENEMY|ITEM_WARRIOR`), se ajusta la orientación absoluta mediante `rotate(yaw + getDirection())`. Los ejes Y/Z del torso y la cabeza se alinean al enemigo cancelando el declive (`bendTorso(pitch)`, `bendHead(-pitch)`).
*   **Evaluación Balística (`chooseWeapon`):**
    Esta función modular toma la variable `dist` y prioriza el mayor daño:
    *   **Evaluación de Granadas:** Si el bot cuenta con carga (`getGrenadeLoad() > 0`) y el enemigo está en el arco parabólico óptimo (`> GRENADE_MIN_F` y `< GRENADE_MAX_F`).
    *   **Anti-Fuego Amigo:** Previo a gatillar, la función proyecta un vector imaginario (`aim(aimTarget)`). Si el objeto devuelto es `ITEM_FRIEND|ITEM_WARRIOR`, el disparo se inhibe totalmente abortando el `launchGrenade()` o el `shootBullet()`.
    *   **Arma Primaria:** Si falla el chequeo de granadas pero el campo visual a través de `aim` está despejado, ejecuta el método nativo `shootBullet()`.
*   **Fallo de Visión:** Si pierde contacto visual, retrocede al último vector entregado por IPC. Si falla, hace fallback auditivo utilizando `hear()`. Si oye armas enemigas (`ITEM_ENEMY|ITEM_GUN`), pivota instantáneamente al origen del estruendo y corre hacia él.
