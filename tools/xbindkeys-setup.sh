#!/usr/bin/env bash
# =============================================================================
#  xbindkeys-setup.sh — bind a global hotkey through xbindkeys
#
#  Why not the desktop environment's own shortcut system? Because KDE's khotkeys
#  re-imports its default shortcut scheme now and then and can wipe custom
#  entries (that is exactly how we lost the recording shortcut once while
#  developing this). xbindkeys grabs the key at the X11 level from a plain text
#  file, so nothing can reset it behind your back.
#
#  用法 / Usage:
#    xbindkeys-setup.sh add    <key-combo> <command> [options]
#    xbindkeys-setup.sh remove <command>             [options]
#
#  Options:
#    --rc FILE        config file (default: ~/.xbindkeysrc)
#    --no-restart     edit the config only, do not (re)start xbindkeys
#    --no-autostart   do not install the "start at login" desktop entry
#
#  Examples:
#    ./xbindkeys-setup.sh add "Ctrl+Alt+R" "$HOME/.local/bin/record-screen.sh"
#    ./xbindkeys-setup.sh remove "$HOME/.local/bin/record-screen.sh"
# =============================================================================
set -euo pipefail

RC="${HOME}/.xbindkeysrc"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/xbindkeys.desktop"
RESTART=1
AUTOSTART_INSTALL=1
BEGIN_MARK="# >>> radxa-screen-recorder >>>"
END_MARK="# <<< radxa-screen-recorder <<<"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; }

MODE="${1:-}"; shift || true
case "$MODE" in
    add)    [ $# -ge 2 ] || { usage; exit 1; }
            KEY="$1"; CMD="$2"; shift 2 ;;
    remove) [ $# -ge 1 ] || { usage; exit 1; }
            CMD="$1"; shift ;;
    -h|--help|"") usage; exit 0 ;;
    *)      usage; exit 1 ;;
esac

while [ $# -gt 0 ]; do
    case "$1" in
        --rc)           RC="${2:?}"; shift 2 ;;
        --no-restart)   RESTART=0; shift ;;
        --no-autostart) AUTOSTART_INSTALL=0; shift ;;
        *)              die "unknown option: $1" ;;
    esac
done

# --- "Ctrl+Alt+R" -> the keysym spelling xbindkeys expects -------------------
xbind_key() {
    local combo="$1" out=() part lower upper
    local IFS='+'
    read -r -a parts <<< "$combo"
    local has_shift=0
    for part in "${parts[@]}"; do
        lower="${part,,}"
        case "$lower" in
            ctrl|control)   out+=("Control") ;;
            alt)            out+=("Alt") ;;
            shift)          out+=("Shift"); has_shift=1 ;;
            meta|super|win) out+=("Mod4") ;;
            *)              LAST="$part" ;;
        esac
    done
    [ -n "${LAST:-}" ] || die "no base key found in combo: $combo"
    case "${LAST,,}" in
        f[0-9]|f1[0-2]) KEYPART="${LAST^^}" ;;                 # F1..F12
        [0-9])          KEYPART="$LAST" ;;
        [a-z])          if [ "$has_shift" = 1 ]; then upper="${LAST^^}"; KEYPART="$upper"
                        else KEYPART="${LAST,,}"; fi ;;
        *)              KEYPART="$LAST" ;;
    esac
    local joined=""
    for part in "${out[@]}"; do joined="${joined}${joined:++}${part}"; done
    printf '%s+%s\n' "$joined" "$KEYPART"
}

strip_block() {
    # remove a previous managed block, if any
    [ -f "$RC" ] || return 0
    python3 - "$RC" "$BEGIN_MARK" "$END_MARK" <<'PY'
import sys
path, begin, end = sys.argv[1], sys.argv[2], sys.argv[3]
raw = open(path, encoding="utf-8").read()
out, skipping = [], False
for line in raw.splitlines(True):
    if line.strip() == begin:
        skipping = True
        continue
    if line.strip() == end:
        skipping = False
        continue
    if not skipping:
        out.append(line)
text = "".join(out).strip("\n")
open(path, "w", encoding="utf-8").write(text + "\n" if text else "")
PY
}

case "$MODE" in
    add)
        command -v xbindkeys >/dev/null 2>&1 || die "xbindkeys is not installed (Debian/Ubuntu: sudo apt install xbindkeys)"
        KEYSPEC="$(xbind_key "$KEY")"

        strip_block
        {
            printf '%s\n' "$BEGIN_MARK"
            printf '# %s  ->  %s\n' "$KEY" "$(basename "$CMD")"
            printf '"%s"\n' "$CMD"
            printf '    %s\n' "$KEYSPEC"
            printf '%s\n' "$END_MARK"
        } >> "$RC"
        ok "bound $KEY ($KEYSPEC) in $RC"

        if [ "$AUTOSTART_INSTALL" = 1 ]; then
            mkdir -p "$(dirname "$AUTOSTART")"
            cat > "$AUTOSTART" <<'EOF'
[Desktop Entry]
Type=Application
Name=xbindkeys
Name[zh_CN]=xbindkeys 全局快捷键
Comment=Global hotkeys (radxa-screen-recorder)
Comment[zh_CN]=radxa-screen-recorder 的全局快捷键
Exec=xbindkeys
Icon=input-keyboard
Terminal=false
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF
            ok "xbindkeys will start at login ($AUTOSTART)"
        fi

        if [ "$RESTART" = 1 ]; then
            pkill -x xbindkeys 2>/dev/null || true
            sleep 0.5
            if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
                nohup xbindkeys >/dev/null 2>&1 &
                disown 2>/dev/null || true
                sleep 1
                if pgrep -x xbindkeys >/dev/null 2>&1; then
                    ok "xbindkeys running (pid $(pgrep -x xbindkeys | head -1))"
                else
                    warn "xbindkeys did not stay running — check $RC"
                fi
            else
                warn "no graphical session detected; xbindkeys will start at next login"
            fi
        fi
        ;;
    remove)
        strip_block
        ok "removed the binding for $CMD from $RC"
        if [ -f "$AUTOSTART" ] && ! grep -q '^"' "$RC" 2>/dev/null; then
            rm -f "$AUTOSTART"
            ok "removed the autostart entry (no bindings left)"
        fi
        if [ "$RESTART" = 1 ] && pgrep -x xbindkeys >/dev/null 2>&1; then
            if grep -q '^"' "$RC" 2>/dev/null; then
                pkill -x xbindkeys 2>/dev/null || true
                sleep 0.5
                nohup xbindkeys >/dev/null 2>&1 &
                disown 2>/dev/null || true
                ok "xbindkeys restarted"
            else
                pkill -x xbindkeys 2>/dev/null || true
                ok "xbindkeys stopped (no bindings left)"
            fi
        fi
        ;;
esac
