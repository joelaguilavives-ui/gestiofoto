# GestioFoto — instrucciones para Claude Code

App nativa de macOS para la tienda de fotografía: sustituye al Excel
`INVENTARI_SOBRES_ENTREGA`. La especificación completa está en
`Especificación – App de gestión Fotografía (macOS).pdf`, en la carpeta local del
proyecto; **no se sube al repositorio** (es público; el PDF está en
`.gitignore`). Este fichero es su apartado 10 más las decisiones tomadas después.

El repositorio de GitHub es **público**: no subir nunca datos reales de la tienda
(Excel, copias `.dump`, clientes), contraseñas ni documentos internos. Los
commits usan el email privado de GitHub (`…@users.noreply.github.com`,
configurado en este repositorio).

## Forma de trabajar

- Una fase cada vez (apartado 9 del PDF). No se pasa a la siguiente sin la
  aprobación del titular.
- Cada fase termina con una lista de comprobación manual para el titular, basada
  en los criterios del apartado 9.
- Idioma: castellano en código de dominio, base de datos, interfaz y documentación.

## Entorno de desarrollo y compilación

- El código se escribe en **Windows**, sin Mac. Nada de SwiftUI se puede ejecutar
  en local.
- Compilación y pruebas en **GitHub Actions**:
  - runner **macOS** (Xcode): compila la app y los paquetes Swift;
  - runner **Linux** con servicio PostgreSQL 16: pruebas de `Domain`,
    `Persistence` y del esquema SQL (PostgresNIO funciona en Linux).
- El proyecto de Xcode **no se escribe a mano**: se genera en el runner con
  XcodeGen a partir de `App/project.yml`. Es herramienta de compilación, no
  dependencia de la app.
- Los minutos de runner macOS cuestan 10× en repos privados: compilar macOS solo
  en push a `main` y en PR.
- Sin cuenta Apple Developer la app sale sin firmar (primera apertura: en macOS
  15+, Ajustes del Sistema → Privacidad y seguridad → «Abrir igualmente»; en
  macOS 14, clic derecho → Abrir).
- **Pruebas del titular en un portátil Mac**, no en la tienda: el portátil hace
  de Mac principal y el segundo Mac se simula (conexión por nombre de red,
  segunda instancia con `open -n`). Lo que exige dos Macs reales queda en la
  lista de comprobación como pendiente para la instalación en la tienda.
  `Tools/setup_server/reiniciar_base.sh` vacía la base de pruebas (p. ej. tras
  cambiar una migración aún no aplicada en la tienda). **Al terminar, el
  portátil debe quedar limpio**: `desinstalar.sh` quita GestioFoto, copias,
  launchd y Postgres.app con sus datos (si no hay bases ajenas). Todo lo que se
  añada en fases nuevas (ficheros, permisos, agentes) debe añadirse también a
  ese script.
- Solo comprobable en un Mac real: etiquetas del Finder (también en el NAS),
  Llavero, agente launchd de copias, impresión, trabajo con dos Macs. Marcarlo en
  la lista de comprobación de cada fase.

## Estructura del proyecto

```
App/                 app SwiftUI (vistas, modelos de vista, sin reglas de negocio)
  project.yml        definición XcodeGen (el .xcodeproj se genera, no se sube)
Packages/
  Package.swift      un manifiesto; un target por carpeta, cada una con
                     Sources/ y Tests/
  Domain/            modelos y reglas de negocio en Swift puro (precios,
                     totales, numeración, cierre de caja)
  Persistence/       acceso a PostgreSQL con PostgresNIO, repositorios,
                     transacciones, migraciones
  Reports/           informes, exportación a Excel y PDF (desde fase 2–3)
  Integrations/      etiquetas del Finder, WhatsApp y email, copias de seguridad
Database/
  migrations/        0001_base.sql, 0002_… (numeradas, solo hacia delante)
  seed/              formas de pago, configuración inicial (repetible)
  tests/             pruebas SQL de las reglas (las ejecuta PersistenceTests)
  ESQUEMA.md         decisiones de diseño del esquema
Docs/                preguntas para el titular, listas de comprobación por fase
Tools/
  migrate_excel/     script Python de migración + informe (fase 2)
  setup_server/      instalación de PostgreSQL y de las copias en el Mac
                     principal (setup.sh, backup.sh, restore.sh) y, solo
                     para pruebas, reiniciar_base.sh y desinstalar.sh
.github/workflows/   CI: paquetes + PostgreSQL 16 en Linux; app en macOS
CLAUDE.md
```

Pruebas de integración en local (sin Mac): definir `GESTIOFOTO_TEST_DB_HOST`
y demás variables descritas en
`Packages/Persistence/Tests/BaseDeDatosIntegracionTests.swift`.

## Convenciones

- Swift 6 con concurrencia estricta, macOS 14+, Observation (`@Observable`),
  async/await.
- Ninguna vista habla con la base de datos: vistas → modelos de vista →
  repositorios.
- Dinero en `Decimal` y `numeric(12,2)`; nunca `Double`. Fechas en la zona
  `Europe/Madrid`; los días de caja son `date`, sin hora.
- Toda regla crítica, en dos sitios: en `Domain` (para la interfaz) y como
  restricción en la base de datos (para que nada incoherente se guarde).
- Migraciones numeradas, aplicadas al arrancar la app en el Mac principal, en una
  transacción. **Nunca se edita una migración ya aplicada** (mientras el esquema
  esté en revisión y no se haya aplicado en la tienda, sí se puede).
- Cada transacción de la app empieza con
  `SELECT set_config('app.usuario_id', $1, true)`; sin eso la base de datos
  rechaza cualquier cambio (todo queda firmado).
- Edición concurrente: `UPDATE … WHERE id = $1 AND version = $2`; 0 filas =
  conflicto, se avisa al usuario y se le muestran los cambios del otro.
- Textos de interfaz en un String Catalog, en castellano, preparados para añadir
  valenciano.
- Sin dependencias fuera de las del apartado 2 del PDF sin justificarlo.

## Pruebas

- Pruebas unitarias (Swift Testing) para cada regla del apartado 4, con casos
  sacados del Excel: totales, descuentos, numeración, cierre de caja, trimestres.
- Pruebas de integración contra un PostgreSQL de pruebas: transacciones,
  numeración con dos conexiones simultáneas, conflicto de versión, triggers de
  auditoría.
- El script de migración tiene su propia prueba: recuentos y sumas iguales a los
  del Excel.

## Decisiones posteriores al PDF

- **Ajuste porcentual por trimestre** (tabla de porcentajes de RESUM CASH): es un
  cálculo interno. Queda **aparcado**; no se implementa hasta que el titular lo
  pida. Entonces, pedir el Excel con sus fórmulas.
