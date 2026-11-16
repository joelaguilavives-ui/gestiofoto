#!/bin/bash
# =============================================================================
# GestioFoto — dejar limpio un Mac de pruebas (el portátil) al terminar.
#
# Quita:
#   - GestioFoto.app, su configuración, cachés, permisos y contraseñas del
#     Llavero;
#   - la copia nocturna (launchd), los scripts y las copias de seguridad de la
#     carpeta de copias (solo las de GestioFoto);
#   - Postgres.app entera: el servidor, TODAS sus bases de datos y su
#     configuración. Si Postgres.app tiene otras bases que no son de GestioFoto,
#     no la toca (avisa) y solo quita lo de GestioFoto.
#
# Queda a mano (el script lo recuerda al final): la carpeta del proyecto, el
# ZIP descargado y, si se dio, el «Acceso total al disco» de /bin/bash.
#
# Uso: bash Tools/setup_server/desinstalar.sh
# NO USAR NUNCA en el Mac de la tienda.
# =============================================================================
set -uo pipefail

PGAPP="/Applications/Postgres.app"
PGBIN="${PGBIN:-$PGAPP/Contents/Versions/latest/bin}"
PGDATOS="$HOME/Library/Application Support/Postgres"
APP="/Applications/GestioFoto.app"
APPID="es.gestiofoto.app"
DIR="$HOME/Library/Application Support/GestioFoto"
ETIQUETA="com.gestiofoto.copia"
PSQL=("$PGBIN/psql" -X -q -v ON_ERROR_STOP=1 -d postgres)

paso() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
quitar() { for r in "$@"; do [ -e "$r" ] && rm -rf "$r" && echo "  quitado: $r"; done; return 0; }

# Carpeta de copias (antes de borrar copias.conf)
CARPETA=""
if [ -f "$DIR/copias.conf" ]; then
  # shellcheck source=/dev/null
  CARPETA="$(source "$DIR/copias.conf" && printf '%s' "${CARPETA:-}")"
fi

cat <<EOF
Esto deja este Mac limpio de GestioFoto y de Postgres.app:
  - $APP y todos sus datos y contraseñas
  - la copia nocturna y las copias de GestioFoto${CARPETA:+ en «$CARPETA»}
  - $PGAPP con TODAS sus bases de datos
NO USAR NUNCA en el Mac de la tienda.
EOF
read -rp "Escribe BORRAR para continuar: " RESPUESTA
if [ "$RESPUESTA" != "BORRAR" ]; then
  echo "Cancelado."
  exit 1
fi

# --- GestioFoto: cerrar y quitar la copia nocturna -----------------------------
paso "GestioFoto"
# Solo si está abierta (si no, osascript preguntaría dónde está la app)
pgrep -xq GestioFoto 2>/dev/null && osascript -e "tell application id \"$APPID\" to quit" >/dev/null 2>&1
launchctl bootout "gui/$(id -u)/$ETIQUETA" 2>/dev/null || true
quitar "$HOME/Library/LaunchAgents/$ETIQUETA.plist"

# --- Postgres.app ---------------------------------------------------------------
paso "PostgreSQL"
QUITAR_POSTGRES=1
if [ -x "$PGBIN/psql" ] && "${PSQL[@]}" -tAc "SELECT 1" >/dev/null 2>&1; then
  # Bases que no son de GestioFoto ni las que crea Postgres.app al inicializar
  OTRAS=$("${PSQL[@]}" -tAc "SELECT string_agg(datname, ', ') FROM pg_database
            WHERE datname NOT IN ('postgres', 'template0', 'template1', current_user)
              AND datname NOT LIKE 'gestiofoto%'")
  if [ -n "$OTRAS" ]; then
    QUITAR_POSTGRES=0
    echo "  Postgres.app tiene otras bases que no son de GestioFoto: $OTRAS"
    echo "  No se quita Postgres.app; solo lo de GestioFoto."
  fi

  "$PGBIN/dropdb" --if-exists --force gestiofoto_prueba 2>/dev/null || true
  "$PGBIN/dropdb" --if-exists --force gestiofoto 2>/dev/null || true
  "${PSQL[@]}" -c "DROP ROLE IF EXISTS gestiofoto_app" -c "DROP ROLE IF EXISTS gestiofoto_owner" || true
  echo "  bases y usuarios de GestioFoto quitados"

  if [ "$QUITAR_POSTGRES" = 0 ]; then
    # Deja Postgres como estaba antes de setup.sh
    HBA=$("${PSQL[@]}" -tAc "SHOW hba_file")
    MARCA="# GestioFoto: red local, solo TLS y contraseña"
    if grep -qF "$MARCA" "$HBA"; then
      grep -vF -e "$MARCA" -e "hostssl gestiofoto gestiofoto_app,gestiofoto_owner samenet scram-sha-256" \
        "$HBA" > "$HBA.tmp" && cat "$HBA.tmp" > "$HBA" && rm -f "$HBA.tmp"
    fi
    "${PSQL[@]}" -c "ALTER SYSTEM RESET listen_addresses" -c "ALTER SYSTEM RESET ssl" || true
    DATA=$("${PSQL[@]}" -tAc "SHOW data_directory")
    "$PGBIN/pg_ctl" -D "$DATA" restart -m fast -w >/dev/null 2>&1 || true
    echo "  acceso por red de GestioFoto quitado"
  fi
fi

if [ "$QUITAR_POSTGRES" = 1 ]; then
  # Parar todos los servidores de Postgres.app antes de borrar sus datos
  if pgrep -xq Postgres 2>/dev/null; then
    osascript -e 'tell application "Postgres" to quit' >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq Postgres 2>/dev/null || break; sleep 1; done
  fi
  if [ -d "$PGDATOS" ] && [ -x "$PGBIN/pg_ctl" ]; then
    for datos in "$PGDATOS"/var-*; do
      [ -f "$datos/postmaster.pid" ] && "$PGBIN/pg_ctl" -D "$datos" stop -m fast -w >/dev/null 2>&1
    done
  fi
  quitar "$PGAPP" "$PGDATOS" \
    "$HOME/Library/Preferences/com.postgresapp.Postgres2.plist" \
    "$HOME/Library/Preferences/com.postgresapp.Postgres2LoginHelper.plist" \
    "$HOME/Library/Caches/com.postgresapp.Postgres2" \
    "$HOME/Library/HTTPStorages/com.postgresapp.Postgres2" \
    "$HOME/Library/Saved Application State/com.postgresapp.Postgres2.savedState"
  defaults delete com.postgresapp.Postgres2 >/dev/null 2>&1 || true
  if [ -e /etc/paths.d/postgresapp ]; then
    echo "  Hace falta la contraseña de este Mac para quitar /etc/paths.d/postgresapp:"
    sudo rm -f /etc/paths.d/postgresapp && echo "  quitado: /etc/paths.d/postgresapp"
  fi
  echo "  Postgres.app y todos sus datos quitados"
fi

# --- GestioFoto: app, datos, contraseñas y permisos ------------------------------
paso "App y datos de GestioFoto"
security delete-generic-password -s es.gestiofoto.basededatos -a gestiofoto_app >/dev/null 2>&1 || true
security delete-generic-password -s es.gestiofoto.basededatos -a gestiofoto_owner >/dev/null 2>&1 || true
echo "  contraseñas del Llavero quitadas"
defaults delete "$APPID" >/dev/null 2>&1 || true
tccutil reset All "$APPID" >/dev/null 2>&1 || true
quitar "$APP" "$DIR" \
  "$HOME/Library/Preferences/$APPID.plist" \
  "$HOME/Library/Caches/$APPID" \
  "$HOME/Library/HTTPStorages/$APPID" \
  "$HOME/Library/Saved Application State/$APPID.savedState"

# --- Copias de seguridad de GestioFoto ------------------------------------------
if [ -n "$CARPETA" ] && [ -d "$CARPETA" ]; then
  paso "Copias de seguridad"
  for sub in diarias mensuales previas; do
    if [ -d "$CARPETA/$sub" ]; then
      rm -f "$CARPETA/$sub"/gestiofoto_*.dump "$CARPETA/$sub"/gestiofoto_*.dump.tmp
      rmdir "$CARPETA/$sub" 2>/dev/null && echo "  quitado: $CARPETA/$sub"
    fi
  done
  rmdir "$CARPETA" 2>/dev/null && echo "  quitado: $CARPETA"
  [ -d "$CARPETA" ] && echo "  «$CARPETA» tiene otros ficheros: se deja (sin las copias de GestioFoto)."
fi

paso "Listo"
cat <<EOF
Queda por hacer a mano:
  - Borrar la carpeta del proyecto (esta, con el script) y el ZIP descargado.
  - Si diste «Acceso total al disco» a /bin/bash para las copias, quítalo en
    Ajustes del Sistema → Privacidad y seguridad → Acceso total al disco.
  - Si en el cortafuegos aparece «postgres», quítalo en Ajustes del Sistema →
    Red → Cortafuegos → Opciones.
  - Vaciar la papelera no hace falta: lo borrado no ha pasado por ella.
EOF
