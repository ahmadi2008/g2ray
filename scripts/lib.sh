#!/usr/bin/env bash
# g2ray — shared library sourced by post-start.sh, post-attach.sh and g2ray.sh
# shellcheck shell=bash
if [ -n "${G2RAY_LIB_LOADED:-}" ]; then return 0; fi
G2RAY_LIB_LOADED=1

G2RAY_VERSION="2.0.0"

# Layout
G2RAY_STATE_DIR="${G2RAY_STATE_DIR:-$HOME/.g2ray}"
G2RAY_STATE_FILE="$G2RAY_STATE_DIR/state.env"
G2RAY_CONFIG="$G2RAY_STATE_DIR/config.json"
G2RAY_LOG="$G2RAY_STATE_DIR/xray.log"
G2RAY_TEMPLATE="${G2RAY_TEMPLATE:-/opt/g2ray/config.template.json}"
G2RAY_BIN="${G2RAY_BIN:-/usr/local/bin/xray}"

# Tunables (all optional)
G2RAY_PORT="${G2RAY_PORT:-443}"                 # internal listen port
G2RAY_TAG="${G2RAY_TAG:-g2ray-v2}"              # connection link label
G2RAY_UUID="${G2RAY_UUID:-}"                    # optional Codespaces secret override

# ---------------------------------------------------------------- utilities --

g2ray_die()   { printf '[g2ray] ERROR: %s\n' "$*" >&2; exit 1; }
g2ray_warn()  { printf '[g2ray] WARN : %s\n' "$*" >&2; }
g2ray_info()  { printf '[g2ray] %s\n' "$*"; }

g2ray_have()  { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------------- naming --

g2ray_host() {
    [ -n "${CODESPACE_NAME:-}" ] || return 1
    printf '%s-%s.app.github.dev' "$CODESPACE_NAME" "$G2RAY_PORT"
}

# -------------------------------------------------------------- state: uuid --

# Priority: G2RAY_UUID secret > persisted state > freshly generated.
g2ray_state_ensure() {
    mkdir -p "$G2RAY_STATE_DIR"
    chmod 700 "$G2RAY_STATE_DIR" 2>/dev/null

    UUID=""; HTTP_PATH=""
    # shellcheck disable=SC1090
    [ -f "$G2RAY_STATE_FILE" ] && . "$G2RAY_STATE_FILE"

    UUID_SOURCE="stored"
    if [ -n "${G2RAY_UUID:-}" ] && [ "$G2RAY_UUID" != "$UUID" ]; then
        UUID="$G2RAY_UUID"
        UUID_SOURCE="secret"
    fi
    if [ -z "$UUID" ]; then
        UUID="$(cat /proc/sys/kernel/random/uuid)"
        UUID_SOURCE="generated"
    fi
    if [ -z "$HTTP_PATH" ]; then
        HTTP_PATH="/g2-$(openssl rand -hex 4 2>/dev/null || head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    fi

    local umask_old; umask_old="$(umask)"
    umask 077
    cat > "$G2RAY_STATE_FILE" <<EOF
UUID='$UUID'
HTTP_PATH='$HTTP_PATH'
EOF
    umask "$umask_old"
}

# ------------------------------------------------------------- config render --

g2ray_render_config() {
    [ -f "$G2RAY_TEMPLATE" ] || g2ray_die "template not found: $G2RAY_TEMPLATE"
    [ -n "$UUID" ] && [ -n "$HTTP_PATH" ] || g2ray_die "state not loaded — call g2ray_state_ensure first"

    sed -e "s|__PORT__|$G2RAY_PORT|g" \
        -e "s|__UUID__|$UUID|g" \
        -e "s|__HTTP_PATH__|$HTTP_PATH|g" \
        "$G2RAY_TEMPLATE" > "$G2RAY_CONFIG"
    chmod 600 "$G2RAY_CONFIG"
}

# -------------------------------------------------------------- link & misc --

g2ray_link() {
    local host; host="$(g2ray_host)" || {
        g2ray_warn "CODESPACE_NAME is not set — cannot build the link outside GitHub Codespaces"
        return 1
    }
    local enc_path="${HTTP_PATH//\//%2F}"
    printf 'vless://%s@%s:443?encryption=none&security=tls&sni=%s&fp=chrome&type=xhttp&mode=packet-up&path=%s#%s\n' \
        "$UUID" "$host" "$host" "$enc_path" "$G2RAY_TAG"
}

g2ray_is_running() {
    pgrep -f "xray run -c $G2RAY_CONFIG" >/dev/null 2>&1
}

# ---------------------------------------------------------------- lifecycle --

g2ray_start() {
    g2ray_state_ensure
    g2ray_render_config

    if g2ray_is_running; then
        g2ray_info "already running (pid $(pgrep -f "xray run -c $G2RAY_CONFIG" | head -n 1))"
        return 0
    fi

    : > "$G2RAY_LOG"

    # Attempt 1: as the current user (works when setcap granted CAP_NET_BIND_SERVICE).
    nohup "$G2RAY_BIN" run -c "$G2RAY_CONFIG" >>"$G2RAY_LOG" 2>&1 &
    sleep 2

    # Attempt 2: fall back to sudo if the low-port bind was denied.
    if ! g2ray_is_running; then
        g2ray_warn "direct bind failed — retrying with sudo"
        nohup sudo -n "$G2RAY_BIN" run -c "$G2RAY_CONFIG" >>"$G2RAY_LOG" 2>&1 &
        sleep 2
    fi

    if ! g2ray_is_running; then
        printf '[g2ray] ERROR: xray exited immediately — last log lines:\n%s\n' \
            "$(tail -n 15 "$G2RAY_LOG" 2>/dev/null || echo '(no log)')" >&2
        return 1
    fi
    g2ray_info "started (pid $(pgrep -f "xray run -c $G2RAY_CONFIG" | head -n 1)), listening on :$G2RAY_PORT"
}

g2ray_stop() {
    local stopped=0
    if pkill -f "xray run -c $G2RAY_CONFIG" 2>/dev/null; then
        stopped=1
    elif sudo -n pkill -f "xray run -c $G2RAY_CONFIG" 2>/dev/null; then
        stopped=1
    fi
    sleep 1
    if [ "$stopped" = 1 ]; then
        g2ray_info "stopped"
    else
        g2ray_info "not running"
    fi
}

# Expose the forwarded port so proxy clients can connect without GitHub auth.
g2ray_expose() {
    if ! g2ray_have gh || [ -z "${CODESPACE_NAME:-}" ]; then
        g2ray_warn "gh CLI unavailable — make port $G2RAY_PORT public manually (Ports panel → Port visibility → Public)"
        return 0
    fi
    if gh codespace ports visibility "$G2RAY_PORT:public" -c "$CODESPACE_NAME" >/dev/null 2>&1; then
        g2ray_info "port $G2RAY_PORT is now public"
    else
        g2ray_warn "could not set port visibility automatically
         → open the PORTS panel, right-click port $G2RAY_PORT, set Port visibility to Public"
    fi
}

# ------------------------------------------------------------------ doctor --

g2ray_doctor() {
    local ok=1 fail=0
    check() { if eval "$2"; then printf '  [ OK ] %s\n' "$1"; else printf '  [FAIL] %s\n' "$1"; fail=1; fi; }

    printf 'g2ray %s — doctor\n' "$G2RAY_VERSION"
    check "Xray binary present"        '[ -x "$G2RAY_BIN" ]'
    check "Codespace name detected"    '[ -n "${CODESPACE_NAME:-}" ]'
    check "state file readable"        '[ -r "$G2RAY_STATE_FILE" ]'
    check "config rendered"            '[ -r "$G2RAY_CONFIG" ]'
    check "xray process running"       'g2ray_is_running'
    check "port $G2RAY_PORT listening" "grep -q \":\$(printf '%04X ' \"$G2RAY_PORT\")\" /proc/net/tcp /proc/net/tcp6 2>/dev/null"
    if g2ray_have gh && [ -n "${CODESPACE_NAME:-}" ]; then
        check "gh CLI authenticated"   'gh auth status >/dev/null 2>&1'
        local vis; vis="$(gh codespace ports -c "$CODESPACE_NAME" 2>/dev/null | grep -E "^$G2RAY_PORT\b" | grep -oiE 'public|private' | head -n 1 || true)"
        if [ "$vis" = "public" ]; then
            printf '  [ OK ] port %s visibility (public)\n' "$G2RAY_PORT"
        elif [ "$vis" = "private" ]; then
            printf '  [FAIL] port %s visibility (private) — run: g2ray start\n' "$G2RAY_PORT"
            fail=1
        else
            printf '  [ ?? ] port %s visibility unknown — check the Ports panel\n' "$G2RAY_PORT"
        fi
    fi
    printf '\n'
    [ "$fail" = 0 ] && g2ray_info "all checks passed" || g2ray_warn "some checks failed — see above"
    return "$fail"
}
