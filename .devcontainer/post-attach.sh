#!/usr/bin/env bash
# g2ray — postAttachCommand
# Runs every time a terminal attaches to the codespace.
# Must be fast and must never fail noisily: only prints a one-line hint.
set -uo pipefail

# Resolve lib.sh: next to the script (container layout) or one level up (repo layout)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$DIR/scripts/lib.sh" ]; then
    # shellcheck source=scripts/lib.sh
    source "$DIR/scripts/lib.sh"
elif [ -f "$DIR/../scripts/lib.sh" ]; then
    # shellcheck source=../scripts/lib.sh
    source "$DIR/../scripts/lib.sh"
else
    exit 0
fi

if g2ray_is_running; then
    echo ""
    if link="$(g2ray_link 2>/dev/null)"; then
        printf '[g2ray] running — %s\n' "$link"
    else
        echo "[g2ray] running — open a codespace terminal to see the connection string"
    fi
else
    echo "[g2ray] is not running — start it with: g2ray start"
fi
