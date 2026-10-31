"""조개 핀 위치 고정 + 옆·뒤 대기(숨쉬기) 동작 만들기.

1) 조개 핀이 프레임마다 좌우로 바뀌는 동작은, 핀이 반대쪽에 있는 프레임을 좌우 반전해 맞춘다.
   서하 기준 왼쪽 머리에 꽂혀 있으므로 정면에서는 화면 오른쪽, 뒷모습에서는 화면 왼쪽.
2) 옆·뒤로 멈췄을 때 쓸 대기 동작을 만든다.
   기준 프레임에서 다리 위쪽 몸 전체를 1픽셀씩 내렸다 올려 숨 쉬는 느낌을 준다.

사용: python3 make_idles.py <캐릭터 폴더>
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

PIN_SIDE = {"walk_down": +1, "idle": +1, "walk_up": -1}   # +1 = 화면 오른쪽, -1 = 화면 왼쪽
IDLE_SOURCES = {           # 대기 동작 이름: (기준 동작, 프레임 번호)
    "idle_right": ("walk_right", 1),   # 다리를 모은 프레임
    "idle_up": ("walk_up", None),      # None = 두 발이 가장 가까운 프레임을 고름
}
BREATH = [0, 1, 2, 1]      # 프레임별로 몸을 내리는 픽셀 수
IDLE_FPS = 3


def pin_offset(frame):
    a = np.array(frame).astype(int)
    alpha = a[..., 3] > 0
    xs = np.nonzero(alpha.any(0))[0]
    if xs.size == 0:
        return 0
    cx = (xs[0] + xs[-1]) / 2
    orange = (a[..., 0] > 190) & (a[..., 1] > 70) & (a[..., 1] < 170) & (a[..., 2] < 100) & alpha
    if orange.sum() < 10:
        return 0
    return np.nonzero(orange)[1].mean() - cx


def leg_top(frame):
    a = np.array(frame)[..., 3] > 0
    bottom = np.nonzero(a.any(1))[0][-1] + 1
    top = bottom
    for y in range(bottom - 1, 0, -1):
        xs = np.nonzero(a[y])[0]
        if xs.size and np.nonzero(np.diff(xs) > 3)[0].size:
            top = y
        elif top < bottom - 4:
            break
    return top + 1 if top < bottom else bottom - 14


def feet_spread(frame):
    a = np.array(frame)[..., 3] > 0
    ys = np.nonzero(a.any(1))[0]
    xs = np.nonzero(a[ys[-6]:ys[-1] + 1].any(0))[0]
    return xs[-1] - xs[0]


def breathe(frame, dy):
    if dy == 0:
        return frame
    a = np.array(frame)
    split = leg_top(frame)
    out = a.copy()
    out[dy:split + dy] = a[:split]
    out[:dy] = 0
    legs = a[split:]
    # 다리는 제자리, 겹치는 줄은 몸이 위에
    for y in range(split + dy, a.shape[0]):
        src = legs[y - split]
        keep = out[y, :, 3] == 0
        out[y][keep] = src[keep]
    return Image.fromarray(out, "RGBA")


def load_frames(folder, name, meta):
    cw, ch = meta["cell"]
    sheet = Image.open(folder / f"{name}.png")
    return [sheet.crop((i * cw, 0, i * cw + cw, ch)) for i in range(meta["animations"][name]["frames"])]


def save_frames(folder, name, frames, meta, fps=None, loop=True):
    cw, ch = meta["cell"]
    sheet = Image.new("RGBA", (cw * len(frames), ch), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, (i * cw, 0))
    sheet.save(folder / f"{name}.png")
    info = meta["animations"].setdefault(name, {"cell": [cw, ch], "loop": loop})
    info["frames"] = len(frames)
    info["cell"] = [cw, ch]
    if fps:
        info["fps"] = fps
    info["loop"] = loop


def main(folder):
    folder = Path(folder)
    meta = json.loads((folder / "frames.json").read_text(encoding="utf-8"))

    for name, side in PIN_SIDE.items():
        if name not in meta["animations"]:
            continue
        frames = load_frames(folder, name, meta)
        fixed = 0
        for i, f in enumerate(frames):
            off = pin_offset(f)
            if off and np.sign(off) != side:
                frames[i] = f.transpose(Image.FLIP_LEFT_RIGHT)
                fixed += 1
        save_frames(folder, name, frames, meta, loop=meta["animations"][name]["loop"])
        print(f"{name}: 조개 위치가 반대인 프레임 {fixed}개 반전")

    for idle_name, (src, idx) in IDLE_SOURCES.items():
        frames = load_frames(folder, src, meta)
        base = frames[idx] if idx is not None else min(frames, key=feet_spread)
        save_frames(folder, idle_name, [breathe(base, dy) for dy in BREATH], meta, fps=IDLE_FPS)
        print(f"{idle_name}: {src} 기준 {len(BREATH)}프레임")
    right = load_frames(folder, "idle_right", meta)
    save_frames(folder, "idle_left", [f.transpose(Image.FLIP_LEFT_RIGHT) for f in right], meta, fps=IDLE_FPS)
    print("idle_left: idle_right 좌우 반전")

    (folder / "frames.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main(sys.argv[1])
