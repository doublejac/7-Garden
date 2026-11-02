"""채린(휠체어) 스프라이트 시트 만들기 — Google Flow 영상 3개에서.

    python3 tools/sprite_cleanup/chaerin_build.py

src/chaerin/push_right.mp4 / push_down.mp4 / push_up.mp4 를 읽어
assets/art/characters/chaerin/ 에 walk_*·idle_* 시트와 frames.json을 쓴다.
(그다음 Godot로 build_spriteframes.gd -- chaerin 실행)

- 크기: 머리카락(금발) 폭을 정면 기준 66px에 맞춤 → 서하와 머리 크기가 같다.
- 비율: 턱 아래(몸+휠체어)는 세로 76.5%로 줄임. 원본 그대로면 앉아 있어도 서하보다 커 보인다.
- 영상은 휠체어가 제자리에 있으므로 첫 프레임 기준 같은 자리를 잘라 모든 프레임에 적용 (흔들림 없음).
- 정지: 루프 첫 프레임 + 숨쉬기(상체 1px) + 깜빡임(영상 속 실제 눈 감은 프레임의 눈 부분).
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from clean_chroma import hq_resize_xy, key_green  # noqa: E402

ROOT = HERE.parent.parent
SRC = HERE / "src" / "chaerin"
OUT = ROOT / "assets" / "art" / "characters" / "chaerin"
CW, CH = 112, 160          # 칸 크기 (발=바퀴 바닥이 아래에서 2px 위)
LOWER = 0.765              # 턱 아래 세로 비율
CHIN = 0.40                # 원본 높이에서 턱 위치(위에서부터 비율)

# 이름, 영상, 시작 프레임, 주기(프레임), 칸 수, fps, 머리 폭 목표(px), 좌우반전 이름, 정지 이름, 반전 정지, 깜빡임 프레임
CLIPS = [
    ("walk_right", "push_right.mp4", 75, 39, 10, 6, 58, "walk_left", "idle_right", "idle_left", 59),
    ("walk_down", "push_down.mp4", 56, 28, 8, 6, 66, None, "idle", None, 26),
    ("walk_up", "push_up.mp4", 59, 48, 12, 6, 66, None, "idle_up", None, None),
]


def read_video(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, 1280, 720, 3)


def keyed(F, i):
    a = F[i].copy()
    cols = np.nonzero(~(a.max(2) < 20).all(0))[0]     # 좌우 검은 띠 제거
    return Image.fromarray(key_green(a[:, cols[0]:cols[-1] + 1]), "RGBA")


def blond_width(im):
    a = np.array(im).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    m = (al > 128) & (r > 170) & (g > 140) & (r - b > 45) & (abs(r - g) < 45)
    m[int(a.shape[0] * 0.35):] = False
    cols = np.nonzero(m.sum(0) >= 3)[0]
    return np.percentile(cols, 98) - np.percentile(cols, 2)


def clip_frames(F, start, period, count, head_w):
    f0 = keyed(F, start)
    x0, y0, x1, y1 = f0.getbbox()
    s = head_w / blond_width(f0)
    chin = round(y0 + CHIN * (y1 - y0))

    def shrink(i):
        c = keyed(F, i)
        W = round(c.width * s)
        up = hq_resize_xy(c.crop((0, 0, c.width, chin)), W, round(chin * s))
        lo = hq_resize_xy(c.crop((0, chin, c.width, y1)), W, round((y1 - chin) * s * LOWER))
        o = Image.new("RGBA", (W, up.height + lo.height))
        o.alpha_composite(up)
        o.alpha_composite(lo, (0, up.height))
        return o

    idx = [start + round(j * period / count) for j in range(count)]
    frames = [shrink(i) for i in idx]
    cx = round((x0 + x1) / 2 * s)          # 첫 프레임 몸 중심
    return frames, cx, shrink


def place(o, cx):
    a = np.array(o)
    a[a[..., 3] < 60] = 0          # 영상 압축 때문에 생긴 희미한 테두리 제거
    o = Image.fromarray(a, "RGBA")
    cell = Image.new("RGBA", (CW, CH))
    cell.alpha_composite(o, (CW // 2 - cx, CH - 2 - o.height))
    return cell


def eye_box(cell):
    a = np.array(cell).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    m = (al > 128) & (b > g + 40) & (r > g + 10)        # 보라 눈동자
    m[int(CH * 0.5):] = False
    ys, xs = np.nonzero(m)
    if ys.size == 0:
        return None
    return xs.min() - 3, ys.min() - 4, xs.max() + 4, ys.max() + 3


def breath(cell):
    a = np.array(cell)
    cut = int(CH * 0.62)          # 휠체어 팔걸이 위(상체)만 1px 내려감
    b = a.copy()
    b[1:cut + 1] = a[0:cut]
    b[0] = 0
    return Image.fromarray(b, "RGBA")


def blink(base, shut):
    box = eye_box(base)
    if box is None:
        return base
    out = base.copy()
    out.paste(shut.crop(box), box[:2])
    return out


def sheet(cells, name, meta, fps, flip=False):
    sh = Image.new("RGBA", (CW * len(cells), CH))
    for i, c in enumerate(cells):
        sh.alpha_composite(c.transpose(Image.FLIP_LEFT_RIGHT) if flip else c, (i * CW, 0))
    sh.save(OUT / f"{name}.png")
    meta["animations"][name] = {"frames": len(cells), "cell": [CW, CH], "fps": fps, "loop": True}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta = {"cell": [CW, CH], "animations": {}}
    for name, video, start, period, count, fps, head_w, mirror, idle, idle_mirror, shut_i in CLIPS:
        F = read_video(SRC / video)
        frames, cx, shrink = clip_frames(F, start, period, count, head_w)
        cells = [place(o, cx) for o in frames]
        sheet(cells, name, meta, fps)
        if mirror:
            sheet(cells, mirror, meta, fps, flip=True)
        base = cells[0]
        shut = blink(base, place(shrink(shut_i), cx)) if shut_i is not None else base
        br = breath(base)
        seq = [base, br, base, br, base, br, base, shut]
        sheet(seq, idle, meta, 3)
        if idle_mirror:
            sheet(seq, idle_mirror, meta, 3, flip=True)
        print(name, "→", count, "칸", "/", idle)
    (OUT / "frames.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
