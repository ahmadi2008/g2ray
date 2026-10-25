#!/bin/sh
# g2ray — build-time installer for Xray-core.
# Runs as root during the devcontainer image build.
set -e

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  XARCH="64" ;;
    aarch64) XARCH="arm64-v8a" ;;
    *) echo "[g2ray] unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XARCH}.zip"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[g2ray] downloading Xray-core ${XRAY_VERSION} (${XARCH})..."
curl -fsSL "$URL" -o "$TMP/xray.zip"

unzip -q -o "$TMP/xray.zip" -d "$TMP"
install -m 755 "$TMP/xray" /usr/local/bin/xray

# Geo assets are required by the routing rule that blocks private networks.
mkdir -p /usr/local/share/xray
[ -f "$TMP/geoip.dat" ]   && install -m 644 "$TMP/geoip.dat"   /usr/local/share/xray/geoip.dat
[ -f "$TMP/geosite.dat" ] && install -m 644 "$TMP/geosite.dat" /usr/local/share/xray/geosite.dat

# Allow the non-root user to bind low ports (443) without sudo.
setcap 'cap_net_bind_service=+ep' /usr/local/bin/xray 2>/dev/null || \
    echo "[g2ray] setcap unavailable — runtime will fall back to sudo"

echo "[g2ray] installed: $(/usr/local/bin/xray version | head -n 1)"
