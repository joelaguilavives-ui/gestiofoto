# Fase 1 — Lista de comprobación

La fase 1 es la base técnica: la base de datos, los usuarios, la configuración, la auditoría y las copias de seguridad. Todavía no hay clientes ni pedidos; llegan en la fase 2.

**Dónde se prueba:** en un **portátil Mac de pruebas**, no en la tienda. El portátil hace de Mac principal. El segundo Mac se simula como se explica más abajo. Los puntos que solo se pueden comprobar con los dos Macs de la tienda están al final, para cuando se instale allí.

---

## 1. Preparar el portátil

1. **Descargar el código.** El repositorio es privado: entra en GitHub con tu cuenta y usa **Code → Download ZIP**. Mejor así que con `git clone`, que obligaría a instalar las herramientas de desarrollo de Apple en el portátil.
2. **Descargar la app.** En GitHub → **Actions**, abre la última ejecución en verde y, en **Artifacts**, descarga `GestioFoto-app`. Descomprímela y mueve `GestioFoto.app` a Aplicaciones.
3. **Primera apertura.** La app no está firmada:
   - En macOS 15 (Sequoia) o posterior: ábrela, cierra el aviso y ve a **Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente»**.
   - En macOS 14: **clic derecho → Abrir**.
   - Alternativa en Terminal: `xattr -dr com.apple.quarantine /Applications/GestioFoto.app`
4. **Postgres.app y el script.** Instala Postgres.app y ejecuta `bash Tools/setup_server/setup.sh`. Los pasos están en `Tools/setup_server/README.md`. Para las pruebas, la carpeta de copias puede ser `~/Documents/Copias GestioFoto`.
5. **Conectar.** Abre GestioFoto, marca «Este es el Mac principal», escribe el nombre de red que muestra el script, elige el `server.crt` y pon las dos contraseñas. Crea el primer usuario titular.

## 2. Criterios de la fase (PDF §9), adaptados a un solo Mac

- [ ] **Conexión por el nombre de red, como el segundo Mac.**
  1. En Ajustes → Conexión → «Cambiar la conexión…», desmarca «Este es el Mac principal».
  2. Escribe el nombre de red del portátil (`nombre.local`), elige el `server.crt` y pon solo la contraseña de `gestiofoto_app`.
  3. Debe aparecer la pantalla para iniciar sesión. Así se conecta por la red, con TLS y contraseña, igual que lo hará el segundo Mac.
  4. Después vuelve a marcarlo como Mac principal.
- [ ] **La copia nocturna se genera y se puede restaurar en una base de pruebas.**
  1. En Ajustes → Copias, pon la hora a 2 o 3 minutos vista y guarda. Al pasar esa hora debe aparecer una copia nueva. Si el portátil estaba dormido, la copia se hace al despertarlo.
  2. Pulsa «Comprobar en base de pruebas»: debe salir un resumen con las tablas y los usuarios, y la base real no debe cambiar.
  3. Después vuelve a poner la hora habitual.
- [ ] **Sin conexión.** Con la app abierta, sal de Postgres.app (menú del elefante → Quit). En unos 10 segundos debe aparecer «Sin conexión con el Mac principal» y no se debe poder trabajar. Al abrir Postgres.app de nuevo, el aviso desaparece solo.

## 3. Más comprobaciones

- [ ] **Usuarios y PIN.** Crear un segundo usuario. Probar un PIN equivocado 5 veces: el usuario queda bloqueado 5 minutos.
- [ ] **Bloqueo por inactividad.** En Ajustes → Tienda, poner 1 minuto. Dejar la app quieta y comprobar que pide el PIN de nuevo. Después, volver a poner el valor habitual.
- [ ] **Dos personas a la vez.** En Terminal, ejecuta `open -n -a GestioFoto` para abrir una segunda copia de la app. Entra con un usuario distinto en cada ventana.
  1. Abre el mismo usuario en Ajustes → Usuarios → Editar en las dos ventanas.
  2. Guarda primero en una y después en la otra.
  3. La segunda debe avisar de que otra persona lo ha cambiado, no sobrescribir en silencio.
- [ ] **Auditoría.** En Ajustes → Auditoría deben aparecer esos cambios, con quién los hizo y qué cambió.
- [ ] **Datos de la tienda.** Rellenar nombre, NIF, dirección, IBAN y el texto del recibo y guardar. Con dos copias de la app abiertas, la otra los muestra en menos de un minuto.
- [ ] **Hacer copia ahora.** Funciona, y la copia aparece en la lista y en la carpeta elegida.
- [ ] **Restaurar.** Hacer un cambio, restaurar una copia anterior y comprobar tres cosas: el cambio ha desaparecido, se ha guardado una copia «Antes de restaurar» y la app pide volver a entrar.

## 4. Volver a empezar y dejar el portátil limpio

- **Empezar de cero** (por ejemplo, si una versión nueva de la app avisa de que «la migración ya aplicada ha cambiado»): cierra la app y ejecuta `bash Tools/setup_server/reiniciar_base.sh`. Deja la base vacía y conserva contraseñas, conexión y copias.
- **Al terminar todas las pruebas, el portátil tiene que quedar limpio.** Ejecuta `bash Tools/setup_server/desinstalar.sh`, que quita:
  - GestioFoto.app, su configuración, cachés, permisos y contraseñas del Llavero;
  - la copia nocturna, los scripts y las copias de GestioFoto de la carpeta de copias;
  - **Postgres.app entera**, con el servidor y todos sus datos. Si Postgres.app tuviera otras bases que no son de GestioFoto, no la quita y avisa.

  Después, a mano:
  - [ ] Borrar la carpeta del proyecto y el ZIP descargado.
  - [ ] Si diste «Acceso total al disco» a `/bin/bash`, quitarlo en Ajustes del Sistema → Privacidad y seguridad.
  - [ ] Si «postgres» aparece en el cortafuegos, quitarlo en Ajustes del Sistema → Red → Cortafuegos → Opciones.

Los dos scripts piden escribir BORRAR. No deben usarse nunca en el Mac de la tienda.

## 5. Pendiente para la instalación en la tienda

Esto no se puede probar con un solo portátil:

- [ ] El segundo Mac de verdad se conecta al principal por la red de la tienda.
- [ ] Con el Mac principal **apagado** (no solo con Postgres.app cerrado), el segundo Mac muestra el aviso «Sin conexión».
- [ ] Dos personas trabajando a la vez desde dos Macs distintos.
- [ ] Las copias se guardan en el disco o la carpeta definitivos (Time Machine o disco externo) y la copia nocturna funciona varios días seguidos.

En el desarrollo ya se han probado: el esquema SQL y sus reglas, la numeración con dos conexiones a la vez, los scripts de copia y restauración, y la lógica de Swift (pruebas automáticas en GitHub Actions).
