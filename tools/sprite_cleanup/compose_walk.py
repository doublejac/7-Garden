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
from clean_chroma import hq_resize, key_green  # noqa: E402


def hem_row(a):
    al = a[..., 3] > 128
    white = al & (a[..., 0] > 215) & (a[..., 1] > 215) & (a[..., 2] > 215)
    return int(np.nonzero(white.sum(1) >= 6)[0].max())


def main(out_dir, name, idle_name, legs_src, fps=6):
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
    src = hq_resize(src, k)
    ea = np.array(src)
    e_hem = hem_row(ea)
    e_cx = np.nonzero((ea[..., 3] > 128).any(0))[0].mean()
    s_cx = np.nonzero(s_al.any(0))[0].mean()

    cut = s_hem - 1                                        # 밑단 바로 위부터 다리
    # 다리만 따로 배율: 서 있는 발(가장 아래)이 정지 그림의 바닥선에 닿도록 (편집 그림은 다리가 가늘고 짧게 나옴)
    s_bot = np.nonzero(s_al.any(1))[0][-1]
    e_bot = np.nonzero((ea[..., 3] > 128).any(1))[0][-1]
    leg_img = Image.fromarray(ea[e_hem - 1:e_bot + 1], "RGBA")
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


    # 반대 발: 다리 부분만 좌우 반전 (몸 가운데 기준)
    other = step.copy()
    xs = np.nonzero((step[cut:, :, 3] > 128).any(0))[0]
    a0, a1 = xs[0], xs[-1] + 1
    other[cut:, a0:a1] = step[cut:, a0:a1][:, ::-1]

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
