#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# ---------- Inputs ----------
read -rp "Enter HTTP Server IP (e.g. 172.29.192.139): " SERVER_IP
read -rp "Enter file path (e.g. /testfile-500mb or /testfile-1gb): " FILE_PATH
read -rp "Enter HTTP port (default 80): " PORT
PORT=${PORT:-80}
read -rp "Enter device name (e.g. Getac/Samsung/Zebra): " DEVICE_LABEL
read -rp "Enter network name (e.g. WiFi/PrivateAPN): " NET_LABEL

# Sanitize labels (no spaces)
DEVICE_LABEL="${DEVICE_LABEL// /_}"
NET_LABEL="${NET_LABEL// /_}"

# Normalize FILE_PATH to have exactly one leading slash
if [ -z "${FILE_PATH:-}" ]; then
  echo "[ERROR] File path must not be empty (e.g. /testfile-500mb)"; exit 1
fi
if [ "${FILE_PATH:0:1}" != "/" ]; then
  FILE_PATH="/$FILE_PATH"
fi

# Build URL (omit :80 for neatness)
if [ "$PORT" = "80" ]; then
  HTTP_URL="http://${SERVER_IP}${FILE_PATH}"
else
  HTTP_URL="http://${SERVER_IP}:${PORT}${FILE_PATH}"
fi

# ---------- Output paths (public storage) ----------
TS="$(date '+%Y-%m-%d_%H-%M-%S')"
BASE="/sdcard/Download/HTTP_Test"
OUTDIR="${BASE}/${TS}_${DEVICE_LABEL}_${NET_LABEL}"
mkdir -p "$OUTDIR"
METRICS="${OUTDIR}/http_metrics.txt"
ERRS="${OUTDIR}/curl_errors.txt"
HEAD="${OUTDIR}/http_head.txt"

echo "[STEP] Collecting HTTP metrics from: $HTTP_URL"
echo "[INFO] Device=$DEVICE_LABEL  Network=$NET_LABEL"
echo "[INFO] Output folder: $OUTDIR"

# ---------- Dependency checks ----------
for cmd in curl awk; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[ERROR] Missing '$cmd'. Run: pkg update && pkg install curl awk"
    exit 1
  fi
done

# ---------- Quick reachability (HEAD) ----------
if ! curl -sSI "$HTTP_URL" >"$HEAD" 2>"$ERRS"; then
  echo "[FAIL] Could not reach URL. See $ERRS"
  {
    echo "ServerIP=$SERVER_IP"
    echo "Port=$PORT"
    echo "FilePath=$FILE_PATH"
    echo "Device=$DEVICE_LABEL"
    echo "Network=$NET_LABEL"
    echo "RunTag=${TS}_${DEVICE_LABEL}_${NET_LABEL}"
    echo "error=head_request_failed"
  } >>"$METRICS"
  exit 1
fi

# ---------- Metrics only (discard payload) ----------
# Single line (no backslashes) to avoid CRLF issues.
curl -sS -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o /dev/null -w "http_code=%{http_code}\nsize_download=%{size_download}\nspeed_download_Bps=%{speed_download}\ntime_namelookup=%{time_namelookup}\ntime_connect=%{time_connect}\ntime_starttransfer_TTFB=%{time_starttransfer}\ntime_total=%{time_total}\n" "$HTTP_URL" >"$METRICS" 2>>"$ERRS"

# ---------- Append labels and compute Mbps ----------
{
  echo "ServerIP=$SERVER_IP"
  echo "Port=$PORT"
  echo "FilePath=$FILE_PATH"
  echo "Device=$DEVICE_LABEL"
  echo "Network=$NET_LABEL"
  echo "RunTag=${TS}_${DEVICE_LABEL}_${NET_LABEL}"
} >>"$METRICS"

awk -F= '
  BEGIN { bps=0 }
  $1=="speed_download_Bps" { bps=$2+0 }
  END { mbps=(bps*8.0)/1000000.0; printf("speed_download_Mbps=%.3f\n", mbps) }
' "$METRICS" >>"$METRICS"

echo
echo "DONE. Logs saved in: $OUTDIR"
echo "Files:"
echo "  http_metrics.txt   (code/size/speed Bps & Mbps + timings + labels)"
echo "  http_head.txt      (response headers)"
echo "  curl_errors.txt    (curl stderr, if any)"
