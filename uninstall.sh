#!/usr/bin/env bash
# =============================================================================
#  radxa-screen-recorder uninstaller / 卸载脚本
#
#    ./uninstall.sh                  remove the installed files
#    ./uninstall.sh --purge          also remove config and the global shortcut
#    ./uninstall.sh --prefix DIR     uninstall from a custom prefix
# =============================================================================
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local}"
PURGE=0
SRC_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="${2:?}"; shift 2 ;;
        --system) PREFIX="/usr/local"; shift ;;
        --purge)  PURGE=1; shift ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/record-screen"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

echo "radxa-screen-recorder uninstaller (prefix: $PREFIX)"

# --- stop a running recording ----------------------------------------------
if [ -x "$BIN_DIR/record-screen.sh" ]; then
    "$BIN_DIR/record-screen.sh" stop >/dev/null 2>&1 && ok "stopped a running recording" || true
fi

# --- files ------------------------------------------------------------------
for f in "$BIN_DIR/record-screen.sh" "$BIN_DIR/record-screen-gui.py"; do
    [ -e "$f" ] && rm -f "$f" && ok "removed $f"
done
for f in "$APP_DIR/record-screen.desktop" "$APP_DIR/record-screen-stop.desktop"; do
    [ -e "$f" ] && rm -f "$f" && ok "removed $f"
done
command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
command -v kbuildsycoca5 >/dev/null 2>&1 && kbuildsycoca5 --noincremental >/dev/null 2>&1 || true

# --- purge ------------------------------------------------------------------
if [ "$PURGE" = 1 ]; then
    if [ -d "$CONFIG_DIR" ]; then
        rm -rf "$CONFIG_DIR"
        ok "removed $CONFIG_DIR"
    fi

    if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] && [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] \
       && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
    fi

    if [ -x "$SRC_DIR/tools/xbindkeys-setup.sh" ] && [ -f "${HOME}/.xbindkeysrc" ]; then
        DISPLAY="${DISPLAY:-:0}" "$SRC_DIR/tools/xbindkeys-setup.sh" remove \
            "$BIN_DIR/record-screen.sh" --no-autostart >/dev/null 2>&1 \
            && ok "removed the xbindkeys binding" || warn "no xbindkeys binding found"
    fi

    if command -v qdbus >/dev/null 2>&1 && qdbus org.kde.kded5 /kded >/dev/null 2>&1; then
        KHOTKEYS="${XDG_CONFIG_HOME:-$HOME/.config}/khotkeysrc"
        EDITOR="$SRC_DIR/tools/khotkeys-edit.py"
        if [ -r "$EDITOR" ] && [ -f "$KHOTKEYS" ]; then
            qdbus org.kde.kded5 /kded org.kde.kded5.unloadModule khotkeys >/dev/null 2>&1 || true
            sleep 1
            case "$(python3 "$EDITOR" remove "$KHOTKEYS" "$BIN_DIR/record-screen.sh")" in
                removed) ok "removed the KDE global shortcut" ;;
                *)       warn "no matching global shortcut found" ;;
            esac
            qdbus org.kde.kded5 /kded org.kde.kded5.loadModule khotkeys >/dev/null 2>&1 || true
        fi
    fi
else
    warn "config and global shortcut kept (use --purge to remove them too)"
    warn "  config:   $CONFIG_DIR"
    warn "  shortcut: KDE System Settings -> Shortcuts -> Custom Shortcuts"
fi

echo
ok "uninstalled. Thanks for trying radxa-screen-recorder!"
