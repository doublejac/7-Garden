# test_runner.gd
# 헤드리스 자동 점검. 실행:
#   godot --headless --path . res://tests/test_runner.tscn
# 1) 1회차를 첫 번째·마지막 선택지로 각각 끝까지 돌려 일차별 평온도가 49/58/67/76인지 확인
# 2) 2회차를 붉은 선택지 우선으로 돌려 오류 없이 끝나는지 확인
# 3) 저장 → 값 변경 → 불러오기로 상태가 복원되는지 확인
extends Node

const EXPECTED_LOOP1_PEACE := {1: 49, 2: 58, 3: 67, 4: 76}
const LAST_DAY := 4

var failures := 0


func _ready() -> void:
	for strategy in ["first", "last"]:
		_play_loop(1, strategy, true)
	_play_loop(2, "red", false)
	_test_save_load()
	print("\n결과: %s (실패 %d건)" % ["통과" if failures == 0 else "실패", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _play_loop(loop: int, strategy: String, check_peace: bool) -> void:
	GameState.reset_run(false)
	GameState.loop = loop
	var runner := DialogueRunner.new()
	var state := {"lines": 0, "choices": 0, "done": false, "pending": []}
	runner.line_shown.connect(func(_l): state.lines += 1)
	runner.choices_shown.connect(func(c): state.pending = c)
	runner.day_finished.connect(func(_d): state.done = true)
	for day in range(1, LAST_DAY + 1):
		GameState.day = day
		_check(runner.load_day(day), "%d일 차 파일 로드" % day)
		state.done = false
		var guard := 0
		while not state.done and guard < 2000:
			guard += 1
			if runner.is_waiting_for_choice():
				var c: Array = state.pending
				var pick := 0
				match strategy:
					"last":
						pick = c.size() - 1
					"red":
						pick = c.size() - 1
						for i in c.size():
							if "text_red" in c[i].fx:
								pick = i
								break
				state.choices += 1
				runner.choose(pick)
			else:
				runner.next()
		_check(state.done, "%d회차 %d일 차가 끝까지 진행됨 (%s)" % [loop, day, strategy])
		if check_peace:
			_check(GameState.peace == EXPECTED_LOOP1_PEACE[day],
				"%d회차 %d일 차 종료 평온도 %d (기대값 %d, %s)" % [loop, day, GameState.peace, EXPECTED_LOOP1_PEACE[day], strategy])
	print("  %d회차 [%s] 대사 %d줄, 선택 %d번 → 평온도 %d 의심도 %d 자아 %d 약 거부 %d" % [
		loop, strategy, state.lines, state.choices, GameState.peace, GameState.suspicion,
		GameState.clarity, GameState.pills_skipped])


func _test_save_load() -> void:
	GameState.reset_run(false)
	GameState.loop = 2
	GameState.day = 3
	GameState.scene_id = "D3_S04"
	GameState.peace = 61
	GameState.flags.lie_choice = true
	SaveManager.can_manual_save = true
	_check(SaveManager.save_slot(1), "슬롯 1 저장")
	SaveManager.can_manual_save = false
	_check(not SaveManager.save_slot(2), "세이브 포인트 밖 수동 저장 거부")
	GameState.reset_run(false)
	_check(SaveManager.load_slot(1), "슬롯 1 불러오기")
	_check(GameState.loop == 2 and GameState.day == 3 and GameState.peace == 61
		and GameState.scene_id == "D3_S04" and GameState.flags.lie_choice,
		"불러온 상태가 저장한 상태와 같음")
	SaveManager.delete_slot(1)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  [OK] " + what)
	else:
		failures += 1
		print("  [실패] " + what)
