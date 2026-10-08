# Allwinner OMX H.264 encoder drops the SPS at non-native resolutions

**中文摘要**:Allwinner A733(Cedar VPU)的 OpenMAX H.264 硬件编码器
(`omxh264videoenc`)**只在屏幕原生分辨率下正常工作**。用其它分辨率(例如
1280x720、1920x1080)录制时,它输出的码流**缺少 SPS 参数集**,解码器一帧也解不出来
—— 而文件大小看起来完全正常(几百 KB ~ 几 MB),属于**静默损坏**。
按 32 对齐、改色彩格式、换封装格式都无法规避;本文给出完整证据和规避方案。

---

## Environment

| | |
|---|---|
| Board | Radxa Cubie A7A (Allwinner A733, aarch64) |
| OS | Debian GNU/Linux 11 (bullseye) |
| Kernel | `5.15.147-21-a733` |
| GStreamer | 1.18.4 (`gstreamer1.0-tools`) |
| gst-omx plugin | 1.18.6.1 |
| Vendor plugin | `libgstreamer-openmax-allwinner` 1.4.6-3 |
| Vendor libs | `libcedarc-dev-2.0.0-arm64` 1.0.1 (`libOmxVenc.so`, `libvencoder.so`, `libvce_h264.so` …) |
| Device nodes | `/dev/cedar_dev`, `/dev/cedar_dev_ve2` (udev `uaccess` rules included) |
| Date observed | 2026-10 |

Element used: `omxh264videoenc` — reported by `gst-inspect-1.0` as
`Klass: Codec/Encoder/Video/Hardware`.

## Symptom

Recording the screen with the hardware encoder at any resolution **other than the
display's native mode** produces a file that:

* has a plausible size (hundreds of KB per few seconds),
* has correct container metadata (`video/x-h264, width=1280, height=720, …`),
* but decodes to **zero frames**.

Decoding the same capture path with the software encoder (`x264enc`) works fine,
so the capture side (`ximagesrc` + `videoconvert`) is not at fault.

## Evidence 1 — frame counts after a full decode

60–150 frame captures, decoded back to JPEG frames:

| Capture | Encoder | Output size | Frames decoded |
|---|---|---|---|
| 2560x1440 full screen (native) | `omxh264videoenc` | 676 KB | **88 / 90** ✅ |
| 1280x720 region | `omxh264videoenc` | 744 KB | **0** ❌ |
| 1280x720 (scaled from full screen) | `omxh264videoenc` | 724 KB | **0** ❌ |
| 1280x720 region | `x264enc` | 616 KB | **90 / 90** ✅ |

`matroskademux` reports `No valid frames found before end of stream`.

## Evidence 2 — the missing SPS in the raw H.264 stream

Writing the encoder output straight to a raw byte-stream file (no muxer) and
counting NAL unit types:

```
2560x1440 : AUD ×59, SPS ×2, PPS ×2, IDR ×2, non-IDR ×57   ✅ decodable
1280x720  : AUD ×59, SPS ×0, PPS ×2, IDR ×2, non-IDR ×57   ❌ no SPS at all
```

The first bytes tell the same story — the 1440p stream starts with an Access Unit
Delimiter followed by a **Sequence Parameter Set** (`67 42 00 0a …`), while the
720p stream goes straight from the AUD to a **Picture Parameter Set**
(`68 ce 3c 80`) — and emits it twice:

```
1440p:  00 00 00 01 09 f0 | 00 00 00 01 67 42 00 0a 89 89 40 14 …   (AUD, SPS, …)
720p :  00 00 00 01 09 f0 | 00 00 00 01 68 ce 3c 80 | 00 00 00 01 68 ce 3c 80 | 65 …
                            (AUD,            PPS,                  PPS,           IDR)
```

Without an SPS there is no profile/level/resolution information, so no decoder can
parse the stream. `h264parse` cannot invent one either.

## Scope of the bug — which resolutions fail

All of these produced **SPS ×0 → undecodable output**:

`1280x720`, `1280x736`, `1280x704`, `1248x720`, `1920x1080`, `1920x1088`,
`2560x720`, `1280x1440`

Only the display's native mode (`2560x1440` on this board) produced a valid stream
(`SPS ×2`).

Ruled out as causes:

* **Not an alignment problem** — 1280x736 and 1920x1088 are multiples of 32 and
  still fail, while 720 (not a multiple of 32) fails too. Every non-native size
  fails regardless of alignment.
* **Not a pixel-format problem** — both the working and the broken case negotiate
  `YV12` into the encoder. Forcing `I420` makes the pipeline fail outright
  (`exit=1`), forcing `NV12` still yields 0 decodable frames.
* **Not a muxer problem** — the raw byte-stream (no `matroskamux`) is equally
  broken, and the same muxer works with the software encoder.

## Second issue — washed-out first frames

At the native resolution the encoder does produce a valid stream, but the first
few frames are visibly washed out (very low contrast). Frame sizes from one
recording: frames 0 and 5 → 88 KB / 107 KB, whereas frames 60 / 120 / 179 →
362 KB / 388 KB / 384 KB. Visually confirmed: frame 5 is a grey haze, frame 120 is
a normal, correctly coloured desktop.

So even in the "working" configuration you should expect roughly the first second
to look faded.

## Other log noise (probably harmless, but confusing)

```
ERROR : cedarc <getDefaultParameter:35>: getDefaultParameter. UnsupportedIndex 100663312. unkonwn param 0x…
WARNING: omx_venc <dealWithInputBuffer:3577>: skip this input buffer, pInBufHd=0x…, buffer_type=74747474, buf_size=0
WARNING: cedarc <VideoEncUnInit:354>: the VideoEnc is not init currently
WARNING: cedarc <getSocIdString:1219>: cannot open /dev/sunxi_soc_info, it maybe ok!
```

## Reproduce it

Everything below needs only `gstreamer1.0-tools`.

**1. Does your board have the hardware encoder?**

```bash
gst-inspect-1.0 omxh264videoenc | head -5     # look for Klass: …/Hardware
```

**2. Record 60 frames at a non-native size and try to decode them:**

```bash
# 1280x720 region, hardware encoder
gst-launch-1.0 -e -q \
  ximagesrc num-buffers=60 use-damage=0 startx=0 starty=0 endx=1279 endy=719 \
  ! video/x-raw,framerate=30/1 ! videoconvert ! omxh264videoenc ! h264parse \
  ! matroskamux ! filesink location=/tmp/hw720.mkv

# count how many frames come back out
gst-launch-1.0 -q filesrc location=/tmp/hw720.mkv ! matroskademux ! h264parse \
  ! avdec_h264 ! videoconvert ! jpegenc ! multifilesink location=/tmp/f%03d.jpg
ls /tmp/f*.jpg | wc -l        # 0  => you are affected
```

**3. Compare with the software encoder** (same region, should give ~60):

```bash
gst-launch-1.0 -e -q \
  ximagesrc num-buffers=60 use-damage=0 startx=0 starty=0 endx=1279 endy=719 \
  ! video/x-raw,framerate=30/1 ! videoconvert \
  ! x264enc speed-preset=ultrafast tune=zerolatency ! h264parse \
  ! matroskamux ! filesink location=/tmp/sw720.mkv
```

**4. See the missing SPS for yourself:**

```bash
gst-launch-1.0 -e -q \
  ximagesrc num-buffers=60 use-damage=0 startx=0 starty=0 endx=1279 endy=719 \
  ! video/x-raw,framerate=30/1 ! videoconvert ! omxh264videoenc ! h264parse \
  ! filesink location=/tmp/raw720.h264

python3 - <<'PY'
data = open('/tmp/raw720.h264','rb').read()
i, types = 0, {}
while True:
    j = data.find(b'\x00\x00\x01', i)
    if j < 0 or j + 3 >= len(data): break
    t = data[j+3] & 0x1F
    types[t] = types.get(t, 0) + 1
    i = j + 3
names = {1:'non-IDR', 5:'IDR', 7:'SPS', 8:'PPS', 9:'AUD'}
print(', '.join('%s×%d' % (names.get(k, k), v) for k, v in sorted(types.items())))
PY
# affected board prints: non-IDR×57, IDR×2, PPS×2, AUD×59   <- no SPS
```

## Workarounds used by this project

1. **Use the hardware encoder only at the native (full-screen) resolution.**
   That is what `HW_FULLSCREEN_ONLY=1` (the default) does: as soon as a region is
   requested, the recorder switches to `x264enc`.
2. **Verify every recording by decoding it** (`VERIFY=1`, the default). The
   recorder decodes the first frame of the finished file and warns you loudly if
   the file is not decodable — this is the only way to catch silent corruption.
3. Force software encoding with `--encoder sw` for maximum reliability.

## Measured performance on this board (2560x1440 display, 8 cores)

| Mode | Effective fps | CPU |
|---|---|---|
| full screen, `omxh264videoenc` | ~16 fps | ~0.6 core |
| full screen, `x264enc ultrafast` | ~8 fps | ~2 cores |
| 1280x720 region, `x264enc ultrafast` | ~17–29 fps | ~1.6 cores |

Numbers vary with how much is moving on screen and what else is running.

## Status

Not fixed as far as we know (observed 2026-10 on the vendor packages listed
above). If you can reproduce it on other Allwinner SoCs or with a newer
`libgstreamer-openmax-allwinner`, please open an issue — knowing whether this is
A733-specific or a general Cedar encoder problem would help a lot.
