"""실내 타일·가구 정리 도구 (Gemini 초록 배경 시트 → Godot용 PNG).

사용: python3 tools/sprite_cleanup/build_interior.py
  입력: tools/sprite_cleanup/src/map/interior_tiles.jpg, interior_props.jpg
  출력: assets/art/tiles/interior.png (64px 타일 아틀라스)
        assets/art/props/interior/<이름>.png + props.json (크기 정보)

타일 시트는 Gemini 한 칸을 타일 2×2칸(128px)으로 쓴다 (견본 방과 디테일 굵기가 맞음).
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, str(Path(__file__).parent))
from clean_chroma import hq_resize, key_green  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).parent / "src" / "map"
T = 64

# 타일 시트: 이름 → ((시트 행, 열), 아틀라스 위치(타일 단위)). 모두 2×2 블록
TILE_BLOCKS = {
    "wood_a": ((0, 0), (0, 0)), "wood_b": ((0, 1), (2, 0)),
    "corridor_a": ((0, 2), (4, 0)), "corridor_b": ((0, 3), (6, 0)),
    "lobby": ((3, 0), (0, 2)), "dining": ((3, 1), (2, 2)),
}
WALL_AT = (4, 2)        # 벽 앞면 2×3 (몰딩 / 회벽 / 판벽)
WALL_TOP_AT = (6, 2)    # 벽 윗면 1칸
ATLAS = (12, 9)

# 2차 시트 (복도 바닥 후보·비상구, 옆벽 문·벽 윗면). 좌표는 원본 2048px 기준 [x0, y0, x1, y1]
CORRIDOR_SRC = "corridor_exit.jpg"
CORRIDOR_BLOCKS = {          # 이름: (원본 칸, 아틀라스 위치, 블록 크기(타일))
    "marble": ((37, 528, 512, 1013), (8, 0), 2),
    "herringbone": ((532, 528, 1014, 1013), (10, 0), 2),
    "floral": ((37, 1035, 511, 1515), (8, 2), 2),
    "runner_v": ((532, 1034, 1014, 1516), (0, 5), 3),   # 세로 복도용 러너 카펫 (3칸 폭)
}
RUNNER_H_AT = (3, 5)         # 러너를 90도 돌린 가로 복도용
EXIT_DOOR = (1034, 527, 2012, 1519)
WALLS_SRC = "side_doors_walls.jpg"
SIDE_DOOR_CLOSED = (245, 20, 342, 1014)
WALL_TOP_V = (26, 1034, 512, 1522)
WALL_TOP_H = (532, 1034, 1014, 1522)
WALL_AUTO_AT = (6, 5)        # 벽 윗면 자동 타일 16종 (4×4). 번호 = 위1 + 오른쪽2 + 아래4 + 왼쪽8 (그쪽도 벽이면 켜짐)

# 가구: 시트에서 찾은 덩어리를 왼쪽 위부터 읽는 순서대로 이름 붙임
PROP_NAMES = ["bed", "nightstand", "sink", "mirror", "plant", "wardrobe", "armchair", "desk",
              "dining_table", "sofa", "frame_photo", "frame_empty", "door", "door_b", "glass_door", "window"]
PROP_SCALE = 0.30                       # 침대 폭이 타일 2칸이 되는 배율 (시트 전체 공통)
PROP_HEIGHT = {"door": 184, "door_b": 184, "glass_door": 184}   # 벽(3칸=192px) 안에 들어가야 하는 것


def grid_runs(v, th=0.3, min_len=100):
    on, out, s = v > th, [], None
    for i, x in enumerate(on):
        if x and s is None:
            s = i
        if not x and s is not None:
            out.append((s, i))
            s = None
    if s is not None:
        out.append((s, len(on)))
    return [o for o in out if o[1] - o[0] > min_len]


def build_tiles():
    img = Image.open(SRC / "interior_tiles.jpg").convert("RGB")
    a = np.array(img).astype(int)
    green = (a[..., 1] > 180) & (a[..., 0] < 120) & (a[..., 2] < 120)
    cols, rows = grid_runs((~green).mean(0)), grid_runs((~green).mean(1))

    def cell(r, c, inset=6):
        (y0, y1), (x0, x1) = rows[r], cols[c]
        return img.crop((x0 + inset, y0 + inset, x1 - inset, y1 - inset)).resize((2 * T, 2 * T), Image.LANCZOS)

    atlas = Image.new("RGBA", (ATLAS[0] * T, ATLAS[1] * T), (0, 0, 0, 0))
    for (r, c), (ax, ay) in TILE_BLOCKS.values():
        atlas.paste(cell(r, c), (ax * T, ay * T))

    # 벽 앞면 128×192: 몰딩 띠(위 칸 윗부분) + 회벽 + 판벽 띠(아래 칸 아랫부분).
    # Gemini 칸은 가장자리가 어두워 이어 붙이면 이음매가 보이므로, 회벽은 칸 가운데 색으로 평평하게 칠함
    top, bottom = cell(1, 0, inset=8), cell(1, 2, inset=8)

    def lum(im):
        return np.array(im.convert("L")).astype(int)[:, 32:96].mean(1)

    lt, lb = lum(top), lum(bottom)
    m = int(np.argmax(lt > 200))                        # 몰딩이 끝나는 줄
    w0 = int(len(lb) - np.argmax(lb[::-1] > 200))       # 판벽이 시작하는 줄
    cream = tuple(int(v) for v in np.median(np.array(top.convert("RGBA"))[m + 8:m + 40, 40:88].reshape(-1, 4), 0))
    strip = Image.new("RGBA", (2 * T, 3 * T), cream)
    strip.paste(top.crop((0, 0, 2 * T, m)), (0, 0))
    strip.paste(bottom.crop((0, w0, 2 * T, 2 * T)), (0, 3 * T - (2 * T - w0)))
    atlas.paste(strip, (WALL_AT[0] * T, WALL_AT[1] * T))

    # 벽 윗면: 짙은 나무색 한 가지 (줄을 넣으면 세로 벽에 가로줄이 반복돼 보임)
    wt = Image.new("RGBA", (T, T), (61, 42, 31, 255))
    atlas.paste(wt, (WALL_TOP_AT[0] * T, WALL_TOP_AT[1] * T))
    build_tiles_2(atlas)
    out = ROOT / "assets/art/tiles"
    out.mkdir(parents=True, exist_ok=True)
    atlas.save(out / "interior.png")
    print("타일:", out / "interior.png", f"(몰딩 {m}px, 판벽 {2 * T - w0}px)")


def build_props():
    rgb = np.array(Image.open(SRC / "interior_props.jpg").convert("RGB"))
    rgba = key_green(rgb)
    solid = rgba[..., 3] > 128
    lab, _ = ndi.label(ndi.binary_closing(solid, iterations=3))
    boxes = [sl for sl in ndi.find_objects(lab) if (sl[0].stop - sl[0].start) * (sl[1].stop - sl[1].start) > 3000]
    # 왼쪽 위부터 읽는 순서: 윗변 150px 단위로 행을 묶고 왼쪽부터
    boxes.sort(key=lambda s: (s[0].start // 150, s[1].start))
    if len(boxes) != len(PROP_NAMES):
        sys.exit(f"가구 {len(boxes)}개를 찾음 (이름은 {len(PROP_NAMES)}개)")
    out = ROOT / "assets/art/props/interior"
    out.mkdir(parents=True, exist_ok=True)
    meta = {}
    for name, sl in zip(PROP_NAMES, boxes):
        im = Image.fromarray(rgba[sl].copy(), "RGBA")
        im = im.crop(im.getbbox())
        k = PROP_HEIGHT[name] / im.height if name in PROP_HEIGHT else PROP_SCALE
        im = hq_resize(im, k)
        im = im.crop(im.getbbox())
        im.save(out / f"{name}.png")
        meta[name] = list(im.size)
        print(f"  {name}: {im.size[0]}x{im.size[1]}")
    (out / "props.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")


def build_tiles_2(atlas):
    """복도 바닥 후보와 벽 윗면 자동 타일."""
    img = Image.open(SRC / CORRIDOR_SRC).convert("RGB")
    for (x0, y0, x1, y1), (ax, ay), n in CORRIDOR_BLOCKS.values():
        block = img.crop((x0 + 6, y0 + 6, x1 - 6, y1 - 6)).resize((n * T, n * T), Image.LANCZOS)
        atlas.paste(block, (ax * T, ay * T))
        if n == 3:
            atlas.paste(block.transpose(Image.ROTATE_90), (RUNNER_H_AT[0] * T, RUNNER_H_AT[1] * T))

    walls = Image.open(SRC / WALLS_SRC).convert("RGB")
    v = walls.crop(WALL_TOP_V).resize((T, T), Image.LANCZOS)
    h = walls.crop(WALL_TOP_H).resize((T, T), Image.LANCZOS)
    a_v, a_h = np.array(v), np.array(h)
    edge = 8                                           # 테두리 장식 두께(px)
    fill = np.median(a_v[20:44, 20:44].reshape(-1, 3), 0).astype(np.uint8)
    for idx in range(16):
        up, right, down, left = idx & 1, idx & 2, idx & 4, idx & 8
        t = np.empty((T, T, 3), np.uint8)
        t[:] = fill
        if not left:
            t[:, :edge] = a_v[:, :edge]
        if not right:
            t[:, -edge:] = a_v[:, -edge:]
        if not up:
            t[:edge, :] = a_h[:edge, :]
        if not down:
            t[-edge:, :] = a_h[-edge:, :]
        # 바깥 모서리: 두 테두리가 만나는 자리는 세로 테두리 무늬로 맞춤
        for cond, ys in ((not up, slice(0, edge)), (not down, slice(T - edge, T))):
            if cond and not left:
                t[ys, :edge] = a_v[ys, :edge]
            if cond and not right:
                t[ys, -edge:] = a_v[ys, -edge:]
        atlas.paste(Image.fromarray(t), ((WALL_AUTO_AT[0] + idx % 4) * T, (WALL_AUTO_AT[1] + idx // 4) * T))


def open_door(closed):
    """닫힌 옆문에서 열린 문을 만든다: 문틀 기둥은 그대로, 문짝만 위 기둥에서 방 쪽(오른쪽)으로 90도 돌림.
    (Gemini가 그린 열린 문은 기둥이 네 개라 닫힌 문과 모양이 달라서 쓰지 않음)"""
    a = np.array(closed)
    wide = (a[..., 3] > 100).sum(1) >= a.shape[1] - 2      # 기둥 줄 (폭이 꽉 찬 줄)
    rows = np.nonzero(~wide)[0]
    p0, p1 = rows[0], rows[-1] + 1                          # 문짝 구간
    leaf = closed.crop((0, p0, closed.width, p1))
    leaf = leaf.crop(leaf.getbbox()).transpose(Image.ROTATE_90)   # 세로 → 가로
    out = Image.new("RGBA", (closed.width + leaf.width, closed.height), (0, 0, 0, 0))
    posts = a.copy()
    posts[p0:p1] = 0
    out.alpha_composite(Image.fromarray(posts, "RGBA"), (0, 0))
    out.alpha_composite(leaf, (closed.width, p0 - leaf.height // 2))
    return out


def build_props_2():
    """비상구 유리문(새 것), 옆벽 문(닫힘/열림)."""
    out = ROOT / "assets/art/props/interior"
    meta = json.loads((out / "props.json").read_text(encoding="utf-8"))

    def cut(src, box, k=None, height=None):
        rgba = key_green(np.array(Image.open(SRC / src).convert("RGB").crop(box)))
        im = Image.fromarray(rgba, "RGBA")
        im = im.crop(im.getbbox())
        im = hq_resize(im, k if k else height / im.height)
        return im.crop(im.getbbox())

    items = {
        "exit_door": cut(CORRIDOR_SRC, EXIT_DOOR, height=184),
        # 옆벽 문: 문틀 기둥 사이 = 타일 2칸 높이. 원본 994px → 128px
        "side_door_closed": cut(WALLS_SRC, SIDE_DOOR_CLOSED, k=2 * T / 994),
    }
    items["side_door_open"] = open_door(items["side_door_closed"])
    for name, im in items.items():
        im.save(out / f"{name}.png")
        meta[name] = list(im.size)
        print(f"  {name}: {im.size[0]}x{im.size[1]}")
    (out / "props.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")


if __name__ == "__main__":
    build_tiles()
    build_props()
    build_props_2()
