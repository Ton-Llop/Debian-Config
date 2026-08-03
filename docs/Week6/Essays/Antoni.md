# Reflection Essay — Antoni

## Introducción

Este proyecto me ha servido para ver que la administración de sistemas no consiste solo en instalar paquetes o lanzar scripts, sino en tener en cuenta muchos detalles pequeños que pueden romper todo el flujo. Al trabajar semana a semana, he visto que gran parte del esfuerzo real está en detectar errores que a primera vista parecen menores, pero que en la práctica bloquean la automatización, los backups o el arranque de servicios.

## Lo más desafiante del proyecto

Lo más difícil ha sido precisamente controlar esos detalles de configuración que no se ven al principio. Por ejemplo, uno de los errores más molestos fue el de permisos dentro del propio repositorio, con mensajes como `error: permisos insuficientes para agregar un objeto a la base de datos del repositorio .git/objects`. Ese tipo de fallo no parece muy grave cuando lo lees, pero en realidad te corta el flujo de trabajo y te obliga a revisar propietarios, permisos y desde qué usuario se están ejecutando ciertos pasos.

Otro problema importante fue el de los locks. En nuestro caso, el instalador 08 y el script de backup 04 usaban el mismo lock (`/var/lock/gsx-week1.lock`). Cuando el instalador llegaba al paso final e intentaba arrancar el servicio de backup, todavía mantenía el lock activo, así que el propio backup interpretaba que ya había una ejecución en curso y abortaba. La solución fue liberar el lock justo antes de arrancar el servicio, y dejarlo reflejado al final del script 8 para que pudiera ejecutarse correctamente.

Otra parte exigente fue la documentación. Antes tendía a pensar que documentar era algo secundario, pero en este proyecto vimos que si un compañero o un administrador nuevo no puede entender qué has montado, entonces el sistema no está realmente terminado. Explicar bien la arquitectura, los pasos de instalación, los runbooks y los posibles fallos llevó bastante tiempo, pero también fue una de las partes más útiles.

## Qué haría diferente si empezara otra vez

Si empezara de nuevo, dedicaría más tiempo desde el principio a definir una estructura fija del proyecto y unas reglas claras para nombres, rutas y configuración. Durante el proyecto fuimos mejorando la organización, pero haberlo cerrado desde la semana 1 nos habría evitado algunos cambios y retrabajo posteriores. También probaría cada script en una instalación más limpia con más frecuencia, porque a veces algo funcionaba en una máquina ya preparada, pero no en un entorno realmente nuevo.

## Cómo ha cambiado mi visión de la administración de sistemas

Antes de este proyecto tenía una visión más superficial de la administración de sistemas. Pensaba más en tareas visibles, como instalar servicios, configurar SSH o montar backups. Ahora entiendo que por debajo hay muchas cosas de fondo que no se ven, pero que hay que tener muy controladas: permisos, propietarios, estados previos del sistema, interacción entre scripts, servicios de `systemd`, temporizadores, logs, idempotencia y recuperación ante fallos.

En otras palabras, ahora veo mucho más claro que un sistema no está bien hecho solo porque “funcione”, sino porque además se puede volver a desplegar, se puede mantener, se puede entender y se puede arreglar cuando algo falla. Esa parte de robustez y operabilidad es seguramente lo que más me ha cambiado la perspectiva.

## Qué me gustaría aprender más a partir de aquí

Después de este proyecto, me gustaría profundizar más en seguridad interna de sistemas y en temas relacionados con el kernel. Me interesa especialmente entender mejor la seguridad de procesos internos, cómo se aíslan, qué mecanismos reales ofrece Linux para limitar recursos o reducir impacto ante fallos, y cómo encajan ahí cosas como `cgroups`, capacidades, namespaces o políticas más avanzadas de protección.

