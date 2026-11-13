#!/bin/bash
# =============================================================================
# GestioFoto — restaurar una copia.
#
#   restore.sh <copia.dump> --prueba   restaura en la base gestiofoto_prueba;
#                                      la base real no se toca
#   restore.sh <copia.dump>            restaura la base real: antes hace una
#                                      copia del estado actual (previas/) y
#                                      corta las conexiones de los dos Macs
#
# La app solo deja usar la restauración real al titular, con doble confirmación.
# =============================================================================
set -euo pipefail

DIR="$HOME/Library/Application Support/GestioFoto"
# shellcheck source=/dev/null
source "$DIR/copias.conf"
PGBIN="${PGBIN:-/Applications/Postgres.app/Contents/Versions/latest/bin}"
BASE="${BASE:-gestiofoto}"

COPIA="${1:?Uso: restore.sh <copia.dump> [--prueba]}"
MODO="${2:-}"
[ -f "$COPIA" ] || { echo "No existe la copia: $COPIA" >&2; exit 1; }
"$PGBIN/pg_restore" --list "$COPIA" >/dev/null || { echo "La copia está dañada: $COPIA" >&2; exit 1; }

resumen() {
  "$PGBIN/psql" -X -d "$1" -c "
    SELECT (SELECT count(*) FROM information_schema.tables
             WHERE table_schema = 'public' AND table_type = 'BASE TABLE')   AS tablas,
           (SELECT count(*) FROM usuario WHERE NOT es_sistema)              AS usuarios,
           (SELECT count(*) FROM auditoria)                                 AS cambios_auditados,
           (SELECT to_timestamp((valor)::text::bigint) FROM configuracion
             WHERE clave = 'copias.ultima' AND jsonb_typeof(valor) = 'number') AS copia_anterior"
}

if [ "$MODO" = "--prueba" ]; then
  PRUEBA="${BASE}_prueba"
  "$PGBIN/dropdb" --if-exists --force "$PRUEBA"
  "$PGBIN/createdb" -O gestiofoto_owner "$PRUEBA"
  "$PGBIN/pg_restore" -d "$PRUEBA" --exit-on-error "$COPIA"
  echo "Copia restaurada en la base de pruebas «$PRUEBA». La base real no se ha tocado."
  resumen "$PRUEBA"
  exit 0
fi

echo "Haciendo copia del estado actual antes de restaurar…"
bash "$(dirname "$0")/backup.sh" --previa

echo "Restaurando $COPIA en la base real «$BASE»…"
"$PGBIN/dropdb" --force "$BASE"
"$PGBIN/pg_restore" -d postgres --create --exit-on-error "$COPIA"
echo "Restauración terminada."
resumen "$BASE"
