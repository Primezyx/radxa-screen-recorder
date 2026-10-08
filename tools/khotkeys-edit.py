#!/usr/bin/env python3
"""Edit KDE's khotkeysrc (Custom Shortcuts) without clobbering the rest of it.

KDE writes this file itself, so we do surgical edits: find the action whose
CommandURL matches, and either set its key or delete the whole group.

khotkeysrc 由 KDE 自己维护,所以这里只做局部修改:找到 CommandURL 匹配的动作,
要么改它的按键,要么整组删掉。

    khotkeys-edit.py set    <khotkeysrc> <key-combo> <command> [name]
    khotkeys-edit.py remove <khotkeysrc> <command>
"""
import os
import re
import sys
import uuid


def span(text, section):
    """Character range of a section body (header line excluded)."""
    m = re.search(r"^\[" + re.escape(section) + r"\]\n", text, re.M)
    if not m:
        return None
    start = m.end()
    nxt = re.search(r"^\[", text[start:], re.M)
    return (start, start + nxt.start() if nxt else len(text))


def get(text, section, key):
    sp = span(text, section)
    if not sp:
        return None
    m = re.search(r"^" + re.escape(key) + r"=(.*)$", text[sp[0]:sp[1]], re.M)
    return m.group(1) if m else None


def put(text, section, key, value):
    sp = span(text, section)
    if not sp:
        return text
    body = text[sp[0]:sp[1]]
    pat = re.compile(r"^" + re.escape(key) + r"=.*$", re.M)
    if pat.search(body):
        body = pat.sub(lambda _m: "%s=%s" % (key, value), body, count=1)
    else:
        if body and not body.endswith("\n"):
            body += "\n"
        body += "%s=%s\n" % (key, value)
    return text[:sp[0]] + body + text[sp[1]:]


def find_action(text, command):
    for group, idx in re.findall(r"^\[Data_(\d+)_(\d+)Actions0\]$", text, re.M):
        if get(text, "Data_%s_%sActions0" % (group, idx), "CommandURL") == command:
            return group, idx
    return None


def read(path):
    if os.path.exists(path):
        return open(path, encoding="utf-8").read()
    return "[Data]\nDataCount=1\n"


def write(path, text):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


NEW_GROUP = """
[Data_%(n)s]
Comment=
DataCount=1
Enabled=true
Name=%(name)s
SystemGroup=0
Type=ACTION_DATA_GROUP

[Data_%(n)s_1]
Comment=
Enabled=true
Name=%(name)s
Type=SIMPLE_ACTION_DATA

[Data_%(n)s_1Actions]
ActionsCount=1

[Data_%(n)s_1Actions0]
CommandURL=%(cmd)s
Type=COMMAND_URL

[Data_%(n)s_1Conditions]
Comment=
ConditionsCount=0

[Data_%(n)s_1Triggers]
Comment=Simple_action
TriggersCount=1

[Data_%(n)s_1Triggers0]
Key=%(key)s
Type=SHORTCUT
Uuid={%(uuid)s}
"""


def cmd_set(path, key, command, name):
    text = read(path)
    target = find_action(text, command)
    if target:
        group, idx = target
        trig = "Data_%s_%sTriggers0" % (group, idx)
        if span(text, trig) is None:
            text = text.rstrip("\n") + (
                "\n[Data_%s_%sTriggers]\nComment=Simple_action\nTriggersCount=1\n"
                "\n[%s]\nKey=%s\nType=SHORTCUT\nUuid={%s}\n"
                % (group, idx, trig, key, uuid.uuid4())
            )
        else:
            text = put(text, trig, "Key", key)
        action = "updated"
    else:
        m = re.search(r"(\[Data\]\n(?:[^\[]*?)DataCount=)(\d+)", text)
        if not m:
            raise SystemExit("cannot find the [Data] section in %s" % path)
        n = int(m.group(2)) + 1
        text = text[:m.start(2)] + str(n) + text[m.end(2):]
        text = text.rstrip("\n") + "\n" + NEW_GROUP % {
            "n": n, "name": name, "cmd": command, "key": key, "uuid": uuid.uuid4(),
        }
        action = "added"
    write(path, text)
    return action


def cmd_remove(path, command):
    text = read(path)
    target = find_action(text, command)
    if not target:
        return "not-found"
    group = target[0]
    # drop every section that belongs to this group: [Data_N] and [Data_N_*]
    keep, skipped = [], False
    for line in text.splitlines(keepends=True):
        m = re.match(r"^\[Data_(\d+)(?:_\d+)?(?:[A-Za-z0-9_]*)?\]$", line.strip())
        if m:
            skipped = (m.group(1) == group)
        if not skipped:
            keep.append(line)
    text = "".join(keep)
    m = re.search(r"(\[Data\]\n(?:[^\[]*?)DataCount=)(\d+)", text)
    if m:
        n = max(0, int(m.group(2)) - 1)
        text = text[:m.start(2)] + str(n) + text[m.end(2):]
    write(path, text.rstrip("\n") + "\n")
    return "removed"


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    mode, path = sys.argv[1], sys.argv[2]
    if mode == "set":
        if len(sys.argv) < 5:
            raise SystemExit(__doc__)
        name = sys.argv[5] if len(sys.argv) > 5 else "Screen Recording"
        print(cmd_set(path, sys.argv[3], sys.argv[4], name))
    elif mode == "remove":
        if len(sys.argv) < 4:
            raise SystemExit(__doc__)
        print(cmd_remove(path, sys.argv[3]))
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
