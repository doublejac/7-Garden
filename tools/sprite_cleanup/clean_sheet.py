"""Gemini 도트 시트 정리 도구.

1) 체크무늬 배경 제거 (실루엣 채우기 방식)
2) 프레임 잘라내기
3) 실제 픽셀 크기로 축소 + 공통 팔레트로 색 정리
4) 발 위치 기준 같은 크기 칸에 정렬 → 애니메이션별 시트 PNG

사용: python3 clean_sheet.py 원본.png 설정.json 출력폴더
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi


def foreground_mask(rgb, checker_a, checker_b, tol=16):
    im = rgb.astype(int)
    d1 = np.sqrt(((im - checker_a) ** 2).sum(-1))
    d2 = np.sqrt(((im - checker_b) ** 2).sum(-1))
    bluish = (im[..., 2] - im[..., 0]) >= 5
    bg = ((d1 < tol) | (d2 < tol)) & bluish
    fg = ndi.binary_opening(~bg, iterations=1)
    return fg


def solid_silhouette(fg_crop):
    """머리끝처럼 배경색과 비슷한 부분에 생긴 구멍을 메운다."""
    lab, n = ndi.label(ndi.binary_dilation(fg_crop, iterations=2))
    if n == 0:
        return fg_crop
    sizes = ndi.sum(np.ones_like(lab), lab, range(1, n + 1))
    keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s > 400])
    closed = ndi.binary_closing(keep, iterations=3)
    filled = ndi.binary_fill_holes(closed)
    return ndi.binary_erosion(filled, iterations=2)


def hq_resize(img, scale):
    """알파를 곱한 상태로 Lanczos 축소 → 가장자리에 어두운 테두리가 생기지 않음."""
    w, h = max(1, round(img.width * scale)), max(1, round(img.height * scale))
    a = np.array(img).astype(np.float32) / 255.0
    rgb_p = a[..., :3] * a[..., 3:4]
    chans = [Image.fromarray((c * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)
             for c in (rgb_p[..., 0], rgb_p[..., 1], rgb_p[..., 2], a[..., 3])]
    r, g, b, al = [np.array(c).astype(np.float32) / 255.0 for c in chans]
    safe = np.maximum(al, 1e-4)
    out = np.dstack([np.clip(r / safe, 0, 1), np.clip(g / safe, 0, 1), np.clip(b / safe, 0, 1), al])
    out[al < 0.04] = 0
    return Image.fromarray((out * 255).round().astype(np.uint8), "RGBA")


def find_boxes(fg, min_h=200):
    lab, _ = ndi.label(ndi.binary_dilation(fg, iterations=6))
    boxes = []
    for sl in ndi.find_objects(lab):
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        if y1 - y0 >= min_h and x1 - x0 > 40:
            boxes.append((y0, y1, x0, x1))
    return boxes


def main(src, cfg_path, out_dir):
    cfg = json.loads(Path(cfg_path).read_text(encoding="utf-8"))
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rgb = np.array(Image.open(src).convert("RGB"))
    for x0, y0, x1, y1 in cfg.get("erase", []):          # 워터마크 등
        rgb[y0:y1, x0:x1] = cfg["checker_a"]
    fg = foreground_mask(rgb, np.array(cfg["checker_a"]), np.array(cfg["checker_b"]))
    boxes = find_boxes(fg)

    # 1차: 프레임마다 투명 배경 + 축소
    frames = {}
    for anim in cfg["animations"]:
        frames[anim["name"]] = []
        for (bx, by) in anim["frames"]:
            box = min(boxes, key=lambda b: abs(b[2] - bx) + abs(b[0] - by))
            y0, y1, x0, x1 = box
            pad = 6
            y0, x0 = max(0, y0 - pad), max(0, x0 - pad)
            y1, x1 = min(rgb.shape[0], y1 + pad), min(rgb.shape[1], x1 + pad)
            mask = solid_silhouette(fg[y0:y1, x0:x1])
            rgba = np.dstack([rgb[y0:y1, x0:x1], (mask * 255).astype(np.uint8)])
            img = Image.fromarray(rgba, "RGBA")
            scale = cfg.get("scale", 0.5)
            if scale != 1:
                img = hq_resize(img, scale)
            frames[anim["name"]].append((img, anim.get("flip", False)))

    def quant(f):
        return f

    # 3차: 같은 크기 칸, 발 위치(아래 가운데) 기준 정렬
    # 3차: 서 있는 동작은 키를 걷기 기준에 맞춤 (Gemini가 동작마다 크기를 다르게 그림)
    ref = cfg.get("reference_height")
    if ref:
        for anim in cfg["animations"]:
            if anim.get("standing"):
                lst = frames[anim["name"]]
                hs = sorted(f.getbbox()[3] - f.getbbox()[1] for f, _ in lst)
                k = ref / hs[len(hs) // 2]
                if abs(k - 1) > 0.02:
                    frames[anim["name"]] = [(hq_resize(f, k), fl) for f, fl in lst]
                    print(f"  {anim['name']}: 크기 x{k:.2f}로 맞춤")

    # 4차: 모든 동작을 같은 크기 칸에, 발바닥을 칸 바닥 가운데에
    every = [f.crop(f.getbbox()) for lst in frames.values() for f, _ in lst]
    cell_w = max(f.width for f in every) + 8
    cell_h = max(f.height for f in every) + 4
    cell_w += cell_w % 2
    meta = {"cell": [cell_w, cell_h], "animations": {}}
    for anim in cfg["animations"]:
        lst = frames[anim["name"]]
        sheet = Image.new("RGBA", (cell_w * len(lst), cell_h), (0, 0, 0, 0))
        for i, (f, flip) in enumerate(lst):
            f = f.crop(f.getbbox())
            if flip:
                f = f.transpose(Image.FLIP_LEFT_RIGHT)
            a = np.array(f)[..., 3] > 0
            lower = a[int(a.shape[0] * 0.66):]
            cx = np.nonzero(lower)[1].mean() if lower.any() else f.width / 2
            x = int(round(cell_w / 2 - cx))
            x = min(max(x, 0), cell_w - f.width)
            y = cell_h - f.height - cfg.get("foot_margin", 2)
            sheet.alpha_composite(f, (i * cell_w + x, y))
        sheet.save(out / f"{anim['name']}.png")
        meta["animations"][anim["name"]] = {
            "frames": len(lst), "cell": [cell_w, cell_h],
            "fps": anim.get("fps", 6), "loop": anim.get("loop", True)}
        print(f"{anim['name']}: {len(lst)}프레임")
    (out / "frames.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main(*sys.argv[1:4])
