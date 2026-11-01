"""실내 타일·가구 정리 도구 – 해무 톤 (Gemini 초록 배경 시트 → Godot용 PNG).

사용: python3 tools/sprite_cleanup/build_interior.py
  입력: tools/sprite_cleanup/src/map/haemu_tiles.jpg       바닥·벽 타일 시트 (4×4, 한 칸 = 타일 2×2)
        tools/sprite_cleanup/src/map/haemu_props_room.jpg  병실 공통 가구·문·창
        tools/sprite_cleanup/src/map/legacy_props/          아직 해무 톤으로 다시 받지 않은 가구 (색만 해무 톤으로 바꿔 씀)
  출력: assets/art/tiles/interior.png (64px 타일 아틀라스)
        assets/art/props/interior/<이름>.png + props.json

이전(따뜻한 갈색) 버전 도구는 build_interior_warm_old.py 로 남겨 둠.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance
from scipy import ndimage as ndi

sys.path.insert(0, str(Path(__file__).parent))
from clean_chroma import hq_resize  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(__file__).parent / "src" / "map"
OUT_TILES = ROOT / "assets/art/tiles"
OUT_PROPS = ROOT / "assets/art/props/interior"
T = 64
ATLAS = (12, 9)

# ── 타일 시트: 칸 [x0, y0, x1, y1] (원본 2048px) → 아틀라스 위치(타일 단위), 2×2 블록 ──
TILE_SRC = "haemu_tiles.jpg"
FLOOR_BLOCKS = {
    "wood_a": ((25, 25, 508, 508), (0, 0)),
    "wood_b": ((529, 25, 1013, 508), (2, 0)),
    "gray_tile": ((1035, 529, 1519, 1013), (4, 0)),      # 주방·투약실
    "bath_hex": ((1540, 24, 2024, 508), (6, 0)),        # 욕실
    "floral": ((1034, 24, 1519, 508), (8, 2)),          # 복도
    "lobby": ((25, 529, 508, 1013), (0, 2)),
    "dining": ((529, 529, 1014, 1014), (2, 2)),
}
RUG = (1541, 529, 2023, 1013)                           # 러그는 이어지지 않는 한 장 그림 → 가구로
WALL_TOP_CELL = (24, 1035, 507, 1519)                   # 몰딩 + 회벽
WALL_BOTTOM_CELL = (1035, 1035, 1519, 1519)             # 회벽 + 판벽
WALL_TOP_V = (24, 1542, 507, 2027)                      # 세로 벽 윗면
WALL_TOP_H = (529, 1542, 1013, 2027)                    # 가로 벽 윗면
WALL_AT = (4, 2)
WALL_AUTO_AT = (6, 5)   # 벽 윗면 16종. 번호 = 위1 + 오른쪽2 + 아래4 + 왼쪽8 (그쪽도 벽 윗면이면 켜짐)

# ── 가구 시트 (원본 1792×2400): 이름 → 상자, 배율 규칙 ──
PROP_SRC = "haemu_props_room.jpg"
K = 128 / 406           # 침대 폭(406px)이 타일 2칸이 되는 배율
PROPS = {
    "bed": ((110, 95, 516, 774), K),
    "nightstand": ((699, 147, 892, 378), K),
    "window": ((1110, 100, 1630, 505), K),
    "vase_table": ((693, 476, 913, 823), K),        # 꽃 꽂힌 원탁
    "table_small": ((1055, 554, 1276, 822), K),     # 빈 꽃병 원탁
    "chair": ((1450, 512, 1645, 836), K),
    "suitcase": ((150, 924, 421, 1189), K),
    "wardrobe": ((581, 882, 912, 1303), K),
    "armchair": ((1026, 916, 1325, 1218), K),
    "plant": ((1461, 947, 1652, 1204), K),
    "door": ((123, 1450, 413, 1932), ("h", 184)),
    "exit_door": ((1077, 1362, 1658, 1973), ("h", 184)),
    "frame_photo": ((1044, 2099, 1264, 2302), 0.26),
    "frame_empty": ((1474, 2099, 1692, 2302), 0.26),
}
# 2차 가구 시트들: (원본 파일, 상자, 맞출 크기 ("w"|"h", px), 조각 모두 유지?)
PROPS2 = {
    # 원장실·투약실·로비·철문 (haemu_props_office.jpg)
    "director_desk": ("haemu_props_office.jpg", (59, 61, 700, 624), ("w", 192)),
    "bookshelf": ("haemu_props_office.jpg", (759, 61, 1186, 624), ("w", 128)),
    "certificate": ("haemu_props_office.jpg", (1546, 178, 1730, 323), ("w", 48)),
    "certificate_b": ("haemu_props_office.jpg", (1540, 442, 1736, 586), ("w", 48)),
    "med_cabinet": ("haemu_props_office.jpg", (55, 686, 450, 1200), ("w", 128)),
    "clock": ("haemu_props_office.jpg", (1535, 660, 1725, 1200), ("w", 60)),
    "fireplace": ("haemu_props_office.jpg", (867, 720, 1439, 1196), ("w", 192)),
    "med_cart": ("haemu_props_office.jpg", (535, 881, 778, 1199), ("w", 62)),
    "entrance_door": ("haemu_props_office.jpg", (55, 1255, 636, 1808), ("h", 184)),
    "steel_door": ("haemu_props_office.jpg", (1375, 1255, 1737, 1805), ("h", 184)),
    "umbrella_stand": ("haemu_props_office.jpg", (716, 1456, 907, 1799), ("w", 52)),
    "door_mat": ("haemu_props_office.jpg", (934, 1620, 1322, 1794), ("w", 128)),
    # 정면으로 다시 받은 것
    "sofa": ("haemu_sofa.jpg", (108, 115, 2445, 1186), ("w", 200)),
    "dining_table": ("haemu_dining_table.jpg", (191, 92, 2030, 1939), ("w", 168)),
    "file_cabinet": ("haemu_file_cabinet.jpg", (216, 191, 1611, 2284), ("w", 62)),
    # 주방·욕실 (haemu_props_kitchen_bath.jpg)
    "kitchen_counter": ("haemu_props_kitchen_bath.jpg", (112, 53, 1680, 569), ("w", 288)),
    "stove": ("haemu_props_kitchen_bath.jpg", (230, 668, 666, 1310), ("w", 112)),
    "cupboard_glass": ("haemu_props_kitchen_bath.jpg", (988, 668, 1606, 1499), ("w", 124)),
    "cupboard": ("haemu_props_kitchen_bath.jpg", (95, 1429, 649, 2293), ("w", 112)),
    "bath_sink": ("haemu_props_kitchen_bath.jpg", (1001, 1622, 1239, 2010), ("w", 56)),
    "bath_mirror": ("haemu_props_kitchen_bath.jpg", (1436, 1648, 1703, 1980), ("w", 52)),
    "toilet": ("haemu_props_kitchen_bath.jpg", (1462, 2022, 1673, 2398), ("w", 48)),
    "bath_mirror_sq": ("haemu_props_kitchen_bath.jpg", (977, 2051, 1267, 2343), ("w", 56)),
    # 채린 방·보호자실·빈 병실 (haemu_props_rooms.jpg)
    "chaerin_bed": ("haemu_props_rooms.jpg", (154, 132, 566, 762), ("w", 128)),
    "vanity": ("haemu_props_rooms.jpg", (835, 125, 1213, 777), ("w", 116)),
    "crayon_drawings": ("haemu_props_rooms.jpg", (1368, 134, 1898, 352), ("w", 132), True),
    "scrapbook_table": ("haemu_props_rooms.jpg", (1445, 467, 1837, 714), ("w", 112)),
    "doll_shelf": ("haemu_props_rooms.jpg", (145, 846, 576, 1227), ("w", 120), True),
    "cot": ("haemu_props_rooms.jpg", (805, 861, 1100, 1392), ("w", 96)),
    "cot_empty": ("haemu_props_rooms.jpg", (1163, 861, 1433, 1392), ("w", 90)),
    "camcorder_side": ("haemu_props_rooms.jpg", (1651, 842, 1821, 1212), ("h", 116)),
    "bed_bare": ("haemu_props_rooms.jpg", (1528, 1276, 1904, 1899), ("w", 128)),
    "camcorder": ("haemu_props_rooms.jpg", (150, 1373, 367, 1899), ("h", 116)),
    "covered_furniture": ("haemu_props_rooms.jpg", (1031, 1523, 1448, 1894), ("w", 120)),
    "tape_box": ("haemu_props_rooms.jpg", (415, 1655, 626, 1838), ("w", 54)),
    "suitcase_open": ("haemu_props_rooms.jpg", (692, 1573, 983, 1884), ("w", 88)),
}
LEGACY = ["mirror", "sink", "desk", "door_b"]


def key(rgb):
    """초록 배경 제거: 초록이 다른 채널보다 확실히 튀는 곳(그림자 포함)은 투명, 경계는 부드럽게, 초록 번짐 제거."""
    im = rgb.astype(np.float32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    diff = g - np.maximum(r, b)
    alpha = np.clip((45.0 - diff) / 25.0, 0.0, 1.0)
    # 테두리와 이어진 초록만 배경. 물건 안쪽의 초록(비상구 표지판 등)은 그대로 둠
    lab, _ = ndi.label(diff > 20)
    border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    inner = (lab > 0) & ~np.isin(lab, border[border > 0])
    # 단, 빨강·파랑이 비슷한 순수 초록(침대 살 사이·의자 등받이 틈으로 보이는 배경과 그 그림자)은
    # 안쪽이어도 배경. 비상구 표지판처럼 청록 기가 있는 초록(파랑 > 빨강)만 남김
    for i in np.unique(lab[inner]):
        reg = lab == i
        if np.median(b[reg] - r[reg]) < 25:
            inner[reg] = False
    alpha[inner] = 1.0
    g2 = np.where((diff > 6) & ~inner, np.maximum(r, b) + 6, g)
    return np.dstack([r, g2, b, alpha * 255]).clip(0, 255).astype(np.uint8)


def cut(img_rgb, box, keep_all=False):
    rgba = key(np.array(img_rgb.crop(box)))
    lab, n = ndi.label(rgba[..., 3] > 30)
    if n > 1 and not keep_all:   # 옆 물건에서 묻어 온 조각 제거 (가장 큰 덩어리의 15% 미만)
        sizes = ndi.sum(np.ones(lab.shape), lab, range(1, n + 1))
        keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= sizes.max() * 0.15])
        rgba[~keep] = 0
    im = Image.fromarray(rgba, "RGBA")
    return im.crop(im.getbbox())


def fogify(im):
    """예전 갈색 가구를 해무 톤으로: 채도를 낮추고 살짝 차갑게."""
    rgb = ImageEnhance.Color(im.convert("RGB")).enhance(0.45)
    rgb = ImageEnhance.Contrast(rgb).enhance(0.9)
    a = np.array(rgb).astype(np.float32) * np.array([0.95, 0.96, 1.0])
    out = Image.fromarray(a.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")
    out.putalpha(im.getchannel("A"))
    return out


def build_tiles():
    img = Image.open(SRC / TILE_SRC).convert("RGB")

    def cell(box, inset=6, n=2):
        x0, y0, x1, y1 = box
        return img.crop((x0 + inset, y0 + inset, x1 - inset, y1 - inset)).resize((n * T, n * T), Image.LANCZOS)

    atlas = Image.new("RGBA", (ATLAS[0] * T, ATLAS[1] * T), (0, 0, 0, 0))
    for box, (ax, ay) in FLOOR_BLOCKS.values():
        atlas.paste(cell(box), (ax * T, ay * T))

    # 벽 앞면 128×192: 몰딩 띠 + 평평한 회벽 + 판벽 띠 (칸 가장자리의 얼룩은 이어 붙이면 이음매가 되므로 회벽은 평평하게)
    top, bottom = cell(WALL_TOP_CELL, inset=8), cell(WALL_BOTTOM_CELL, inset=8)

    def lum(im):
        return np.array(im.convert("L")).astype(int)[:, 32:96].mean(1)

    lt, lb = lum(top), lum(bottom)
    m = int(np.argmax(lt > 190))                        # 몰딩이 끝나는 줄
    w0 = int(len(lb) - np.argmax(lb[::-1] > 190))       # 판벽이 시작하는 줄
    plaster = tuple(int(v) for v in np.median(np.array(top.convert("RGBA"))[m + 10:m + 50, 40:88].reshape(-1, 4), 0))
    strip = Image.new("RGBA", (2 * T, 3 * T), plaster)
    strip.paste(top.crop((0, 0, 2 * T, m)), (0, 0))
    strip.paste(bottom.crop((0, w0, 2 * T, 2 * T)), (0, 3 * T - (2 * T - w0)))
    atlas.paste(strip, (WALL_AT[0] * T, WALL_AT[1] * T))

    # 벽 윗면: 시트의 세로/가로 벽 칸에서 갈색 띠(테두리 포함)만 잘라 64px로 → 테두리 조각으로 16종 합성
    def band(box, axis):
        a = np.array(img.crop(box)).astype(int)
        brown = (a[..., 0] - a[..., 2]) > 4             # 갈색 띠 (옆의 회색 여백은 파란 기가 더 많음)
        prof = brown.mean(axis)
        idx = np.nonzero(prof > 0.6)[0]
        lo, hi = idx[0], idx[-1] + 1
        sub = img.crop(box)
        sub = sub.crop((lo, 0, hi, sub.height)) if axis == 0 else sub.crop((0, lo, sub.width, hi))
        return np.array(sub.resize((T, T), Image.LANCZOS))

    a_v, a_h = band(WALL_TOP_V, 0), band(WALL_TOP_H, 1)
    edge = 9
    fill = np.median(a_v[24:40, 24:40].reshape(-1, 3), 0).astype(np.uint8)
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
        for cond, ys in ((not up, slice(0, edge)), (not down, slice(T - edge, T))):
            if cond and not left:
                t[ys, :edge] = a_v[ys, :edge]
            if cond and not right:
                t[ys, -edge:] = a_v[ys, -edge:]
        atlas.paste(Image.fromarray(t), ((WALL_AUTO_AT[0] + idx % 4) * T, (WALL_AUTO_AT[1] + idx // 4) * T))

    OUT_TILES.mkdir(parents=True, exist_ok=True)
    atlas.save(OUT_TILES / "interior.png")
    print("타일:", OUT_TILES / "interior.png", f"(몰딩 {m}px, 판벽 {2 * T - w0}px)")


def build_props():
    OUT_PROPS.mkdir(parents=True, exist_ok=True)
    meta = {}

    def save(name, im):
        im = im.crop(im.getbbox())
        im.save(OUT_PROPS / f"{name}.png")
        meta[name] = list(im.size)
        print(f"  {name}: {im.size[0]}x{im.size[1]}")

    img = Image.open(SRC / PROP_SRC).convert("RGB")
    for name, (box, rule) in PROPS.items():
        im = cut(img, box)
        k = rule[1] / im.height if isinstance(rule, tuple) else rule
        save(name, hq_resize(im, k))
    # 러그: 타일 시트의 러그 칸 → 가로 3칸 × 세로 2칸 크기의 바닥 깔개
    tiles = Image.open(SRC / TILE_SRC).convert("RGB")
    rug = tiles.crop((RUG[0] + 6, RUG[1] + 6, RUG[2] - 6, RUG[3] - 6)).resize((3 * T, 2 * T), Image.LANCZOS)
    save("rug", rug.convert("RGBA"))
    cache = {}
    for name, spec in PROPS2.items():
        src, box, (axis, px) = spec[0], spec[1], spec[2]
        if src not in cache:
            cache[src] = Image.open(SRC / src).convert("RGB")
        im = cut(cache[src], box, keep_all=len(spec) > 3 and spec[3])
        save(name, hq_resize(im, px / (im.width if axis == "w" else im.height)))
    for name in LEGACY:
        save(name, fogify(Image.open(SRC / "legacy_props" / f"{name}.png").convert("RGBA")))
    build_doors(save)
    (OUT_PROPS / "props.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")


def build_doors(save):
    """문 부품을 정면 나무 문 그림 하나에서 만든다 (색과 그림체가 모든 문에서 같도록).
    door_frame / door_leaf : 정면 문의 문틀과 문짝 (열면 문짝이 경첩 쪽으로 접히는 애니메이션)
    side_leaf              : 옆벽 문을 열었을 때 방 안에 세워진 문짝 (3/4 시점에서는 문짝 앞면이 보임)
    door_plank_v/_h        : 옆벽·가로벽 문을 위에서 본 문짝 두께 (닫힌 문, 가로벽 문이 열렸을 때)
    door_post              : 문틀 기둥 윗면"""
    door = Image.open(OUT_PROPS / "door.png").convert("RGBA")
    a = np.array(door)
    lum = a[..., :3].astype(int).sum(2)
    mid = a.shape[0] // 2
    dark = np.nonzero((lum[mid] < 120) & (a[mid, :, 3] > 100))[0]
    x0, x1 = int(dark[dark < a.shape[1] // 2].max()) + 1, int(dark[dark > a.shape[1] // 2].min())
    col = a[:, a.shape[1] // 2 + 6]
    dark_y = np.nonzero((col[..., :3].astype(int).sum(1) < 140) & (col[..., 3] > 100))[0]
    y0 = int(dark_y[(dark_y > 4) & (dark_y < 30)].min()) + 1
    leaf = door.crop((x0, y0, x1, door.height))
    frame = door.copy()
    frame.paste((0, 0, 0, 0), (x0, y0, x1, door.height))
    save("door_frame", frame)
    save("door_leaf", leaf)
    save("side_leaf", leaf.resize((112, leaf.height - 8), Image.LANCZOS))
    # 위에서 본 문짝: 문짝 색 판 + 어두운 테두리 + 양쪽 손잡이
    wood = tuple(int(v) for v in np.median(np.array(leaf)[20:60, 20:60].reshape(-1, 4), 0))
    edge = tuple(int(v) for v in np.percentile(np.array(leaf)[..., :4].reshape(-1, 4), 5, axis=0))
    knob = (196, 182, 150, 255)

    def shade(c, d):
        return tuple(max(0, min(255, v + d)) for v in c[:3]) + (255,)

    def plank(length, thick=20):
        """위에서 본 닫힌 문짝: 두께 있는 원목 판 + 가운데 홈 + 양쪽 손잡이."""
        w = thick + 8
        im = Image.new("RGBA", (w, length), (0, 0, 0, 0))
        x0, x1 = 4, 4 + thick
        im.paste(edge[:3] + (255,), (x0, 0, x1, length))                  # 테두리
        im.paste(wood[:3] + (255,), (x0 + 1, 1, x1 - 1, length - 1))        # 판
        im.paste(shade(wood, 26), (x0 + 2, 2, x0 + 4, length - 2))          # 윗면 빛
        im.paste(shade(wood, -22), (x1 - 3, 2, x1 - 1, length - 2))         # 그늘
        cx = (x0 + x1) // 2
        im.paste(shade(wood, -34), (cx, 6, cx + 1, length - 6))             # 가운데 홈
        for yy in (8, length - 9):                                          # 위아래 가로대
            im.paste(shade(wood, -28), (x0 + 1, yy, x1 - 1, yy + 1))
        k = length // 2
        for kx in (0, x1 + 1):                                              # 손잡이 (양쪽)
            im.paste(edge[:3] + (255,), (kx, k - 4, kx + 4, k + 4))
            im.paste(knob, (kx + 1, k - 3, kx + 3, k + 3))
        return im

    pv = plank(100)
    save("door_plank_v", pv)
    save("door_plank_h", pv.transpose(Image.ROTATE_90))
    post = Image.new("RGBA", (24, 16), edge[:3] + (255,))
    post.paste(shade(wood, 8), (1, 1, 23, 15))
    post.paste(shade(wood, 30), (2, 2, 22, 4))
    save("door_post", post)


if __name__ == "__main__":
    build_tiles()
    build_props()
