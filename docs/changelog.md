### 1. Análisis y Cambio Arquitectónico Propuesto

Actualmente, el sistema utiliza una arquitectura **Descentralizada (Point-to-Point)**. Caleb y los Rambos se comunican directamente a través de canales de radio (`CH_ENEMY_SPOTTED`, `CH_RAMBO_ACTIVE`). Cuando un Rambo muere, él mismo ejecuta la lógica para calcular quién será su sucesor.

Para cumplir con los requerimientos, migraremos a una arquitectura **Centralizada (Estrella / Hub-and-Spoke)** donde el Bot Jefe (`ID = 0`) actuará como el único cerebro táctico (Router y Command Center):

1.  **Nuevos Canales Lógicos:**
    *   `CH_CHIEF_TX` (Canal de Mando): Sólo el Jefe habla aquí. Caleb y Rambos escuchan.
    *   `CH_CHIEF_RX` (Canal de Reporte): Caleb y Rambos hablan aquí. Sólo el Jefe escucha.
2.  **Caleb (ID 1):** Inicia en estado de reposo absoluto. Sólo arranca el motor DFS cuando el Jefe emite el comando atómico `CMD_START_EXPLORE`. Cuando ve a un enemigo, manda las coordenadas al Jefe (no a Rambo).
3.  **Jefe (ID 0):** Implementa un loop infinito dedicado (`runChiefCycle`). Despierta a Caleb, nombra al primer Rambo, enruta la telemetría de Caleb hacia el escuadrón, y procesa las bajas (`MSG_RAMBO_KIA`) para recalcular e inyectar dinámicamente un nuevo Rambo.
4.  **Rambo (ID 2+):** Pasan a depender del evento `CMD_WAKE_RAMBO_BASE + ID` que emite el Jefe. Si mueren, simplemente envían la señal al Jefe y terminan su ejecución.

### 2. Modificación del contrato
Se eliminaron las constantes:

1.  `SG_RAMBO_ACK`. Su funcionalidad ahora no tiene importancia. La constante eliminada es:

    ```sh
    // Rambo confirmó activación tras MSG_CALEB_KIA.
    #define MSG_RAMBO_ACK       4
    ```
    
2.  Se reemplazaron los canales de radio para centralizar la lógica de decisión hacia el Chief (Jefe).
    A continuación se muestran las constantes eliminadas:

    ```sh
    // Canal usado por Caleb para reportar contacto con enemigo.
    // Caleb habla y Rambo escucha.
    #define CH_ENEMY_SPOTTED    0

    // Canal usado por Caleb para reportar su propia muerte (evento de relevo).
    // Caleb habla y Rambo escucha.
    #define CH_CALEB_DOWN       1

    // Canal usado por Rambo para confirmar que tomó el control (ACK).
    // Rambo habla y Caleb escucha (útil para coordinación).
    #define CH_RAMBO_ACTIVE     2
    ``` 

### 3. Explicación Detallada de los Cambios

1.  **Módulo `runChiefCycle()` introducido:** El bot 0 entra ahora a su propio loop. Emite `CMD_START_EXPLORE` para desencadenar el script de Caleb. Acto seguido emite `CMD_WAKE_RAMBO_BASE + 2` para despertar al Rambo inicial. Luego de esto, queda permanentemente escuchando y retransmitiendo (`listen()` seguido de `speak()`).
2.  **Transmisión de Coordenadas de Enemigos (Caleb -> Jefe -> Rambo):**
    *   La función `ipcTickTransmit()` de Caleb cambió `CH_ENEMY_SPOTTED` por el canal de subida `CH_CHIEF_RX`.
    *   El Jefe captura esos 3 enteros, y si la secuencia es exitosa (`receiveSequence`), los redirige hacia abajo usando `CH_CHIEF_TX`.
    *   `ipc_pollIncoming()` (usado por los Rambos) ahora extrae las coordenadas de `CH_CHIEF_TX` y no directamente de Caleb.
3.  **Lógica de Sucesión de Rambo Transferida:** 
    *   La función `selectNextRamboID` fue alterada para depender del estado central del Jefe en vez del propio.
    *   Si un Rambo detecta que su salud llega a 0 (`if(getHealth() <= 0.0)`), ejecuta `speak(CH_CHIEF_RX, MSG_RAMBO_KIA)` y muere lógicamente. Ya no calcula a su sucesor.
    *   El Jefe lee ese `MSG_RAMBO_KIA`, calcula y notifica al escuadrón el nuevo ID.
4.  **Asignación de Comandos Atómicos (`CMD_WAKE_RAMBO_BASE`):** Dado que en el motor de GunTactyx enviar múltiples mensajes para un simple comando puede ser propenso a desincronizaciones si muchos bots están esperando leer del canal, convertí el "ID del próximo Rambo" en un comando atómico. Sumando un offset de `1000` (Ej: el Jefe envía `1002`). El Rambo lee, ve que es mayor a 1000, le resta 1000 y se asigna el estado, todo en 1 solo `listen()`. Eliminando la necesidad de leer cadenas largas que podrían causar demoras (waits).

