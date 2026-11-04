# 해무장 (Godot 4.7 프로젝트)

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
  - 서하 방에는 작은 욕실(세면대·거울·변기)이 딸려 있음. 로비 현관 옆 우산꽂이의 노란 우산은 3일 차 단서.
- 그림: `assets/art/tiles/interior.png`(64px 타일), `assets/art/props/interior/`(가구).
  그림체는 해무 톤(기준 견본 `tools/sprite_cleanup/src/map/style_haemu_reference.jpg`). 그림은 한 벌만 두고 분위기는 조명 톤과 안개(`shaders/sea_fog.gdshader`)로 바꿉니다.
  Gemini 원본은 `tools/sprite_cleanup/src/map/`, 정리는 `python3 tools/sprite_cleanup/build_interior.py`.
  아직 해무 톤으로 다시 받지 않은 가구(옆벽 문, 투약실 세면대 등 몇 개)는 `src/map/legacy_props/`의 예전 그림을 색만 바꿔 씁니다.
  타일 시트는 Gemini 한 칸을 타일 2×2칸(128px)으로 씁니다. 벽 앞면은 3칸(몰딩/회벽/판벽), 벽 윗면은 이웃을 보고 16종 자동.

## 아직 할 일
- 한글 폰트: 지금은 운영체제 기본 폰트로 한글을 표시합니다. 배포 전에 Pretendard나 Noto Sans KR 같은 무료 폰트를 `assets/fonts/`에 넣고 테마에 지정해야 합니다.
- 연출 키(`fx` 열)는 글리치 깜빡임과 채도만 연결되어 있고, 나머지는 화면 위 표시줄에 키 이름만 표시됩니다.
- 저장 데이터 위치(Windows): `%APPDATA%\Godot\app_userdata\해무장\`
