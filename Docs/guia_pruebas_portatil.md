# Guía: probar la fase 1 en el portátil Mac

Paso a paso para instalar, probar y, al terminar, dejar el portátil limpio. Calcula una hora la primera vez.

**Requisitos:** macOS 14 (Sonoma) o posterior, un usuario administrador, internet y unos 2 GB libres.

**La lista de lo que hay que comprobar** está en [`fase1_comprobacion.md`](fase1_comprobacion.md). Esta guía explica cómo llegar hasta ahí.

---

## Paso 1 — Descargar el proyecto

1. Abre <https://github.com/joelaguilavives-ui/gestiofoto>.
2. Pulsa el botón verde **Code → Download ZIP**.
3. En Descargas, haz doble clic en el ZIP. Queda una carpeta `gestiofoto-main` con los scripts y la documentación.

No hace falta cuenta de GitHub ni `git`.

## Paso 2 — Instalar la app

1. Descarga **GestioFoto.zip** desde <https://github.com/joelaguilavives-ui/gestiofoto/releases/latest>, en el apartado «Assets».
2. Haz doble clic en el ZIP y arrastra **GestioFoto** a **Aplicaciones**.
3. **Primera apertura.** La app no está firmada por Apple, así que macOS la bloquea:
   - **macOS 15 o posterior:** abre GestioFoto y cierra el aviso con «Hecho». Ve a **Ajustes del Sistema → Privacidad y seguridad**, baja hasta «GestioFoto se ha bloqueado…» y pulsa **Abrir igualmente**. Confirma con la contraseña del Mac.
   - **macOS 14:** clic derecho sobre GestioFoto → **Abrir** → **Abrir**.

   De momento no la uses: ciérrala. Primero hay que preparar la base de datos.

## Paso 3 — Instalar Postgres.app

1. Entra en <https://postgresapp.com/downloads.html> y descarga **Postgres.app** con PostgreSQL 16 o posterior. Vale la versión recomendada.
2. Arrastra **Postgres** a **Aplicaciones** y ábrelo.
3. Pulsa **Initialize**. Aparece un servidor «Running» con un elefante en la barra de menús.

No hace falta configurar el PATH que sugiere su web.

## Paso 4 — Preparar la base de datos (Terminal)

1. Abre **Terminal** (en Aplicaciones → Utilidades) y escribe:

   ```bash
   cd ~/Downloads/gestiofoto-main
   bash Tools/setup_server/setup.sh
   ```

2. El script pregunta:

   | Pregunta | Qué responder |
   |---|---|
   | Contraseña para `gestiofoto_owner` | Una inventada, de 12 caracteres o más. **Apúntala.** |
   | Contraseña para `gestiofoto_app` | Otra distinta, de 12 caracteres o más. **Apúntala.** |
   | Carpeta para las copias | Pulsa Intro: se usa `~/Documents/Copias GestioFoto`. |
   | Hora de la copia nocturna | Pulsa Intro: las 02:00. |

   Mientras escribes las contraseñas no se ve nada; es normal.

3. Si macOS pregunta si **«postgres» puede aceptar conexiones entrantes**, pulsa **Permitir**.
4. Al terminar aparece **«Nombre de red de este Mac: algo.local»**. Apúntalo.
5. Copia el certificado al Escritorio para elegirlo fácilmente desde la app:

   ```bash
   cp ~/Library/Application\ Support/Postgres/var-*/server.crt ~/Desktop/
   ```

## Paso 5 — Primer arranque de GestioFoto

1. Abre **GestioFoto**. Sale la pantalla «Conexión con el Mac principal».
2. Rellena:
   - ☑ **Este es el Mac principal**
   - **Nombre de red:** el `algo.local` del paso 4
   - **Comprobar el certificado:** activado → **Elegir server.crt…** → Escritorio → `server.crt`
   - **Contraseña de gestiofoto_app** y **Contraseña de gestiofoto_owner**: las del paso 4
3. Pulsa **Conectar**.
   - Si macOS pregunta si GestioFoto puede **buscar dispositivos en la red local**, pulsa **Permitir**.
   - Si pregunta por el **Llavero**, pulsa **Permitir siempre**.
4. Verás «Actualizando la base de datos…» y luego **Primer usuario**. Escribe tu nombre y un PIN de 4 a 6 cifras, dos veces. Pulsa **Crear y entrar**.
5. Se abre la ventana principal, en **Ajustes**. Es la única sección que funciona en la fase 1; las demás indican en qué fase llegan.

## Paso 6 — Hacer las comprobaciones

Abre [`fase1_comprobacion.md`](fase1_comprobacion.md) y sigue los apartados 2 y 3. Algunos trucos:

- **Comprobar una copia en poco tiempo:** en Ajustes → Copias, pon la hora a 2 o 3 minutos vista y pulsa **Guardar**. También puedes usar **Hacer copia ahora**.
- **Dos personas a la vez:** en Terminal, `open -n -a GestioFoto` abre una segunda ventana independiente de la app.
- **Sin conexión:** en el elefante de la barra de menús, **Quit Postgres**. Para volver, abre Postgres.app de nuevo.
- **Probar como «segundo Mac»:** en Ajustes → Conexión → **Cambiar la conexión…**, desmarca «Este es el Mac principal». Al acabar, vuelve a marcarlo.

## Si algo falla

| Lo que ves | Qué hacer |
|---|---|
| «No responde…» o «Sin conexión con el Mac principal» | Comprueba que el elefante de Postgres.app está en la barra de menús y dice «Running». |
| «password authentication failed» | La contraseña no es la del paso 4. Si no la recuerdas, vuelve a ejecutar `setup.sh`: deja poner otras nuevas sin perder datos. |
| El certificado da error | Repite el paso 4.5 y vuelve a elegir `server.crt`. O desactiva «Comprobar el certificado», que sigue cifrando. |
| La app no deja conectar y no preguntó por la red local | Ajustes del Sistema → Privacidad y seguridad → **Red local** → activa GestioFoto. |
| «La migración … ya aplicada ha cambiado» (tras instalar una versión nueva) | Cierra la app y ejecuta `bash Tools/setup_server/reiniciar_base.sh`. Escribe BORRAR. Al abrir la app, crea de nuevo el primer usuario. |
| La copia falla | Mira el error en Ajustes → Copias y el registro: `~/Library/Application Support/GestioFoto/logs/copia.log`. |

**Para contarme cómo ha ido:** dime qué casillas han fallado, con una captura de pantalla del error. Si falló una copia, añade también el contenido de `copia.log`.

## Instalar una versión nueva

Cuando haya cambios, descarga otra vez **GestioFoto.zip** de la página de Releases y sustituye la app en Aplicaciones. Si cambian los scripts, descarga también otra vez el ZIP del proyecto (paso 1).

## Paso final — Dejar el portátil limpio

Cuando hayas terminado **todas** las pruebas:

1. Cierra GestioFoto.
2. En Terminal:

   ```bash
   cd ~/Downloads/gestiofoto-main
   bash Tools/setup_server/desinstalar.sh
   ```

   Escribe BORRAR. Quita GestioFoto, sus datos y contraseñas, la copia nocturna, las copias y **Postgres.app con todos sus datos**. Puede pedir la contraseña del Mac.
3. A mano:
   - Borra `~/Downloads/gestiofoto-main`, los dos ZIP descargados y `server.crt` del Escritorio.
   - Si diste «Acceso total al disco» a `/bin/bash`, quítalo en Ajustes del Sistema → Privacidad y seguridad → Acceso total al disco.
   - Si «postgres» aparece en Ajustes del Sistema → Red → Cortafuegos → Opciones, quítalo.
