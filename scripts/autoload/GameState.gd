# GameState.gd
# Autoload 이름: GameState (SaveManager보다 위에 등록)
# 한 회차(7일) 동안의 진행 상태를 담는다. 저장/불러오기는 SaveManager가 담당.
extends Node

signal stat_changed(stat: String, value: int)
## "early" = 조기 엔딩(폐기 처분), "ending_1" = 평온도 100 도달
signal ending_triggered(ending_id: String)

const START_PEACE := 40
const START_CLARITY := 20

var loop := 1                 # 회차
var day := 1                  # 일차 (1~7)
var scene_id := "D1_S00"      # 마지막으로 시작한 장면. 불러오면 이 장면 처음부터 재생
var peace := START_PEACE      # 평온도 (공개)
var suspicion := 0            # 의심도 (숨김)
var clarity := START_CLARITY  # 자아 회복도 (숨김)
var pills_skipped := 0        # 약 거부 횟수

const FLAG_NAMES := [
	"found_capsule", "lie_choice", "read_floor_message", "found_archive",
	"inner_text", "park_ally", "reverse_engineered", "glass_shard",
]
var flags: Dictionary = {}
var _ending_fired := false   # 즉시 엔딩 신호를 한 번만 보내기 위한 잠금


func _ready() -> void:
	reset_run(false)


## 새 회차를 시작할 때 호출. inner_text는 회차를 넘어 유지되므로 메타에서 받아온다.
func reset_run(keep_inner_text: bool) -> void:
	_ending_fired = false
	day = 1
	scene_id = "D1_S00"
	peace = START_PEACE
	suspicion = 0
	clarity = START_CLARITY
	pills_skipped = 0
	flags.clear()
	for f in FLAG_NAMES:
		flags[f] = false
	flags["inner_text"] = keep_inner_text


## 대사 시트의 stat 열("peace+2;clarity-15")을 그대로 넘겨도 된다.
func apply_stat_string(s: String) -> void:
	for part in s.split(";", false):
		var m := RegEx.create_from_string("^(\\w+)([+-]\\d+)$").search(part.strip_edges())
		if m:
			change(m.get_string(1), int(m.get_string(2)))


func change(stat: String, delta: int) -> void:
	if stat == "pills_skipped":
		pills_skipped += delta
		return
	set(stat, clampi(get(stat) + delta, 0, 100))
	stat_changed.emit(stat, get(stat))
	_check_instant_endings()


## 대사 시트의 flag 열("lie_choice=true;found_capsule=true")을 그대로 넘겨도 된다.
func apply_flag_string(s: String) -> void:
	for part in s.split(";", false):
		var kv := part.strip_edges().split("=")
		if kv.size() == 2:
			flags[kv[0]] = kv[1] == "true"


func _check_instant_endings() -> void:
	if _ending_fired:
		return
	if loop > 1 and suspicion >= 100:
		_ending_fired = true
		ending_triggered.emit("early")
	elif peace >= 100:
		_ending_fired = true
		ending_triggered.emit("ending_1")


## 7일 차 수술 직전 판정. 설계서 '엔딩 판정'과 같은 순서.
func judge_ending() -> String:
	if loop == 1 or peace >= 80:
		return "ending_1"
	if not flags.found_archive or clarity < 50:
		return "ending_1"
	if flags.park_ally and flags.reverse_engineered and clarity >= 100 and peace >= 50:
		return "ending_3"
	return "ending_2"


# --- 저장용 직렬화 -------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"loop": loop,
		"day": day,
		"scene_id": scene_id,
		"peace": peace,
		"suspicion": suspicion,
		"clarity": clarity,
		"pills_skipped": pills_skipped,
		"flags": flags.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	_ending_fired = false
	loop = d.get("loop", 1)
	day = d.get("day", 1)
	scene_id = d.get("scene_id", "D1_S00")
	peace = d.get("peace", START_PEACE)
	suspicion = d.get("suspicion", 0)
	clarity = d.get("clarity", START_CLARITY)
	pills_skipped = d.get("pills_skipped", 0)
	var saved_flags: Dictionary = d.get("flags", {})
	for f in FLAG_NAMES:
		flags[f] = saved_flags.get(f, false)
