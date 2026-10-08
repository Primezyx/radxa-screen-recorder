# radxa-screen-recorder

[![CI](https://github.com/Primezyx/radxa-screen-recorder/actions/workflows/ci.yml/badge.svg)](https://github.com/Primezyx/radxa-screen-recorder/actions/workflows/ci.yml)

> A lightweight screen recorder for Linux, made for Allwinner / Radxa boards.
> **It uses the hardware encoder when that is safe, and it verifies that every
> recording is actually decodable** — plus a floating "Stop & Save" bar.

![Floating control bar](docs/images/recording-bar.png)

*中文文档:[README.md](README.md)*

---

## Why another recorder?

Recording your screen on a dev board is awkward with the usual options:

- **OBS and friends** are heavy to install and run on an ARM SBC.
- **Plain `ffmpeg`** needs a pile of flags nobody remembers, and many board images
  do not ship it at all.
- **Desktop built-ins**: Plasma only got screen recording in 5.27, so older
  releases (e.g. Plasma 5.20 on Debian 11) have nothing.

Worse, many ARM SoCs have **broken hardware encoders**. On the Allwinner A733 used
to develop this tool, the OpenMAX H.264 encoder only works at the display's native
resolution. At any other size it emits a stream **without an SPS**, i.e. a file
that looks fine (hundreds of KB, correct container metadata) but decodes to
**zero frames** — with no error anywhere. Full analysis:
[docs/allwinner-omxh264-encoder-bug.md](docs/allwinner-omxh264-encoder-bug.md).

So the two things this tool cares about are: **actually use the hardware encoder**,
and **never hand you a corrupt file**.

## Features

- 🎬 **One-key toggle** — global shortcut, desktop menu, floating bar or terminal
- ⚡ **Hardware encoder first** — auto-detects `omxh264videoenc`, `v4l2h264enc`,
  `vah264enc`, `nvh264enc`, falls back to software
- 🔍 **Decodability self-check** — a broken recording warns you immediately instead
  of when you try to play it back
- 🖱️ **Floating stop bar** — the whole bar is one big button, and it never steals focus
- 📐 Region capture, frame rate, system audio, timed stop, mkv or mp4
- ⚙️ Layered config: CLI > environment > config file > defaults
- 🌏 Chinese/English UI, following `$LANG`
- 📦 Installer that only touches `~/.local`, with a matching uninstaller. MIT licensed

## Requirements

| | |
|---|---|
| Session | **X11** (built on `ximagesrc`; see [limitations](#limitations) for Wayland) |
| Required | GStreamer 1.x + `gstreamer1.0-tools` (for `gst-launch-1.0`) |
| Floating bar | `python3-gi` + GTK3 (`gir1.2-gtk-3.0`) — optional |
| Notifications | `kdialog` (KDE) or `notify-send` — optional, terminal output otherwise |
| Audio | PulseAudio or PipeWire's pulse layer — optional |
| Global shortcut | `xbindkeys` (recommended, desktop-independent) or KDE's `khotkeys` — optional |

On Debian/Ubuntu:

```bash
sudo apt install gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly \
                 python3-gi gir1.2-gtk-3.0
```

## Install

```bash
git clone https://github.com/Primezyx/radxa-screen-recorder.git
cd radxa-screen-recorder
./install.sh                 # installs into ~/.local, no root needed
./install.sh --hotkey        # also bind a global shortcut (Ctrl+Alt+R, KDE)
./install.sh --system        # install into /usr/local (needs sudo)
```

The installer checks dependencies, installs both scripts into `~/.local/bin`,
creates two desktop entries and drops an annotated example config at
`~/.config/record-screen/config.example`.

## Usage

### 1. Floating bar

Once recording starts, a bar appears at the top of the screen:

```
● Recording 00:05                 ■ Stop & Save
  screen-20261003-000857.mkv
```

**Click anywhere on it** to stop and save. It never steals keyboard focus.

### 2. Global shortcut

Installed with `--hotkey` (xbindkeys by default): press once to start, press again
to stop. To change the key, edit the line in `~/.xbindkeysrc` and run
`pkill -x xbindkeys && xbindkeys`.

> **Why xbindkeys instead of the desktop's own shortcut system?**
> Desktop shortcut systems store custom entries in their own config and sometimes
> re-import a default scheme, wiping them — KDE's khotkeys did exactly that to our
> recording shortcut once. xbindkeys grabs the key at the X11 level from a plain
> text file, so nothing can reset it. Without xbindkeys you can still use
> `--hotkey-backend khotkeys`; the installer backs the config up and verifies the
> binding before trusting it.

### 3. Command line

```bash
record-screen.sh                     # full screen; run again to stop
record-screen.sh status              # is it recording?
record-screen.sh -r 1280x720 -a      # 720p region + system audio
record-screen.sh -e sw -d 60         # software encoder, 60 seconds
record-screen.sh discard             # stop and throw it away
record-screen.sh --help              # everything
```

### Options

| Option | Meaning |
|---|---|
| `-r, --region WxH[+X+Y]` | capture a region, e.g. `1280x720` or `800x600+100+50` (default: full screen) |
| `-f, --fps N` | frame rate, default 30 |
| `-e, --encoder auto\|hw\|sw\|<element>` | encoder choice, default `auto` |
| `-a, --audio` | also record system audio |
| `-d, --duration N` | stop after N seconds |
| `-o, --outdir DIR` | output directory, default `~/Videos` |
| `--format mkv\|mp4` | container, default `mkv` |
| `--no-gui` / `--no-verify` | disable the floating bar / the self-check |
| `--notify auto\|kdialog\|notify-send\|none` | notification backend |

### Config file

`~/.config/record-screen/config` (copy `config.example`), e.g.:

```ini
FPS=30
REGION=1280x720
ENCODER=auto
AUDIO=1
OUTDIR=/home/me/Videos
```

Priority: **CLI > environment > config file > defaults**.

## Encoder selection and measurements

`--encoder auto` (the default) works like this:

1. Probe for a usable hardware encoder; fall back to `x264enc` if there is none.
2. If a **region** was requested, prefer software encoding, because several vendor
   encoders are broken at non-native sizes (Allwinner definitely is). Force
   hardware with `-e hw`.

Measured on the development board (Radxa Cubie A7A / A733, 2560x1440 display,
8 cores):

| Mode | Effective fps | CPU |
|---|---|---|
| full screen, `omxh264videoenc` | ~16 fps | ~0.6 core |
| full screen, `x264enc ultrafast` | ~8 fps | ~2 cores |
| 1280x720 region, software | ~17–29 fps | ~1.6 cores |

Numbers move with screen activity and background load; 30 fps at full 1440p is out
of reach on this board.

## ⚠️ The Allwinner hardware encoder bug

On Allwinner boards, `omxh264videoenc` at any resolution **other than the native
display mode** writes a stream **without an SPS** — the file has a plausible size
and correct container metadata, but **zero decodable frames**, and nothing logs an
error.

Measured on a 2560x1440 panel:

| Capture | Encoder | Frames decoded |
|---|---|---|
| 2560x1440 full screen | hardware | 88 / 90 ✅ |
| 1280x720 region | hardware | **0** ❌ |
| 1280x720 region | software x264 | 90 / 90 ✅ |

Raw NAL counts: 1440p → `AUD×59, SPS×2, PPS×2, …`; 720p → `AUD×59, **SPS×0**, PPS×2, …`.

Two mitigations are built in:

1. `HW_FULLSCREEN_ONLY=1` (default) — switch to software encoding as soon as a
   region is requested.
2. `VERIFY=1` (default) — decode a frame of every finished recording and warn
   loudly if the file is broken.

Full evidence, reproduction steps and the debugging trail:
[docs/allwinner-omxh264-encoder-bug.md](docs/allwinner-omxh264-encoder-bug.md)

## Troubleshooting

**The recording will not play / shows 0 frames.**
Re-record with `--encoder sw`. On an Allwinner board with the hardware encoder at a
non-native resolution, this is almost certainly the bug above.

**No floating bar.**
Install `python3-gi` and `gir1.2-gtk-3.0`, or pass `--no-gui` to silence it.

**No audio.**
`-a` records the system output (the PulseAudio/PipeWire monitor source). This tool
does not pick microphones; if the machine has no monitor source, `-a` stays silent.

**GStreamer-based players refuse to play the file.**
The board's hardware *decoder* `omxh264dec` is broken as well (it fails on valid
streams). Export `GST_PLUGIN_FEATURE_RANK=omxh264dec:0` to force software decoding,
or use mpv / VLC / Dragon Player (on Debian Dragon uses the VLC backend and is
unaffected). Details in the
[docs](docs/allwinner-omxh264-encoder-bug.md#bonus-bug--the-hardware-decoder-is-broken-too).

**Frame rate is low.**
Full-screen 2560x1440 tops out around 16 fps with the hardware encoder. Record a
smaller region (`-r 1280x720`) for smooth output.

**The global shortcut does nothing.**
KDE needs the `khotkeys` package (if you can see the entry in System Settings →
Shortcuts → Custom Shortcuts, it is there). Log out and back in if it was just
installed. On other desktops, bind `record-screen.sh` yourself with `sxhkd`,
`xbindkeys` or your desktop's shortcut settings.

> ⚠️ **A caveat we hit ourselves:** KDE's `khotkeys` sometimes re-imports its
> default shortcut scheme when the module is reloaded or you log out, wiping
> hand-added custom entries — that is how the recording shortcut disappeared once
> during development. This is why the project defaults to **xbindkeys** instead.
> If you do want khotkeys, `--hotkey-backend khotkeys` **backs up
> `~/.config/khotkeysrc` first** and verifies that the key really got bound,
> rolling back if it did not. If a custom shortcut ever vanishes, look for the
> `.bak-*` files next to the config.

## Limitations

- **X11 only.** On Wayland, `ximagesrc` sees only XWayland windows, not the whole
  desktop. Wayland users should use
  [wf-recorder](https://github.com/ammen99/wf-recorder) or the desktop's built-in
  recorder.
- Audio is limited to the system output; no microphone selection.
- Region capture deliberately avoids the hardware encoder (see above).

## Uninstall

```bash
./uninstall.sh            # remove installed files
./uninstall.sh --purge    # also remove config and the global shortcut
```

## License

[MIT](LICENSE).

## Credits

Standing on the shoulders of [GStreamer](https://gstreamer.tv/),
[x264](https://www.videolan.org/developers/x264.html) and
[KDE](https://kde.org/) (KDialog / KHotKeys / KGlobalAccel), plus the VPU
user-space components shipped by Allwinner and Radxa.
