---
name: Bug report
about: Something is broken — recording fails, the file is corrupt, the bar does not show…
title: "[Bug] "
labels: [bug]
---

<!--
  Please fill in as much as you can. The two commands in "Diagnostics" answer most
  questions right away.
  请尽量填全。下面「Diagnostics / 诊断信息」里的两条命令能回答大部分问题。
-->

## What happens / 现象

<!-- e.g. "The recording is saved but no player can open it" / 例如:录完能保存,但播放器打不开 -->

## Steps to reproduce / 复现步骤

1.
2.
3.

## Diagnostics / 诊断信息

<details>
<summary><code>record-screen.sh list-encoders</code></summary>

```
paste output here / 把输出贴在这里
```

</details>

<details>
<summary>Result of the decodability check / 解码自检结果</summary>

```bash
# replace FILE with your recording / 把 FILE 换成你的录像
FILE=~/Videos/screen-XXXX.mkv

# software decoding, forced (vendor hardware decoders are often broken too)
GST_PLUGIN_FEATURE_RANK="omxh264dec:0,avdec_h264:MAX" \
  gst-launch-1.0 -q filesrc location="$FILE" ! decodebin ! fakesink num-buffers=1
echo "exit=$?"     # 0 means the file is fine

# how many frames really decode / 真正能解出多少帧
gst-launch-1.0 -q filesrc location="$FILE" ! matroskademux ! h264parse ! avdec_h264 \
  ! videoconvert ! jpegenc ! multifilesink location=/tmp/f%03d.jpg
ls /tmp/f*.jpg | wc -l
```

```
paste output here / 把输出贴在这里
```

</details>

## Environment / 环境

| | |
|---|---|
| Board / SoC | <!-- e.g. Radxa Cubie A7A / Allwinner A733 --> |
| Kernel | <!-- `uname -r` --> |
| Distro | <!-- e.g. Debian 11 (bullseye) --> |
| Desktop / session | <!-- e.g. KDE Plasma 5.20, X11 --> |
| GStreamer | <!-- `gst-launch-1.0 --version` --> |
| record-screen-recorder | <!-- `record-screen.sh --version` --> |
| Encoder used | <!-- auto / hw / sw; and the output of `list-encoders` --> |

## Checklist / 自查

- [ ] I re-recorded with `--encoder sw` and the problem disappeared (**that means the vendor
      hardware encoder is at fault — see
      [docs/allwinner-omxh264-encoder-bug.md](../blob/main/docs/allwinner-omxh264-encoder-bug.md)**)
      <!-- 用 --encoder sw 重录后问题消失 → 说明是厂商硬件编码器的问题 -->
- [ ] I read [docs/allwinner-omxh264-encoder-bug.md](../blob/main/docs/allwinner-omxh264-encoder-bug.md)
- [ ] `record-screen.sh status` says "Not recording" while I am not recording
      <!-- 没在录的时候 status 显示未在录制 -->
- [ ] My session is X11 (Wayland only captures XWayland windows)
      <!-- 会话是 X11;Wayland 下只能录 XWayland 窗口 -->

## Anything else / 补充

<!-- Logs, screenshots, the exact command line you used… -->
<!-- 日志、截图、你用的完整命令… -->
