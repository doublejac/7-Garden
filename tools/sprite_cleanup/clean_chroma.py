"""단색 초록(#00FF00) 배경 스프라이트 시트 정리 도구.

1) 초록 배경 제거 (가장자리 반투명 처리 + 초록 번짐 제거)
2) 격자 순서대로 프레임 자동 인식 (줄 → 칸)
3) 서 있는 동작은 '머리 꼭대기~발바닥' 높이로 캐릭터 크기 통일 (정면 앉은 동작은 normalize: "head"로 머리 폭, 그 밖은 scale_like로 다른 동작 배율을 빌림)
4) 조개 핀이 반대쪽에 그려진 프레임, 옆모습에서 반대 방향을 보는 프레임 좌우 반전
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
    if n > 1:   # 캐릭터 본체와 떨어진 얼룩·잔상 제거 (본체의 15% 미만 덩어리)
        sizes = ndi.sum(np.ones(lab.shape), lab, range(1, n + 1))
        big = max(sizes)
        keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= max(300, big * 0.15)])
        crop[~keep] = 0
    img = Image.fromarray(crop, "RGBA")
    return img.crop(img.getbbox())


def hq_resize(img, scale):
    return hq_resize_xy(img, max(1, round(img.width * scale)), max(1, round(img.height * scale)))


def chin_rows(img):
    """(머리 꼭대기, 턱, 발바닥) 행 번호. 턱 = 위쪽 60% 안에서 얼굴 피부가 보이는 마지막 줄."""
    a = np.array(img).astype(int)
    al = a[..., 3] > 128
    ys = np.nonzero(al.any(1))[0]
    top, bot = ys[0], ys[-1]
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    skin = al & (r > 200) & (g > 150) & (b > 130) & (r - b > 25)
    rows = np.nonzero(skin.sum(1) >= 3)[0]
    rows = rows[rows < top + 0.6 * (bot - top)]
    return top, (rows[-1] + 1 if rows.size else top + (bot - top) // 2), bot


def hq_resize_xy(img, w, h):
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


def hair_height(img):
    """머리카락 맨 위부터 맨 아래까지의 높이. 옆모습끼리 크기를 비교할 때 쓴다 (폭은 그림마다 들쭉날쭉)."""
    a = np.array(img).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    spread = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
    lum = (r + g + b) / 3
    hair = (al > 128) & (spread < 28) & (lum > 90) & (lum < 228)   # 흰 원피스(거의 흰색)는 제외
    hair[int(a.shape[0] * 0.6):] = False
    rows = np.nonzero(hair.sum(1) >= 4)[0]
    return (rows[-1] - rows[0]) if rows.size else img.height


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


def face_side(img):
    """얼굴(피부색)이 머리 가운데보다 어느 쪽에 있는지. +면 오른쪽을 봄."""
    a = np.array(img).astype(int)
    al = a[..., 3] > 128
    ys = np.nonzero(al.any(1))[0]
    top, h = ys[0], ys[-1] - ys[0]
    head = a[top: top + int(h * 0.42)]
    hal = al[top: top + int(h * 0.42)]
    r, g, b = head[..., 0], head[..., 1], head[..., 2]
    skin = hal & (r > 200) & (g > 150) & (b > 130) & (r - b > 25)
    xs = np.nonzero(hal.any(0))[0]
    sx = np.nonzero(skin)[1]
    if xs.size == 0 or sx.size < 20:
        return 0
    return sx.mean() - (xs[0] + xs[-1]) / 2


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
        for x0, y0, x1, y1 in cfg.get("erase", {}).get(name, []):   # 잔상·얼룩 지우기 (원본 좌표)
            rgba[y0:y1, x0:x1, 3] = 0
        sheets[name] = (rgba, find_frames(rgba))
        print(f"{name}: " + ", ".join(f"{len(r)}칸" for r in sheets[name][1]))

    # 1차: 잘라내기 + 조개 위치 맞춤
    raw = {}
    for anim in cfg["animations"]:
        frames = []
        for sheet, row, col in anim["frames"]:
            rgba, rows = sheets[sheet]
            img = cut(rgba, rows[row][col])
            face = anim.get("face")         # 옆모습: +1 오른쪽을 봄, -1 왼쪽을 봄
            if face:
                f = face_side(img)
                if f and np.sign(f) != face:
                    img = img.transpose(Image.FLIP_LEFT_RIGHT)
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
    ref_head = np.median([head_width(f) for f in raw[ref_anim]])
    ref_scale = cfg["reference"]["height"] / np.median([f.height for f in raw[ref_anim]])
    factor = {}
    pending = []
    for anim in cfg["animations"]:
        how = anim.get("normalize", True)
        fr = raw[anim["name"]]
        if how == "head":
            ref = anim.get("head_ref")
            if ref:                  # 옆모습끼리 머리 높이로 비교
                pending.append(anim)
                continue
            factor[anim["name"]] = ref_head / np.median([head_width(f) for f in fr])
        elif how:
            factor[anim["name"]] = ref_stature / np.median([stature(f) for f in fr])
    for anim in pending:
        ref = anim["head_ref"]
        ref_h = np.median([hair_height(f) for f in raw[ref]])
        k_h = ref_h / np.median([hair_height(f) for f in raw[anim["name"]]])
        if anim.get("head_metric") == "both":   # 머리 높이와 폭 비율의 평균 (걷기처럼 같은 방향끼리 비교할 때)
            ref_w = np.median([head_width(f) for f in raw[ref]])
            k_w = ref_w / np.median([head_width(f) for f in raw[anim["name"]]])
            k_h = float(np.sqrt(k_h * k_w))
        elif anim.get("head_metric") == "stature":   # 같은 방향 정지 동작과 키(머리 꼭대기~발)를 맞춤
            k_h = np.median([stature(f) for f in raw[ref]]) / np.median([stature(f) for f in raw[anim["name"]]])
        factor[anim["name"]] = factor.get(ref, 1.0) * k_h
    scaled = {}
    for anim in cfg["animations"]:
        fr = raw[anim["name"]]
        # 앉은 동작처럼 키로 맞출 수 없는 동작은 같은 시트의 다른 동작 배율을 빌려 씀
        k = ref_scale * factor.get(anim["name"], factor.get(anim.get("scale_like"), 1.0))
        scaled[anim["name"]] = [hq_resize(f, k) for f in fr]

    # 2.5차: 비율 맞춤 – 그림마다 머리·몸 비율이 다르게 그려진 동작을 기준 동작의 비율로 고친다
    # (머리끝~턱, 턱~발바닥을 따로 늘이거나 줄이고, 폭은 머리 폭 비율로 맞춤)
    for anim in cfg["animations"]:
        ref = anim.get("match_proportions")
        if not ref:
            continue
        def parts(fs):
            up, low = [], []
            for f in fs:
                top, chin, bot = chin_rows(f)
                up.append(chin - top); low.append(bot - chin)
            return np.median(up), np.median(low)
        ru, rl = parts(scaled[ref])
        mu, ml = parts(scaled[anim["name"]])
        kx = np.median([head_width(f) for f in scaled[ref]]) / np.median([head_width(f) for f in scaled[anim["name"]]])
        ku, kl = ru / mu, rl / ml
        new = []
        for f in scaled[anim["name"]]:
            top, chin, bot = chin_rows(f)
            w = max(1, round(f.width * kx))
            a = hq_resize_xy(f.crop((0, 0, f.width, chin)), w, max(1, round(chin * ku)))
            b = hq_resize_xy(f.crop((0, chin, f.width, f.height)), w, max(1, round((f.height - chin) * kl)))
            g = Image.new("RGBA", (w, a.height + b.height), (0, 0, 0, 0))
            g.alpha_composite(a, (0, 0)); g.alpha_composite(b, (0, a.height))
            new.append(g.crop(g.getbbox()))
        scaled[anim["name"]] = new
        print(f"  {anim['name']}: 비율 맞춤 (폭 x{kx:.3f}, 머리 x{ku:.3f}, 몸 x{kl:.3f})")

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
        if anim.get("steady_head"):
            for nm in (anim["name"], anim.get("mirror_as")):
                if nm:
                    steady_head(out / f"{nm}.png", len(fr), cell_w, cell_h, anim["steady_head"])
    (out / "frames.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"칸 크기 {cell_w}x{cell_h}, 동작 {len(meta['animations'])}개")


def steady_head(path, n, cw, ch, opt):
    """걷기처럼 머리를 매 칸 새로 그린 동작은 머리카락이 칸마다 달라 부르르 떨어 보인다.
    첫 칸의 머리(턱 아래 몇 줄까지)를 모든 칸에 똑같이 붙이고, 위아래로만 bob(px)만큼 움직인다.
    opt = {"bob": [..칸마다 px..], "back": 뒷모습이면 true (턱 대신 머리카락 높이로 자름)}"""
    sheet = Image.open(path).convert("RGBA")
    fs = [sheet.crop((i * cw, 0, i * cw + cw, ch)) for i in range(n)]

    def chin(f):
        a = np.array(f)
        top = np.nonzero((a[..., 3] > 128).any(1))[0][0]
        return top + hair_height(f) if opt.get("back") else chin_rows(f)[1]

    if opt.get("alt_legs"):
        # 정면·뒷모습: Gemini가 한 발만 드는 그림을 그려서 한 발로만 걷는 것처럼 보임.
        # 뒤쪽 반 주기는 앞쪽 반 주기의 다리(치마 밑단 아래)를 좌우 반전해 써서 왼발·오른발이 번갈아 나가게 함
        half = n // 2
        for i in range(half, n):
            a = np.array(fs[i - half]).copy()
            al = a[..., 3] > 128
            r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
            white = al & (r > 215) & (g > 215) & (b > 215)
            hem = np.nonzero(white.sum(1) >= 6)[0].max() - 1          # 원피스 밑단 조금 위부터 (원피스는 좌우 대칭이라 같이 뒤집어도 됨)
            legs = a[hem:].copy()
            xs = np.nonzero((legs[..., 3] > 128).any(0))[0]
            x0, x1 = xs[0], xs[-1] + 1
            a[hem:, x0:x1] = legs[:, x0:x1][:, ::-1]
            fs[i] = Image.fromarray(a, "RGBA")

    if opt.get("head") is False:     # 머리는 그림 그대로 두고 다리 교대만
        out = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
        for i, f in enumerate(fs):
            out.alpha_composite(f, (i * cw, 0))
        out.save(path)
        return
    chins = [chin(f) for f in fs]
    head = fs[0].crop((0, 0, cw, max(chins) + 5))
    bob = opt.get("bob", [0] * n)
    out = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    for i, f in enumerate(fs):
        a = np.array(f)
        a[:chins[i] - 3] = 0              # 이 칸의 머리를 지우고 (몸은 그대로)
        g = Image.fromarray(a, "RGBA")
        g.alpha_composite(head, (0, bob[i % len(bob)]))
        out.alpha_composite(g, (i * cw, 0))
    out.save(path)


if __name__ == "__main__":
    main(*sys.argv[1:3])
