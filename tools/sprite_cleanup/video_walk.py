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


def main(out_dir, name, idle_name, video, start, period, count, fps=8, mirror_as=None):
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
    t0 = c_top
    sheet = Image.new("RGBA", (cw * count, ch), (0, 0, 0, 0))
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
