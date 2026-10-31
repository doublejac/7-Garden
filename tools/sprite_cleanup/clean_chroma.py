"""단색 초록(#00FF00) 배경 스프라이트 시트 정리 도구.

1) 초록 배경 제거 (가장자리 반투명 처리 + 초록 번짐 제거)
2) 격자 순서대로 프레임 자동 인식 (줄 → 칸)
3) 서 있는 동작은 '머리 꼭대기~발바닥' 높이로 캐릭터 크기 통일 (앉은 동작은 normalize: false)
4) 조개 핀이 반대쪽에 그려진 프레임 좌우 반전
5) 같은 크기 칸, 발바닥 기준 정렬 → 동작별 PNG + frames.json

사용: python3 clean_chroma.py 설정.json 출력폴더
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi


def key_green(rgb):
    im = rgb.astype(np.float32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    green = g - np.maximum(r, b)
    alpha = np.clip((150.0 - green) / 110.0, 0.0, 1.0)
    alpha[(g > 200) & (r < 60) & (b < 60)] = 0.0
    # 초록 번짐 제거: 초록이 다른 채널보다 튀는 만큼 깎음
    spill = np.maximum(r, b) + 8
    g2 = np.where(green > 8, np.minimum(g, spill), g)
    out = np.dstack([r, g2, b, alpha * 255]).clip(0, 255).astype(np.uint8)
    return out


def find_frames(rgba, min_h=120):
    solid = rgba[..., 3] > 128
    lab, _ = ndi.label(ndi.binary_dilation(solid, iterations=5))
    boxes = []
    for sl in ndi.find_objects(lab):
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        if y1 - y0 >= min_h:
            boxes.append((y0, y1, x0, x1))
    boxes.sort(key=lambda b: b[0])
    rows, cur = [], []
    for b in boxes:
        if cur and b[0] - cur[0][0] > 80:
            rows.append(sorted(cur, key=lambda c: c[2]))
            cur = []
        cur.append(b)
    if cur:
        rows.append(sorted(cur, key=lambda c: c[2]))
    return rows


def cut(rgba, box, pad=4):
    y0, y1, x0, x1 = box
    y0, x0 = max(0, y0 - pad), max(0, x0 - pad)
    y1, x1 = min(rgba.shape[0], y1 + pad), min(rgba.shape[1], x1 + pad)
    crop = rgba[y0:y1, x0:x1].copy()
    lab, n = ndi.label(crop[..., 3] > 20)
    if n > 1:   # 작은 얼룩 제거
        sizes = ndi.sum(np.ones(lab.shape), lab, range(1, n + 1))
        keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 300])
        crop[~keep] = 0
    img = Image.fromarray(crop, "RGBA")
    return img.crop(img.getbbox())


def hq_resize(img, scale):
    w, h = max(1, round(img.width * scale)), max(1, round(img.height * scale))
    a = np.array(img).astype(np.float32) / 255.0
    pre = a[..., :3] * a[..., 3:4]
    chans = [Image.fromarray((c * 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)
             for c in (pre[..., 0], pre[..., 1], pre[..., 2], a[..., 3])]
    r, g, b, al = [np.array(c).astype(np.float32) / 255.0 for c in chans]
    safe = np.maximum(al, 1e-4)
    out = np.dstack([np.clip(r / safe, 0, 1), np.clip(g / safe, 0, 1), np.clip(b / safe, 0, 1), al])
    out[al < 0.04] = 0
    return Image.fromarray((out * 255).round().astype(np.uint8), "RGBA")


def head_width(img):
    """은발 머리카락 영역의 폭 (손이나 소매가 머리 높이에 있어도 영향 없음)."""
    a = np.array(img).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    spread = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
    hair = (al > 128) & (spread < 28) & ((r + g + b) / 3 > 90)
    hair[int(a.shape[0] * 0.45):] = False
    cols = np.nonzero(hair.sum(0) >= 3)[0]
    if cols.size < 5:
        return img.width
    return np.percentile(cols, 98) - np.percentile(cols, 2)


def stature(img):
    """머리카락 맨 윗줄부터 발바닥까지의 높이. 머리 위로 올린 손은 세지 않는다."""
    a = np.array(img).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    spread = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
    hair = (al > 128) & (spread < 28) & ((r + g + b) / 3 > 90)
    rows = np.nonzero(hair.sum(1) >= 4)[0]
    solid = np.nonzero((al > 128).any(1))[0]
    if rows.size == 0:
        return img.height
    return solid[-1] - rows[0]


def pin_offset(img):
    a = np.array(img).astype(int)
    alpha = a[..., 3] > 128
    top = alpha[: int(a.shape[0] * 0.4)]
    xs = np.nonzero(alpha.any(0))[0]
    cx = (xs[0] + xs[-1]) / 2
    orange = (a[..., 0] > 200) & (a[..., 1] > 90) & (a[..., 1] < 180) & (a[..., 2] < 90) & alpha
    orange[int(a.shape[0] * 0.4):] = False
    if orange.sum() < 15 or not top.any():
        return 0
    return np.nonzero(orange)[1].mean() - cx


def main(cfg_path, out_dir):
    cfg = json.loads(Path(cfg_path).read_text(encoding="utf-8"))
    base = Path(cfg_path).parent
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    sheets = {}
    for name, path in cfg["sheets"].items():
        rgba = key_green(np.array(Image.open(base / path).convert("RGB")))
        sheets[name] = (rgba, find_frames(rgba))
        print(f"{name}: " + ", ".join(f"{len(r)}칸" for r in sheets[name][1]))

    # 1차: 잘라내기 + 조개 위치 맞춤
    raw = {}
    for anim in cfg["animations"]:
        frames = []
        for sheet, row, col in anim["frames"]:
            rgba, rows = sheets[sheet]
            img = cut(rgba, rows[row][col])
            side = anim.get("pin")          # +1 화면 오른쪽, -1 화면 왼쪽
            if side:
                off = pin_offset(img)
                if off and np.sign(off) != side:
                    img = img.transpose(Image.FLIP_LEFT_RIGHT)
            frames.append(img)
        raw[anim["name"]] = frames

    # 2차: 머리 폭 기준으로 크기 통일
    ref_anim = cfg["reference"]["animation"]
    ref_stature = np.median([stature(f) for f in raw[ref_anim]])
    ref_scale = cfg["reference"]["height"] / np.median([f.height for f in raw[ref_anim]])
    factor = {}
    for anim in cfg["animations"]:
        if anim.get("normalize", True):
            factor[anim["name"]] = ref_stature / np.median([stature(f) for f in raw[anim["name"]]])
    scaled = {}
    for anim in cfg["animations"]:
        fr = raw[anim["name"]]
        # 앉은 동작처럼 키로 맞출 수 없는 동작은 같은 시트의 다른 동작 배율을 빌려 씀
        k = ref_scale * factor.get(anim["name"], factor.get(anim.get("scale_like"), 1.0))
        scaled[anim["name"]] = [hq_resize(f, k) for f in fr]

    # 3차: 같은 칸, 발바닥 정렬, 좌우 반전 동작 생성
    every = [f for fr in scaled.values() for f in fr]
    cell_w = max(f.width for f in every) + 8
    cell_h = max(f.height for f in every) + 4
    cell_w += cell_w % 2
    meta = {"cell": [cell_w, cell_h], "animations": {}}

    def write(name, frames, anim):
        sheet = Image.new("RGBA", (cell_w * len(frames), cell_h), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            a = np.array(f)[..., 3] > 128
            lower = a[int(a.shape[0] * 0.75):]
            cx = np.nonzero(lower)[1].mean() if lower.any() else f.width / 2
            x = min(max(int(round(cell_w / 2 - cx)), 0), cell_w - f.width)
            y = cell_h - f.height - 2
            sheet.alpha_composite(f, (i * cell_w + x, y))
        sheet.save(out / f"{name}.png")
        meta["animations"][name] = {"frames": len(frames), "cell": [cell_w, cell_h],
                                    "fps": anim.get("fps", 6), "loop": anim.get("loop", True)}

    for anim in cfg["animations"]:
        fr = scaled[anim["name"]]
        write(anim["name"], fr, anim)
        if anim.get("mirror_as"):
            write(anim["mirror_as"], [f.transpose(Image.FLIP_LEFT_RIGHT) for f in fr], anim)
    (out / "frames.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"칸 크기 {cell_w}x{cell_h}, 동작 {len(meta['animations'])}개")


if __name__ == "__main__":
    main(*sys.argv[1:3])
