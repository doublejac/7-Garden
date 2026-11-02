"""도윤 스프라이트 시트 만들기 — Google Flow 걷기 영상 3개에서.

    python3 tools/sprite_cleanup/doyun_build.py

src/doyun/walk_right.mp4 / walk_down.mp4 / walk_up.mp4 → assets/art/characters/doyun/
(그다음 Godot로 build_spriteframes.gd -- doyun 실행)

- 크기: 갈색 머리카락 폭을 서하 머리 폭(72px)에 맞춤. 옆모습은 머리가 더 넓게 그려져서 비율만큼 보정.
- 키: 머리(76px)는 그대로, 턱 아래를 줄여 전체 178px (서하 148px의 1.2배).
- 걷기: 프레임마다 가장 낮은 발이 바닥선에 닿게 (걸을 때의 출렁임은 그대로).
- 정지: 영상 첫 장면(정지 그림 그대로) + 숨쉬기 + 깜빡임.
  옆모습 깜빡임은 영상 속 실제로 눈 감은 장면의 눈 부분, 정면은 영상에 깜빡임이 없어 눈을 피부색으로 덮고 선을 그림.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from clean_chroma import hq_resize_xy, key_green  # noqa: E402

ROOT = HERE.parent.parent
SRC = HERE / "src" / "doyun"
OUT = ROOT / "assets" / "art" / "characters" / "doyun"
CW, CH = 124, 192          # 칸 크기 (발바닥이 아래에서 2px 위)
HEAD_W = 72                # 서하 머리 폭
HEAD_H = 76                # 머리 꼭대기~턱 (그대로 둠)
TOTAL = 178                # 정지 키

# 걷기 재생 속도. 맵 이동 속도(150px/s)에 비해 발이 바닥을 미는 속도가 서하와 비슷하게:
# 옆 보폭 약 53px·한 바퀴 두 걸음 → 8fps면 1.5초에 두 걸음. 정면·뒤는 서하와 같은 2초에 두 걸음

# 이름, 영상, 시작, 주기(프레임), 칸 수, 머리 폭 보정, 좌우반전 이름, 정지 이름, 반전 정지, 깜빡임("frame:N" / "draw" / None)
# 걷기는 "작은 보폭" 영상(*_small.mp4, 서하처럼 1초에 두 걸음쯤), 정지는 처음 영상의 첫 장면(눈 뜬 정지 그림)과 깜빡임.
# 두 영상 모두 같은 정지 그림에서 시작해서 축척·위치가 그대로 맞음. 재생 속도는 영상 속 걸음 빠르기 그대로
CLIPS = [
    ("walk_right", "walk_right_small.mp4", 43, 26, 10, 762 / 717, "walk_left", "idle_right", "idle_left", "frame:12", "walk_right.mp4"),
    ("walk_down", "walk_down_small.mp4", 36, 32, 10, 1.0, None, "idle", None, "draw", "walk_down.mp4"),
    ("walk_up", "walk_up_small.mp4", 116, 24, 8, 722 / 717, None, "idle_up", None, None, "walk_up.mp4"),
]


def read_video(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, 1280, 720, 3)


def keyed(F, i):
    a = F[i].copy()
    cols = np.nonzero((a.max(2) > 45).mean(0) > 0.5)[0][3:-3]   # 좌우 검은 띠(경계 포함) 제거
    return Image.fromarray(key_green(a[:, cols[0]:cols[-1] + 1]), "RGBA")


def hair_width(im):
    a = np.array(im).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    m = (al > 128) & (r > 40) & (r < 150) & (r > b + 15) & (g < r) & (r - g < 60)
    m[int(a.shape[0] * 0.3):] = False
    cols = np.nonzero(m.sum(0) >= 3)[0]
    return np.percentile(cols, 99) - np.percentile(cols, 1)


def clean(o):
    a = np.array(o)
    a[a[..., 3] < 60] = 0                       # 영상 압축으로 생긴 희미한 테두리
    lab, n = ndi.label(a[..., 3] > 0)           # 몸에서 떨어진 작은 점·줄
    if n > 1:
        sz = ndi.sum(np.ones(lab.shape), lab, range(1, n + 1))
        a[np.isin(lab, [i + 1 for i, v in enumerate(sz) if v < 40])] = 0
    return Image.fromarray(a, "RGBA")


def maker(F, start, head_fix):
    """첫 장면(정지 그림)으로 축척·턱 위치·몸 중심을 정하고, 모든 프레임에 똑같이 적용하는 함수를 돌려줌."""
    f0 = keyed(F, 0)
    x0, y0, x1, y1 = f0.getbbox()
    s = HEAD_W * head_fix / hair_width(f0)
    chin = round(y0 + HEAD_H / s)
    lo_k = (TOTAL - HEAD_H) / ((y1 - chin) * s)
    cx = round((x0 + x1) / 2 * s)

    def make(i):
        c = keyed(F, i)
        bot = c.getbbox()[3]
        W = round(c.width * s)
        up = hq_resize_xy(c.crop((0, 0, c.width, chin)), W, round(chin * s))
        lo = hq_resize_xy(c.crop((0, chin, c.width, bot)), W, round((bot - chin) * s * lo_k))
        o = Image.new("RGBA", (W, up.height + lo.height))
        o.alpha_composite(up)
        o.alpha_composite(lo, (0, up.height))
        cell = Image.new("RGBA", (CW, CH))
        cell.alpha_composite(clean(o), (CW // 2 - cx, CH - 2 - o.height))
        return cell
    return make


def breath(cell):
    a = np.array(cell)
    ys = np.nonzero(a[..., 3].any(1))[0]
    cut = ys[0] + int((ys[-1] - ys[0]) * 0.55)   # 셔츠 밑단 위(상체)만 1px 내려감
    b = a.copy()
    b[1:cut + 1] = a[0:cut]
    b[0] = 0
    return Image.fromarray(b, "RGBA")


def eye_boxes(cell):
    """정면 눈 두 개의 상자: 얼굴 피부 사이(같은 세로줄 위·아래에 피부가 있음)에 낀 피부 아닌 덩어리 중 큰 두 개."""
    a = np.array(cell).astype(int)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    top = np.nonzero((al > 128).any(1))[0][0]
    skin = (al > 128) & (r > 190) & (g > 140) & (r - b > 20)
    cand = np.zeros_like(skin)
    for y in range(top + 40, top + 66):
        above = skin[y - 9:y].any(0)
        below = skin[y + 1:y + 10].any(0)
        cand[y] = (al[y] > 128) & ~skin[y] & above & below
    lab, n = ndi.label(cand)
    if n == 0:
        return [], top
    sz = ndi.sum(np.ones(lab.shape), lab, range(1, n + 1))
    boxes = []
    for i in np.argsort(sz)[::-1][:2]:
        yy, xx = np.nonzero(lab == i + 1)
        boxes.append((yy.min(), yy.max(), xx.min(), xx.max()))
    return boxes, top


def draw_blink(cell):
    a = np.array(cell).copy()
    boxes, top = eye_boxes(cell)
    if not boxes:
        return cell
    ai = a.astype(int)
    skin = (ai[..., 3] > 128) & (ai[..., 0] > 190) & (ai[..., 1] > 140) & (ai[..., 0] - ai[..., 2] > 20)
    band = skin.copy()
    band[:top + 30] = False
    band[top + HEAD_H:] = False
    cols = [tuple(c) for c in a[band][:, :3]]
    base = max(set(cols), key=cols.count)
    lash = np.array([60, 40, 35, 255], np.uint8)
    for y0, y1, x0, x1 in boxes:
        a[y0:y1 + 1, x0:x1 + 1, :3] = base
        a[y0:y1 + 1, x0:x1 + 1, 3] = 255
        ly = y0 + (y1 - y0) * 2 // 3
        a[ly:ly + 2, x0 + 2:x1 - 1] = lash
        a[ly - 1:ly + 1, x0 + 1] = lash
        a[ly - 1:ly + 1, x1 - 1] = lash
    return Image.fromarray(a, "RGBA")


def paste_eyes(base, shut):
    a = np.array(base).astype(int)
    al = a[..., 3] > 128
    ys = np.nonzero(al.any(1))[0]
    top = ys[0]
    xs = np.nonzero(al[top + 30:top + HEAD_H].any(0))[0]
    # 옆모습: 얼굴 앞쪽(오른쪽) 절반, 눈 높이 띠
    box = (int(xs.mean()), top + 34, int(xs.max()) - 2, top + 58)
    out = base.copy()
    out.paste(shut.crop(box), box[:2])
    return out


def sheet(cells, name, meta, fps, flip=False):
    sh = Image.new("RGBA", (CW * len(cells), CH))
    for i, c in enumerate(cells):
        sh.alpha_composite(c.transpose(Image.FLIP_LEFT_RIGHT) if flip else c, (i * CW, 0))
    sh.save(OUT / f"{name}.png")
    meta["animations"][name] = {"frames": len(cells), "cell": [CW, CH], "fps": fps, "loop": True}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    meta = {"cell": [CW, CH], "animations": {}}
    for name, video, start, period, count, head_fix, mirror, idle, idle_mirror, bl, idle_video in CLIPS:
        F = read_video(SRC / video)
        make = maker(F, start, head_fix)
        cells = [make(start + round(j * period / count)) for j in range(count)]
        fps = round(count / (period / 24))
        del F
        F = read_video(SRC / idle_video)
        make = maker(F, 0, head_fix)
        sheet(cells, name, meta, fps)
        if mirror:
            sheet(cells, mirror, meta, fps, flip=True)
        base = make(0)
        if bl == "draw":
            shut = draw_blink(base)
        elif bl:
            shut = paste_eyes(base, make(int(bl.split(":")[1])))
        else:
            shut = base
        br = breath(base)
        sheet([base, br, base, br, base, br, base, shut], idle, meta, 3)
        if idle_mirror:
            sheet([base, br, base, br, base, br, base, shut], idle_mirror, meta, 3, flip=True)
        print(name, "→", count, "칸", fps, "fps /", idle)
        del F
    (OUT / "frames.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
