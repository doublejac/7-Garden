"""게임 폰트(본명조 = Noto Serif CJK KR)를 필요한 글자만 남겨 줄임.

사용: python3 tools/fonts/build_fonts.py
  원본: 시스템의 NotoSerifCJK-{Regular,SemiBold}.ttc 안의 KR 글꼴 (OFL)
  남기는 글자: 한글 전체, 영문·숫자, 문장부호·괄호(「」 『』 … · — 등), 화살표·도형·원문자,
               그리고 대사·데이터 파일에 실제로 쓰인 한자 등 나머지 글자 전부
  출력: assets/fonts/NotoSerifKR-{Regular,SemiBold}.otf
"""
import glob
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTCollection

ROOT = Path(__file__).resolve().parents[2]
RANGES = [(0x20, 0x7E), (0xA0, 0xFF), (0x2000, 0x206F), (0x2190, 0x21FF), (0x2200, 0x22FF),
          (0x2460, 0x24FF), (0x2500, 0x257F), (0x25A0, 0x25FF), (0x2600, 0x26FF),
          (0x3000, 0x303F), (0x3131, 0x318E), (0xAC00, 0xD7A3), (0xFF00, 0xFFEF)]


def used_chars() -> set[int]:
    s = set()
    for pat in ("data/**/*.csv", "data/**/*.json", "scripts/**/*.gd", "scenes/**/*.gd"):
        for p in glob.glob(str(ROOT / pat), recursive=True):
            s |= {ord(c) for c in Path(p).read_text(encoding="utf-8") if ord(c) >= 0x20}
    return s


def main() -> None:
    codes = used_chars()
    for a, b in RANGES:
        codes |= set(range(a, b + 1))
    for weight in ("Regular", "SemiBold"):
        col = TTCollection(f"/usr/share/fonts/opentype/noto/NotoSerifCJK-{weight}.ttc")
        font = col.fonts[1]                       # 1 = KR
        opts = subset.Options()
        opts.layout_features = ["*"]
        opts.name_IDs = ["*"]
        opts.notdef_outline = True
        sub = subset.Subsetter(opts)
        sub.populate(unicodes=sorted(codes))
        sub.subset(font)
        out = ROOT / f"assets/fonts/NotoSerifKR-{weight}.otf"
        font.save(out)
        print(out.name, out.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
