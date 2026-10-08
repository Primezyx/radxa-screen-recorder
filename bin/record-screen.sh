#!/usr/bin/env bash
# =============================================================================
#  radxa-screen-recorder — lightweight screen recorder built on GStreamer
#  radxa-screen-recorder — 基于 GStreamer 的轻量屏幕录制工具
#
#  Highlights / 特点:
#    * Uses the SoC hardware H.264 encoder when it is usable
#      能用则用 SoC 硬件 H.264 编码器(Allwinner Cedar / V4L2 / VA-API / NVENC)
#    * Optional floating "Stop & Save" bar, no terminal needed
#      可选的悬浮「停止并保存」控制条,无需开终端
#    * Verifies every recording is decodable, so you never end up with a
#      silently corrupted file (some vendor encoders do produce those!)
#      录完自动解码自检,不会让你拿到静默损坏的文件
#
#  License: MIT
# =============================================================================
set -uo pipefail

VERSION="1.0.0"
PROG="${0##*/}"

# -----------------------------------------------------------------------------
# i18n / 多语言(跟随 $LANG)
# -----------------------------------------------------------------------------
case "${LC_ALL:-${LANG:-}}" in
    zh*|*_CN*|*_TW*|*_HK*) LANG_CODE=zh ;;
    *)                     LANG_CODE=en ;;
esac

declare -A MSG_ZH=(
    [no_x11]='错误: 未检测到 X11 会话(DISPLAY 为空)。\n本工具基于 ximagesrc,只能录制 X11 桌面。\nWayland 用户建议改用 wf-recorder 或桌面自带录屏。'
    [wayland]='警告: 检测到 Wayland 会话,当前通过 XWayland 工作,只能录到 XWayland 窗口,无法录制整个桌面。'
    [no_gst]='错误: 找不到 gst-launch-1.0。请先安装: sudo apt install gstreamer1.0-tools'
    [no_hw]='错误: 没有找到可用的硬件编码器。请改用 --encoder sw(软件编码)。'
    [bad_region]='错误: 区域格式应为 WxH 或 WxH+X+Y,例如 1280x720 或 1280x720+100+50'
    [start]='开始录制 [%s, %s fps, 编码 %s]%s → %s'
    [hint_stop]='点屏幕上方悬浮条的「停止并保存」,或再运行一次本命令'
    [saved]='录制已保存: %s (%s)'
    [broken]='⚠ 录到的文件无法解码!请改用 --encoder sw 重录。文件: %s'
    [empty]='录制失败: 文件为空。日志: %s'
    [startfail]='启动失败,日志:'
    [notrec]='当前没有在录制。'
    [discarded]='已丢弃本次录制,未保存文件。'
    [running]='正在录制 (PID %s): %s'
    [idle]='未在录制。'
    [autostop]='%s 秒后自动停止'
    [withaudio]=' +声音'
    [no_hw_list]='(未检测到硬件编码器)'
    [hw_list]='硬件编码器: %s'
    [sw_list]='软件编码器: x264enc (libx264)'
)
declare -A MSG_EN=(
    [no_x11]='Error: no X11 session detected (DISPLAY is empty).\nThis tool uses ximagesrc and only works on X11 desktops.\nOn Wayland please use wf-recorder or your desktop'"'"'s built-in recorder.'
    [wayland]='Warning: Wayland session detected. Running through XWayland, so only XWayland windows can be captured, not the whole desktop.'
    [no_gst]='Error: gst-launch-1.0 not found. Install it first: sudo apt install gstreamer1.0-tools'
    [no_hw]='Error: no usable hardware encoder found. Use --encoder sw instead.'
    [bad_region]='Error: region must look like WxH or WxH+X+Y, e.g. 1280x720 or 1280x720+100+50'
    [start]='Recording [%s, %s fps, encoder %s]%s -> %s'
    [hint_stop]='Click "Stop & Save" on the floating bar, or run this command again'
    [saved]='Saved: %s (%s)'
    [broken]='WARNING: the recorded file is not decodable! Re-record with --encoder sw. File: %s'
    [empty]='Recording failed: empty file. Log: %s'
    [startfail]='Failed to start, log:'
    [notrec]='Not recording.'
    [discarded]='Recording discarded, nothing saved.'
    [running]='Recording (PID %s): %s'
    [idle]='Not recording.'
    [autostop]='auto-stop after %ss'
    [withaudio]=' +audio'
    [no_hw_list]='(no hardware encoder detected)'
    [hw_list]='hardware encoder: %s'
    [sw_list]='software encoder: x264enc (libx264)'
)

msg() {
    local key="$1"; shift
    if [ "$LANG_CODE" = zh ]; then
        # shellcheck disable=SC2059
        printf "${MSG_ZH[$key]}" "$@"
    else
        # shellcheck disable=SC2059
        printf "${MSG_EN[$key]}" "$@"
    fi
}

# -----------------------------------------------------------------------------
# Defaults / 默认值
# -----------------------------------------------------------------------------
FPS=30
REGION=""
AUDIO=0
ENCODER=auto          # auto | hw | sw | <gst element name>
DURATION=""
OUTDIR="${HOME}/Videos"
FORMAT=mkv            # mkv | mp4
GUI=auto              # auto | 0
VERIFY=1
NOTIFY=auto           # auto | kdialog | notify-send | none
NAME_PREFIX=screen
HW_FULLSCREEN_ONLY=1  # see docs/allwinner-omxh264-encoder-bug.md

# Remember what the user exported, so env vars beat the config file
declare -A FROM_ENV=()
for _v in FPS REGION AUDIO ENCODER DURATION OUTDIR FORMAT GUI VERIFY NOTIFY NAME_PREFIX HW_FULLSCREEN_ONLY; do
    FROM_ENV[$_v]="${!_v:-}"
done

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/record-screen"
CONFIG_FILE="$CONFIG_DIR/config"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE="$RUNTIME_DIR/record-screen.$(id -u).state"
LOG="$RUNTIME_DIR/record-screen.$(id -u).log"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
GUI_SCRIPT="$SCRIPT_DIR/record-screen-gui.py"

# -----------------------------------------------------------------------------
# Helpers / 工具函数
# -----------------------------------------------------------------------------
die()  { printf '%s\n' "$*" >&2; exit 1; }
warn() { printf '%s\n' "$*" >&2; }

load_config() {
    [ -r "$CONFIG_FILE" ] || return 0
    local line key value
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in ''|'#'*) continue ;; esac
        key="${line%%=*}"
        value="${line#*=}"
        value="${value%$'\r'}"
        case "$value" in \"*\") value="${value#\"}"; value="${value%\"}" ;; esac
        case "$key" in
            FPS|REGION|AUDIO|ENCODER|DURATION|OUTDIR|FORMAT|GUI|VERIFY|NOTIFY|NAME_PREFIX|HW_FULLSCREEN_ONLY)
                printf -v "$key" '%s' "$value" ;;
        esac
    done < "$CONFIG_FILE"
}

restore_env() {
    local v
    for v in FPS REGION AUDIO ENCODER DURATION OUTDIR FORMAT GUI VERIFY NOTIFY NAME_PREFIX HW_FULLSCREEN_ONLY; do
        [ -n "${FROM_ENV[$v]}" ] && printf -v "$v" '%s' "${FROM_ENV[$v]}"
    done
    return 0
}

notify() {
    local text="$1"
    case "$NOTIFY" in
        none) ;;
        kdialog)
            command -v kdialog >/dev/null 2>&1 && kdialog --passivepopup "$text" 8 >/dev/null 2>&1 ;;
        notify-send)
            command -v notify-send >/dev/null 2>&1 && notify-send -t 8000 "$PROG" "$text" >/dev/null 2>&1 ;;
        auto)
            if command -v kdialog >/dev/null 2>&1; then
                kdialog --passivepopup "$text" 8 >/dev/null 2>&1
            elif command -v notify-send >/dev/null 2>&1; then
                notify-send -t 8000 "$PROG" "$text" >/dev/null 2>&1
            fi ;;
    esac
    printf '%s\n' "$text"
}

# Find a usable hardware H.264 encoder element
find_hw_encoder() {
    local e
    for e in omxh264videoenc v4l2h264enc vah264enc nvh264enc; do
        if gst-inspect-1.0 "$e" >/dev/null 2>&1; then
            printf '%s\n' "$e"
            return 0
        fi
    done
    return 1
}

resolve_encoder() {
    case "$ENCODER" in
        sw) printf 'x264enc speed-preset=ultrafast tune=zerolatency\n' ;;
        hw)
            local hw; hw="$(find_hw_encoder)" || die "$(msg no_hw)"
            printf '%s\n' "$hw" ;;
        auto)
            # Vendor encoders can be broken at non-native resolutions, so when a
            # region is used we default to software encoding (see docs).
            if [ "$HW_FULLSCREEN_ONLY" = 1 ] && [ -n "$REGION" ]; then
                printf 'x264enc speed-preset=ultrafast tune=zerolatency\n'
            else
                local hw; hw="$(find_hw_encoder)" || hw=""
                if [ -n "$hw" ]; then printf '%s\n' "$hw"
                else printf 'x264enc speed-preset=ultrafast tune=zerolatency\n'; fi
            fi ;;
        *) printf '%s\n' "$ENCODER" ;;
    esac
}

check_environment() {
    command -v gst-launch-1.0 >/dev/null 2>&1 || die "$(msg no_gst)"
    [ -n "${DISPLAY:-}" ] || die "$(msg no_x11)"
    if [ "${XDG_SESSION_TYPE:-}" = wayland ]; then
        warn "$(msg wayland)"
    fi
    [ -n "${WAYLAND_DISPLAY:-}" ] && [ "${XDG_SESSION_TYPE:-}" = wayland ] && \
        warn "$(msg wayland)"
    return 0
}

running_pid() {
    [ -f "$STATE" ] || return 1
    local pid
    pid="$(cut -d' ' -f1 "$STATE" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && printf '%s\n' "$pid"
}

# Is the recorded file actually decodable?
#
# Software decoding is forced on purpose: on several ARM SoCs the vendor
# hardware *decoder* is as broken as the encoder (Allwinner's omxh264dec fails
# with "decode fatal error[-1]" on perfectly valid streams), and decodebin would
# happily pick it, reporting a good recording as corrupt.
verify_file() {
    GST_PLUGIN_FEATURE_RANK="omxh264dec:0,avdec_h264:MAX" \
        gst-launch-1.0 -q filesrc location="$1" ! decodebin ! fakesink num-buffers=1 >/dev/null 2>&1
}

print_help() {
    if [ "$LANG_CODE" = zh ]; then
        cat <<EOF
$PROG $VERSION — 用 GStreamer 录屏(优先使用硬件编码器)

用法:
  $PROG [选项] [命令]

命令:
  start          开始录制(默认;若已在录制则等同于 toggle)
  stop           停止并保存
  discard        停止并丢弃
  status         查看是否在录制
  list-encoders  列出检测到的编码器
  help           显示本帮助

选项:
  -r, --region WxH[+X+Y]   只录该区域(默认全屏),例如 1280x720 或 800x600+100+50
  -f, --fps N              帧率,默认 30
  -e, --encoder NAME       auto(默认) | hw | sw | 具体的 gst 元素名
  -a, --audio              同时录制系统声音
  -d, --duration N         录制 N 秒后自动停止
  -o, --outdir DIR         输出目录,默认 ~/Videos
      --format mkv|mp4     容器格式,默认 mkv
      --no-gui             不显示悬浮控制条
      --no-verify          录完不做解码自检
      --notify MODE        auto(默认) | kdialog | notify-send | none
  -h, --help               显示帮助
  -V, --version            显示版本

配置文件(优先级: 命令行 > 环境变量 > 配置文件 > 默认值):
  $CONFIG_FILE
  内容形如 FPS=30、ENCODER=auto、OUTDIR=/home/me/Videos

示例:
  $PROG                          # 全屏录制,再运行一次停止
  $PROG -r 1280x720 -a           # 录 720p 区域 + 系统声音
  $PROG -e sw -d 60              # 软件编码,录 60 秒
EOF
    else
        cat <<EOF
$PROG $VERSION — screen recorder built on GStreamer (hardware encoder preferred)

Usage:
  $PROG [options] [command]

Commands:
  start          start recording (default; toggles if already recording)
  stop           stop and save
  discard        stop and throw the recording away
  status         show whether recording is in progress
  list-encoders  list detected encoders
  help           show this help

Options:
  -r, --region WxH[+X+Y]   capture only this region, e.g. 1280x720 or 800x600+100+50
  -f, --fps N              frame rate, default 30
  -e, --encoder NAME       auto (default) | hw | sw | explicit gst element name
  -a, --audio              record system audio as well
  -d, --duration N         stop automatically after N seconds
  -o, --outdir DIR         output directory, default ~/Videos
      --format mkv|mp4     container format, default mkv
      --no-gui             do not show the floating stop bar
      --no-verify          skip the decodability self-check
      --notify MODE        auto (default) | kdialog | notify-send | none
  -h, --help               show this help
  -V, --version            show version

Config file (priority: CLI > environment > config file > defaults):
  $CONFIG_FILE
  e.g. FPS=30, ENCODER=auto, OUTDIR=/home/me/Videos

Examples:
  $PROG                          # full screen, run again to stop
  $PROG -r 1280x720 -a           # 720p region plus system audio
  $PROG -e sw -d 60              # software encoder, 60 seconds
EOF
    fi
}

# -----------------------------------------------------------------------------
# Recording control / 录制控制
# -----------------------------------------------------------------------------
start_recording() {
    check_environment
    mkdir -p "$OUTDIR" || die "cannot create $OUTDIR"

    local out
    out="$OUTDIR/${NAME_PREFIX}-$(date +%Y%m%d-%H%M%S).${FORMAT}"

    # region -> ximagesrc properties
    local region_args=()
    local size_note
    if [ "$LANG_CODE" = zh ]; then size_note="全屏"; else size_note="fullscreen"; fi
    if [ -n "$REGION" ]; then
        local geo wh xy w h x y
        geo="$REGION"; wh="${geo%%+*}"; xy="${geo#"$wh"}"
        w="${wh%%x*}"; h="${wh##*x}"
        case "$w$h" in ''|*[!0-9]*) die "$(msg bad_region)" ;; esac
        region_args=(startx=0 starty=0 "endx=$((w - 1))" "endy=$((h - 1))")
        if [ -n "$xy" ]; then
            x="${xy#+}"; x="${x%%+*}"; y="${xy##*+}"
            case "$x$y" in ''|*[!0-9]*) die "$(msg bad_region)" ;; esac
            region_args=("startx=$x" "starty=$y" "endx=$((x + w - 1))" "endy=$((y + h - 1))")
        fi
        size_note="$REGION"
    fi

    local enc_args=()
    read -r -a enc_args <<< "$(resolve_encoder)"
    local enc_name="${enc_args[0]}"

    local mux="matroskamux"
    [ "$FORMAT" = mp4 ] && mux="qtmux"

    local pipe=(
        gst-launch-1.0 -e -q
        "$mux" name=mux ! filesink "location=$out"
        ximagesrc use-damage=0 "${region_args[@]}"
        ! "video/x-raw,framerate=$FPS/1"
        ! videoconvert
        ! "${enc_args[@]}"
        ! h264parse
        ! mux.
    )
    if [ "$AUDIO" = 1 ]; then
        pipe+=( pulsesrc ! audioconvert ! audioresample ! queue ! voaacenc ! aacparse ! mux. )
    fi

    nohup "${pipe[@]}" >"$LOG" 2>&1 &
    local pid=$!
    sleep 2

    if ! kill -0 "$pid" 2>/dev/null; then
        printf '%s\n' "$(msg startfail)"
        grep -viE 'DEBUG|INFO.*cedarc|ionAlloc' "$LOG" 2>/dev/null | tail -8
        return 1
    fi

    printf '%s %s\n' "$pid" "$out" > "$STATE"

    # Floating stop bar / 悬浮停止条
    if [ "$GUI" != 0 ] && [ -x "$GUI_SCRIPT" ] && command -v python3 >/dev/null 2>&1 \
       && python3 -c 'import gi' >/dev/null 2>&1; then
        nohup python3 "$GUI_SCRIPT" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi

    # Auto-stop timer / 定时自动停止
    if [ -n "$DURATION" ]; then
        nohup bash -c "sleep $DURATION; '$SCRIPT_DIR/$PROG' stop" >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi

    local extra=""
    [ "$AUDIO" = 1 ] && extra="$(msg withaudio)"
    [ -n "$DURATION" ] && extra="$extra, $(msg autostop "$DURATION")"
    notify "$(msg start "$size_note" "$FPS" "$enc_name" "$extra" "$out")"
    printf '%s\n' "$(msg hint_stop)"
}

stop_recording() {
    local pid out
    if ! pid="$(running_pid)"; then
        printf '%s\n' "$(msg notrec)"
        rm -f "$STATE"
        return 0
    fi
    out="$(cut -d' ' -f2- "$STATE")"

    # SIGINT + gst-launch -e => proper file trailer
    kill -INT "$pid" 2>/dev/null
    local tries=0
    while [ "$tries" -lt 60 ]; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
        tries=$((tries + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null
        sleep 1
    fi
    rm -f "$STATE"

    if [ ! -s "$out" ]; then
        notify "$(msg empty "$LOG")"
        grep -viE 'DEBUG|INFO.*cedarc|ionAlloc' "$LOG" 2>/dev/null | tail -5
        return 1
    fi

    if [ "$VERIFY" = 1 ] && ! verify_file "$out"; then
        notify "$(msg broken "$out")"
        return 1
    fi
    notify "$(msg saved "$(basename "$out")" "$(du -h "$out" | cut -f1)")"
}

discard_recording() {
    local pid out
    if ! pid="$(running_pid)"; then
        printf '%s\n' "$(msg notrec)"
        rm -f "$STATE"
        return 0
    fi
    out="$(cut -d' ' -f2- "$STATE")"
    kill -KILL "$pid" 2>/dev/null
    sleep 0.5
    rm -f "$STATE" "$out"
    notify "$(msg discarded)"
}

show_status() {
    local pid
    if pid="$(running_pid)"; then
        msg running "$pid" "$(cut -d' ' -f2- "$STATE")"; printf '\n'
    else
        printf '%s\n' "$(msg idle)"
    fi
}

list_encoders() {
    local hw
    if hw="$(find_hw_encoder)"; then msg hw_list "$hw"; else msg no_hw_list; fi
    printf '\n'
    msg sw_list
    printf '\n'
    printf 'gstreamer: %s\n' "$(gst-launch-1.0 --version 2>/dev/null | head -1)"
}

# -----------------------------------------------------------------------------
# Argument parsing / 参数解析
# -----------------------------------------------------------------------------
COMMAND=""
load_config
restore_env

while [ $# -gt 0 ]; do
    case "$1" in
        -r|--region)   REGION="${2:-}"; shift 2 ;;
        -f|--fps)      FPS="${2:-}"; shift 2 ;;
        -e|--encoder)  ENCODER="${2:-}"; shift 2 ;;
        -a|--audio)    AUDIO=1; shift ;;
        -d|--duration) DURATION="${2:-}"; shift 2 ;;
        -o|--outdir)   OUTDIR="${2:-}"; shift 2 ;;
        --format)      FORMAT="${2:-}"; shift 2 ;;
        --no-gui)      GUI=0; shift ;;
        --no-verify)   VERIFY=0; shift ;;
        --notify)      NOTIFY="${2:-}"; shift 2 ;;
        -h|--help)     print_help; exit 0 ;;
        -V|--version)  printf '%s %s\n' "$PROG" "$VERSION"; exit 0 ;;
        -*)            die "unknown option: $1 (try --help)" ;;
        *)             COMMAND="$1"; shift ;;
    esac
done

case "${COMMAND:-start}" in
    start|toggle)
        if running_pid >/dev/null; then stop_recording; else start_recording; fi ;;
    stop)          stop_recording ;;
    discard)       discard_recording ;;
    status)        show_status ;;
    list-encoders) list_encoders ;;
    help)          print_help ;;
    *)             die "unknown command: $COMMAND (try --help)" ;;
esac
