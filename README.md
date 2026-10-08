# radxa-screen-recorder

[![CI](https://github.com/Primezyx/radxa-screen-recorder/actions/workflows/ci.yml/badge.svg)](https://github.com/Primezyx/radxa-screen-recorder/actions/workflows/ci.yml)

> 给 Linux(尤其是 Allwinner / Radxa 开发板)用的轻量录屏工具。
> **能用硬件编码器就用,录完自动检查文件是不是真的能播**,还带一个「停止并保存」的悬浮按钮。

![悬浮控制条](docs/images/recording-bar.png)

*English: [README.en.md](README.en.md)*

---

## 为什么又造一个轮子

在开发板上"随手录一段屏幕"这件事,现有的选择都不太顺手:

- **OBS / 大型录屏软件**:功能全,但在 ARM 开发板上装一堆依赖、跑起来也重
- **纯命令行 ffmpeg**:参数记不住,而且很多板子镜像里根本没装
- **桌面自带录屏**:Plasma 要 5.27+ 才有,老版本(比如 Debian 11 的 Plasma 5.20)没有

更麻烦的是,很多 ARM SoC 的**硬件编码器是有坑的**。以本项目开发的 Allwinner A733 为例,
它的 OpenMAX H.264 编码器**只在屏幕原生分辨率下正常**,换个分辨率就会输出缺少 SPS 的码流 ——
文件大小看着正常,实际**一帧都解不出来**,而且**全程没有任何报错**
(完整分析见 [docs/allwinner-omxh264-encoder-bug.md](docs/allwinner-omxh264-encoder-bug.md))。

所以这个工具的重点是两件事:**把硬件编码器用起来**,以及**不让你拿到坏文件**。

## 特点

- 🎬 **一键开关**:全局快捷键 / 应用菜单 / 悬浮条 / 命令行,随你习惯
- ⚡ **优先硬件编码**:自动探测 `omxh264videoenc`、`v4l2h264enc`、`vah264enc`、`nvh264enc`,没有就回退软件编码
- 🔍 **录完自动解码自检**:文件解不出来会当场弹窗报警,而不是等你回放时才发现
- 🖱️ **悬浮控制条**:录制时屏幕顶部出现一条「■ 停止并保存」,整条都是按钮,不抢焦点
- 📐 **区域录制 / 帧率 / 系统声音 / 定时停止 / mkv 或 mp4**
- ⚙️ **三层配置**:命令行 > 环境变量 > 配置文件 > 默认值
- 🌏 **中英双语**:界面跟随 `$LANG`
- 📦 **安装不改系统**:默认装到 `~/.local`,带完整的安装/卸载脚本,自带 MIT 许可

## 系统要求

| | |
|---|---|
| 会话 | **X11**(基于 `ximagesrc`;Wayland 见[已知限制](#已知限制)) |
| 必需 | GStreamer 1.x + `gstreamer1.0-tools`(提供 `gst-launch-1.0`) |
| 悬浮条 | `python3-gi` + GTK3(`gir1.2-gtk-3.0`)—— 可选 |
| 通知 | `kdialog`(KDE)或 `notify-send` —— 可选,没有就只在终端打印 |
| 音频 | PulseAudio 或 PipeWire 的 pulse 层 —— 可选 |
| 全局快捷键 | `xbindkeys`(推荐,不依赖桌面环境)或 KDE 的 `khotkeys` —— 可选 |

Debian / Ubuntu 一次装齐:

```bash
sudo apt install gstreamer1.0-tools gstreamer1.0-plugins-good gstreamer1.0-plugins-ugly \
                 python3-gi gir1.2-gtk-3.0
```

## 安装

```bash
git clone https://github.com/Primezyx/radxa-screen-recorder.git
cd radxa-screen-recorder
./install.sh                 # 装到 ~/.local,不需要 root
./install.sh --hotkey        # 顺便绑一个全局快捷键(默认 Ctrl+Alt+R,KDE)
./install.sh --system        # 装到 /usr/local(需要 sudo)
```

安装脚本会检查依赖、把两个脚本装进 `~/.local/bin`、生成两个应用菜单项,
并在 `~/.config/record-screen/config.example` 放一份带注释的配置示例。

## 使用

### 方式一:悬浮条(最直观)

开始录制后,屏幕顶部会出现:

```
● 录制中 00:05                    ■ 停止并保存
  screen-20261003-000857.mkv
```

**点它任意位置**就停止并保存。整条都是按钮,不用瞄准;它不会抢当前程序的焦点。

### 方式二:全局快捷键

装的时候用 `--hotkey` 绑好(默认走 **xbindkeys**),之后**按一下开始、再按一下停止**。

想换键位:改 `~/.xbindkeysrc` 里那一行,然后 `pkill -x xbindkeys && xbindkeys`。

> **为什么推荐 xbindkeys 而不是桌面自带的快捷键?**
> 桌面环境的快捷键系统会把自定义条目存在自家配置里,偶尔会"重置方案"把它们冲掉
> (KDE 的 khotkeys 就把我们的录屏快捷键冲掉过一次)。xbindkeys 直接在 X11 层面抓键、
> 配置就是一个普通文本文件,**没有任何东西能把它重置**。
> 如果你的系统没有 xbindkeys,也可以 `--hotkey-backend khotkeys` 用桌面自带的,
> 但请知悉上述风险(安装脚本会先备份配置并验证)。

### 方式三:命令行

```bash
record-screen.sh                     # 全屏录制;再运行一次 = 停止
record-screen.sh status              # 看是否在录
record-screen.sh -r 1280x720 -a      # 录 720p 区域 + 系统声音
record-screen.sh -e sw -d 60         # 软件编码,录 60 秒
record-screen.sh discard             # 停止并丢弃(录错了)
record-screen.sh --help              # 全部参数
```

### 参数

| 参数 | 说明 |
|---|---|
| `-r, --region WxH[+X+Y]` | 只录该区域,如 `1280x720` 或 `800x600+100+50`,默认全屏 |
| `-f, --fps N` | 帧率,默认 30 |
| `-e, --encoder auto\|hw\|sw\|<元素名>` | 编码器选择,默认 `auto` |
| `-a, --audio` | 同时录系统声音 |
| `-d, --duration N` | N 秒后自动停止 |
| `-o, --outdir DIR` | 输出目录,默认 `~/Videos` |
| `--format mkv\|mp4` | 容器格式,默认 `mkv` |
| `--no-gui` / `--no-verify` | 关掉悬浮条 / 关掉解码自检 |
| `--notify auto\|kdialog\|notify-send\|none` | 通知方式 |

### 配置文件

`~/.config/record-screen/config`(把 `config.example` 复制过去改),例如:

```ini
FPS=30
REGION=1280x720
ENCODER=auto
AUDIO=1
OUTDIR=/home/me/Videos
```

优先级:**命令行 > 环境变量 > 配置文件 > 默认值**。

## 编码器与实测数据

`--encoder auto`(默认)的决策逻辑:

1. 探测可用的硬件编码器,没有就用 `x264enc`
2. 如果**指定了区域**(`-r`),默认改用软件编码 —— 因为不少厂商编码器在非原生分辨率下有坑
   (Allwinner 就是这样,见下)。想强制用硬件:`-e hw`

在本项目开发机(Radxa Cubie A7A / A733,2560x1440 屏,8 核)上的实测:

| 模式 | 实际帧率 | CPU 占用 |
|---|---|---|
| 全屏 + 硬件编码 `omxh264videoenc` | ~16 fps | ~0.6 核 |
| 全屏 + 软件 `x264enc ultrafast` | ~8 fps | ~2 核 |
| 1280x720 区域 + 软件编码 | ~17–29 fps | ~1.6 核 |

> 数字会随画面变化量和后台负载浮动;全屏 1440p 想跑满 30fps 这块板子做不到。

## ⚠️ Allwinner 硬件编码器的坑

**如果你用的是 Allwinner 的板子,请务必知道这件事:**

`omxh264videoenc` 在**非屏幕原生分辨率**下会输出**缺少 SPS 参数集**的码流 →
生成的视频**一帧都无法解码**,但文件大小、容器信息全部正常,**没有任何报错**。

实测(2560x1440 原生屏):

| 捕获 | 编码器 | 解出帧数 |
|---|---|---|
| 2560x1440 全屏 | 硬件 | 88 / 90 ✅ |
| 1280x720 区域 | 硬件 | **0** ❌ |
| 1280x720 区域 | 软件 x264 | 90 / 90 ✅ |

裸流 NAL 统计:1440p 是 `AUD×59, SPS×2, PPS×2, …`;720p 是 `AUD×59, **SPS×0**, PPS×2, …`。

两个应对措施已内置:

1. `HW_FULLSCREEN_ONLY=1`(默认)—— 一旦指定区域就自动改用软件编码
2. `VERIFY=1`(默认)—— 每次录完都解码首帧验证,坏文件当场弹窗提示

完整证据、复现步骤和排查过程:[docs/allwinner-omxh264-encoder-bug.md](docs/allwinner-omxh264-encoder-bug.md)

## 常见问题

**录出来的视频打不开 / 播放器显示 0 帧?**
用 `--encoder sw` 重录。如果你在 Allwinner 板子上用硬件编码器录了非原生分辨率,基本就是这个坑。

**悬浮条没出现?**
装 `python3-gi` 和 `gir1.2-gtk-3.0`;或者用 `--no-gui` 明确关掉。

**没有声音?**
`-a` 录制的是**系统输出**(PulseAudio/PipeWire 的 monitor 源)。本工具不选择麦克风;
如果你的机器连 monitor 源都没有,`-a` 会静音。

**用 GStreamer 系播放器放不出来?**
这块板子的硬件解码器 `omxh264dec` 也是坏的(解不了完全正常的流)。设置
`export GST_PLUGIN_FEATURE_RANK=omxh264dec:0` 强制软件解码,或改用 mpv / VLC /
Dragon 播放器(Debian 上 Dragon 走 VLC 后端,不受影响)。详见
[docs](docs/allwinner-omxh264-encoder-bug.md#bonus-bug--the-hardware-decoder-is-broken-too)。

**帧率偏低?**
全屏 2560x1440 这块板子硬件编码也就 ~16fps。想流畅就录小区域:`-r 1280x720`。

**全局快捷键不生效?**
KDE 需要 `khotkeys` 包(系统设置 → 快捷键 → 自定义快捷键里能看到就说明有)。
刚装完如果没立刻生效,注销重登一次。非 KDE 桌面请自己绑:`sxhkd`、`xbindkeys`
或桌面环境的自定义快捷键,命令填 `record-screen.sh`。

> ⚠️ **关于桌面自带快捷键的坑**:KDE 的 `khotkeys` 在模块重载/注销时偶尔会**重新导入
> 默认快捷键方案**,把自定义条目冲掉(我们在开发过程中就踩到过,录屏快捷键消失)。
> 所以本项目的**默认方案是 xbindkeys**(见上),它不受影响。
> 如果你确实要用 khotkeys,`--hotkey-backend khotkeys` 会在改动前**自动备份**
> `~/.config/khotkeysrc`,装完用 D-Bus 验证按键是否真的生效,失败就自动回滚;
> 遇到快捷键消失时先找同目录的 `.bak-*` 备份。

## 已知限制

- **只支持 X11**。Wayland 下只能通过 XWayland 抓到 XWayland 窗口,抓不到整个桌面;
  Wayland 用户建议用 [wf-recorder](https://github.com/ammen99/wf-recorder) 或桌面自带录屏。
- 音频只支持系统输出,不支持选择麦克风。
- 区域录制默认不使用硬件编码器(原因见上)。

## 卸载

```bash
./uninstall.sh            # 删掉安装的文件
./uninstall.sh --purge    # 连配置和全局快捷键一起删
```

## 许可证

[MIT](LICENSE) —— 随便用,出问题别找我 😄

## 致谢

站在这些项目的肩膀上:[GStreamer](https://gstreamer.tv/)、
[x264](https://www.videolan.org/developers/x264.html)、
[KDE](https://kde.org/)(KDialog / KHotKeys / KGlobalAccel),
以及 Allwinner 和 Radxa 提供的 VPU 用户态组件。
