# Preguntas para el titular

Estas preguntas salen del diseño de la app. Las respuestas cambian cómo guarda y calcula los datos. Están ordenadas según cuándo hacen falta: primero las de **pedidos y cobros** (fase 2), luego las de **caja** (fase 3) y al final las de **banco y tickets** (fase 7).

Para cada una se explica el contexto, se hace la pregunta y, cuando la hay, se indica qué haría la app si no se dice nada.

---

## Pedidos y cobros (hacen falta ya, fase 2)

### 1. ¿Qué significa «SOBRANTE»?

**Contexto.** En el Excel, cada pedido tiene una columna SOBRANTE y otra REDONDEO DEBE. Además, en la caja existe el concepto «Sobrante pedido no cobrado». En la app, cuando lo cobrado no cuadra con el precio del pedido, la diferencia se apunta como un ajuste y hay que saber de qué tipo es.

**Preguntas.**
- Cuando apuntabas un SOBRANTE en un pedido, ¿qué había pasado?
  - a) El cliente pagó **más** de lo que costaba (por ejemplo, el pedido era de 61 € y dejó 62 € sin esperar el cambio).
  - b) El cliente pagó **menos** y le perdonaste la diferencia.
  - c) Otra cosa. ¿Cuál?
- Y «Sobrante pedido no cobrado», ¿qué es? ¿Un pedido que el cliente nunca recogió ni pagó y que se da por perdido? ¿O dinero que entró en caja sin saber de qué pedido era?
- En cualquiera de los casos, ¿ese dinero entraba en la caja del día?

**Si no se dice nada:** la app separa «cobrado de más» (sobrante) y «perdonado» (condonado), y nunca oculta la diferencia.

### 2. ¿Los presupuestos necesitan un número?

**Contexto.** Para no gastar números de pedido con presupuestos que luego no se aceptan, en la app un presupuesto **no recibe número de pedido** (tipo `26P0001`) hasta que el cliente lo acepta. Hasta entonces se identifica por cliente y fecha.

**Pregunta.** Cuando entregas un presupuesto impreso, ¿necesitas que lleve un número de referencia propio (por ejemplo `26B0001`) para encontrarlo cuando el cliente vuelve? ¿O te basta con buscar por el nombre del cliente?

**Si no se dice nada:** el presupuesto va sin número.

### 3. Al aceptar un presupuesto, ¿qué fecha lleva el pedido?

**Contexto.** El número de pedido se reinicia cada año. Si un presupuesto de diciembre se acepta en enero, la fecha que se elija decide si el pedido es `25P…` o `26P…`.

**Pregunta.** Cuando un cliente acepta un presupuesto, ¿el pedido debe tener la fecha del día en que lo acepta o la fecha del presupuesto?

**Si no se dice nada:** la fecha del día en que se acepta.

### 4. ¿Cobras alguna vez algo que no es de un pedido?

**Contexto.** Las ventas de mostrador (pilas, marcos, fotos de carnet…) se apuntan directamente en la caja. Los cobros de la app, en cambio, van ligados a un pedido. Hay que saber si existe algún cobro que no encaje en ninguno de los dos.

**Pregunta.** ¿Hay algún caso en que cobres dinero que no sea de un pedido ni una venta de mostrador? Por ejemplo, una señal que deja un cliente antes de decidir qué encarga, o una reserva de fecha para una boda.

**Si no se dice nada:** todo cobro tiene que ir ligado a un pedido.

### 5. El código del pedido y la carpeta del trabajo

**Contexto.** El código sigue el formato actual: `26P0001-C1535-Nombre Apellido`. Con nombres muy largos, la app corta el nombre a 31 letras y quita los caracteres que no valen en un nombre de carpeta (`/` y `:`).

**Preguntas.**
- ¿Ese código es también el nombre de la carpeta del trabajo en el ordenador o en el NAS?
- Si es así, ¿las carpetas actuales tienen exactamente ese nombre, o las renombras a mano?
- Si un cliente cambia de nombre o se corrige una falta, ¿el código del pedido debe quedarse como estaba? (La app lo deja como estaba, para no romper la carpeta.)

### 6. Datos de clientes con formato raro

**Contexto.** Al pasar los 1.537 clientes del Excel, la app guarda los teléfonos solo con cifras, el código postal con 5 cifras y el NIF en mayúsculas. Lo que no encaje sale en un informe para revisarlo a mano.

**Preguntas.**
- ¿Hay clientes con dos teléfonos en la misma casilla, o con texto («móvil de la madre», «no llamar»)? Si los hay, ¿prefieres que el texto pase a las notas del cliente?
- El Excel tiene 13 parejas de clientes con el mismo nombre. ¿Quieres revisarlas tú para decidir si son la misma persona?

### 7. PIN y bloqueo de la pantalla

**Contexto.** Cada persona entra con su nombre y un PIN de 4 a 6 cifras.

**Preguntas.**
- Tras 5 intentos fallidos seguidos, la app bloquea ese usuario 5 minutos. ¿Te parece bien?
- Si nadie toca el ordenador durante un rato, la sesión se bloquea y hay que volver a poner el PIN. ¿Cuántos minutos? (Por defecto, 10.)

---

## Caja (hacen falta antes de la fase 3)

### 8. ¿Qué es el «caixó»?

**Contexto.** En el Excel aparecen traspasos entre la «caja» y el «caixó». Para hacer el cierre del día, la app necesita saber qué dinero hay que contar.

**Preguntas.**
- ¿El caixó es un segundo cajón de efectivo dentro de la tienda (por ejemplo, una reserva o el dinero grande), o es otra cosa?
- Al cerrar el día, ¿cuentas solo la caja, o también el caixó?
- ¿Quién pasa dinero de un sitio a otro, y cuándo?

### 9. Conceptos personales de la caja

**Contexto.** Entre los conceptos de caja hay algunos personales: «a cuenta» con nombre de persona, o «jo guarde en casa». La app tiene que saber si son retiradas, préstamos o pagos, porque cada uno se trata distinto en el cierre y en los informes.

**Pregunta.** En cada uno de estos conceptos, ¿qué pasa con el dinero?
- a) Lo sacas tú de la caja para ti (retirada del titular).
- b) Es un préstamo o adelanto a otra persona, que luego devuelve.
- c) Es un pago a alguien (proveedor, trabajador…).
- d) Es dinero que guardas en casa pero sigue siendo de la tienda.

### 10. Cambio inicial de la caja

**Pregunta.** ¿Cada mañana empiezas con la misma cantidad de cambio (un fondo fijo, por ejemplo 150 €), o con lo que quedó al cerrar el día anterior?

**Si no se dice nada:** se propone lo que quedó al cerrar el día anterior, y se puede cambiar.

### 11. Lo que recibe el gestor

**Contexto.** Cada trimestre la app genera, en Excel y PDF, la caja diaria con el efectivo y el Bizum por separado. Queremos que sea exactamente lo que el gestor espera.

**Petición.** ¿Puedes conseguir un ejemplo de lo que le das hoy al gestor (el fichero o una foto del papel)? Si se puede, que diga también si quiere algún cambio: otras columnas, totales por mes, otro formato…

### 12. IVA por tipo de trabajo

**Contexto.** Los precios de la tarifa llevan el IVA incluido. Cuando un informe necesita separar la base del IVA, la app usa el IVA de cada tipo de trabajo, que por defecto es el 21 %.

**Pregunta para el gestor.** ¿Todo lo que vende la tienda va al 21 %? ¿Hay algún tipo de trabajo o producto con otro IVA (por ejemplo libros, como el «Llibre Fogueres»)?

---

## Banco y tickets (más adelante, fase 7)

### 13. Ejemplos de exportación

**Petición.** Cuando sea posible, conseguir:
- un Excel de movimientos tal como lo descarga el banco;
- una exportación de tickets del programa homologado (Verifactu).

Basta con unas pocas filas, y con los nombres e importes cambiados o borrados. Sirven para que la app los importe sola en lugar de copiarlos a mano.
