# Esquema SQL — fases 1 y 2 (propuesta para revisar)

Ficheros:

- `migrations/0001_base.sql`: fase 1. Usuarios y PIN, auditoría, configuración, contador y triggers comunes.
- `migrations/0002_clientes_tarifa_pedidos.sql`: fase 2. Clientes, eventos, tarifa, pedidos, cobros y ajustes.
- `seed/seed.sql`: formas de pago y configuración inicial.
- `tests/reglas_fase1_2.sql`: pruebas de las reglas del apartado 4 del PDF, entre ellas el caso 63,00 − 2,00 = 61,00 €.

Mientras no se aplique en la tienda, estas migraciones se pueden editar. Después, solo se avanza con migraciones nuevas.

## Tablas

Son 16 de las 26 del PDF. Las 10 restantes (caja, banco, gastos y campañas) llegan en sus fases.

| Fase | Tabla | Para qué |
|---|---|---|
| 1 | `usuario` | Nombre, PIN (bcrypt, la app no lo puede leer), rol y bloqueo tras 5 fallos |
| 1 | `auditoria` | Cada alta, cambio y borrado, con el antes y el después. No se puede modificar ni borrar |
| 1 | `configuracion` | Clave → valor (JSON) |
| 1 | `contador` | Numeración por serie y año, sin repeticiones |
| 2 | `cliente`, `evento` | Fichas, eventos (comunión, boda…) y fusión de duplicados |
| 2 | `producto`, `tamano`, `precio` | Tarifa con histórico. Solo existen las combinaciones con precio |
| 2 | `tipo_trabajo`, `forma_pago` | Las REF del Excel (con IVA por tipo) y efectivo, Bizum y transferencia |
| 2 | `pedido`, `pedido_linea`, `pedido_estado_log` | Pedidos y presupuestos, líneas sin límite e historial de estados |
| 2 | `cobro`, `pedido_ajuste` | Cobros sin límite y ajustes (sobrante, redondeo, condonado) |

Vistas: `pedido_resumen` (subtotal, descuento, total, cobrado, ajustes, pendiente), `cliente_deuda` y `tarifa_actual`.

## Cómo se garantizan las reglas

- **Todo cambio queda firmado.** La app abre cada transacción con `set_config('app.usuario_id', …)`. Sin eso, la base de datos rechaza el cambio. El usuario «Sistema» (id 1) firma la migración del Excel y los procesos automáticos.
- **Edición a la vez.** Todas las tablas llevan `version`. La app guarda con `UPDATE … WHERE id = $1 AND version = $2`. Si no se actualiza ninguna fila, es que hay conflicto y se avisa al usuario.
- **Código de pedido.** Lo asigna un trigger con `siguiente_numero('P', año)`, que bloquea la fila del contador hasta que termina la transacción. Dos Macs a la vez nunca obtienen el mismo número. Una vez asignado, el código no cambia aunque cambie el nombre del cliente.
- **Precio.** Si la línea lleva producto y tamaño, el trigger busca el precio vigente en la fecha del pedido. Si no hay precio, rechaza la línea (regla 4.3). Si el precio es distinto del de la tarifa, marca la línea como `manual` (regla 4.2).
- **Importes.** `importe` es una columna calculada: `round(cantidad × precio × (1 − dto%), 2)`. El total nunca se guarda; se suma desde las líneas.
- **Pedidos.** No se borran (la app no tiene permiso de borrado). Anular exige motivo, y un pedido anulado no se reactiva ni admite líneas ni cobros.
- **Permisos.** La app se conecta con el rol `gestiofoto_app`, que no puede crear tablas, borrar pedidos, escribir en la auditoría ni leer los PIN.
- **Avisos al otro Mac.** Cada cambio envía `NOTIFY gestiofoto_cambios` con la tabla y el id, y la app refresca sus listas.

## Decisiones tomadas al diseñar (revisar)

1. **Presupuestos sin número.** Siguiendo el PDF, un presupuesto no tiene código hasta que se convierte en pedido. Al convertirlo, la app pone `fecha = hoy`, y ese año decide la numeración.
2. **Formato del código.** Interpreto «nombre (hasta 31 caracteres)» como que el nombre se corta a 31 caracteres. Además, se quitan `/ : \`, que no valen en el nombre de una carpeta.
3. **Signo de los ajustes.** El pendiente se calcula como total − cobros − ajustes. Por eso un «sobrante» (cobrado de más) es negativo, un «condonado» es positivo y un «redondeo» puede ser de cualquier signo.
4. **Cantidad con decimales** (`numeric(10,2)`), por si se cobra algo por metros o por horas.
5. **Datos normalizados.** Teléfonos solo con cifras (y `+` opcional), código postal de 5 cifras y NIF en mayúsculas sin espacios. La migración del Excel normaliza los datos y manda al informe los que no encajan.
6. **Dos roles de PostgreSQL.** `gestiofoto_owner` aplica las migraciones y solo lo usa la app del Mac principal al arrancar. `gestiofoto_app` es el de trabajo diario. Así se cumplen a la vez «migraciones al arrancar» y «usuario de aplicación sin permisos de administrador».
7. **Bloqueo de PIN.** Tras 5 fallos seguidos, el usuario queda bloqueado 5 minutos.
8. **Fusión de clientes.** Los pedidos de la ficha absorbida conservan su código original, con el C-código antiguo.

## Preguntas para el titular

Redactadas con contexto en [`Docs/preguntas_titular.md`](../Docs/preguntas_titular.md). Las que afectan a este esquema son:

- **SOBRANTE** (pendiente en el PDF, fase 2): ¿es dinero cobrado de más o un importe que se perdona? El esquema admite las dos cosas (`sobrante` o `condonado`), pero hay que saber a cuál corresponde cada concepto del Excel.
- ¿Los presupuestos necesitan un **número propio** para imprimirlos (p. ej. `26B0001`)? Ahora mismo solo tienen un id interno.
- ¿Un **cobro sin pedido** (el PDF lo permite) tiene algún uso real? Si no, conviene hacerlo obligatorio.

## Estado de la verificación

Probado el 2026-11-13 en un PostgreSQL 16.11 temporal (Windows):

- Las migraciones 0001 y 0002 se aplican sin errores. El seed también, y se puede ejecutar dos veces sin duplicar.
- `tests/reglas_fase1_2.sql` pasa entero con el rol de la app. Los 15 casos que deben fallar fallan por el motivo correcto (permiso, CHECK, FK o trigger).
- Numeración a la vez: 2 conexiones crean 25 pedidos cada una. Salen 50 pedidos con 50 números distintos, del 1 al 50, sin huecos ni errores.

Falta automatizarlo en GitHub Actions (runner Linux con PostgreSQL 16) cuando exista el repositorio.
