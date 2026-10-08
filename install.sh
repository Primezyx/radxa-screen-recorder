#!/usr/bin/env bash
# =============================================================================
#  radxa-screen-recorder installer / 安装脚本
#
#    ./install.sh                     install to ~/.local (no root needed)
#    ./install.sh --system            install to /usr/local (needs sudo)
#    ./install.sh --hotkey            also bind a KDE global shortcut (toggle)
#    ./install.sh --hotkey --key "Ctrl+Alt+R"
#    ./install.sh --install-deps      let it run the package manager itself
# =============================================================================
set -euo pipefail

VERSION="1.0.0"
SRC_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
HOTKEY=0
HOTKEY_BACKEND="auto"     # auto | xbindkeys | khotkeys
KEY="Ctrl+Alt+R"
INSTALL_DEPS=0

usage() {
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Options:
  --prefix DIR      install prefix (default: $HOME/.local)
  --system          shortcut for --prefix /usr/local (needs sudo)
  --hotkey          install a global shortcut that toggles recording
  --hotkey-backend B  auto (default) | xbindkeys | khotkeys
                      auto prefers xbindkeys: it grabs the key at the X11 level
                      and cannot be reset by the desktop environment
  --key COMBO       key for --hotkey (default: Ctrl+Alt+R)
  --install-deps    run the system package manager to install missing deps
  -h, --help        show this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix)       PREFIX="${2:?}"; shift 2 ;;
        --system)       PREFIX="/usr/local"; shift ;;
        --hotkey)       HOTKEY=1; shift ;;
        --hotkey-backend) HOTKEY_BACKEND="${2:?}"; shift 2 ;;
        --key)          KEY="${2:?}"; shift 2 ;;
        --install-deps) INSTALL_DEPS=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

BIN_DIR="$PREFIX/bin"
APP_DIR="$PREFIX/share/applications"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/record-screen"

say()  { printf '%s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
say "radxa-screen-recorder $VERSION installer"
say "  prefix: $PREFIX"
say ""

# --- 1. dependencies --------------------------------------------------------
say "[1/5] checking dependencies"
MISSING=()
command -v gst-launch-1.0 >/dev/null 2>&1 || MISSING+=("gstreamer1.0-tools")
command -v gst-inspect-1.0 >/dev/null 2>&1 || MISSING+=("gstreamer1.0-tools")

if [ ${#MISSING[@]} -gt 0 ]; then
    warn "missing: ${MISSING[*]}"
    PKGMGR=""
    for m in apt-get dnf pacman zypper; do command -v "$m" >/dev/null 2>&1 && { PKGMGR="$m"; break; }; done
    if [ -n "$PKGMGR" ]; then
        case "$PKGMGR" in
            apt-get) CMD="sudo apt-get install -y gstreamer1.0-tools"
                     [ "$HOTKEY" = 1 ] && CMD="$CMD xbindkeys" ;;
            dnf)     CMD="sudo dnf install -y gstreamer1-tools" ;;
            pacman)  CMD="sudo pacman -S --needed gstreamer" ;;
            zypper)  CMD="sudo zypper install gstreamer-plugins-base" ;;
        esac
        if [ "$INSTALL_DEPS" = 1 ]; then
            say "  running: $CMD"
            eval "$CMD"
        else
            warn "install it with:  $CMD"
            warn "or re-run this script with --install-deps"
        fi
    fi
else
    ok "gst-launch-1.0 $(gst-launch-1.0 --version 2>/dev/null | head -1 | awk '{print $NF}')"
fi

if [ "$HOTKEY" = 1 ] && ! command -v xbindkeys >/dev/null 2>&1; then
    warn "xbindkeys is not installed, so the shortcut would fall back to KDE's khotkeys"
    warn "  (khotkeys can re-import its default scheme and wipe custom shortcuts)."
    warn "  Recommended:  sudo apt install xbindkeys   or re-run with --install-deps"
    [ "$INSTALL_DEPS" = 1 ] && MISSING+=("xbindkeys")
fi

# optional pieces
if command -v kdialog >/dev/null 2>&1 || command -v notify-send >/dev/null 2>&1; then
    ok "desktop notifications"
else
    warn "no kdialog/notify-send: notifications will be printed to the terminal only"
fi
if python3 -c 'import gi; gi.require_version("Gtk","3.0")' >/dev/null 2>&1; then
    ok "GTK3 python bindings (floating stop bar available)"
else
    warn "python3-gi missing: the floating stop bar will be disabled"
    warn "  Debian/Ubuntu: sudo apt install python3-gi gir1.2-gtk-3.0"
fi

# --- 2. install files -------------------------------------------------------
say ""
say "[2/5] installing files"
mkdir -p "$BIN_DIR" "$APP_DIR"
install -m 755 "$SRC_DIR/bin/record-screen.sh"     "$BIN_DIR/record-screen.sh"
install -m 755 "$SRC_DIR/bin/record-screen-gui.py" "$BIN_DIR/record-screen-gui.py"
ok "$BIN_DIR/record-screen.sh"
ok "$BIN_DIR/record-screen-gui.py"

for d in record-screen record-screen-stop; do
    sed "s|@EXEC@|$BIN_DIR/record-screen.sh|g" "$SRC_DIR/desktop/$d.desktop.in" \
        > "$APP_DIR/$d.desktop"
    chmod 644 "$APP_DIR/$d.desktop"
done
ok "$APP_DIR/record-screen.desktop"
ok "$APP_DIR/record-screen-stop.desktop"

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$APP_DIR"/record-screen*.desktop || true
fi
command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
command -v kbuildsycoca5 >/dev/null 2>&1 && kbuildsycoca5 --noincremental >/dev/null 2>&1 || true

# --- 3. config example ------------------------------------------------------
say ""
say "[3/5] configuration"
if [ -f "$CONFIG_DIR/config" ]; then
    ok "keeping existing $CONFIG_DIR/config"
else
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/config.example" <<'EOF'
# radxa-screen-recorder configuration
# Copy to "config" (same directory) and edit. Command line flags win over this.
#
# FPS=30                 frame rate
# REGION=1280x720        capture only this region (default: full screen)
#                        also supports an offset: 1280x720+100+50
# AUDIO=1                also record system audio (needs a PulseAudio/PipeWire source)
# ENCODER=auto           auto | hw | sw | <gstreamer element name>
# DURATION=60            stop automatically after N seconds
# OUTDIR=/home/me/Videos output directory
# FORMAT=mkv             mkv | mp4
# GUI=0                  set to 0 to disable the floating stop bar
# VERIFY=1               set to 0 to skip the decodability self-check
# NOTIFY=auto            auto | kdialog | notify-send | none
# NAME_PREFIX=screen     output file name prefix
# HW_FULLSCREEN_ONLY=1   only use the hardware encoder at the native (full screen)
#                        resolution. Keep this at 1 on Allwinner SoCs: their OMX
#                        encoder writes broken files at other resolutions.
#                        See docs/allwinner-omxh264-encoder-bug.md
EOF
    ok "wrote $CONFIG_DIR/config.example"
fi

# --- 4. optional KDE global shortcut ---------------------------------------
say ""
say "[4/5] global shortcut"
if [ "$HOTKEY" != 1 ]; then
    warn "skipped (pass --hotkey to let the installer bind one)"
else
    BACKEND="$HOTKEY_BACKEND"
    if [ "$BACKEND" = auto ]; then
        if command -v xbindkeys >/dev/null 2>&1; then
            BACKEND=xbindkeys
        elif command -v qdbus >/dev/null 2>&1 && qdbus org.kde.kded5 /kded >/dev/null 2>&1; then
            BACKEND=khotkeys
        else
            BACKEND=none
        fi
    fi
    case "$BACKEND" in
        xbindkeys)
            # XBINDKEYS_SETUP_OPTS lets scripted installs pass e.g. "--no-restart"
            # shellcheck disable=SC2086
            "$SRC_DIR/tools/xbindkeys-setup.sh" add "$KEY" "$BIN_DIR/record-screen.sh" \
                ${XBINDKEYS_SETUP_OPTS:-} || \
                warn "could not bind the key; add it to ~/.xbindkeysrc by hand" ;;
        khotkeys)
            warn "using KDE khotkeys: it occasionally re-imports its default shortcut"
            warn "  scheme and can wipe custom entries. For a binding that cannot be"
            warn "  reset, install xbindkeys and re-run with --hotkey-backend xbindkeys."
            "$SRC_DIR/tools/set-hotkey.sh" "$KEY" "$BIN_DIR/record-screen.sh" || \
                warn "could not install the shortcut automatically; bind '$BIN_DIR/record-screen.sh' to a key manually" ;;
        *)
            warn "no xbindkeys and no KDE session found."
            say "  Bind '$BIN_DIR/record-screen.sh' to a key yourself:"
            say "    GNOME : Settings -> Keyboard -> Custom Shortcuts -> +"
            say "    XFCE  : Settings -> Keyboard -> Application Shortcuts"
            say "    others: sxhkd / xbindkeys / your desktop's shortcut settings" ;;
    esac
fi

# --- 5. done ----------------------------------------------------------------
say ""
say "[5/5] done"
case ":$PATH:" in
    *":$BIN_DIR:"*) ok "$BIN_DIR is in your PATH" ;;
    *) warn "$BIN_DIR is NOT in your PATH"
       warn "  add this to ~/.bashrc / ~/.zshrc:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
say ""
say "Try it:"
say "  record-screen.sh                 # full screen, run again to stop"
say "  record-screen.sh -r 1280x720 -a  # 720p region + system audio"
say "  record-screen.sh status          # is it recording?"
say "  record-screen.sh --help          # all options"
say ""
say "Your desktop menu should now have:  Screen Recording (start/stop)  and  Stop Recording"
