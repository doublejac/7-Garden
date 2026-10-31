# DialogueRunner.gd
# data/dialogue/dayN.csv (대사 스크립트 양식에서 내보낸 파일)를 읽어 한 줄씩 진행한다.
# 화면 표시는 하지 않는다. UI는 신호를 받아 그리고, next()/choose()로 진행만 시킨다.
class_name DialogueRunner
extends RefCounted

signal line_shown(line: Dictionary)
signal choices_shown(choices: Array)
signal day_finished(day: int)

const DIALOGUE_PATH := "res://data/dialogue/day%d.csv"
const STAT_NAMES := ["loop", "day", "peace", "suspicion", "clarity", "pills_skipped"]

var rows: Array = []          # 각 줄 = { id, loop, day, scene, ..., status }
var index_by_id := {}
var pos := 0                  # 다음에 검사할 줄 번호
var waiting_choices: Array = []  # 지금 고를 수 있는 선택지 줄 번호
var _after_choices := 0       # 선택지 묶음 바로 다음 줄 번호


func load_day(day: int) -> bool:
	rows.clear()
	index_by_id.clear()
	pos = 0
	waiting_choices.clear()
	var path := DIALOGUE_PATH % day
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var header := f.get_csv_line()
	while not f.eof_reached():
		var cells := f.get_csv_line()
		if cells.size() < 2 or cells[0].strip_edges() == "":
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = cells[i].strip_edges() if i < cells.size() else ""
		if index_by_id.has(row.id):
			push_warning("대사 ID 중복: %s (%s)" % [row.id, path])
		index_by_id[row.id] = rows.size()
		rows.append(row)
	return true


## 저장된 장면 ID의 첫 줄부터 시작한다. 장면을 못 찾으면 그날 처음부터.
func start_at_scene(scene_id: String) -> void:
	pos = 0
	for i in rows.size():
		if rows[i].scene == scene_id:
			pos = i
			return


## 다음 줄을 찾아 line_shown 또는 choices_shown을 보낸다. 그날 대사가 끝나면 day_finished.
func next() -> void:
	waiting_choices.clear()
	while pos < rows.size():
		var row: Dictionary = rows[pos]
		if not is_visible(row):
			pos += 1
			continue
		if row.type == "선택지":
			var j := pos
			while j < rows.size() and rows[j].type == "선택지":
				if is_visible(rows[j]):
					waiting_choices.append(j)
				j += 1
			_after_choices = j
			if waiting_choices.is_empty():
				pos = j
				continue
			choices_shown.emit(waiting_choices.map(func(k): return rows[k]))
			return
		_enter_scene(row)
		_apply(row)
		pos = _jump_target(row, pos + 1)
		line_shown.emit(row)
		return
	day_finished.emit(GameState.day)


## choices_shown으로 받은 목록에서 index번째를 고른다.
func choose(index: int) -> void:
	if index < 0 or index >= waiting_choices.size():
		push_error("잘못된 선택지 번호: %d" % index)
		return
	var row: Dictionary = rows[waiting_choices[index]]
	_apply(row)
	pos = _jump_target(row, _after_choices)
	next()


func is_waiting_for_choice() -> bool:
	return not waiting_choices.is_empty()


## 회차 열과 표시 조건 열을 함께 본다.
func is_visible(row: Dictionary) -> bool:
	match row.loop:
		"1":
			if GameState.loop != 1:
				return false
		"2+":
			if GameState.loop < 2:
				return false
	if row.cond != "":
		return eval_cond(row.cond)
	return true


## "loop>=2 and clarity>=30", "lie_choice" 같은 조건식을 계산한다.
func eval_cond(text: String) -> bool:
	var names := PackedStringArray(STAT_NAMES)
	var values := [GameState.loop, GameState.day, GameState.peace, GameState.suspicion,
			GameState.clarity, GameState.pills_skipped]
	for f in GameState.FLAG_NAMES:
		names.append(f)
		values.append(GameState.flags.get(f, false))
	var e := Expression.new()
	if e.parse(text, names) != OK:
		push_error("조건식 오류 '%s': %s" % [text, e.get_error_text()])
		return false
	var result = e.execute(values, null, false)
	if e.has_execute_failed():
		push_error("조건식 실행 실패: '%s'" % text)
		return false
	return bool(result)


## 붉은 속마음은 inner_text 플래그가 켜졌을 때만 보여준다.
func inner_text_of(row: Dictionary) -> String:
	return row.inner if GameState.flags.get("inner_text", false) else ""


func _apply(row: Dictionary) -> void:
	SaveManager.mark_line_seen(row.id)
	if row.stat != "":
		GameState.apply_stat_string(row.stat)
	if row.flag != "":
		GameState.apply_flag_string(row.flag)


func _enter_scene(row: Dictionary) -> void:
	if row.scene != "" and row.scene != GameState.scene_id:
		GameState.scene_id = row.scene


func _jump_target(row: Dictionary, fallback: int) -> int:
	if row.next == "":
		return fallback
	if not index_by_id.has(row.next):
		push_error("다음 ID를 찾을 수 없음: %s → %s" % [row.id, row.next])
		return fallback
	return index_by_id[row.next]
