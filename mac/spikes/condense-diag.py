#!/usr/bin/env python3
"""진단 기록(diag.log)을 읽기 쉽게 접는다 — S1c-1이 9,008줄을 약 2,000줄로 줄여 읽은 방법.

    python3 mac/spikes/condense-diag.py                   # ~/Library/Logs/Focus & Draw/diag.log 전체
    python3 mac/spikes/condense-diag.py --from "MARK 항목 R1"   # 이 글이 처음 나오는 줄부터 (재시험)
    python3 mac/spikes/condense-diag.py --idle            # 쉬는 동안(draw=0, 입력 0)의 표본도 남긴다

- 1초 표본(SAMPLE)은 moves·keys만 다른 줄끼리 한 줄로 합치고 합계를 적는다.
- 같은 화면 알림(SCREEN changed + SCREEN #0)이 이어지면 한 줄로 센다.
- 앞 숫자는 원래 기록의 줄 번호다. 번들 ID는 짧게(FD = 우리 앱), 판 위의 창 목록은 앞 4개만.
"""
import os
import re
import sys

args = sys.argv[1:]
path = os.path.expanduser("~/Library/Logs/Focus & Draw/diag.log")
start_mark = None
keep_idle = "--idle" in args
if "--from" in args:
    start_mark = args[args.index("--from") + 1]
for a in args:
    if a.endswith(".log"):
        path = a

lines = open(path, encoding="utf-8").read().splitlines()
first = 0
if start_mark:
    first = next((i for i, l in enumerate(lines) if start_mark in l), len(lines))


def ts(l): return l[11:23]
def body(l): return l[24:]


def shorten(s):
    for a, b in [("io.github.maker-ssam.focus-draw", "FD"), ("com.apple.iWork.Keynote", "Keynote"),
                 ("com.microsoft.Powerpoint", "PPT"), ("com.google.Chrome", "Chrome"), ("com.apple.", ""),
                 ("cgCursorVisible=", "cgCur="), ("inkOnscreenList=", "onList=")]:
        s = s.replace(a, b)
    m = re.search(r"above=\[([^\]]*)\]", s)
    if m:
        parts = [p for p in m.group(1).split(",") if p and not re.search(r":-\d", p)]
        s = s[:m.start()] + "above=[" + ",".join(parts[:4]) + "]" + s[m.end():]
    return s


def sample_key(b): return re.sub(r"moves=\d+ keys=\d+ ", "", b)


out = []
i = first
while i < len(lines):
    l, b = lines[i], body(lines[i])
    if b.startswith("SCREEN changed") or b.startswith("SCREEN #"):
        j, n = i, 0
        while j < len(lines) and (body(lines[j]).startswith("SCREEN changed") or body(lines[j]).startswith("SCREEN #")):
            n += body(lines[j]).startswith("SCREEN changed")
            j += 1
        if n <= 1:
            out += [f"{k + 1:5d} {ts(lines[k])} {body(lines[k])[:170]}" for k in range(i, j)]
        else:
            out.append(f"{i + 1:5d} {ts(l)}..{ts(lines[j - 1])} SCREEN changed x{n} (폭주)")
        i = j
        continue
    if b.startswith("SAMPLE"):
        key, j, moves, keys = sample_key(b), i, 0, 0
        while j < len(lines) and body(lines[j]).startswith("SAMPLE") and sample_key(body(lines[j])) == key:
            m = re.search(r"moves=(\d+) keys=(\d+)", body(lines[j]))
            moves += int(m.group(1)) if m else 0
            keys += int(m.group(2)) if m else 0
            j += 1
        idle = "draw=0" in key and moves == 0 and keys == 0
        if keep_idle or not idle:
            out.append(f"{i + 1:5d} {ts(l)}..{ts(lines[j - 1])} x{j - i} moves={moves} keys={keys} | {shorten(key[7:])}")
        i = j
        continue
    if not re.search(r"KEY \w+ down code=\d+ mods=\S+ repeat$", b):  # 누르고 있는 키의 반복 줄은 뺀다
        out.append(f"{i + 1:5d} {ts(l)} {shorten(b)}")
    i += 1

print("\n".join(out))
