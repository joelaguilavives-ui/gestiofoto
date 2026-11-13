#!/bin/bash
# =============================================================================
# GestioFoto — programa la copia nocturna con launchd según copias.conf.
# Lo llaman setup.sh y la app (al cambiar la hora en Ajustes → Copias).
# Si el Mac está dormido a esa hora, launchd la lanza al despertar.
# =============================================================================
set -euo pipefail

DIR="$HOME/Library/Application Support/GestioFoto"
# shellcheck source=/dev/null
source "$DIR/copias.conf"
ETIQUETA="com.gestiofoto.copia"
PLIST="$HOME/Library/LaunchAgents/$ETIQUETA.plist"

mkdir -p "$HOME/Library/LaunchAgents" "$DIR/logs"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$ETIQUETA</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$DIR/scripts/backup.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key><integer>${HORA:-2}</integer>
    <key>Minute</key><integer>${MINUTO:-0}</integer>
  </dict>
  <key>StandardOutPath</key><string>$DIR/logs/copia.log</string>
  <key>StandardErrorPath</key><string>$DIR/logs/copia.log</string>
</dict>
</plist>
EOF

DOMINIO="gui/$(id -u)"
launchctl bootout "$DOMINIO/$ETIQUETA" 2>/dev/null || true
launchctl bootstrap "$DOMINIO" "$PLIST"
printf 'Copia nocturna programada a las %02d:%02d.\n' "${HORA:-2}" "${MINUTO:-0}"
