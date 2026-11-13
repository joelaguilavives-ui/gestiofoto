#!/bin/bash
# =============================================================================
# GestioFoto — copia de seguridad (pg_dump). La lanza launchd cada noche y la
# app con «Hacer copia ahora».
#
#   backup.sh            copia diaria; la primera de cada mes se guarda también
#                        en mensuales/
#   backup.sh --previa   copia antes de restaurar (carpeta previas/)
#
# Conserva las últimas CONSERVAR_DIARIAS diarias, CONSERVAR_MENSUALES mensuales
# y 10 previas. Anota el resultado en la tabla configuracion (copias.ultima /
# copias.ultimo_error) para que los dos Macs vean el estado.
# =============================================================================
set -euo pipefail

DIR="$HOME/Library/Application Support/GestioFoto"
# shellcheck source=/dev/null
source "$DIR/copias.conf"
: "${CARPETA:?Falta CARPETA en copias.conf}"
PGBIN="${PGBIN:-/Applications/Postgres.app/Contents/Versions/latest/bin}"
BASE="${BASE:-gestiofoto}"
CONSERVAR_DIARIAS="${CONSERVAR_DIARIAS:-30}"
CONSERVAR_MENSUALES="${CONSERVAR_MENSUALES:-12}"

anotar() {   # anotar <clave> <expresión SQL jsonb>
  "$PGBIN/psql" -X -q -d "$BASE" -c "SELECT set_config('app.usuario_id', '1', true);
    INSERT INTO configuracion (clave, valor) VALUES ('$1', $2)
    ON CONFLICT (clave) DO UPDATE SET valor = EXCLUDED.valor" >/dev/null 2>&1 || true
}

fallo() {
  local mensaje="$1"
  echo "ERROR: $mensaje" >&2
  anotar copias.ultimo_error "to_jsonb('$(date '+%Y-%m-%d %H:%M') $(printf '%s' "$mensaje" | sed "s/'/''/g")'::text)"
  exit 1
}

mkdir -p "$CARPETA/diarias" "$CARPETA/mensuales" "$CARPETA/previas" \
  || fallo "No se puede escribir en la carpeta de copias: $CARPETA"

SELLO=$(date +%Y-%m-%d_%H%M%S)
if [ "${1:-}" = "--previa" ]; then
  DESTINO="$CARPETA/previas/gestiofoto_$SELLO.dump"
else
  DESTINO="$CARPETA/diarias/gestiofoto_$SELLO.dump"
fi

if ! "$PGBIN/pg_dump" -Fc -d "$BASE" -f "$DESTINO.tmp"; then
  rm -f "$DESTINO.tmp"
  fallo "pg_dump no ha podido hacer la copia"
fi
mv "$DESTINO.tmp" "$DESTINO"

# Comprueba que la copia se puede leer.
"$PGBIN/pg_restore" --list "$DESTINO" >/dev/null || fallo "La copia $DESTINO está dañada"

if [ "${1:-}" != "--previa" ]; then
  MES=$(date +%Y-%m)
  if ! compgen -G "$CARPETA/mensuales/gestiofoto_${MES}-*.dump" >/dev/null; then
    cp "$DESTINO" "$CARPETA/mensuales/"
  fi
fi

podar() {   # podar <carpeta> <cuántas conservar>
  local carpeta="$1" conservar="$2"
  # Carpeta vacía: ls falla y, con pipefail, cortaría el script.
  { ls -1t "$carpeta"/gestiofoto_*.dump 2>/dev/null || true; } | tail -n +$((conservar + 1)) |
    while IFS= read -r fichero; do rm -f "$fichero"; done
}
podar "$CARPETA/diarias" "$CONSERVAR_DIARIAS"
podar "$CARPETA/mensuales" "$CONSERVAR_MENSUALES"
podar "$CARPETA/previas" 10

anotar copias.ultima "to_jsonb(extract(epoch FROM now())::bigint)"
anotar copias.ultimo_error "'null'::jsonb"

echo "Copia guardada: $DESTINO ($(du -h "$DESTINO" | cut -f1))"
