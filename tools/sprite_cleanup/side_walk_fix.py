"""옆모습 걷기에 '다리 모음' 프레임을 만들어 넣는다.

Gemini 옆모습 프레임은 모두 다리를 벌린 같은 자세라서, 그대로 이으면 다리가 움직이지 않는다.
홀수 프레임(1, 3)의 다리 두 개를 몸 가운데로 모으고 몸을 1픽셀 올려,
벌림 → 모음 → 벌림 → 모음 순서의 걷기를 만든다.

사용: python3 side_walk_fix.py <캐릭터 폴더>
  walk_right.png를 고치고, walk_left.png는 좌우 반전으로 다시 만든다.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

GAP = 3              # 모은 두 다리 중심 사이 거리의 절반


def leg_top(alpha, bottom):
    """아래에서부터 올라가며, 불투명 구간이 두 덩어리(두 다리)로 나뉘는 가장 윗줄을 찾는다."""
    top = bottom
    for y in range(bottom - 1, 0, -1):
        xs = np.nonzero(alpha[y])[0]
        if xs.size == 0:
            continue
        gaps = np.nonzero(np.diff(xs) > 3)[0]
        if gaps.size >= 1:
            top = y
        elif top < bottom - 4:
            break
    return top + 1


def gather_legs(frame: Image.Image) -> Image.Image:
    a = np.array(frame)
    x0, y0, x1, y1 = frame.getbbox()
    hem = leg_top(a[..., 3] > 0, y1)
    legs = a[hem:y1].copy()
    body = a.copy()
    body[hem:y1] = 0

    lab, n = ndi.label(legs[..., 3] > 0)
    if n < 2:
        return frame
    sizes = ndi.sum(np.ones(lab.shape), lab, range(1, n + 1))
    biggest = sorted(range(1, n + 1), key=lambda i: -sizes[i - 1])[:2]
    parts = []
    for i in biggest:
        ys, xs = np.nonzero(lab == i)
        parts.append((xs.mean(), i))
    parts.sort()

    # 엉덩이 중심 = 밑단 바로 위 줄의 불투명 구간 가운데
    row = a[hem - 2, :, 3] > 0
    hip = np.nonzero(row)[0].mean()

    out = np.zeros_like(a)
    out[:] = body
    # 몸을 1픽셀 올림 (다리가 모일 때 몸이 가장 높음)
    out[:-1] = out[1:]
    out[-1] = 0
    out[hem - 1] = out[hem - 2] * (out[hem - 2, :, 3:4] > 0)   # 올린 자리 메우기
    # 뒷다리 먼저, 앞다리를 위에 그림
    for (cx, i), target in zip(parts, (hip - GAP, hip + GAP)):
        dx = int(round(target - cx))
        mask = lab == i
        ys, xs = np.nonzero(mask)
        for y, x in zip(ys, xs):
            nx = x + dx
            if 0 <= nx < a.shape[1]:
                out[hem + y, nx] = legs[y, x]
    return Image.fromarray(out, "RGBA")


def main(folder):
    folder = Path(folder)
    meta = json.loads((folder / "frames.json").read_text(encoding="utf-8"))
    cw, ch = meta["cell"]
    src = Image.open(folder / "walk_right.png")
    n = meta["animations"]["walk_right"]["frames"]
    frames = [src.crop((i * cw, 0, i * cw + cw, ch)) for i in range(n)]
    fixed = [gather_legs(f) if i % 2 == 1 else f for i, f in enumerate(frames)]
    right = Image.new("RGBA", src.size, (0, 0, 0, 0))
    left = Image.new("RGBA", src.size, (0, 0, 0, 0))
    for i, f in enumerate(fixed):
        right.alpha_composite(f, (i * cw, 0))
        left.alpha_composite(f.transpose(Image.FLIP_LEFT_RIGHT), (i * cw, 0))
    right.save(folder / "walk_right.png")
    left.save(folder / "walk_left.png")
    print(f"walk_right / walk_left: {n}프레임 중 {len(range(1, n, 2))}개를 다리 모음 자세로 바꿈")


if __name__ == "__main__":
    main(sys.argv[1])
