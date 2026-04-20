// figura.sma - Script para formar y mover un circulo
#include "core"
#include "math"
#include "bots"

new const float:PI = 3.141592
new const float:TWO_PI = 6.283185

stock float:atan2(float:y, float:x) {
  new const float:EPS = 0.00001
  if(abs(x) < EPS) {
    if(y > 0.0) return PI/2.0
    if(y < 0.0) return -PI/2.0
    return 0.0
  }
  new float:a = atan(y/x)
  if(x < 0.0 && y >= 0.0) return a + PI
  if(x < 0.0 && y < 0.0) return a - PI
  return a
}

stock float:wrapPi(float:angle) {
  while(angle > PI) angle -= TWO_PI
  while(angle < -PI) angle += TWO_PI
  return angle
}

stock rotateTo(float:absAngle) {
  new float:cur = getDirection()
  new float:delta = wrapPi(absAngle - cur)
  if(abs(delta) > 0.05) {
    rotate(cur + delta)
  }
}

main() {
  new mates = getMates()
  new id = getID()
  
  if(mates <= 1) {
    for(;;) wait(1.0)
  }

  // Ajustamos el radio para que tengan mucho espacio
  new float:radius = 8.0 + float(mates)*0.5
  new float:myAngle = TWO_PI * float(id) / float(mates)

  new float:leaderX = 0.0
  new float:leaderY = 0.0
  new bool:leaderFound = false
  new float:lastSayTime = -1000.0

  // Fase 1: 0 - 12 seg -> Lider corre lejos de las esquinas para ganar mucho espacio
  // Fase 2: 12 - 28 seg -> Lider espera, permitiendo rellenar el circulo sin chocar las paredes del spawn
  // Fase 3: > 28 seg -> Todos rotan a la misma direccion (0.0) y caminan juntos

  for(;;) {
    new float:now = getTime()
    new float:x, float:y, float:z
    getLocation(x, y, z)

    if(id == 0) {
       // El líder transmite su posición constantemente
       if(now - lastSayTime >= getTimeNeededFor(ACTION_SAY)) {
         if(say(1234)) {
           lastSayTime = now
         }
       }
       
       if(now < 12.0) {
         // Fase 1: Correr ganando espacio
         if(sight() < 10.0) rotateTo(getDirection() + PI/2.5)
         if(isWalking() || isStanding()) run()
       } 
       else if (now < 28.0) {
         // Fase 2: Estatico para que el grupo arme el circulo
         if(isWalking() || isRunning()) stand()
       } 
       else {
         // Fase 3: Avance conjunto de expedicion
         if(sight() < 3.0) rotateTo(getDirection() + PI/3.0)
         else rotateTo(0.0) // Direccion comun
         if(isStanding()) walk()
       }
       
       wait(0.1)
       continue
    } else {
       // Seguidores buscan el ping del lider
       new item = ITEM_FRIEND | ITEM_WARRIOR
       new sound = 0
       new float:d = 0.0
       new float:yaw = 0.0
       new float:pitch = 0.0
       new hit_id = 0
       
       d = hear(item, sound, yaw, pitch, hit_id)
       if(item == (ITEM_FRIEND | ITEM_WARRIOR) && hit_id == 0 && sound == 1234) {
           new float:absDir = getDirection() + getHeadYaw() + getTorsoYaw() + yaw
           leaderX = x + d * cos(absDir)
           leaderY = y + d * sin(absDir)
           leaderFound = true
       }
    }

    if(leaderFound) {
      new float:targetX = leaderX + radius * cos(myAngle)
      new float:targetY = leaderY + radius * sin(myAngle)
      
      new float:dx = targetX - x
      new float:dy = targetY - y
      new float:dist = sqrt(dx*dx + dy*dy)
      
      // Fase 3 y a menos de 3 metros de margen
      if(now >= 28.0 && dist <= 3.0) {
        if(sight() < 3.0) rotateTo(getDirection() + PI/3.0)
        else rotateTo(0.0) // Direccion comun conjunta
        
        if(isStanding()) walk()
      } 
      else {
        // Fases 1 & 2 o estamos muy atrasados (drift)
        if(dist > 1.5) {
          new float:heading = atan2(dy, dx)
          if(sight() < 2.0) heading += PI/4.0 
          
          rotateTo(heading)
          
          if(dist > 8.0) {
             // Si el lider corrio, lo alcanzamos corriendo
             if(isStanding() || isWalking()) run()
          } else {
             if(isStanding() || isRunning()) walk()
          }
        } else {
          // Posicionado en el circulo 
          // Ajusta direccion final justo antes de marchar
          if(now > 26.0) rotateTo(0.0)
          else rotateTo(myAngle)
          
          if(isWalking() || isRunning()) stand()
        }
      }
    } else {
      // Girar para evitar quedarse atascados
      rotateTo(getDirection() + PI/8.0)
      if(isStanding()) walk()
    }
    
    wait(0.1)
  }
}
