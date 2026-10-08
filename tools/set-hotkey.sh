#!/usr/bin/env bash
# =============================================================================
#  set-hotkey.sh <key-combo> <command> [<name>]
#
#  Installs a KDE global shortcut (Custom Shortcuts / khotkeys) that runs
#  <command>. Re-running it updates the existing entry instead of duplicating.
#
#  给 KDE 安装一个全局快捷键(自定义快捷键 / khotkeys),重复运行只会更新而不会重复添加。
#
#  Example:  ./set-hotkey.sh "Ctrl+Alt+R" /home/me/.local/bin/record-screen.sh
# =============================================================================
set -euo pipefail

KEY="${1:?usage: set-hotkey.sh <key-combo> <command> [name]}"
CMD="${2:?usage: set-hotkey.sh <key-combo> <command> [name]}"
NAME="${3:-Screen Recording}"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# Make sure we talk to the session bus even when run from a plain shell.
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || die "no graphical session detected"

command -v qdbus  >/dev/null 2>&1 || die "qdbus not found (this helper only configures KDE shortcuts)"
command -v python3 >/dev/null 2>&1 || die "python3 not found"
python3 -c 'import gi' >/dev/null 2>&1 || true   # not required here

# --- convert "Ctrl+Alt+R" into the Qt key code KGlobalAccel uses -------------
qt_keycode() {
    local combo="$1" mods=0 base=0 part upper n
    local IFS='+'
    read -r -a parts <<< "$combo"
    for part in "${parts[@]}"; do
        case "${part,,}" in
            ctrl|control)    mods=$((mods | 0x04000000)) ;;
            alt)             mods=$((mods | 0x08000000)) ;;
            shift)           mods=$((mods | 0x02000000)) ;;
            meta|super|win)  mods=$((mods | 0x10000000)) ;;
            f1|f2|f3|f4|f5|f6|f7|f8|f9|f10|f11|f12)
                             n="${part,,}"; n="${n#f}"      # F10 -> f10 -> 10
                             base=$((0x01000030 + n - 1)) ;;
            [a-z])           upper="${part^^}"; base=$(printf '%d' "'$upper") ;;
            [0-9])           base=$((0x30 + part)) ;;
            *)               die "unsupported key in combo: $part" ;;
        esac
    done
    [ "$base" -ne 0 ] || die "no base key found in combo: $combo"
    printf '%d\n' "$((mods | base))"
}

KEYCODE="$(qt_keycode "$KEY")"

# --- KDE? -------------------------------------------------------------------
if ! qdbus org.kde.kded5 /kded org.kde.kded5.loadedModules 2>/dev/null | grep -qx khotkeys; then
    if ! qdbus org.kde.kded5 /kded >/dev/null 2>&1; then
        warn "this does not look like a running KDE session."
        say  "  Bind this command to a key yourself instead:"
        say  "    GNOME : Settings -> Keyboard -> Custom Shortcuts -> +   command: $CMD"
        say  "    XFCE  : Settings -> Keyboard -> Application Shortcuts"
        say  "    others: use sxhkd / xbindkeys / your DE shortcut settings"
        exit 1
    fi
    warn "the KDE 'khotkeys' module is not loaded (package: khotkeys)."
    warn "the shortcut will be written to the config and applied after next login."
    MODULE_LOADED=0
else
    MODULE_LOADED=1
fi

# --- warn about conflicts ---------------------------------------------------
if gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
      --method org.kde.KGlobalAccel.isGlobalShortcutAvailable "$KEYCODE" khotkeys 2>/dev/null | grep -q false; then
    warn "$KEY is already taken by another shortcut (it may win over this one)."
fi

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/khotkeysrc"

# KDE occasionally re-imports its default shortcut scheme when the khotkeys
# module reloads. Always keep a backup so nothing of yours can be lost.
BACKUP=""
if [ -f "$CONFIG" ]; then
    BACKUP="${CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"
    cp -a "$CONFIG" "$BACKUP"
fi

# --- unload first: the module rewrites its config on unload -----------------
if [ "$MODULE_LOADED" = 1 ]; then
    qdbus org.kde.kded5 /kded org.kde.kded5.unloadModule khotkeys >/dev/null 2>&1 || true
    sleep 1
fi

# --- edit the config --------------------------------------------------------
EDITOR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/khotkeys-edit.py"
[ -r "$EDITOR" ] || die "khotkeys-edit.py not found next to this script"
say "  $(python3 "$EDITOR" set "$CONFIG" "$KEY" "$CMD" "$NAME") -> $CONFIG"

# --- reload the module ------------------------------------------------------
if [ "$MODULE_LOADED" = 1 ]; then
    qdbus org.kde.kded5 /kded org.kde.kded5.loadModule khotkeys >/dev/null 2>&1 || true
    sleep 2
fi

# --- verify -----------------------------------------------------------------
# KGlobalAccel answers "(@a(ssssssaiai) [],)" when nobody holds the key and
# "([('{uuid}', 'name', ...)],)" when somebody does.
key_is_bound() {
    gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method org.kde.KGlobalAccel.getGlobalShortcutsByKey "$1" 2>/dev/null \
        | grep -qF "[('"
}

if key_is_bound "$KEYCODE"; then
    ok "$KEY is bound now (toggle recording)"
    say "  backup of the previous shortcut config: ${BACKUP:-none}"
    exit 0
fi

warn "$KEY does not look bound yet."
if [ "$MODULE_LOADED" = 1 ] && [ -n "${BACKUP:-}" ] && [ -f "$BACKUP" ]; then
    cp -a "$BACKUP" "$CONFIG"
    warn "restored your previous config from $BACKUP"
    qdbus org.kde.kded5 /kded org.kde.kded5.unloadModule khotkeys >/dev/null 2>&1 || true
    qdbus org.kde.kded5 /kded org.kde.kded5.loadModule khotkeys >/dev/null 2>&1 || true
fi
say ""
say "Bind it by hand instead (reliable):"
say "  KDE   : System Settings -> Shortcuts -> Custom Shortcuts -> Edit -> New ->"
say "          Command/URL, command: $CMD"
say "  GNOME : Settings -> Keyboard -> Custom Shortcuts -> +   command: $CMD"
say "  XFCE  : Settings -> Keyboard -> Application Shortcuts"
exit 1
