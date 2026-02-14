#!/bin/bash
set -e

# ── configurable env vars ──
VLESS_UUID="${VLESS_UUID:-$(cat /proc/sys/kernel/random/uuid)}"
VLESS_PORT="${VLESS_PORT:-8443}"
VLESS_PATH="${VLESS_PATH:-/vless}"

echo "========================================="
echo " VLESS UUID : ${VLESS_UUID}"
echo " VLESS PORT : ${VLESS_PORT}"
echo " VLESS PATH : ${VLESS_PATH}"
echo "========================================="

# ── generate xray config from template ──
sed -e "s|VLESS_UUID_PLACEHOLDER|${VLESS_UUID}|g" \
    -e "s|VLESS_PORT_PLACEHOLDER|${VLESS_PORT}|g" \
    -e "s|VLESS_PATH_PLACEHOLDER|${VLESS_PATH}|g" \
    /etc/xray/config-template.json > /etc/xray/config.json

# ── start dbus (required by warp-svc) ──
mkdir -p /run/dbus
if [ -f /run/dbus/pid ]; then
    rm /run/dbus/pid
fi
dbus-daemon --system --nofork &
sleep 1

# ── start warp-svc ──
warp-svc &
sleep 3

# ── register warp (first run only, data persisted via volume) ──
if ! warp-cli --accept-tos registration show &>/dev/null; then
    echo "[warp] registering new device..."
    warp-cli --accept-tos registration new
fi

# ── configure warp as local SOCKS5 proxy ──
warp-cli --accept-tos mode proxy
warp-cli --accept-tos proxy port 40000
warp-cli --accept-tos connect

# wait for warp to establish connection
for i in $(seq 1 15); do
    if warp-cli --accept-tos status 2>/dev/null | grep -q "Connected"; then
        echo "[warp] connected"
        break
    fi
    echo "[warp] waiting for connection... (${i}/15)"
    sleep 2
done

warp-cli --accept-tos status

# ── start xray (foreground) ──
echo "[xray] starting..."
exec /usr/local/bin/xray run -config /etc/xray/config.json
