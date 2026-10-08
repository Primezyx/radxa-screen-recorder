#!/usr/bin/env python3
"""Floating control bar shown while recording.

The whole bar is one big button: click anywhere to stop and save.
It is started automatically by record-screen.sh and disappears when the
recording ends.

录制中的悬浮控制条:整条就是一个「停止并保存」按钮,点哪里都能停。
由 record-screen.sh 自动拉起,录制结束后自动消失。
"""
import os
import subprocess
import sys
import time

try:
    import gi

    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")
    from gi.repository import Gdk, GLib, Gtk
except Exception:
    sys.exit(0)  # no GTK available: stay silent, recording is unaffected

ZH = os.environ.get("LC_ALL", os.environ.get("LANG", "")).startswith("zh")
TXT = {
    "recording": "录制中" if ZH else "Recording",
    "stop": "■ 停止并保存" if ZH else "■ Stop & Save",
    "title": "录制中" if ZH else "Recording",
}

HERE = os.path.dirname(os.path.abspath(os.path.realpath(__file__)))
SCRIPT = os.path.join(HERE, "record-screen.sh")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
STATE = os.path.join(RUNTIME, "record-screen.%d.state" % os.getuid())


def read_state():
    try:
        with open(STATE) as fh:
            pid, path = fh.read().strip().split(" ", 1)
        return int(pid), path
    except Exception:
        return None, None


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


PID, OUT = read_state()
if PID is None or not alive(PID):
    sys.exit(0)

START = time.time()

CSS = b"""
button { background: rgba(18,18,20,0.92); border-radius: 12px;
         border: 1px solid rgba(255,255,255,0.12); padding: 6px 14px; }
button:hover { background: rgba(45,45,52,0.96); }
button:active { background: rgba(70,70,80,0.96); }
#dot   { color: #ff4d4d; font-size: 17px; font-weight: bold; }
#timer { color: #ffffff; font-size: 14px; }
#name  { color: #b8b8c0; font-size: 11px; }
#hint  { color: #ffffff; font-size: 13px; }
"""

win = Gtk.Window()
win.set_decorated(False)
win.set_resizable(False)
win.set_keep_above(True)
win.set_skip_taskbar_hint(True)
win.set_skip_pager_hint(True)
win.set_accept_focus(False)      # never steal focus from what you are doing
win.set_focus_on_map(False)
win.set_type_hint(Gdk.WindowTypeHint.UTILITY)
win.set_title(TXT["title"])

btn = Gtk.Button()
btn.set_relief(Gtk.ReliefStyle.NONE)

box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
box.set_size_request(330, -1)

dot = Gtk.Label(label="●")
dot.set_name("dot")
box.pack_start(dot, False, False, 0)

info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
timer = Gtk.Label(label="%s 00:00" % TXT["recording"])
timer.set_name("timer")
name = Gtk.Label(label=os.path.basename(OUT))
name.set_name("name")
info.pack_start(timer, False, False, 0)
info.pack_start(name, False, False, 0)
box.pack_start(info, True, True, 0)

hint = Gtk.Label(label=TXT["stop"])
hint.set_name("hint")
box.pack_start(hint, False, False, 0)

btn.add(box)
win.add(btn)


def do_stop(*_args):
    subprocess.Popen([SCRIPT, "stop"])
    Gtk.main_quit()


btn.connect("clicked", do_stop)


def tick():
    if not alive(PID):
        Gtk.main_quit()
        return False
    el = int(time.time() - START)
    timer.set_text("%s %02d:%02d" % (TXT["recording"], el // 60, el % 60))
    dot.set_opacity(1.0 if (el % 2 == 0) else 0.25)   # blinking red dot
    return True


win.show_all()
screen = win.get_screen()
geo = screen.get_monitor_geometry(screen.get_primary_monitor())
w = win.get_allocated_width() or 330
win.move(geo.x + max(0, (geo.width - w) // 2), geo.y + 16)

css = Gtk.CssProvider()
css.load_from_data(CSS)
Gtk.StyleContext.add_provider_for_screen(
    screen, css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
)

GLib.timeout_add(1000, tick)
Gtk.main()
