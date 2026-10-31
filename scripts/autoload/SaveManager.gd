# SaveManager.gd
# Autoload 이름: SaveManager (GameState 아래에 등록)
#
# 슬롯 0      : 자동 저장. 매일 아침 일차가 시작될 때 덮어쓴다. 게임 오버 후 "그날 아침으로"에 사용.
# 슬롯 1~3    : 수동 저장. 서하 방 침대(세이브 포인트)에서만 can_manual_save = true.
# meta.save   : 회차를 넘어 유지되는 데이터. 슬롯을 불러오거나 지워도 바뀌지 않는다.
extends Node

signal saved(slot: int)
signal loaded(slot: int)

const SAVE_VERSION := 1
const AUTO_SLOT := 0
const MANUAL_SLOTS := [1, 2, 3]
const META_PATH := "user://meta.save"

## 세이브 포인트에 들어가면 true, 나오면 false로 바꿔준다.
var can_manual_save := false

var meta: Dictionary = {
	"loops_completed": 0,   # 7일 차 엔딩을 본 횟수
	"endings_seen": [],     # ["ending_1", "early", ...]
	"inner_text": false,    # 붉은 속마음 해금 (회차를 넘어 유지)
	"seen_lines": {},       # 대사 ID -> true. 이미 본 대사 스킵용
}


func _ready() -> void:
	_load_meta()
	GameState.ending_triggered.connect(_on_ending_triggered)


# --- 슬롯 -----------------------------------------------------------------

func _slot_path(slot: int) -> String:
	return "user://slot_%d.save" % slot


## 장면이 끝난 뒤에만 호출한다. scene_id는 다음에 재생할 장면이어야 한다.
func save_slot(slot: int) -> bool:
	if slot != AUTO_SLOT and not can_manual_save:
		push_warning("수동 저장은 세이브 포인트에서만 가능합니다.")
		return false
	var ok := _write(_slot_path(slot), {
		"version": SAVE_VERSION,
		"time": Time.get_datetime_string_from_system(false, true),
		"state": GameState.to_dict(),
	})
	if ok:
		_save_meta()
		saved.emit(slot)
	return ok


func load_slot(slot: int) -> bool:
	var data = _read(_slot_path(slot))
	if data == null:
		return false
	GameState.from_dict(data.get("state", {}))
	# 회차를 넘어 유지되는 값은 메타가 우선
	GameState.flags["inner_text"] = GameState.flags["inner_text"] or meta.inner_text
	loaded.emit(slot)
	return true


func has_slot(slot: int) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func delete_slot(slot: int) -> void:
	if has_slot(slot):
		DirAccess.remove_absolute(_slot_path(slot))


## 불러오기 화면 표시용: { "loop": 2, "day": 4, "time": "2026-10-30 17:55:00" }
func slot_info(slot: int) -> Dictionary:
	var data = _read(_slot_path(slot))
	if data == null:
		return {}
	var st: Dictionary = data.get("state", {})
	return {"loop": st.get("loop", 1), "day": st.get("day", 1), "time": data.get("time", "")}


# --- 진행 흐름에서 부르는 함수 ---------------------------------------------

## 일차가 시작되는 첫 장면 직전에 호출 (예: D4_S00 재생 전).
func autosave_day_start() -> void:
	save_slot(AUTO_SLOT)


## 게임 오버 화면의 "그날 아침으로 돌아가기". 회차는 그대로.
func retry_today() -> bool:
	return load_slot(AUTO_SLOT)


## 7일 차 엔딩을 다 본 뒤 호출하면 다음 회차를 1일 차부터 시작한다.
func start_next_loop() -> void:
	GameState.reset_run(meta.inner_text)
	GameState.loop = meta.loops_completed + 1
	autosave_day_start()


## 7일 차 엔딩 연출이 끝났을 때 호출 (GameState.judge_ending() 결과를 넘긴다).
func record_final_ending(ending_id: String) -> void:
	_add_ending(ending_id)
	meta.loops_completed += 1
	_save_meta()


func _on_ending_triggered(ending_id: String) -> void:
	# 조기 엔딩(폐기 처분)과 7일 차 이전의 평온도 100은 회차로 세지 않는다.
	_add_ending(ending_id)
	_save_meta()


func _add_ending(ending_id: String) -> void:
	if not meta.endings_seen.has(ending_id):
		meta.endings_seen.append(ending_id)


# --- 메타 데이터 --------------------------------------------------------------

func mark_line_seen(line_id: String) -> void:
	meta.seen_lines[line_id] = true
	# inner_text가 이번 회차에 켜졌다면 메타에도 기록
	if GameState.flags.get("inner_text", false):
		meta.inner_text = true


func is_line_seen(line_id: String) -> bool:
	return meta.seen_lines.has(line_id)


func _load_meta() -> void:
	var data = _read(META_PATH)
	if data != null:
		for k in data.get("meta", {}):
			meta[k] = data.meta[k]


func _save_meta() -> void:
	_write(META_PATH, {"version": SAVE_VERSION, "meta": meta})


# --- 파일 입출력 ----------------------------------------------------------------
# 임시 파일에 먼저 쓰고 바꿔치기해서, 저장 중 꺼져도 기존 세이브가 깨지지 않게 한다.

func _write(path: String, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("저장 실패: %s (%d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_var(data)
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


func _read(path: String):
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var data = f.get_var()
	if typeof(data) != TYPE_DICTIONARY:
		return null
	return data
