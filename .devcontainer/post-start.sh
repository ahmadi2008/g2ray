#!/usr/bin/env bash
# g2ray — postStartCommand
# Runs once every time the codespace container starts:
#   1. load/create persistent state (UUID + secret path)
#   2. render the xray config from the template
#   3. start xray (single instance)
#   4. make the forwarded port public
#   5. print the connection link
set -euo pipefail

# Resolve lib.sh: next to the script (container layout) or one level up (repo layout)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$DIR/scripts/lib.sh" ]; then
    # shellcheck source=scripts/lib.sh
    source "$DIR/scripts/lib.sh"
elif [ -f "$DIR/../scripts/lib.sh" ]; then
    # shellcheck source=../scripts/lib.sh
    source "$DIR/../scripts/lib.sh"
else
    echo "[g2ray] ERROR: scripts/lib.sh not found" >&2
    exit 1
fi

echo ""
echo "=============================================="
printf '  g2ray v%s — starting up\n' "$G2RAY_VERSION"
echo "=============================================="

g2ray_state_ensure
g2ray_render_config

if g2ray_start; then
    g2ray_expose
    echo ""
    echo "Connection string:"
    g2ray_link || true
    echo ""
    echo "Manage the server with the 'g2ray' command (try: g2ray help)."
else
    echo ""
    echo "g2ray failed to start. Investigate with: g2ray doctor"
fi
