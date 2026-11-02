"""영상(Google Flow 등)으로 만든 제자리 걷기를 스프라이트 시트로.

사용: python3 tools/sprite_cleanup/video_walk.py <정리된 출력 폴더> <동작 이름> <정지 동작> <영상> <시작 프레임> <주기 프레임 수> <칸 수> [fps] [반전 이름]
  - 영상에서 [시작, 시작+주기) 구간을 칸 수만큼 고르게 뽑음 (한 걸음 주기 = 왼발·오른발 한 번씩)
  - 초록 배경 제거, 정지 동작과 키(머리 꼭대기~발바닥)를 맞춰 줄이고, 발바닥을 칸 바닥에 맞춤
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from clean_chroma import chin_rows, head_width, hq_resize, hq_resize_xy, key_green, stature  # noqa: E402


def hem_row(a):
    al = a[..., 3] > 128
    white = al & (a[..., 0] > 215) & (a[..., 1] > 215) & (a[..., 2] > 215)
    return int(np.nonzero(white.sum(1) >= 3)[0].max())


def blink(img):
    """눈 감기: 파란 눈동자 둘레를 피부색으로 덮고 아래쪽에 감은 눈 선을 그림."""
    from scipy import ndimage as ndi
    a = np.array(img).copy()
    r, g, b = (a[..., i].astype(int) for i in range(3))
    blue = (a[..., 3] > 128) & (b > r + 40) & (b > g + 10)
    lab, n = ndi.label(ndi.binary_dilation(blue, iterations=1))
    if n == 0:
        return img
    sizes = ndi.sum(np.ones(lab.shape), lab, range(1, n + 1))
    eyes = [i + 1 for i, sz in enumerate(sizes) if sz >= sizes.max() * 0.4]   # 정면은 눈이 둘
    if len(eyes) > 1:
        out = img
        for e in eyes:
            m = (lab == e)
            out = _blink_one(out, m)
        return out
    return _blink_one(img, lab == np.argmax(sizes) + 1)


def _blink_one(img, mask):
    from scipy import ndimage as ndi
    a = np.array(img).copy()
    ys, xs = np.nonzero(mask)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    skin = a[min(a.shape[0] - 1, y1 + 3), (x0 + x1) // 2].copy()
    lash = a[y0 - 1, (x0 + x1) // 2].copy()
    if lash[:3].astype(int).sum() > 300:   # 위 속눈썹이 안 잡히면 어두운 색
        lash = np.array([40, 30, 40, 255], np.uint8)
    # 눈 둘레에서 피부가 아닌 것은 모두 피부색으로 덮되, 바깥까지 이어진 머리카락 덩어리는 남김
    pad = 8
    by0, by1, bx0, bx1 = y0 - 3, y1 + 3, x0 - 5, x1 + 3
    R0, R1, C0, C1 = by0 - pad, by1 + pad, bx0 - pad, bx1 + pad
    big = a[R0:R1, C0:C1]
    rr, gg, bb = (big[..., i].astype(int) for i in range(3))
    is_skin = (rr > 195) & (gg > 145) & (rr - bb > 15)
    nonskin = (big[..., 3] > 128) & ~is_skin
    inner = np.zeros(nonskin.shape, bool)
    inner[pad:-pad, pad:-pad] = True
    lab, n = ndi.label(nonskin)
    border = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    eye_blob = np.isin(lab, np.unique(lab[inner & nonskin])) & ~np.isin(lab, border[border > 0])
    # 머리카락과 붙어 있는 속눈썹은 덩어리로 안 잡히므로, 상자 안의 어두운 점·흰자·파랑도 덮음
    lum = (rr + gg + bb) / 3
    small = inner & nonskin & ((lum < 120) | (bb > rr + 20) | ((lum > 170) & (bb >= rr - 8)))
    small[:pad + 2] &= lum[:pad + 2] < 110   # 위쪽(앞머리 닿는 줄)은 어두운 속눈썹만
    hair_like = np.isin(lab, border[border > 0])
    spread = np.maximum(np.maximum(rr, gg), bb) - np.minimum(np.minimum(rr, gg), bb)
    small &= ~(hair_like & (lum > 120) & (spread < 30) & ~((lum > 170) & (bb >= rr - 8) & (lum < 200)))   # 바깥으로 이어진 회색 머리카락만 그대로
    gray_hair = hair_like & (lum > 120) & (spread < 30) & ~((lum > 170) & (bb >= rr - 8) & (lum < 200))
    kill = inner & (big[..., 3] > 128) & ~gray_hair   # 눈 상자 안은 머리카락 말고 전부 얼굴 바탕색으로 (눈두덩 그늘 점까지)
    # 지운 자리는 얼굴 바탕색(눈 아래 피부에서 가장 흔한 색)으로 메움. 도트 얼굴은 바탕색이 거의 한 색이라 자국이 안 남음
    below = big[inner.nonzero()[0].max() + 1: inner.nonzero()[0].max() + 6, pad:-pad]
    bm = (below[..., 0] > 200) & (below[..., 1] > 150) & (below[..., 0].astype(int) - below[..., 2] > 15)
    cols = [tuple(c) for c in below[bm][:, :3]] or [tuple(skin[:3])]
    base = max(set(cols), key=cols.count)
    col = big[..., :3].astype(float)
    col[kill] = base
    big[..., :3] = col.round().astype(np.uint8)
    # 감은 눈: 아래로 살짝 휜 2px 선 (양 끝이 1px 위)
    ly = y0 + (y1 - y0) * 2 // 3
    xa, xb = x0, x1 + 1
    a[ly:ly + 2, xa + 1:xb - 1] = lash
    a[ly - 1:ly + 1, xa] = lash
    a[ly - 1:ly + 1, xb - 1] = lash
    return Image.fromarray(a, "RGBA")


def write_idle(out, meta, name, mirror, cell, cw, ch):
    """정지 동작 8칸: 기본, 숨쉬기(상체 1px 내려감), 마지막 칸은 눈 깜빡임."""
    a = np.array(cell)
    al = a[..., 3] > 128
    white = al & (a[..., 0] > 215) & (a[..., 1] > 215) & (a[..., 2] > 215)
    hem = int(np.nonzero(white.sum(1) >= 3)[0].max())
    br = a.copy()
    br[1:hem + 1] = a[0:hem]
    br[0] = 0
    base, breath = cell, Image.fromarray(br, "RGBA")
    seq = [base, breath, base, breath, base, breath, base, blink(base)]
    for nm, flip in ((name, False), (mirror, True)):
        if not nm:
            continue
        sh = Image.new("RGBA", (cw * len(seq), ch), (0, 0, 0, 0))
        for i, f in enumerate(seq):
            sh.alpha_composite(f.transpose(Image.FLIP_LEFT_RIGHT) if flip else f, (i * cw, 0))
        sh.save(out / f"{nm}.png")
        meta["animations"][nm] = {"frames": len(seq), "cell": [cw, ch], "fps": 3, "loop": True}


def main(out_dir, name, idle_name, video, start, period, count, fps=8, mirror_as=None, idle_as=None, idle_mirror=None, proportion=True):
    out = Path(out_dir)
    meta = json.loads((out / "frames.json").read_text(encoding="utf-8"))
    cw, ch = meta["cell"]
    stand = Image.open(out / f"{idle_name}.png").convert("RGBA").crop((0, 0, cw, ch))
    sa = np.array(stand)
    s_al = sa[..., 3] > 128
    s_bot = np.nonzero(s_al.any(1))[0][-1]
    s_cx = np.nonzero(s_al.any(0))[0].mean()
    target = stature(stand)

    with tempfile.TemporaryDirectory() as td:
        subprocess.run(["ffmpeg", "-v", "error", "-i", str(video), f"{td}/f_%04d.png"], check=True)
        picks = [start + round(i * period / count) for i in range(count)]
        if idle_as:
            picks.append(0)   # 영상 첫 장면 = 넣은 정지 그림 자세 → 정지 동작도 영상 그림으로 (걷다 멈출 때 그림이 안 바뀌게)
        raw = []
        for p in picks:
            a = np.array(Image.open(f"{td}/f_{p + 1:04d}.png").convert("RGB"))
            g = (a[..., 1].astype(int) - np.maximum(a[..., 0], a[..., 2]).astype(int)) > 40
            cols = np.nonzero(g.mean(0) > 0.5)[0]          # 양옆 검은 띠 제외
            a = a[:, cols.min() + 2:cols.max() - 1]
            im = Image.fromarray(key_green(a), "RGBA")
            raw.append(im)
    # 배율: 모든 칸 공통 (첫 칸 키 기준) → 칸마다 크기가 흔들리지 않음
    r0 = raw[0].crop(raw[0].getbbox())
    k = target / stature(r0)
    # 영상은 원본 그림을 세로 화면(9:16)에 맞추느라 가로로 눌려 있음 → 머리 폭/키 비율을 정지 그림에 맞춰 가로로 되돌림
    kx = k * (head_width(stand) / stature(stand)) / (head_width(r0) / stature(r0))
    frames = []
    first_box = raw[0].getbbox()
    for im in raw:
        # 영상은 카메라가 고정이므로 같은 영역을 잘라 그대로 줄이면 몸 위치·오르내림이 보존됨
        crop = im.crop((first_box[0] - 20, 0, first_box[2] + 20, im.height))
        small = hq_resize_xy(crop, round(crop.width * kx), round(crop.height * k))
        frames.append(small)
    # 발바닥·가운데 맞춤: 첫 칸 기준으로 모든 칸을 같은 만큼 옮김
    f0 = np.array(frames[0])
    al0 = f0[..., 3] > 128
    dy = s_bot - np.nonzero(al0.any(1))[0][-1]
    dx = round(s_cx - np.nonzero(al0.any(0))[0].mean())
    sheet = Image.new("RGBA", (cw * count, ch), (0, 0, 0, 0))
    cells = []
    for i, f in enumerate(frames):
        cell = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        cell.alpha_composite(f, (dx, dy)) if dx >= 0 and dy >= 0 else cell.paste(f, (dx, dy), f)
        cells.append(cell)
        sheet.alpha_composite(cell, (i * cw, 0))
    # 비율 맞춤 (그림을 섞지 않음): 영상은 머리를 작게·몸을 길게 그려서, 같은 영상 그림을 턱에서 나눠
    # 머리는 정지 그림 머리 크기로, 몸은 정지 그림 몸 길이로 따로 늘이고 줄임. 가로 배율은 둘이 같아 이음매가 그대로 맞음.
    s_top, s_chin, _ = chin_rows(stand)
    c_top, c_chin, c_bot = chin_rows(cells[0])
    ku = (s_chin - s_top) / (c_chin - c_top)
    kl = (s_bot - s_chin) / (c_bot - c_chin)
    kxx = head_width(stand) / head_width(cells[0])
    if not proportion:   # 뒷모습처럼 턱(얼굴)이 안 보이면 비율 맞춤을 하지 않음 (키만 맞춤)
        ku = kl = 1.0
    t0 = c_top
    sheet = Image.new("RGBA", (cw * len(cells), ch), (0, 0, 0, 0))
    fixed = []
    sx = np.nonzero((sa[s_chin + 2:s_chin + 2 + int((s_bot - s_chin) * 0.55), :, 3] > 128).any(0))[0]
    for i, cell in enumerate(cells):
        top, chin, bot = chin_rows(cell)
        w = max(1, round(cw * kxx))
        up = hq_resize_xy(cell.crop((0, 0, cw, chin)), w, max(1, round(chin * ku)))
        low = hq_resize_xy(cell.crop((0, chin, cw, bot + 1)), w, max(1, round((bot + 1 - chin) * kl)))
        g = Image.new("RGBA", (w, up.height + low.height), (0, 0, 0, 0))
        g.alpha_composite(up, (0, 0))
        g.alpha_composite(low, (0, up.height))
        ga = np.array(g)
        gx = np.nonzero((ga[up.height + 2:up.height + 2 + int(low.height * 0.55), :, 3] > 128).any(0))[0]
        ox = int(round((sx[0] + sx[-1]) / 2 - (gx[0] + gx[-1]) / 2))
        oy = s_bot + 1 - g.height                     # 발바닥을 바닥선에
        out_c = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        out_c.paste(g, (ox, oy), g)
        fixed.append(out_c)
        sheet.alpha_composite(out_c, (i * cw, 0))
    cells = fixed
    if idle_as:
        stand_cell = cells.pop()
        sheet = sheet.crop((0, 0, cw * count, ch))
        write_idle(out, meta, idle_as, idle_mirror, stand_cell, cw, ch)
    sheet.save(out / f"{name}.png")
    meta["animations"][name] = {"frames": count, "cell": [cw, ch], "fps": fps, "loop": True}
    if mirror_as:
        mir = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
        for i, c in enumerate(cells):
            mir.alpha_composite(c.transpose(Image.FLIP_LEFT_RIGHT), (i * cw, 0))
        mir.save(out / f"{mirror_as}.png")
        meta["animations"][mirror_as] = dict(meta["animations"][name])
    (out / "frames.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{name}: 영상 {count}칸 (세로 x{k:.3f}, 가로 x{kx:.3f})")


if __name__ == "__main__":
    a = sys.argv[1:]
    main(a[0], a[1], a[2], a[3], int(a[4]), int(a[5]), int(a[6]), int(a[7]) if len(a) > 7 else 8, a[8] if len(a) > 8 else None)
