# capsule.gd
# 캡슐 삼키는 척하기 (2회차 아침·저녁 투약). 원장의 눈을 속여 붉은 캡슐을 소매에 숨긴다.
#   ① 원장이 보는 앞에서 캡슐을 클릭 → 입에 넣는 척 (혀 밑에 숨김)
#   ② 물컵을 꾹 누르고 있기 → 물을 마셔 삼킨 척. 원장이 보고 있어야 믿는다
#   ③ 원장이 차트를 적느라 눈을 돌린 사이, 입의 캡슐을 끌어 소매에 넣기
#      원장은 돌아보기 직전 눈동자가 먼저 움찔한다(…?). 원장이 보고 있을 때 손이 움직이면 들킴
#   눈을 돌리는 틈을 세 번 놓치면 "입 한번 벌려 볼까요?" → 결국 삼킴
# 결과: finished("hidden" | "caught" | "swallowed"). 수치는 RESULT_STATS를 GameState에 적용(부르는 쪽에서)
# difficulty 0~1: 눈을 돌리는 시간이 짧아지고, 돌아보기 전 신호도 짧아짐 (의심도가 높을수록 올리면 됨)
class_name CapsuleTrick
extends Control

signal finished(result: String)

## 설계서 '행동별 수치 변화'와 같음. caught = 들켜서 의심도 +20, 그 자리에서 결국 복용
const RESULT_STATS := {
	"hidden": "clarity+15;pills_skipped+1",
	"caught": "suspicion+20;peace+2;clarity-15",
	"swallowed": "peace+2;suspicion-5;clarity-15",
}
const CAPSULE_RED := Color("#c8323a")
const SLEEVE := Color("#4f5a2c")            # 서하의 올리브색 카디건
const SKIN := Color("#f2d6c4")
const EYE_C := Vector2(640, 175)
const MOUTH_C := Vector2(640, 438)
const PALM_C := Vector2(640, 600)
const CUP_C := Vector2(930, 560)
const SLEEVE_R := Rect2(150, 520, 230, 150)
const DRINK_TIME := 1.2
const MAX_CHANCES := 3

@export var difficulty := 0.3

var step := 1                    # 1 입에 넣기, 2 물 마시기, 3 소매에 숨기기, 4 끝
var state := "watch"             # watch / away / tell
var _timer := 0.0
var _look := 0.0                 # 0 = 서하를 봄, 1 = 차트를 봄
var _look_target := 0.0
var _twitch := 0.0
var _chances := 0
var _capsule := PALM_C
var _dragging := false
var _drink := 0.0
var _drinking := false
var _danger := 0.0               # 들킬 뻔한 붉은 테두리
var _done := false
var _line: Label
var _status: Label
var _help: Label
var _result: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_line = _label(22, Color(1, 1, 1, 0.92))
	_line.position = Vector2(140, 300)
	_line.size = Vector2(1000, 34)
	_status = _label(16, Color(1, 1, 1, 0.55))
	_status.position = Vector2(140, 268)
	_status.size = Vector2(1000, 24)
	_help = _label(17, Color(1, 1, 1, 0.6))
	_help.position = Vector2(140, 684)
	_help.size = Vector2(1000, 26)
	_say("원장: 자, 오늘 것도 잘 삼켜요. 물이랑 같이.")
	_update_help()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _say(t: String) -> void:
	_line.text = t


func _update_help() -> void:
	match step:
		1: _help.text = "① 캡슐을 클릭해 입에 넣는 척하기"
		2: _help.text = "② 물컵을 꾹 누르고 있기 — 원장이 보는 앞에서 삼킨 척"
		3: _help.text = "③ 원장이 눈을 돌린 사이, 입의 캡슐을 끌어 소매 속으로 · 눈동자가 움찔하면 손을 멈출 것"
		_: _help.text = ""


# ── 원장의 시선 ───────────────────────────────────────────
func _process(delta: float) -> void:
	if _done:
		return
	_look = move_toward(_look, _look_target, delta * (5.0 if _look_target < _look else 3.0))
	_twitch = maxf(0.0, _twitch - delta)
	_danger = maxf(0.0, _danger - delta * 1.5)
	if _drinking and step == 2:
		_drink += delta
		if _drink >= DRINK_TIME:
			_finish_drink()
	if step == 3:
		_timer -= delta
		match state:
			"watch":
				_status.text = "원장이 보고 있다"
				if _timer <= 0.0:
					if _chances >= MAX_CHANCES:
						_end("swallowed")
						return
					_set_state("away")
			"away":
				_status.text = "원장이 차트를 적고 있다"
				if _timer <= 0.0:
					_set_state("tell")
			"tell":
				_status.text = "…?"
				if _timer <= 0.0:
					_set_state("watch")
		if state == "watch" and _dragging and _capsule.distance_to(MOUTH_C) > 18.0:
			_end("caught")
			return
	queue_redraw()


func _set_state(s: String) -> void:
	state = s
	match s:
		"watch":
			_look_target = 0.0
			_timer = randf_range(1.4, 2.6)
		"away":
			_chances += 1
			_look_target = 1.0
			_timer = lerpf(1.9, 1.0, difficulty) + randf_range(-0.2, 0.3)
			_say(["원장: 음, 차트에 적어 둘게요…", "원장: 오늘 혈압이…", "원장: 잠깐만요, 이것만 쓰고."][(_chances - 1) % 3])
			if _chances == MAX_CHANCES:
				_say("원장: 그럼, 마지막으로 하나만 확인할게요…")
		"tell":
			_look_target = 0.55
			_twitch = 0.25
			_danger = 0.8
			_timer = lerpf(0.5, 0.28, difficulty)


# ── 조작 ─────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if _done:
		if _result and event is InputEventMouseButton and event.pressed:
			_close()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			match step:
				1:
					if event.position.distance_to(_capsule) < 40:
						_put_in_mouth()
				2:
					if _cup_rect().has_point(event.position):
						_drinking = true
				3:
					if event.position.distance_to(_capsule) < 40:
						_dragging = true
		else:
			if _drinking and step == 2 and _drink < DRINK_TIME:
				_drink = 0.0
				_say("원장: 물은 넉넉히 마셔요.")
			_drinking = false
			if _dragging:
				_dragging = false
				if SLEEVE_R.grow(10).has_point(_capsule):
					_end("hidden")
				else:
					create_tween().tween_property(self, "_capsule", MOUTH_C, 0.15)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_capsule = event.position
		accept_event()


func _put_in_mouth() -> void:
	step = 0
	var t := create_tween()
	t.tween_property(self, "_capsule", MOUTH_C, 0.45).set_trans(Tween.TRANS_SINE)
	t.tween_callback(func():
		step = 2
		_say("원장: 그렇지. 이제 물.")
		_update_help())


func _finish_drink() -> void:
	_drinking = false
	step = 3
	_say("원장: 잘했어요.")
	_update_help()
	state = "watch"
	_timer = randf_range(1.0, 1.6)


func _cup_rect() -> Rect2:
	return Rect2(CUP_C - Vector2(55, 80), Vector2(110, 160))


# ── 끝 ───────────────────────────────────────────────────
func _end(result: String) -> void:
	_done = true
	_dragging = false
	set_meta("result", result)
	var title := ""
	var sub := ""
	match result:
		"hidden":
			title = "소매 안에 캡슐을 숨겼다."
			sub = "원장은 아무것도 눈치채지 못했다. 혀끝에 쓴맛만 남았다."
			_look_target = 1.0
		"caught":
			title = "원장과 눈이 마주쳤다."
			sub = "원장: …서하 씨, 손에 그거 뭐예요? 다시 삼켜요. 내 앞에서."
			_look = 0.0
			_danger = 1.0
		"swallowed":
			title = "끝내 캡슐을 삼켰다."
			sub = "원장: 자, 입 한번 벌려 볼까요. …착하네요."
			_look = 0.0
	_help.text = ""
	_status.text = ""
	_line.text = ""
	queue_redraw()
	_result = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.06, 0.9)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	_result.add_theme_stylebox_override("panel", sb)
	_result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_result.add_child(v)
	var a := Label.new()
	a.text = title
	a.add_theme_font_size_override("font_size", 28)
	a.add_theme_color_override("font_color", Color("#ff6a6a") if result != "hidden" else Color("#e8e2d0"))
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(a)
	var b := Label.new()
	b.text = sub
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(b)
	var c := Label.new()
	c.text = "클릭: 계속"
	c.add_theme_font_size_override("font_size", 14)
	c.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	add_child(_result)
	_result.reset_size()
	_result.position = Vector2(640 - _result.size.x / 2.0, 300)
	_result.modulate.a = 0.0
	var t := create_tween()
	t.tween_interval(0.5)
	t.tween_property(_result, "modulate:a", 1.0, 0.35)


func _close() -> void:
	var r: String = get_meta("result")
	_result = null
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.3)
	t.tween_callback(func():
		finished.emit(r)
		queue_free())


# ── 그리기 ────────────────────────────────────────────────
func _draw() -> void:
	# 진찰실: 어두운 벽, 창으로 드는 흐린 빛
	draw_rect(Rect2(Vector2.ZERO, size), Color("#1d2226"))
	draw_rect(Rect2(0, 0, size.x, 330), Color("#252c31"))
	draw_rect(Rect2(880, 30, 260, 230), Color(0.75, 0.82, 0.86, 0.06))
	draw_line(Vector2(1010, 30), Vector2(1010, 260), Color(0, 0, 0, 0.25), 3)
	draw_line(Vector2(880, 145), Vector2(1140, 145), Color(0, 0, 0, 0.25), 3)
	draw_rect(Rect2(0, 330, size.x, 4), Color(0, 0, 0, 0.3))
	_draw_eye()
	_draw_mouth()
	_draw_palm()
	_draw_cup()
	_draw_sleeve()
	_draw_capsule(_capsule, 0.85 if _capsule.distance_to(MOUTH_C) < 4.0 else 1.0)
	if step == 2 or _drinking:
		var r := _cup_rect()
		draw_rect(Rect2(r.position.x, r.end.y + 10, r.size.x, 6), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(r.position.x, r.end.y + 10, r.size.x * clampf(_drink / DRINK_TIME, 0, 1), 6), Color("#9fc6d8"))
	if _danger > 0.0:
		var a := _danger * 0.5
		for i in 12:
			var w := 3.0 + i * 3.0
			draw_rect(Rect2(Vector2(w, w), size - Vector2(w, w) * 2), Color(0.8, 0.1, 0.12, a * (1.0 - i / 12.0) * 0.35), false, 3.0)


func _draw_eye() -> void:
	var c := EYE_C + Vector2(0, _look * 6)
	var w := 300.0
	var open := lerpf(62.0, 26.0, _look)        # 아래를 보면 눈꺼풀이 내려옴
	# 눈가 그늘
	for k in 6:
		draw_circle(c, 190.0 - k * 22.0, Color(0, 0, 0, 0.035))
	# 눈 흰자(아몬드 모양)
	var pts := PackedVector2Array()
	for i in 33:
		var t := float(i) / 32.0
		pts.append(c + Vector2(lerpf(-w / 2, w / 2, t), -sin(t * PI) * open))
	for i in range(31, 0, -1):
		var t := float(i) / 32.0
		pts.append(c + Vector2(lerpf(-w / 2, w / 2, t), sin(t * PI) * 44.0))
	draw_colored_polygon(pts, Color("#e9e4dc"))
	# 눈동자: 서하를 볼 땐 정면, 차트를 볼 땐 오른쪽 아래, 움찔하면 떨림
	var shake := Vector2(sin(Time.get_ticks_msec() * 0.09) * 6.0, 0) if _twitch > 0.0 else Vector2.ZERO
	var iris := c + Vector2(_look * 70.0, _look * 26.0 - (1.0 - _look) * 4.0) + shake
	var iris_pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		var p := iris + Vector2(cos(a), sin(a)) * 40.0
		p.y = clampf(p.y, c.y - open + 2, c.y + 42)
		iris_pts.append(p)
	draw_colored_polygon(iris_pts, Color("#3d2a22"))
	draw_circle(iris, 17, Color("#0e0a09"))
	draw_circle(iris + Vector2(-12, -12), 6, Color(1, 1, 1, 0.75))
	# 눈꺼풀 선·속눈썹
	var lid := PackedVector2Array()
	for i in 33:
		var t := float(i) / 32.0
		lid.append(c + Vector2(lerpf(-w / 2, w / 2, t), -sin(t * PI) * open))
	draw_polyline(lid, Color("#2a1f1b"), 6.0, true)
	for i in range(4, 30, 4):
		var t := float(i) / 32.0
		var p := c + Vector2(lerpf(-w / 2, w / 2, t), -sin(t * PI) * open)
		draw_line(p, p + Vector2((t - 0.5) * 22, -14), Color("#2a1f1b"), 3.0)
	var low := PackedVector2Array()
	for i in 33:
		var t := float(i) / 32.0
		low.append(c + Vector2(lerpf(-w / 2, w / 2, t), sin(t * PI) * 44.0))
	draw_polyline(low, Color(0.16, 0.12, 0.1, 0.5), 2.0, true)
	# 눈썹: 볼 때는 반듯, 움찔하면 살짝 올라감
	var brow_y := -open - 38.0 - (8.0 if state == "tell" else 0.0)
	var brow := PackedVector2Array()
	for i in 17:
		var t := float(i) / 16.0
		brow.append(c + Vector2(lerpf(-w * 0.42, w * 0.46, t), brow_y - sin(t * PI) * 16.0 + t * 6.0))
	draw_polyline(brow, Color("#3a2b24"), 9.0, true)


func _draw_mouth() -> void:
	var c := MOUTH_C
	draw_arc(c + Vector2(0, -44), 60, PI * 0.3, PI * 0.7, 20, Color(SKIN, 0.25), 2.0)
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		var x := lerpf(-54, 54, t)
		upper.append(c + Vector2(x, -absf(sin(t * TAU)) * 6.0 - 4))
		lower.append(c + Vector2(x, sin(t * PI) * 14.0))
	draw_polyline(upper, Color("#b9757a"), 4.0, true)
	draw_polyline(lower, Color("#b9757a"), 4.0, true)
	if step >= 2:
		_small_text(c + Vector2(0, 40), "혀 밑에 숨긴 캡슐", Color(1, 1, 1, 0.35))


## 위로 편 오른손 손바닥 (손가락 길이 다르게, 엄지는 왼쪽으로 비스듬히)
func _draw_palm() -> void:
	var line := Color(0.62, 0.44, 0.38, 0.55)
	var fingers := [[-45.0, 62.0], [-15.0, 78.0], [15.0, 74.0], [43.0, 58.0]]
	for f in fingers:
		_capsule_shape(PALM_C + Vector2(f[0], -18), PALM_C + Vector2(f[0] * 1.08, -18 - f[1]), 13.0, SKIN)
	_capsule_shape(PALM_C + Vector2(-50, 30), PALM_C + Vector2(-100, -12), 15.0, SKIN)   # 엄지
	draw_set_transform(PALM_C + Vector2(0, 22), 0.0, Vector2(1.0, 0.92))
	draw_circle(Vector2.ZERO, 66, SKIN)
	draw_set_transform(Vector2.ZERO)
	for f in fingers:                                          # 손가락 마디 주름
		var x: float = PALM_C.x + f[0] * 1.04
		var y: float = PALM_C.y - 18 - f[1] * 0.55
		draw_line(Vector2(x - 7, y), Vector2(x + 7, y), line, 1.5)
	draw_arc(PALM_C + Vector2(-4, 34), 46, PI * 1.12, PI * 1.6, 14, line, 2.0)       # 손금
	draw_arc(PALM_C + Vector2(10, -2), 52, PI * 0.15, PI * 0.62, 14, line, 2.0)


func _capsule_shape(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	draw_line(a, b, col, r * 2.0)
	draw_circle(a, r, col)
	draw_circle(b, r, col)


func _draw_cup() -> void:
	var r := _cup_rect()
	var tilt := -0.35 * clampf(_drink / DRINK_TIME, 0.0, 1.0) if _drinking else 0.0
	draw_set_transform(CUP_C, tilt, Vector2.ONE)
	var w := r.size.x
	var h := r.size.y
	var glass := PackedVector2Array([Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2 - 12, h / 2), Vector2(-w / 2 + 12, h / 2)])
	var level := lerpf(-h * 0.15, h * 0.35, clampf(_drink / DRINK_TIME, 0.0, 1.0))
	var water := PackedVector2Array([Vector2(-w / 2 + 4, level), Vector2(w / 2 - 4, level), Vector2(w / 2 - 13, h / 2 - 3), Vector2(-w / 2 + 13, h / 2 - 3)])
	draw_colored_polygon(water, Color(0.62, 0.8, 0.9, 0.35))
	draw_colored_polygon(glass, Color(1, 1, 1, 0.07))
	glass.append(glass[0])
	draw_polyline(glass, Color(1, 1, 1, 0.45), 2.0, true)
	draw_line(Vector2(-w / 2 + 14, -h / 2 + 12), Vector2(-w / 2 + 22, h / 2 - 16), Color(1, 1, 1, 0.25), 3.0)
	draw_set_transform(Vector2.ZERO)
	_small_text(CUP_C + Vector2(0, 108), "물", Color(1, 1, 1, 0.4))


func _draw_sleeve() -> void:
	var r := SLEEVE_R
	draw_rect(r, SLEEVE)
	for i in range(int(r.position.x) + 8, int(r.end.x), 10):
		draw_line(Vector2(i, r.position.y), Vector2(i, r.end.y), Color(0, 0, 0, 0.12), 2.0)
	var mouth := Rect2(r.end.x - 34, r.position.y + 20, 28, r.size.y - 40)   # 소매 끝 안쪽 어둠
	draw_rect(mouth, Color(0.08, 0.09, 0.05))
	var hot := step == 3 and _dragging
	draw_rect(r.grow(4), Color(1, 1, 1, 0.35 if hot else 0.1), false, 2.0)
	_small_text(r.get_center() + Vector2(0, r.size.y / 2 + 18), "소매", Color(1, 1, 1, 0.4))


func _draw_capsule(p: Vector2, s: float) -> void:
	draw_set_transform(p, -0.5, Vector2.ONE * s)
	draw_rect(Rect2(-22, -11, 22, 22), CAPSULE_RED)
	draw_circle(Vector2(-22, 0), 11, CAPSULE_RED)
	draw_rect(Rect2(0, -11, 22, 22), Color("#f0e8e2"))
	draw_circle(Vector2(22, 0), 11, Color("#f0e8e2"))
	draw_line(Vector2(-26, -6), Vector2(16, -6), Color(1, 1, 1, 0.45), 3.0)
	draw_set_transform(Vector2.ZERO)


func _small_text(p: Vector2, t: String, col: Color) -> void:
	var f := get_theme_default_font()
	var fs := 14
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, p - Vector2(w / 2.0, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
