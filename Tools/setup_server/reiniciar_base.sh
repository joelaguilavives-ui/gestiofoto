#!/bin/bash
# =============================================================================
# GestioFoto — deja la base de datos vacía (SOLO PARA PRUEBAS).
#
# Borra la base «gestiofoto» (y «gestiofoto_prueba») y la crea de nuevo, vacía.
# Conserva los usuarios de PostgreSQL, sus contraseñas, la conexión guardada en
# la app y la copia nocturna. Al abrir GestioFoto, la app vuelve a crear las
# tablas y pide el primer titular.
#
# Para qué sirve: mientras el esquema esté en pruebas, una migración puede
# cambiar; la app avisaría de que «la migración ya aplicada ha cambiado».
# Con este script se empieza de cero.
#
# Uso: bash Tools/setup_server/reiniciar_base.sh   (con GestioFoto cerrada)
# =============================================================================
set -euo pipefail

PGBIN="${PGBIN:-/Applications/Postgres.app/Contents/Versions/latest/bin}"
BASE="gestiofoto"

echo "Esto BORRA todos los datos de la base «$BASE» de este Mac."
echo "No usar nunca en el Mac de la tienda con datos reales."
read -rp "Escribe BORRAR para continuar: " RESPUESTA
if [ "$RESPUESTA" != "BORRAR" ]; then
  echo "Cancelado."
  exit 1
fi

"$PGBIN/dropdb" --if-exists --force "${BASE}_prueba"
"$PGBIN/dropdb" --if-exists --force "$BASE"
"$PGBIN/createdb" -O gestiofoto_owner -E UTF8 -T template0 "$BASE"
"$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d postgres \
  -c "REVOKE ALL ON DATABASE $BASE FROM PUBLIC" \
  -c "GRANT CONNECT ON DATABASE $BASE TO gestiofoto_app"

echo "Base «$BASE» vacía. Abre GestioFoto: creará las tablas y pedirá el primer titular."
