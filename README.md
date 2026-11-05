# 해무장 (Godot 4.7 프로젝트)

> 시스템 설계서 (최종본, 앞으로 바뀌는 설정은 여기에 반영): [구글 문서 「완전한 작별을 위한 정원 — 시스템 설계서 최종본」](https://docs.google.com/document/d/1JD9Y2g0wYH64W0j8GlLbQTZPz5DDTDum7eI_Ed6r3Qw/edit)

## 여는 법
1. Godot **4.7.2 Standard** 버전을 설치합니다. (.NET 버전 아님)
2. Godot 프로젝트 관리자에서 **가져오기**를 누르고 이 폴더의 `project.godot`을 선택합니다.
3. 에디터 오른쪽 위 **▶ (F5)** 를 누르면 개발용 대사 재생기가 실행됩니다.
   - 클릭 / 스페이스 / 엔터: 다음 줄
   - F1: 화면 위 수치 표시 켜기/끄기
   - "2회차로 시작"은 개발용 버튼입니다.

## 폴더 구조
```
assets/        그림, 소리, 폰트 (아직 비어 있음)
data/dialogue/ day1~4.csv  대사 (엑셀 양식에서 내보낸 파일)
scenes/main/   main.tscn   개발용 대사 재생기
scripts/autoload/  GameState.gd, SaveManager.gd  (Autoload로 등록됨)
scripts/dialogue/  DialogueRunner.gd  대사 CSV를 읽고 분기·수치·플래그를 처리
shaders/       screen_fx.gdshader  채도(색채 상실)와 비네트(시야 상실)
tests/         test_runner.tscn  자동 점검
```

## 대사 고치는 법
1. 엑셀 양식(`haemujang_dialogue_dayN.xlsx`)의 '대사' 시트를 고칩니다.
2. '대사' 시트만 **CSV UTF-8**로 저장하고, 1행(한글 제목)을 지워 2행(영문 키)이 첫 줄이 되게 합니다.
3. `data/dialogue/dayN.csv`에 덮어씁니다.
   - 같은 폴더의 `dayN.csv.import`는 지우지 마세요. Godot이 CSV를 번역 파일로 바꾸지 않게 막아줍니다.
   - 새 일차 파일을 추가할 때는 `day1.csv.import`를 복사해 이름만 바꾸면 됩니다.

## 자동 점검
에디터에서 `tests/test_runner.tscn`을 열고 **현재 씬 실행 (F6)** 을 누르면 결과 창이 뜹니다. 확인한 뒤 창을 닫으면 됩니다.
- 1회차를 첫 선택지 / 마지막 선택지로 각각 끝까지 돌려, 일차별 평온도가 49 → 58 → 67 → 76인지 확인
- 2회차를 붉은 선택지 위주로 끝까지 돌려 오류가 없는지 확인
- 저장 → 불러오기 확인

대사나 수치를 고친 뒤에는 이 점검을 한 번 돌려보세요.

## 캐릭터 스프라이트
- `scenes/characters/seoha.tscn`: 서하 (AnimatedSprite2D). 발바닥이 노드 위치에 오도록 맞춰져 있습니다.
- `scenes/dev/sprite_viewer.tscn`: 확인용 씬. F6으로 실행 후 방향키로 걷기, 숫자키로 특수 동작.
- **v3 (다시 만드는 중)**: 기준 그림 `tools/sprite_cleanup/src/v3/seoha_reference.jpg`, 기본 이동 시트 `seoha_base.jpg`
  - 지금 들어 있는 동작: walk_down / walk_up / walk_left / walk_right, idle / idle_up / idle_left / idle_right,
    take_pill, hide_pill, startle, cry, cry_left / cry_right (`seoha_story1.jpg`)
  - 기본 이동 시트가 그림체·비율의 기준. 추가 동작 시트는 이 시트를 첨부해서 같은 머리 크기로 받는다.
- 정리: `python3 tools/sprite_cleanup/clean_chroma.py tools/sprite_cleanup/seoha_v3.json assets/art/characters/seoha`
  → 초록 배경 제거, 조개 핀 위치·옆모습 방향 맞춤, 크기 통일, 발바닥 정렬. 프레임 위치는 json에 (시트, 줄, 칸)으로 적습니다.
  같은 프레임 번호를 여러 번 적어 재생 순서를 만들 수 있습니다 (대기의 눈 깜빡임을 8프레임 중 한 번만).
- 애니메이션 리소스 만들기: `godot --headless --path . -s res://tools/build_spriteframes.gd -- seoha`
- 서하 노드는 텍스처 필터가 Linear입니다. 1배 크기로 쓰는 것을 기준으로 합니다.

### 서하 걷기·정지 (Google Flow 영상)
- 네 방향 걷기와 정지는 Google Flow로 만든 제자리걷기 영상에서 뽑음: `tools/sprite_cleanup/src/v3/flow/walk_*.mp4`
- `seoha_v3.json`의 `video_walks` 항목으로 정리 도구가 자동 처리 (`tools/sprite_cleanup/video_walk.py`)
  - 한 걸음 주기(start, period)에서 count칸을 고르게 뽑음 → 초록 배경 제거 → 키·머리 폭을 맞춤
  - Flow가 9:16 세로 화면에 맞추며 가로로 눌러 놓은 것을 되돌림, 머리·몸 비율은 턱에서 나눠 맞춤
  - 정지(`idle_as`)는 영상 첫 장면 + 숨쉬기 + 눈 깜빡임(합성)이라 걷다 멈춰도 그림이 안 바뀜
  - 뒷모습은 `proportion: false`(턱이 안 보임), `width_like: idle`(폭을 정면에 맞춤)
- 새 영상 만들 때: Flow의 Frames 방식에 정지 그림(초록 배경)을 첫 프레임으로, "walk in place, camera fixed, demure tiny steps, arms close to body" 조건

### 채린 휠체어 이동·정지 (Google Flow 영상)
- 원본: `tools/sprite_cleanup/src/chaerin/` — 서하 정지 그림을 Gemini로 채린(휠체어)으로 바꾼 3방향 그림 + Flow 휠체어 밀기 영상 `push_right/down/up.mp4`
- `python3 tools/sprite_cleanup/chaerin_build.py` → `assets/art/characters/chaerin/` 시트, 그다음 `build_spriteframes.gd -- chaerin`
  - 머리(금발) 폭을 서하 머리 크기에 맞추고, 턱 아래(몸+휠체어)는 세로 76.5%로 줄임
  - 정면 영상은 Flow가 같은 프레임을 반복해 멈춘 구간이 있어 실제로 움직이는 구간만 씀. 깜빡임 없는 구간을 루프로
  - 정지 = 루프 첫 장면 + 숨쉬기 + 영상 속 실제 눈 감은 장면의 눈 부분
- 옆모습 바퀴엔 바큇살이 있어야 굴러가는 게 보임 (`chaerin_side_spokes.jpg`). Flow 문장엔 "바퀴 위쪽을 잡고 민다, 링을 들지 않는다, 축 둘레를 돌리지 않는다"를 넣을 것
- 맵 단독 실행 중 **C 키**로 서하 → 채린 → 도윤 전환

### 도윤 걷기·정지 (Google Flow 영상)
- 원본: `tools/sprite_cleanup/src/doyun/` — 일러스트, 서하 정지 그림을 Gemini로 바꾼 3방향 그림, Flow 걷기 영상 `walk_right/down/up.mp4`
- `python3 tools/sprite_cleanup/doyun_build.py` → `assets/art/characters/doyun/`, 그다음 `build_spriteframes.gd -- doyun`
  - 머리 폭은 서하와 같게, 키는 서하의 1.2배(178px): 머리는 그대로 두고 턱 아래만 줄임
  - 정지 = 영상 첫 장면(정지 그림) + 숨쉬기 + 깜빡임. 옆은 영상 속 눈 감은 장면, 정면은 영상에 깜빡임이 없어 그려 넣음

## 일러스트 (CG)
- 그림: `assets/art/cg/<이름>.jpg` (지금은 임시본. 4K판은 같은 이름으로 덮어씀)
- 대사 CSV의 `fx`에 `cg:<이름>`을 넣으면 그 줄에서 일러스트가 서서히 나타나고, `cg_off`면 사라짐 (일차가 바뀌면 자동으로 내림)
- 1일 차: `L1_D1_S05_005`(온실 별 보기)에서 켜고 `L1_D1_S06_001`(새벽)에서 끔
- 타이틀의 **일러스트 보기 (개발용)**: 폴더의 일러스트를 하나씩 넘겨 봄 (클릭 다음, Esc 타이틀)

## 그림책 「누비각시와 아홉 개의 껍데기」
- 채린이 아끼는 그림동화. 설정·본문: Claude 문서와 구글 문서 「누비각시와 아홉 개의 껍데기」
- 글 `data/storybook/nubi.json`, 그림 `assets/art/storybook/` (원본 2000px는 `tools/sprite_cleanup/src/storybook/`, 게임용은 1400px)
- `scripts/ui/storybook.gd` (Storybook): 닫힌 천 표지 → 표지가 넘어가며 펼쳐짐 → 왼쪽 그림·오른쪽 글. 종이 결·제본선 그늘·책 옆면 종이 겹, 쪽 넘김 애니메이션, 앞뒤 면지
  - `found_torn = false`(1회차): 14쪽 뒤 찢긴 밑동만 남은 쪽 + 뒤표지 안쪽 글 한 줄
  - `found_torn = true`(찢긴 장을 찾은 뒤): 15·16쪽이 누렇게 바랜 종이, 접힌 자국, 찢긴 가장자리로 붙음
  - 글자는 띄어쓰기에서만 줄이 바뀜 (낱말 중간에서 안 끊김). 글꼴 `assets/fonts/NotoSerifKR-*.otf` (OFL)
- 타이틀 개발용: **그림책 보기** / **그림책 · 찢긴 장 찾음** / **읽어 주기 · 첫날 밤 (2~7페이지)** / **읽어 주기 · 2회차 (10~13페이지)**

### 밤마다 채린에게 읽어 주기
- **단위**: 화면에 보이는 건 책에 찍힌 **페이지** 번호. 데이터·fx는 이야기 **장면** 번호(그림+글 한 펼침면 = 장면 1개, 장면 k = 2k·2k+1페이지)
- 1~6일 차 밤마다 장면 2~3개 = 4~6페이지 (1일 2~7p · 2일 8~11p · 3일 12~15p · 4일 16~19p · 5일 20~23p · 6일 24~29p). 7일 차 밤은 수술이라 읽지 않음. 계획은 `nubi.json`의 `nights`(장면 번호)
- **서하 방 협탁 서랍**: 맵에서 가까이 가면 "E 협탁 서랍". 지금까지 읽어 준 데까지(`GameState.book_read`) 한꺼번에 다시 보기 (반응 대사 없음, 마지막 쪽에서 덮기). 아직 안 읽었으면 "서랍 안은 비어 있다." 맵 단독 실행 중 **B 키**(개발용)로 읽은 페이지 바꾸기
- 살펴볼 곳은 맵 JSON의 `interact` 배열 (`id`, `name`, `x`, `y`, `range`)
- 대사 CSV의 fx 열에 `book:3-4` → 그 줄을 보여 준 뒤 다음 클릭에 책이 펼쳐짐. 덮으면 다음 대사로 이어짐
- 그날 읽을 쪽만 넘길 수 있음. 앞쪽부터 이어 읽으면 덮인 책 아래로 가름끈이 나와 있고, 펼치면 가름끈 꽂힌 쪽부터 시작
- 처음 읽는 쪽은 글이 천천히 나타남 (클릭하면 바로 다 보임). 읽은 쪽은 `SaveManager.meta.book_seen`에 남아 다음부터 바로 보임
- 쪽 글을 다 보면 책 아래에 채린의 반응 한마디 (`react`), 붉은 속마음이 해금됐으면 `react_inner`도
- 읽은 마지막 쪽은 `GameState.book_read`에 저장 (서재에서 다시 볼 때 `page_to = book_read`로 열면 됨). 찢긴 장 플래그는 `found_torn`

## 캡슐 숨기기 (2회차 투약 미니게임)
- `scripts/minigames/capsule.gd` (CapsuleTrick): 원장의 큰 눈이 화면 위에서 서하를 지켜봄
  1. 캡슐 클릭 → 입에 넣는 척 (혀 밑)
  2. 물컵을 1.2초 꾹 누르기 → 원장 앞에서 삼킨 척
  3. 원장이 차트를 적느라 눈을 돌린 사이, 입의 캡슐을 끌어 소매에 넣기. 돌아보기 직전 눈동자가 움찔하고 눈썹이 올라감(…?). 원장이 보고 있을 때 손이 움직이면 들킴
  4. 눈을 돌리는 틈을 3번 놓치면 "입 한번 벌려 볼까요?" → 결국 삼킴
- 결과 `hidden` / `caught` / `swallowed`, 수치는 `CapsuleTrick.RESULT_STATS` (설계서 행동별 수치와 같음)
- 대사 CSV fx에 `capsule` → 그 줄 다음 클릭에 미니게임, 끝나면 수치 적용 후 다음 대사. 의심도가 높을수록 원장이 눈을 짧게 돌림
- 타이틀 개발용 **캡슐 숨기기 (2회차 투약)**

## 그림 그리기 놀이
- `scripts/minigames/sketchbook.gd` (Sketchbook): 스케치북에 마우스로 크레용 그림. 왼쪽 끌기 그리기, 오른쪽 끌기 지우기, 크레용 12색·굵기 3단계·지우개·전부 지우기·다 그렸어
- `color_loss = true`면 도화지와 크레용이 흑백으로 보임 (칠한 색은 그대로 저장. 색채 상실 연출)
- 다 그리면 `finished(그림, 비었는지, 저장 경로)` 신호, 그림은 `user://drawings/`에 PNG로 남음
- 채린 반응: `data/minigames/chaerin_drawing.json`에서 칭찬 하나를 무작위로 (연달아 같은 것 안 나옴), 빈 도화지면 따로. 2회차는 붉은 속마음이 붙음
- 타이틀의 **그림 그리기 (개발용)** / **그림 그리기 · 색 잃은 뒤 · 2회차 (개발용)**으로 시험

## NPC (스스로 걷는 인물)
- `scripts/npc/npc.gd` (Npc): 맵의 길찾기로 벽·가구를 돌아 걷고, 가는 길의 닫힌 문은 직접 엶 (잠긴 문은 못 지나감)
- 행동: `stay` 가만히 / `film` 촬영(제자리에서 서하 쪽으로 돌아서 찍음, 보일 때만 ● REC. 따라다니지 않음) / `wander` 집 근처 배회 / `patrol` 경로 순찰
- 맵 JSON의 `npcs`에 넣으면 단독 실행 때 생김. 본관 1층: 도윤(보호자실, 배회)
- 길찾기: `InteriorMap.find_path(발 위치, 목표)` — 32px 칸, 발 상자가 벽·가구·문틀에 닿는 칸은 막힘
- NPC는 서하를 막지 않음 (문간에서 서로 갇히지 않게)
- 맵 단독 실행 중 **N 키**로 도윤 행동 바꾸기 (배회 → 가만히 → 촬영)

## 맵
- 실내 맵은 공용 로더 `scripts/map/interior_map.gd`(InteriorMap) + 맵 데이터 `data/maps/<이름>.json` 한 쌍으로 만듭니다.
  JSON 형식(바닥·벽 글자 배열, 가구, 문, 방 이름, 달빛)은 `interior_map.gd` 맨 위 설명 참고.
- `scenes/maps/int_main.tscn`: 본관 1층 (병동 4실, 병동 복도, 중앙 복도, 식당, 주방, 원장실, 투약실, 로비, 현관, 철문). F6으로 단독 실행.
  - 방향키 걷기 · E 문 열기/닫기 · L 방 이름 · T 시간대(아침/낮/저녁/밤) · V 조명 톤(1회차 따뜻하게/평소/2회차 차갑게) · F 화면 가장자리 안개(0~2단계) · Z 확대(100/75/50%) · G 격자 · Esc
  - 문 종류: 세로 벽 문(v), 가로 벽 문(h), 정면 벽 문(f). 철문은 잠겨 있음. 서하가 문 자리에 서 있으면 닫히지 않음.
  - 병실에는 욕실이 없고, 공용 화장실이 중앙 복도 남쪽(로비 동쪽, 철문 가까이)에 따로 있음: 긴 세면대(2구)·넓은 거울·종이 타월·정면 휴지통, 옆 칸막이(`stall_divider`, 휴지걸이 달린 `stall_divider_paper`)로 나눈 변기 두 칸, 손잡이 달린 장애인용 변기. 표지판은 쓰지 않음. 에셋 원본 `src/map/haemu_props_restroom.jpg`(세면대)·`haemu_props_restroom2.jpg`(나머지).
- 그림: `assets/art/tiles/interior.png`(64px 타일), `assets/art/props/interior/`(가구).
  그림체는 해무 톤(기준 견본 `tools/sprite_cleanup/src/map/style_haemu_reference.jpg`). 그림은 한 벌만 두고 분위기는 조명 톤과 안개(`shaders/sea_fog.gdshader`)로 바꿉니다.
  Gemini 원본은 `tools/sprite_cleanup/src/map/`, 정리는 `python3 tools/sprite_cleanup/build_interior.py`.
  아직 해무 톤으로 다시 받지 않은 가구(옆벽 문, 투약실 세면대 등 몇 개)는 `src/map/legacy_props/`의 예전 그림을 색만 바꿔 씁니다.
  타일 시트는 Gemini 한 칸을 타일 2×2칸(128px)으로 씁니다. 벽 앞면은 3칸(몰딩/회벽/판벽), 벽 윗면은 이웃을 보고 16종 자동.

## 아직 할 일
- 한글 폰트: 지금은 운영체제 기본 폰트로 한글을 표시합니다. 배포 전에 Pretendard나 Noto Sans KR 같은 무료 폰트를 `assets/fonts/`에 넣고 테마에 지정해야 합니다.
- 연출 키(`fx` 열)는 글리치 깜빡임과 채도만 연결되어 있고, 나머지는 화면 위 표시줄에 키 이름만 표시됩니다.
- 저장 데이터 위치(Windows): `%APPDATA%\Godot\app_userdata\해무장\`
