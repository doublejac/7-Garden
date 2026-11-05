"""복도 러너·로비 깔개 (haemu_rugs.jpg, Gemini 초록 배경 시트) → Godot PNG.

사용: python3 tools/sprite_cleanup/build_rugs.py
  러너는 [끝 + 가운데 조각 × N + 끝]을 원본 크기에서 이어 붙인 뒤 한 번에 줄여서 이음매가 안 보이게 함
  출력: assets/art/props/interior/runner_h.png (중앙 복도), runner_v.png (병동 복도), lobby_rug.png
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from build_interior import key  # noqa: E402
from clean_chroma import hq_resize_xy  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).parent / "src/map/haemu_rugs.jpg"
OUT = ROOT / "assets/art/props/interior"
WIDTH = 104          # 러너 폭(px) = 1.6칸. 복도는 3칸

# 가로 러너: 같은 세로 범위로 잘라야 이어 붙였을 때 위아래가 맞음
H_ROWS = (136, 541)
H_LEFT, H_MID, H_RIGHT = (109, 420), (466, 1325), (1373, 1684)   # 조각 이음 쪽은 3~4px 안으로 (번진 가장자리 빼기)
H_COUNT = 14          # 가운데 조각 수 → 중앙 복도 길이에 맞춤
# 세로 러너: 같은 가로 범위
V_COLS = (1354, 1706)
V_TOP, V_MID, V_BOTTOM = (702, 1008), (1056, 1899), (1951, 2300)
V_COUNT = 4
LOBBY = (108, 735, 1218, 2245)


def piece(img, box):
    return Image.fromarray(key(np.array(img.crop(box))), "RGBA")


def main() -> None:
    img = Image.open(SRC).convert("RGB")
    y0, y1 = H_ROWS
    parts = [piece(img, (H_LEFT[0], y0, H_LEFT[1], y1))]
    mid = piece(img, (H_MID[0], y0, H_MID[1], y1))
    parts += [mid] * H_COUNT
    parts.append(piece(img, (H_RIGHT[0], y0, H_RIGHT[1], y1)))
    w = sum(p.width for p in parts)
    run = Image.new("RGBA", (w, y1 - y0))
    x = 0
    for p in parts:
        run.alpha_composite(p, (x, 0))
        x += p.width
    s = WIDTH / run.height
    hq_resize_xy(run, round(run.width * s), WIDTH).save(OUT / "runner_h.png")

    x0, x1 = V_COLS
    parts = [piece(img, (x0, V_TOP[0], x1, V_TOP[1]))]
    mid = piece(img, (x0, V_MID[0], x1, V_MID[1]))
    parts += [mid] * V_COUNT
    parts.append(piece(img, (x0, V_BOTTOM[0], x1, V_BOTTOM[1])))
    h = sum(p.height for p in parts)
    run = Image.new("RGBA", (x1 - x0, h))
    y = 0
    for p in parts:
        run.alpha_composite(p, (0, y))
        y += p.height
    s = WIDTH / run.width
    hq_resize_xy(run, WIDTH, round(run.height * s)).save(OUT / "runner_v.png")

    rug = piece(img, LOBBY)
    rug = rug.crop(rug.getbbox()).transpose(Image.ROTATE_90)    # 로비에 가로로 깔기
    hq_resize_xy(rug, 400, round(rug.height * 400 / rug.width)).save(OUT / "lobby_rug.png")
    for n in ("runner_h", "runner_v", "lobby_rug"):
        print(n, Image.open(OUT / f"{n}.png").size)


if __name__ == "__main__":
    main()
