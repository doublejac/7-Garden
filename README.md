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
- `scenes/dev/sprite_viewer.tscn`: 확인용 씬. F6으로 실행 후 방향키로 걷기(Shift: 살금살금), 숫자키와 Q·W·E·R로 특수 동작.
- 이동: walk_down / walk_up / walk_left / walk_right, 대기: idle / idle_up / idle_left / idle_right
  (멈추면 마지막으로 바라본 방향의 대기 동작이 재생됩니다)
- 살금살금: sneak_left / sneak_right (`walk(dir, true)`)
- 특수: take_pill, hide_pill, fake_swallow, startle, step_back_left/right, cry, sad, crouch_look, happy, wave, point_left/right
- 앉기: sit_bench, write, piano (피아노·책상 같은 소품은 따로 배치)
- 원본: `tools/sprite_cleanup/src/` 의 Gemini 시트 5장 (단색 초록 배경)
- 정리: `python3 tools/sprite_cleanup/clean_chroma.py tools/sprite_cleanup/seoha_v2.json assets/art/characters/seoha`
  → 초록 배경 제거, 조개 핀 위치 맞춤, 캐릭터 크기 통일, 발바닥 정렬. 프레임 위치는 json에 (시트, 줄, 칸)으로 적습니다.
  체크무늬 배경 시트는 `clean_sheet.py`를 씁니다. 두 스크립트 모두 Python과 numpy, scipy, Pillow가 필요합니다.
- 애니메이션 리소스 만들기: `godot --headless --path . -s res://tools/build_spriteframes.gd -- seoha`
- 서하 노드는 텍스처 필터가 Linear입니다. 1배 크기로 쓰는 것을 기준으로 합니다.

## 아직 할 일
- 한글 폰트: 지금은 운영체제 기본 폰트로 한글을 표시합니다. 배포 전에 Pretendard나 Noto Sans KR 같은 무료 폰트를 `assets/fonts/`에 넣고 테마에 지정해야 합니다.
- 연출 키(`fx` 열)는 글리치 깜빡임과 채도만 연결되어 있고, 나머지는 화면 위 표시줄에 키 이름만 표시됩니다.
- 저장 데이터 위치(Windows): `%APPDATA%\Godot\app_userdata\해무장\`
