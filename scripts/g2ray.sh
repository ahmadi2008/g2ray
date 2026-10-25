#!/usr/bin/env bash
# g2ray — management CLI for the codespace proxy server.
#
# Usage: g2ray <command>
#   status     show server status and the connection link
#   start      start the xray server and expose the port
#   stop       stop the xray server
#   restart    stop + start
#   link       print the connection string only
#   log [n]    show the last n log lines (default 50)
#   new-uuid   rotate the UUID, restart and print the new link
#   reset      wipe state (UUID + path), restart and print the new link
#   doctor     run environment health checks
#   help       show this help
set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

cmd="${1:-help}"
case "$cmd" in

    start)
        g2ray_start
        g2ray_expose
        echo ""
        echo "Connection string:"
        g2ray_link || true
        ;;

    stop)
        g2ray_stop
        ;;

    restart)
        g2ray_stop
        sleep 1
        g2ray_start
        g2ray_expose
        echo ""
        echo "Connection string:"
        g2ray_link || true
        ;;

    link)
        g2ray_state_ensure
        g2ray_link
        ;;

    log)
        n="${2:-50}"
        [ -f "$G2RAY_LOG" ] || { g2ray_info "log file is empty (nothing logged yet)"; exit 0; }
        tail -n "$n" "$G2RAY_LOG"
        ;;

    status)
        printf 'g2ray v%s — status\n' "$G2RAY_VERSION"
        printf '  %-12s %s\n' "codespace" "${CODESPACE_NAME:-<not a codespace>}"
        printf '  %-12s %s\n' "endpoint"   "$(g2ray_host 2>/dev/null || echo '<unknown>')"
        printf '  %-12s %s\n' "port"       "$G2RAY_PORT"
        if g2ray_is_running; then
            printf '  %-12s %s\n' "server" "running (pid $(pgrep -f "xray run -c $G2RAY_CONFIG" | head -n 1))"
        else
            printf '  %-12s %s\n' "server" "stopped"
        fi
        g2ray_state_ensure
        printf '  %-12s %s (%s)\n' "uuid" "${UUID:0:13}…" "$UUID_SOURCE"
        printf '  %-12s %s\n' "path" "$HTTP_PATH"
        echo ""
        if g2ray_is_running && link="$(g2ray_link 2>/dev/null)"; then
            printf '  link: %s\n' "$link"
        else
            echo "  start the server with: g2ray start"
        fi
        ;;

    new-uuid)
        g2ray_state_ensure
        if [ -n "${G2RAY_UUID:-}" ]; then
            g2ray_warn "G2RAY_UUID secret is set — rotation is overridden by the secret"
        fi
        UUID="$(cat /proc/sys/kernel/random/uuid)"
        UUID_SOURCE="generated"
        umask 077
        printf "UUID='%s'\nHTTP_PATH='%s'\n" "$UUID" "$HTTP_PATH" > "$G2RAY_STATE_FILE"
        g2ray_render_config
        g2ray_stop 2>/dev/null || true
        g2ray_start
        g2ray_expose
        echo ""
        echo "New connection string:"
        g2ray_link || true
        ;;

    reset)
        rm -f "$G2RAY_STATE_FILE"
        g2ray_info "state wiped — generating fresh UUID and path"
        g2ray_state_ensure
        g2ray_render_config
        g2ray_stop 2>/dev/null || true
        g2ray_start
        g2ray_expose
        echo ""
        echo "New connection string:"
        g2ray_link || true
        ;;

    doctor)
        g2ray_doctor
        ;;

    help|--help|-h)
        sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        ;;

    *)
        g2ray_die "unknown command: $cmd (try: g2ray help)"
        ;;
esac
