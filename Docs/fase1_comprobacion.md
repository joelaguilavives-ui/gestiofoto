# Fase 1 — Lista de comprobación para el titular

La fase 1 es la base técnica: la base de datos, los usuarios, la configuración, la auditoría y las copias de seguridad. Todavía no hay clientes ni pedidos; llegan en la fase 2.

**Antes de empezar:**

- Descarga la app (`GestioFoto.zip`) desde la última ejecución correcta de GitHub Actions, en el apartado «Artifacts».
- Descomprímela y muévela a Aplicaciones en los dos Macs.
- La primera vez, ábrela con **clic derecho → Abrir**, porque la app no está firmada.

## Preparación

- [ ] Instalar Postgres.app en el Mac principal y ejecutar `Tools/setup_server/setup.sh`. Los pasos están en `Tools/setup_server/README.md`.
- [ ] Abrir la app en el Mac principal, conectar y crear el primer usuario titular.

## Criterios de la fase (PDF §9)

- [ ] **El segundo Mac se conecta al principal por su nombre de red.** En el segundo Mac, escribe `nombre.local`, elige el `server.crt` y pon la contraseña de `gestiofoto_app`. Debe aparecer la pantalla para iniciar sesión.
- [ ] **La copia nocturna se genera y se puede restaurar en una base de pruebas.**
  - Al día siguiente, en Ajustes → Copias, debe aparecer una copia de la noche anterior.
  - Pulsa «Comprobar en base de pruebas»: debe salir un resumen con las tablas y los usuarios, y la base real no debe cambiar.
- [ ] **Con el principal apagado, el segundo Mac muestra el aviso «Sin conexión con el Mac principal».** Apaga el principal, o cierra Postgres.app, con la app abierta en el segundo Mac. En unos 10 segundos debe aparecer el aviso y no se debe poder trabajar. Al volver a encender, el aviso desaparece solo.

## Más comprobaciones

- [ ] **Usuarios y PIN.** Crear un segundo usuario. Probar un PIN equivocado 5 veces: el usuario queda bloqueado 5 minutos.
- [ ] **Bloqueo por inactividad.** En Ajustes → Tienda, poner 1 minuto. Dejar la app quieta y comprobar que pide el PIN de nuevo. Después, volver a poner el valor habitual.
- [ ] **Dos personas a la vez.** Abrir el mismo usuario en Ajustes → Usuarios → Editar en los dos Macs y guardar en los dos. El segundo debe ver un aviso de que otra persona lo ha cambiado, no sobrescribir en silencio.
- [ ] **Auditoría.** En Ajustes → Auditoría deben aparecer esos cambios, con quién los hizo y qué cambió.
- [ ] **Datos de la tienda.** Rellenar nombre, NIF, dirección, IBAN y el texto del recibo, guardar y ver que el otro Mac los muestra (se actualiza en menos de un minuto).
- [ ] **Hacer copia ahora.** Funciona, y la copia aparece en la lista y en la carpeta elegida.
- [ ] **Restaurar** (opcional, mejor con datos de prueba). Restaurar una copia, comprobar que se ha guardado una copia «Antes de restaurar» y que la app pide volver a entrar.

## Solo se puede comprobar en los Macs de la tienda

Estos puntos no se pueden probar desde el entorno de desarrollo (Windows y GitHub Actions):

- el Llavero;
- launchd (la copia nocturna);
- la conexión real entre los dos Macs con TLS;
- el aviso «sin conexión» con el Mac principal apagado;
- el aspecto de las pantallas.

En el desarrollo sí se han probado:

- el esquema SQL y sus reglas;
- la numeración con dos conexiones a la vez;
- los scripts de copia y restauración;
- la lógica de Swift (las pruebas automáticas se ejecutan en GitHub Actions).
