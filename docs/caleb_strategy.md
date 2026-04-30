# Especificación Técnica - Estrategia Caleb (DFS Exploration)

Este documento detalla la arquitectura algorítmica del bot explorador (Caleb), encargado de mapear el terreno y fungir como radar avanzado de telemetría sin involucrarse en combate directo.

### 1. Implementación del Algoritmo DFS (Depth-First Search)
Para evitar el desborde de pila (Stack Overflow) inherente a las funciones recursivas en Pawn, el DFS se implementa de forma iterativa utilizando una pila manual en memoria estática.
*   **Gestión del Stack:** Se utiliza el arreglo `g_dfsStack[DFS_STACK_SIZE]` (donde `DFS_STACK_SIZE = 64`) controlado por el puntero `g_dfsStackTop`.
*   **Flujo Base:**
    1.  `dfsInit()`: Se invoca al inicio. Calcula la celda inicial, la marca y empuja sus vecinos.
    2.  `dfsPush(idx)`: Valida que no se supere el límite de 64 nodos y que el índice no haya sido visitado (usando `isVisited()`). Si es válido, lo inyecta a la pila y lo marca de inmediato (`markVisited()`) para evitar duplicados en la cola.
    3.  `dfsPushNeighbors(col, row)`: Calcula las celdas adyacentes ortogonales. Utiliza la función `random()` para hacer un *shuffle* del array temporal de direcciones, garantizando que el árbol de exploración varíe en cada partida.
    4.  `dfsAdvance()`: Extrae el siguiente nodo con `dfsPop()`, actualiza el objetivo en el mundo real (`g_targetX`, `g_targetY`) y levanta la bandera `g_hasTarget = true`.

### 2. Mapeo del Entorno y Transformación Espacial
El motor de GunTactyx opera en un espacio euclidiano continuo, pero el DFS requiere grafos discretos. 
*   **`worldToCell(float:wx, float:wy, &col, &row)`:** Convierte coordenadas continuas (flotantes) en índices de grilla bidimensional. Aplica un desfase (`MAP_OFFSET_F = 65.0`) para evitar coordenadas negativas y divide por `CELL_SIZE_F`. Se aplica `clamp` para asegurar que los índices caigan en `[0, GRID_W - 1]`.
*   **`cellToWorld(col, row, &float:wx, &float:wy)`:** Operación inversa. Devuelve el centro geométrico de la celda elegida para orientar el avance biomecánico del bot.

### 3. Concepto y Tamaño de la "Celda"
Técnicamente, una celda es un cuadrante imaginario de **10x10 metros** (`CELL_SIZE_F = 10.0`). 
*   El mapa se define como una matriz de 14x14 (`GRID_W = 14`), totalizando 196 celdas (`GRID_TOTAL`).
*   **Estructura de Datos en Memoria:** Pawn 1.8 usa celdas de 32 bits. Para ahorrar el limitadísimo Heap Space del motor, la matriz de 196 celdas se comprime en el arreglo `g_visited[VISITED_CELLS]`, donde `VISITED_CELLS = 7`. El estado se evalúa con operaciones bitwise (shifteos): `(g_visited[idx / 32] >> (idx % 32)) & 1`.

### 4. Resiliencia y Persistencia (Caso: Muerte de Caleb)
La arquitectura actual impone restricciones específicas debido al aislamiento de memoria por instancia de bot:
*   **Trigger de Baja:** Evaluado en `ipcReportKIA()`. Si la salud cruza el umbral crítico (`getHealth() < HEALTH_LOW_F`), emite un código `MSG_CALEB_KIA` al canal `CH_CALEB_DOWN`.
*   **Pérdida Volátil (Sin persistencia global):** Al morir Caleb, la memoria del arreglo `g_visited` y la pila `g_dfsStack` **se pierden**. En el motor actual, los arreglos de memoria son locales para cada thread de bot. Ante su muerte, el sistema pasa a un estado degenerado: los Rambos en reserva interrumpen la táctica de cacería dirigida y entran en modo de defensa pasivo/reactivo permanente. No se delega la rutina DFS a otro bot.

### 5. Control de Navegación y Prevención de Atascos
*   **Validación y Evasión:** Dentro de `doDFSExplore()`, si el bot mira hacia su objetivo (`abs(turn) < FRONT_TOLERANCE_F`), invoca el sensor `aim(item)`. Si detecta pared (`frontDist < WALL_DIST_F` y `ITEM_NONE`), ejecuta un paso atrás (`walkbk()`), descarta esa rama espacial activando inmediatamente `dfsAdvance()` (haciendo un bypass o Backtracking lógico).
*   **Corrección Mecánica (`checkAntiStuck`):** Un supervisor mide la deltas vectoriales usando Pitágoras. Si `getTime() - g_stuckTime > STUCK_TIME_LIMIT_F` (3.0s) y el desplazamiento es inferior a `DIST_TWO_F` (2 metros), fuerza un escape mecánico y avanza la pila DFS.

### 6. Protocolo de Salida (Caleb -> Rambo)
Debido a la restricción nativa de `speak()` que solo permite enviar 1 *word* (entero), `ipcPrepareEnemyReport()` y `ipcTickTransmit()` fragmentan el paquete de telemetría:

| Paso de Red | Canal IPC | Valor Transmitido (Word/Int) | Descripción de la Carga |
| :--- | :--- | :--- | :--- |
| **Paso 0** | `CH_ENEMY_SPOTTED` | `MSG_ENEMY_CONTACT` (1) | Bandera (Handshake) indicando inicio de envío. |
| **Paso 1** | `CH_ENEMY_SPOTTED` | `g_ipcEnemyYawEncoded` | Orientación `Yaw` * 1000 (Miliradianes escalados). |
| **Paso 2** | `CH_ENEMY_SPOTTED` | `g_ipcEnemyDistEncoded` | Distancia truncada en metros (máx 200). |

