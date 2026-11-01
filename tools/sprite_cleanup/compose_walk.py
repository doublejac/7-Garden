"""걷기 합성: 정지 그림은 그대로 두고, 원피스 밑단 아래 다리만 '다리 편집 그림'에서 가져와 붙인다.
RPG 방식 4칸 걷기: [한 발 내딛기, 서기, 반대 발 내딛기(다리 좌우 반전), 서기]
머리·몸은 정지 그림과 픽셀 단위로 같으므로 떨림·얼굴 차이·크기 차이가 없다.

사용: python3 tools/sprite_cleanup/compose_walk.py <정리된 출력 폴더> <동작 이름> <정지 동작> <다리 편집 그림> [fps]
  예: python3 tools/sprite_cleanup/compose_walk.py /tmp/out walk_down idle src/v3/seoha_legs_down_step.jpg 6
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from clean_chroma import chin_rows, hq_resize, key_green  # noqa: E402


def hem_row(a):
    al = a[..., 3] > 128
    white = al & (a[..., 0] > 215) & (a[..., 1] > 215) & (a[..., 2] > 215)
    return int(np.nonzero(white.sum(1) >= 6)[0].max())


def main(out_dir, name, idle_name, legs_src, fps=6, body=False):
    out = Path(out_dir)
    meta = json.loads((out / "frames.json").read_text(encoding="utf-8"))
    cw, ch = meta["cell"]
    stand = Image.open(out / f"{idle_name}.png").convert("RGBA").crop((0, 0, cw, ch))
    sa = np.array(stand)
    s_al = sa[..., 3] > 128
    s_top = np.nonzero(s_al.any(1))[0][0]
    s_hem = hem_row(sa)

    src = Image.fromarray(key_green(np.array(Image.open(legs_src).convert("RGB"))), "RGBA")
    src = src.crop(src.getbbox())
    ea = np.array(src)
    e_top = np.nonzero((ea[..., 3] > 128).any(1))[0][0]
    k = (s_hem - s_top) / (hem_row(ea) - e_top)          # 머리끝~밑단 길이를 정지 그림에 맞춤
    big = src
    for _ in range(3):   # 원본은 해상도가 커서 밑단 위치가 줄인 뒤와 다르게 잡힘 → 줄인 결과로 다시 맞춤
        src = hq_resize(big, k)
        ea = np.array(src)
        got = hem_row(ea) - np.nonzero((ea[..., 3] > 128).any(1))[0][0]
        k *= (s_hem - s_top) / got
    e_hem = hem_row(ea)
    if body:
        # 색 맞춤: 편집 그림은 색감이 조금 달라 정지 그림과 번갈아 나오면 깜빡임 → 몸 부분 색 분포를 정지 그림에 맞춤
        chin_s = chin_rows(stand)[1] + 2
        e_top0 = np.nonzero((ea[..., 3] > 128).any(1))[0][0]
        s_reg = sa[chin_s:s_hem][sa[chin_s:s_hem, :, 3] > 200][:, :3].astype(float)
        eb = ea[chin_s - s_top + e_top0:e_hem]
        e_reg = eb[eb[..., 3] > 200][:, :3].astype(float)
        f = ea[..., :3].astype(float)
        for c in range(3):
            sm, ss = s_reg[:, c].mean(), s_reg[:, c].std() + 1e-3
            em, es = e_reg[:, c].mean(), e_reg[:, c].std() + 1e-3
            f[..., c] = (f[..., c] - em) * (ss / es) + sm
        ea = ea.copy()
        ea[..., :3] = f.clip(0, 255).astype(np.uint8)
    if body:
        # 폭 맞춤: 편집 그림의 몸이 더 홀쭉하게 나와서, 카디건 폭(밑단 위 줄)을 정지 그림에 맞춤
        def wid(a, y):
            xs = np.nonzero(a[y, :, 3] > 128)[0]
            return xs[-1] - xs[0] + 1
        e_top0 = np.nonzero((ea[..., 3] > 128).any(1))[0][0]
        rows = range(s_hem - 30, s_hem - 10)
        kxb = np.median([wid(sa, y) / wid(ea, y - s_top + e_top0) for y in rows])
        from clean_chroma import hq_resize_xy
        ea = np.array(hq_resize_xy(Image.fromarray(ea, "RGBA"), round(ea.shape[1] * kxb), ea.shape[0]))
    e_cx = np.nonzero((ea[..., 3] > 128).any(0))[0].mean()
    s_cx = np.nonzero(s_al.any(0))[0].mean()

    cut = s_hem + 2 if body else s_hem - 1                 # 다리가 시작하는 줄 (몸도 바꾸면 밑단 외곽선 아래부터)
    # 다리만 따로 배율: 서 있는 발(가장 아래)이 정지 그림의 바닥선에 닿도록 (편집 그림은 다리가 가늘고 짧게 나옴)
    s_bot = np.nonzero(s_al.any(1))[0][-1]
    e_bot = np.nonzero((ea[..., 3] > 128).any(1))[0][-1]
    leg_img = Image.fromarray(ea[(e_hem + 2 if body else e_hem - 1):e_bot + 1], "RGBA")
    k2 = (s_bot - cut + 1) / leg_img.height
    # 폭: 다리 묶음 폭을 정지 그림의 다리 폭에 맞춤 (편집 그림은 다리·신발이 가늘게 나옴)
    sl = np.nonzero((sa[s_hem + 2:, :, 3] > 128).any(0))[0]
    el = np.nonzero((np.array(leg_img)[3:, :, 3] > 128).any(0))[0]
    kx = max(k2, (sl[-1] - sl[0] + 1) / (el[-1] - el[0] + 1))
    from clean_chroma import hq_resize_xy
    leg_img = hq_resize_xy(leg_img, round(leg_img.width * kx), round(leg_img.height * k2))
    legs = np.array(leg_img)
    e_cx = e_cx * k2 + 0.0   # 아래에서 다시 계산
    lx = np.nonzero((legs[..., 3] > 128).any(0))[0]
    e_cx = (lx[0] + lx[-1]) / 2
    sx = np.nonzero((sa[cut:, :, 3] > 128).any(0))[0]
    s_cx = (sx[0] + sx[-1]) / 2
    step = sa.copy()
    step[cut:] = 0
    x0 = int(round(s_cx - e_cx))
    h = min(legs.shape[0], ch - cut)
    for y in range(h):
        for_row = legs[y]
        xs = np.arange(for_row.shape[0]) + x0
        ok = (xs >= 0) & (xs < cw)
        row = step[cut + y]
        src_px = for_row[ok]
        m = src_px[..., 3] > 0
        tgt = row[xs[ok]]
        tgt[m] = src_px[m]
        row[xs[ok]] = tgt

    top_cut = cut
    if body:
        # 몸(턱 아래 ~ 밑단)도 편집 그림에서: 팔 흔들림. 머리는 정지 그림 그대로
        chin = chin_rows(stand)[1] + 2
        e_top2 = np.nonzero((ea[..., 3] > 128).any(1))[0][0]
        dy = s_top - e_top2
        bx = np.nonzero((ea[..., 3] > 128).any(0))[0]
        bx0 = int(round(np.nonzero(s_al.any(0))[0].mean() - bx.mean()))
        step[chin:cut] = 0
        for y in range(chin, cut):
            ey = y - dy
            if 0 <= ey < ea.shape[0]:
                row = ea[ey]
                xs = np.arange(row.shape[0]) + bx0
                ok = (xs >= 0) & (xs < cw)
                m = row[ok][..., 3] > 0
                tgt = step[y][xs[ok]]
                tgt[m] = row[ok][m]
                step[y][xs[ok]] = tgt
        top_cut = chin

    # 반대 발: 다리(와 몸) 부분만 좌우 반전 (몸 가운데 기준)
    other = step.copy()
    xs = np.nonzero((step[top_cut:, :, 3] > 128).any(0))[0]
    a0, a1 = xs[0], xs[-1] + 1
    other[top_cut:, a0:a1] = step[top_cut:, a0:a1][:, ::-1]

    frames = [Image.fromarray(step, "RGBA"), stand, Image.fromarray(other, "RGBA"), stand]
    sheet = Image.new("RGBA", (cw * 4, ch), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.alpha_composite(f, (i * cw, 0))
    sheet.save(out / f"{name}.png")
    meta["animations"][name] = {"frames": 4, "cell": [cw, ch], "fps": fps, "loop": True}
    (out / "frames.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{name}: 4칸 (몸 배율 x{k:.3f}, 다리 배율 x{k2:.2f})")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]) if len(sys.argv) > 5 else 6)
