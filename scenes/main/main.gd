# main.gd
# 개발용 대사 재생기. 그림 없이 1~4일 차 대사를 텍스트로 돌려보며 분기와 수치를 확인한다.
# 클릭 / 스페이스 / 엔터: 다음 줄   F1: 디버그 수치 표시 켜고 끄기
extends Control

const LAST_WRITTEN_DAY := 4   # 대사를 작성한 마지막 일차

var runner := DialogueRunner.new()

var _bg: ColorRect
var _fx: ColorRect
var _debug: Label
var _box: PanelContainer
var _speaker: Label
var _text: RichTextLabel
var _inner: RichTextLabel
var _choices: VBoxContainer
var _menu: VBoxContainer
var _ending_shown := false


func _ready() -> void:
	_build_ui()
	runner.line_shown.connect(_on_line)
	runner.choices_shown.connect(_on_choices)
	runner.day_finished.connect(_on_day_finished)
	GameState.ending_triggered.connect(_on_ending)
	GameState.stat_changed.connect(func(_s, _v): _refresh_debug())
	_show_title()


# --- 진행 ---------------------------------------------------------------------

func _start_new(loop: int) -> void:
	GameState.reset_run(SaveManager.meta.inner_text)
	GameState.loop = loop
	_begin_day(1, true)


func _continue_from(slot: int) -> void:
	if not SaveManager.load_slot(slot):
		return
	var scene := GameState.scene_id
	_begin_day(GameState.day, false)
	GameState.scene_id = scene
	runner.start_at_scene(scene)
	runner.next()


func _begin_day(day: int, play_now: bool) -> void:
	_ending_shown = false
	GameState.day = day
	GameState.scene_id = "D%d_S00" % day
	_apply_day_fx()
	_menu.hide()
	_box.show()
	if not runner.load_day(day):
		_show_message("%d일 차 대사 파일이 아직 없습니다." % day)
		return
	if play_now:
		SaveManager.autosave_day_start()
		runner.next()
	_refresh_debug()


func _on_day_finished(day: int) -> void:
	if day >= LAST_WRITTEN_DAY:
		_show_message("작성된 대사는 여기까지입니다. (%d일 차)" % day)
		return
	_begin_day(day + 1, true)


func _on_ending(ending_id: String) -> void:
	if _ending_shown:
		return
	_ending_shown = true
	_clear_choices()
	_speaker.text = ""
	_inner.text = ""
	_text.text = "[center]%s[/center]" % ("조기 엔딩 · 폐기 처분" if ending_id == "early" else "엔딩 1 · 축복받은 빈 껍데기")
	_add_choice_button("그날 아침으로 돌아가기", func(): _continue_from(SaveManager.AUTO_SLOT))
	_add_choice_button("타이틀로", _show_title)


# --- 화면 표시 -----------------------------------------------------------------

func _on_line(line: Dictionary) -> void:
	_clear_choices()
	_speaker.text = "" if line.speaker in ["내레이션", "시스템"] else line.speaker
	var body: String = line.text
	if line.type == "독백":
		body = "[i]%s[/i]" % body
	elif line.type == "시스템":
		body = "[center][color=#bbbbbb]%s[/color][/center]" % body
	_text.text = body
	_inner.text = runner.inner_text_of(line)
	for key in line.fx.split(";", false):
		_play_fx(key.strip_edges())
	_refresh_debug()


func _on_choices(choices: Array) -> void:
	_clear_choices()
	for i in choices.size():
		var c: Dictionary = choices[i]
		var red: bool = "text_red" in c.fx
		var b := _add_choice_button(c.text, runner.choose.bind(i))
		if red:
			b.add_theme_color_override("font_color", Color("#ff5a5a"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_debug.visible = not _debug.visible
		return
	if not _box.visible or _menu.visible or _ending_shown or runner.is_waiting_for_choice():
		return
	var advance: bool = event.is_action_pressed("ui_accept") \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if advance:
		runner.next()


func _play_fx(key: String) -> void:
	# 연출은 아직 자리만 잡아둔 상태. 화면 효과 외에는 디버그 표시줄에 키만 띄운다.
	match key:
		"saturation_down":
			pass  # 일차별 채도는 _apply_day_fx에서 적용
		"glitch_short", "noise_short":
			var t := create_tween()
			_bg.color = Color("#dfe7ea")
			t.tween_property(_bg, "color", _garden_color(), 0.25)
	_debug.text = _debug.text.split("\n")[0] + "\n연출: " + key


## 일차가 넘어갈 때 감각 상실 상태를 맞춘다. (2일 차 색채, 6일 차 시야)
func _apply_day_fx() -> void:
	var mat := _fx.material as ShaderMaterial
	mat.set_shader_parameter("saturation", 1.0 if GameState.day < 2 else 0.7)
	mat.set_shader_parameter("vignette", 0.6 if GameState.day >= 6 else 0.0)


func _refresh_debug() -> void:
	_debug.text = "%d회차 %d일 차  |  평온도 %d  의심도 %d  자아 %d  약 거부 %d  |  %s" % [
		GameState.loop, GameState.day, GameState.peace, GameState.suspicion,
		GameState.clarity, GameState.pills_skipped, GameState.scene_id]


func _show_title() -> void:
	_box.hide()
	_clear_choices()
	for c in _menu.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "해무장"
	title.add_theme_font_size_override("font_size", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(title)
	_menu_button("새로 시작 (1회차)", _start_new.bind(1))
	_menu_button("2회차로 시작 (개발용)", _start_new.bind(2))
	if SaveManager.has_slot(SaveManager.AUTO_SLOT):
		var info := SaveManager.slot_info(SaveManager.AUTO_SLOT)
		_menu_button("이어하기 (%d회차 %d일 차)" % [info.loop, info.day], _continue_from.bind(SaveManager.AUTO_SLOT))
	_menu.show()


func _show_message(msg: String) -> void:
	_clear_choices()
	_speaker.text = ""
	_inner.text = ""
	_text.text = "[center]%s[/center]" % msg
	_add_choice_button("타이틀로", _show_title)


# --- UI 만들기 -----------------------------------------------------------------

func _garden_color() -> Color:
	return Color("#6f8f74")


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg = ColorRect.new()
	_bg.color = _garden_color()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_menu = VBoxContainer.new()
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.custom_minimum_size = Vector2(360, 0)
	_menu.position = Vector2(-180, -120)
	_menu.add_theme_constant_override("separation", 12)
	add_child(_menu)

	_box = PanelContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_box.offset_top = -260
	_box.offset_left = 40
	_box.offset_right = -40
	_box.offset_bottom = -30
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_box.add_child(v)
	_speaker = Label.new()
	_speaker.add_theme_font_size_override("font_size", 22)
	v.add_child(_speaker)
	_text = _rich(24)
	v.add_child(_text)
	_inner = _rich(20)
	_inner.add_theme_color_override("default_color", Color("#ff5a5a"))
	v.add_child(_inner)
	_choices = VBoxContainer.new()
	v.add_child(_choices)

	# 화면 효과 층: 모든 그림 위, 디버그 표시줄 아래
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 10
	add_child(fx_layer)
	_fx = ColorRect.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/screen_fx.gdshader")
	_fx.material = mat
	fx_layer.add_child(_fx)

	var debug_layer := CanvasLayer.new()
	debug_layer.layer = 20
	add_child(debug_layer)
	_debug = Label.new()
	_debug.position = Vector2(12, 8)
	_debug.add_theme_color_override("font_color", Color.WHITE)
	_debug.add_theme_color_override("font_outline_color", Color.BLACK)
	_debug.add_theme_constant_override("outline_size", 4)
	debug_layer.add_child(_debug)


func _rich(size: int) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _menu_button(label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(cb)
	_menu.add_child(b)


func _add_choice_button(label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	_choices.add_child(b)
	return b


func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()
