"""화장실 칸막이(옆판) 그리기 – 뒷벽에서 앞으로 뻗은 판을 정면 3/4 시점에서 본 모양.

사용: python3 tools/sprite_cleanup/build_stall_divider.py
출력: assets/art/props/interior/stall_divider.png
  위에서 보이는 윗면(나무 몰딩) 세로 띠 = 판의 깊이(뒷벽까지 2칸),
  맨 아래 좁은 앞면(회색 판 끝) + 스테인리스 발. 색은 haemu_props_restroom2.jpg 칸막이에서 뽑음.
그림 바닥 = 판 앞 끝이 바닥에 닿는 곳 (맵 props의 y)
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/art/props/interior/stall_divider.png"

W = 12            # 판 두께(화면에 보이는 폭)
DEPTH = 128       # 뒷벽까지 깊이 → 윗면 띠 길이
FACE = 72         # 앞면 높이 (판 높이)
GAP = 8           # 바닥에서 뜬 틈 (발)
OUTLINE = (58, 50, 45)
WOOD = (138, 119, 105)
WOOD_HI = (164, 145, 128)
GRAY = (129, 142, 150)
GRAY_DK = (106, 115, 124)
GRAY_HI = (152, 164, 171)
STEEL = (174, 176, 175)
STEEL_DK = (120, 122, 124)


def main() -> None:
    h = DEPTH + FACE + GAP
    a = np.zeros((h, W, 4), np.uint8)

    def rect(x0, y0, x1, y1, c):
        a[y0:y1, x0:x1, :3] = c
        a[y0:y1, x0:x1, 3] = 255

    # 윗면 나무 띠 (뒤 → 앞)
    rect(0, 0, W, DEPTH, OUTLINE)
    rect(1, 1, W - 1, DEPTH, WOOD)
    rect(2, 1, 4, DEPTH - 2, WOOD_HI)
    for y in range(9, DEPTH - 4, 23):          # 나뭇결 조금
        rect(6, y, 9, y + 1, OUTLINE)
    # 앞면 (판의 끝): 위에 나무 몰딩 끝, 아래 회색 판
    rect(0, DEPTH, W, DEPTH + FACE, OUTLINE)
    rect(1, DEPTH, W - 1, DEPTH + 5, WOOD)
    rect(1, DEPTH + 5, W - 1, DEPTH + FACE - 1, GRAY)
    rect(2, DEPTH + 6, 4, DEPTH + FACE - 3, GRAY_HI)
    rect(W - 3, DEPTH + 6, W - 1, DEPTH + FACE - 1, GRAY_DK)
    # 발 두 개
    for x in (2, W - 5):
        rect(x, DEPTH + FACE, x + 3, h - 1, STEEL)
        rect(x + 2, DEPTH + FACE, x + 3, h - 1, STEEL_DK)
        rect(x - 1, h - 2, x + 4, h, STEEL_DK)
    Image.fromarray(a).save(OUT)
    print(OUT.name, a.shape[1], "x", a.shape[0])


if __name__ == "__main__":
    main()
