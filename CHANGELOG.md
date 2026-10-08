# Changelog

## [1.0.0] — 2026-10-03

First public release / 首个公开版本。

### Added / 新增

- Screen recording on top of GStreamer, preferring a hardware H.264 encoder
  (`omxh264videoenc`, `v4l2h264enc`, `vah264enc`, `nvh264enc`) and falling back to
  software (`x264enc`).
  基于 GStreamer 的录屏,优先硬件 H.264 编码,自动回退软件编码。
- Floating "Stop & Save" bar (GTK3): the whole bar is one big button, it never
  steals focus, and it closes itself when recording ends.
  悬浮「停止并保存」控制条:整条都是按钮,不抢焦点,录制结束自动消失。
- Post-recording decodability self-check (`VERIFY=1`), so silently corrupted
  files are caught immediately.
  录完自动解码自检,静默损坏的文件当场发现。
- Region capture (`WxH`, `WxH+X+Y`), frame rate, system audio, timed stop,
  `mkv`/`mp4` output, output directory and file-name prefix.
  区域录制、帧率、系统声音、定时停止、mkv/mp4、输出目录与文件名前缀。
- Three layers of configuration: CLI flags, environment variables, config file
  (`~/.config/record-screen/config`), plus a documented example.
  三层配置:命令行、环境变量、配置文件,并附注释示例。
- Chinese/English UI that follows `$LANG`.
  界面中英双语,跟随 `$LANG`。
- `install.sh` / `uninstall.sh` (installs into `~/.local` by default, no root).
- Optional global shortcut, **xbindkeys by default** (`tools/xbindkeys-setup.sh`)
  because desktop shortcut systems can silently reset custom entries; KDE's
  khotkeys (`tools/set-hotkey.sh`) is still available as a fallback and backs the
  config up before touching it.
  安装/卸载脚本(默认装进 `~/.local`,无需 root)+ 可选的 KDE 全局快捷键工具。
- Documentation of the Allwinner OMX H.264 encoder bug, with evidence and
  reproduction steps (`docs/allwinner-omxh264-encoder-bug.md`).
  Allwinner OMX H.264 编码器缺陷的完整记录(含证据与复现步骤)。

### Notes / 说明

- **X11 only**: capture uses `ximagesrc`. On Wayland sessions only XWayland windows
  can be recorded.
  **仅支持 X11**;Wayland 下只能录到 XWayland 窗口。
- Region capture uses software encoding by default on Allwinner SoCs, because the
  vendor encoder writes broken files at non-native resolutions
  (`HW_FULLSCREEN_ONLY=1`).
  Allwinner 板子上区域录制默认走软件编码(厂商编码器在非原生分辨率下会写出坏文件)。
- The first ~1 second of a hardware-encoded 1440p recording looks washed out on the
  tested A733 board; later frames are fine.
  在实测的 A733 上,硬件编码的全屏录像开头约 1 秒画面发灰,之后正常。
