#!/bin/bash
# =============================================================================
# GestioFoto — preparación del Mac principal (se ejecuta una vez).
#
#  1. Comprueba Postgres.app (PostgreSQL 16 o posterior).
#  2. Crea los roles gestiofoto_owner y gestiofoto_app y la base gestiofoto.
#  3. Abre PostgreSQL a la red local: solo con TLS y contraseña.
#  4. Instala los scripts de copias y programa la copia nocturna.
#
# Uso (en el Mac principal, con Postgres.app en marcha):
#   bash Tools/setup_server/setup.sh
# Se puede repetir: no borra nada; vuelve a fijar contraseñas y configuración.
# =============================================================================
set -euo pipefail

PGBIN="${PGBIN:-/Applications/Postgres.app/Contents/Versions/latest/bin}"
BASE="gestiofoto"
DIR="$HOME/Library/Application Support/GestioFoto"
AQUI="$(cd "$(dirname "$0")" && pwd)"
PSQL=("$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d postgres)

paso() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

# --- 1. Postgres.app ----------------------------------------------------------
paso "Comprobando Postgres.app"
if [ ! -x "$PGBIN/psql" ]; then
  echo "No encuentro Postgres.app en $PGBIN."
  echo "Instálalo desde https://postgresapp.com (versión con PostgreSQL 16), ábrelo y pulsa «Initialize»."
  exit 1
fi
if ! VERSION=$("${PSQL[@]}" -tAc "SHOW server_version_num" 2>/dev/null); then
  echo "PostgreSQL no responde. Abre Postgres.app y comprueba que el servidor está en marcha."
  exit 1
fi
if [ "$VERSION" -lt 160000 ]; then
  echo "Hace falta PostgreSQL 16 o posterior (hay $VERSION)."
  exit 1
fi
echo "PostgreSQL $VERSION en marcha."

# --- 2. Roles y base de datos -------------------------------------------------
paso "Roles y base de datos"
echo "Elige dos contraseñas largas y guárdalas: la app te las pedirá una vez y las guardará en el Llavero."
read -rsp "Contraseña para gestiofoto_owner (migraciones, solo Mac principal): " OWNER_PW; echo
read -rsp "Contraseña para gestiofoto_app (trabajo diario, los dos Macs): " APP_PW; echo
if [ ${#OWNER_PW} -lt 12 ] || [ ${#APP_PW} -lt 12 ]; then
  echo "Las contraseñas deben tener al menos 12 caracteres."
  exit 1
fi

"${PSQL[@]}" -v owner_pw="$OWNER_PW" -v app_pw="$APP_PW" -v base="$BASE" <<'SQL'
SELECT 'CREATE ROLE gestiofoto_owner LOGIN'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gestiofoto_owner') \gexec
SELECT 'CREATE ROLE gestiofoto_app LOGIN'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gestiofoto_app') \gexec
SELECT format('ALTER ROLE gestiofoto_owner LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'owner_pw') \gexec
SELECT format('ALTER ROLE gestiofoto_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L', :'app_pw') \gexec
SELECT format('CREATE DATABASE %I OWNER gestiofoto_owner ENCODING %L TEMPLATE template0', :'base', 'UTF8')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'base') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'base') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO gestiofoto_app', :'base') \gexec
SQL
unset OWNER_PW APP_PW
echo "Roles y base de datos listos."

# --- 3. Red local con TLS -----------------------------------------------------
paso "Acceso desde la red local (TLS)"
DATA=$("${PSQL[@]}" -tAc "SHOW data_directory")
HBA=$("${PSQL[@]}" -tAc "SHOW hba_file")
NOMBRE_RED="$(scutil --get LocalHostName).local"

if [ ! -f "$DATA/server.crt" ]; then
  openssl req -new -x509 -days 3650 -nodes -newkey rsa:2048 \
    -subj "/CN=$NOMBRE_RED/O=GestioFoto" \
    -keyout "$DATA/server.key" -out "$DATA/server.crt" 2>/dev/null
  chmod 600 "$DATA/server.key"
  echo "Certificado TLS creado para $NOMBRE_RED (válido 10 años)."
fi

"${PSQL[@]}" <<'SQL'
ALTER SYSTEM SET listen_addresses = '*';
ALTER SYSTEM SET ssl = on;
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SQL

MARCA="# GestioFoto: red local, solo TLS y contraseña"
if ! grep -qF "$MARCA" "$HBA"; then
  cp "$HBA" "$HBA.antes-gestiofoto"
  {
    echo ""
    echo "$MARCA"
    echo "hostssl $BASE gestiofoto_app,gestiofoto_owner samenet scram-sha-256"
  } >> "$HBA"
  echo "Regla añadida a $HBA (copia en $HBA.antes-gestiofoto)."
fi

"$PGBIN/pg_ctl" -D "$DATA" restart -m fast -w >/dev/null
echo "PostgreSQL reiniciado."

if [ "$("${PSQL[@]}" -tAc "SHOW ssl")" = "on" ]; then
  echo "TLS activo."
else
  echo "Aviso: TLS no se ha activado. Revisa el registro de Postgres.app."
fi

# --- 4. Copias de seguridad ---------------------------------------------------
paso "Copias de seguridad"
mkdir -p "$DIR/scripts" "$DIR/logs"
cp "$AQUI/backup.sh" "$AQUI/restore.sh" "$AQUI/instalar_agente.sh" "$DIR/scripts/"
chmod 755 "$DIR/scripts/"*.sh

if [ ! -f "$DIR/copias.conf" ]; then
  PREDETERMINADA="$HOME/Documents/Copias GestioFoto"
  read -rp "Carpeta para las copias [$PREDETERMINADA]: " CARPETA
  CARPETA="${CARPETA:-$PREDETERMINADA}"
  read -rp "Hora de la copia nocturna (HH:MM) [02:00]: " HORA_TEXTO
  HORA_TEXTO="${HORA_TEXTO:-02:00}"
  HORA=$((10#${HORA_TEXTO%%:*}))
  MINUTO=$((10#${HORA_TEXTO##*:}))
  comillas() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
  cat > "$DIR/copias.conf" <<EOF
# GestioFoto — configuración de copias de seguridad (la escribe la app)
CARPETA=$(comillas "$CARPETA")
HORA=$HORA
MINUTO=$MINUTO
CONSERVAR_DIARIAS=30
CONSERVAR_MENSUALES=12
PGBIN=$(comillas "$PGBIN")
BASE=$(comillas "$BASE")
EOF
fi
bash "$DIR/scripts/instalar_agente.sh"

# --- Resumen ------------------------------------------------------------------
paso "Listo"
cat <<EOF
Nombre de red de este Mac:  $NOMBRE_RED
Certificado del servidor:   $DATA/server.crt

Siguientes pasos:
  1. Abre GestioFoto en este Mac, marca «Este es el Mac principal» y escribe
     $NOMBRE_RED y las dos contraseñas. La app creará las tablas y te pedirá
     el primer usuario titular.
  2. Copia $DATA/server.crt al segundo Mac (AirDrop o USB) y elígelo en la
     pantalla de conexión de la app, con el mismo nombre de red y la
     contraseña de gestiofoto_app.
  3. Si macOS pregunta si «postgres» puede aceptar conexiones entrantes, pulsa
     «Permitir».
  4. Si la carpeta de copias está en un disco externo y la copia falla por
     permisos, da «Acceso total al disco» a /bin/bash en Ajustes del Sistema →
     Privacidad y seguridad.
EOF
