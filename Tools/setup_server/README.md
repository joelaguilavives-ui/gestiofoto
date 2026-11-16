# Preparar el Mac principal

Se hace una sola vez, en el Mac del mostrador, que es el que guarda los datos.

## 1. Postgres.app

1. Descargar Postgres.app con PostgreSQL 16 (o posterior) desde <https://postgresapp.com> y moverlo a Aplicaciones.
2. Abrirlo y pulsar **Initialize**.
3. En los ajustes de Postgres.app, activar **Iniciar automáticamente al arrancar el Mac**.

## 2. Ejecutar el script

En el Terminal, desde la carpeta del proyecto:

```bash
bash Tools/setup_server/setup.sh
```

El script pide:

- **Dos contraseñas** de al menos 12 caracteres. Guárdalas en un sitio seguro: la app las pide una vez y las guarda en el Llavero.
  - `gestiofoto_owner`: crea y actualiza las tablas. Solo se usa en este Mac.
  - `gestiofoto_app`: el trabajo diario. Se usa en los dos Macs.
- **La carpeta de las copias de seguridad** (por ejemplo, un disco externo o una carpeta incluida en Time Machine).
- **La hora de la copia nocturna** (por defecto, las 02:00).

Lo que hace:

- Crea la base de datos `gestiofoto` y los dos usuarios.
- Abre PostgreSQL a la red local. Solo admite conexiones de la red de la tienda, cifradas con TLS y con contraseña.
- Crea un certificado TLS propio para este Mac (`server.crt`).
- Instala `backup.sh`, `restore.sh` e `instalar_agente.sh` en `~/Library/Application Support/GestioFoto/scripts` y programa la copia nocturna con launchd.

Se puede volver a ejecutar sin perder datos, por ejemplo para cambiar las contraseñas.

## 3. Primer arranque de la app

- **En este Mac:** al abrir GestioFoto, marca «Este es el Mac principal» y escribe el nombre de red que muestra el script (`algo.local`) y las dos contraseñas. Para el cifrado, elige el `server.crt` que indica el script. La app crea las tablas y pide el primer usuario titular.
- **En el segundo Mac:** copia el `server.crt` (por AirDrop o USB) y, en la app, escribe el mismo nombre de red, elige ese certificado y pon la contraseña de `gestiofoto_app`.

## Copias de seguridad

- Cada noche, `backup.sh` deja un fichero `gestiofoto_AAAA-MM-DD_HHMMSS.dump` en `diarias/`. La primera copia de cada mes se guarda también en `mensuales/`.
- Se conservan 30 copias diarias y 12 mensuales. Se puede cambiar en la app, en Ajustes → Copias.
- Si el Mac está dormido a la hora de la copia, la copia se hace al despertar.
- Los dos Macs muestran un aviso si la última copia tiene más de 2 días.
- Para comprobar una copia sin tocar nada, usa **Ajustes → Copias → Comprobar en base de pruebas**. Restaura la copia en `gestiofoto_prueba` y muestra un resumen.
- Para restaurar de verdad, usa **Restaurar…**: solo puede el titular, pide escribir RESTAURAR y, antes de restaurar, guarda el estado actual en `previas/`.

Si la copia falla al escribir en un disco externo, da **Acceso total al disco** a `/bin/bash` en Ajustes del Sistema → Privacidad y seguridad.

Registro de las copias nocturnas: `~/Library/Application Support/GestioFoto/logs/copia.log`.

## Mac de pruebas (portátil)

- Para empezar de cero con la base vacía: `bash Tools/setup_server/reiniciar_base.sh`.
- Al terminar las pruebas, para dejar el portátil limpio: `bash Tools/setup_server/desinstalar.sh`. Quita GestioFoto, la copia nocturna, las copias y **Postgres.app con todos sus datos**. Si Postgres.app tiene otras bases que no son de GestioFoto, no la quita y avisa.

Los dos scripts piden escribir BORRAR. No deben usarse nunca en el Mac de la tienda.
