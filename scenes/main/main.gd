# main.gd
# 개발용 대사 재생기. 그림 없이 1~4일 차 대사를 텍스트로 돌려보며 분기와 수치를 확인한다.
# 클릭 / 스페이스 / 엔터: 다음 줄   F1: 디버그 수치 표시 켜고 끄기
# 일러스트: 대사 줄의 fx에 cg:<파일 이름> 이면 assets/art/cg/<이름>.jpg를 띄우고, cg_off 면 내림
# 그림책: fx에 book:<시작>-<끝> (예: book:3-4, 이야기 장면 번호. 책에 찍힌 페이지로는 장면 k = 2k·2k+1페이지) 이면 그 줄을 보여 준 뒤, 다음 클릭에 채린에게 그 쪽들을 읽어 줌.
#         책을 덮으면 다음 대사로 이어짐. 밤마다 읽을 쪽은 data/storybook/nubi.json의 nights
# 캡슐 숨기기: fx에 capsule 이면 그 줄 다음 클릭에 미니게임. 결과 수치(CapsuleTrick.RESULT_STATS)를 적용하고 다음 대사로
extends Control

const LAST_WRITTEN_DAY := 4   # 대사를 작성한 마지막 일차
const CG_DIR := "res://assets/art/cg/"
const CG_FADE := 0.6

var runner := DialogueRunner.new()

var _bg: ColorRect
var _cg: TextureRect
var _cg_tween: Tween
var _gallery: PackedStringArray = []   # 일러스트 보기(개발용)에서 넘겨 볼 이름들
var _gallery_i := -1
var _gallery_label: Label
var _sketch: Sketchbook
var _after_sketch := false   # 그림 놀이 뒤 채린 반응을 보여 주는 중 (클릭하면 타이틀로)
var _pending_book := ""      # 다음 클릭에 펼칠 그림책 쪽 범위 ("3-4")
var _book_open := false
var _pending_capsule := false
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
	_begin_day(0, true)   # 0일 차 = 프롤로그 (백화증 안내 → 진료실 → 차 안 → 해무장 입구), 끝나면 1일 차


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
	_hide_cg(false)
	GameState.day = day
	GameState.scene_id = "D%d_S00" % day
	_apply_day_fx()
	_menu.hide()
	_box.show()
	if not runner.load_day(day):
		_show_message("%s 대사 파일이 아직 없습니다." % _day_name(day))
		return
	if play_now:
		SaveManager.autosave_day_start()
		runner.next()
	_refresh_debug()


func _day_name(day: int) -> String:
	return "프롤로그" if day == 0 else "%d일 차" % day


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
	if _book_open:
		return
	if _gallery_i >= 0:
		_gallery_input(event)
		return
	if _after_sketch:
		if event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			_after_sketch = false
			_show_title()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		_debug.visible = not _debug.visible
		return
	if not _box.visible or _menu.visible or _ending_shown or runner.is_waiting_for_choice():
		return
	var advance: bool = event.is_action_pressed("ui_accept") \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if advance:
		if _pending_capsule:
			_pending_capsule = false
			_play_capsule(func(): runner.next())
			return
		if _pending_book != "":
			var r := _pending_book.split("-")
			_pending_book = ""
			_read_book(int(r[0]), int(r[r.size() - 1]), GameState.flags.get("inner_text", false), false, func(): runner.next())
			return
		runner.next()


func _play_fx(key: String) -> void:
	# 연출은 아직 자리만 잡아둔 상태. 화면 효과 외에는 디버그 표시줄에 키만 띄운다.
	if key.begins_with("cg:"):
		_show_cg(key.substr(3))
	if key == "capsule":
		_pending_capsule = true
	if key.begins_with("book:"):
		_pending_book = key.substr(5)
	match key:
		"cg_off":
			_hide_cg()
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
	_debug.text = "%d회차 %s  |  평온도 %d  의심도 %d  자아 %d  약 거부 %d  |  %s" % [
		GameState.loop, _day_name(GameState.day), GameState.peace, GameState.suspicion,
		GameState.clarity, GameState.pills_skipped, GameState.scene_id]


# --- 일러스트 ------------------------------------------------------------------

func _show_cg(cg_name: String, animate := true) -> void:
	var path := CG_DIR + cg_name + ".jpg"
	if not ResourceLoader.exists(path):
		push_warning("일러스트 없음: " + path)
		return
	_cg.texture = load(path)
	_cg.show()
	if _cg_tween:
		_cg_tween.kill()
	if animate:
		_cg.modulate.a = 0.0
		_cg_tween = create_tween()
		_cg_tween.tween_property(_cg, "modulate:a", 1.0, CG_FADE)
	else:
		_cg.modulate.a = 1.0


func _hide_cg(animate := true) -> void:
	if _cg_tween:
		_cg_tween.kill()
	if not animate or not _cg.visible:
		_cg.hide()
		return
	_cg_tween = create_tween()
	_cg_tween.tween_property(_cg, "modulate:a", 0.0, CG_FADE)
	_cg_tween.tween_callback(_cg.hide)


## 개발용: assets/art/cg의 일러스트를 하나씩 넘겨 봄. 클릭·스페이스 다음, Esc·오른쪽 클릭 타이틀로
func _open_gallery() -> void:
	_gallery = PackedStringArray()
	for f in DirAccess.get_files_at(CG_DIR):
		f = f.trim_suffix(".import")
		if f.ends_with(".jpg") and not _gallery.has(f.get_basename()):
			_gallery.append(f.get_basename())
	_gallery.sort()
	if _gallery.is_empty():
		return
	_menu.hide()
	_gallery_i = 0
	_gallery_label.show()
	_show_gallery_item()


func _show_gallery_item() -> void:
	_show_cg(_gallery[_gallery_i])
	_gallery_label.text = "%s   (%d / %d)   클릭: 다음 · Esc: 타이틀" % [_gallery[_gallery_i], _gallery_i + 1, _gallery.size()]


func _gallery_input(event: InputEvent) -> void:
	var back: bool = event.is_action_pressed("ui_cancel") \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)
	var advance: bool = event.is_action_pressed("ui_accept") \
			or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if back or (advance and _gallery_i == _gallery.size() - 1):
		_gallery_i = -1
		_gallery_label.hide()
		_hide_cg(false)
		_show_title()
	elif advance:
		_gallery_i += 1
		_show_gallery_item()


## 채린의 그림동화. found_torn = 2회차에 찢긴 마지막 장을 찾은 뒤
func _open_storybook(found_torn: bool) -> void:
	_menu.hide()
	_book_open = true
	var book := Storybook.new()
	book.found_torn = found_torn
	add_child(book)
	book.closed.connect(func():
		_book_open = false
		_show_title())


## 채린에게 그림책 읽어 주기: from~to 쪽만. 덮으면 읽은 데까지 기록하고 after 호출
func _read_book(from: int, to: int, inner: bool, dev_reveal: bool, after: Callable) -> void:
	_book_open = true
	_box.hide()
	_menu.hide()
	var book := Storybook.new()
	book.found_torn = GameState.flags.get("found_torn", false)
	book.page_from = from
	book.page_to = to
	book.reactions = true
	book.show_inner = inner
	book.always_reveal = dev_reveal
	add_child(book)
	book.closed.connect(func():
		GameState.book_read = maxi(GameState.book_read, book.furthest)
		_book_open = false
		_box.show()
		after.call())


## 캡슐 숨기기 미니게임. 의심도가 높을수록 원장이 눈을 짧게 돌림
func _play_capsule(after: Callable) -> void:
	_book_open = true
	_box.hide()
	_menu.hide()
	var g := CapsuleTrick.new()
	g.difficulty = clampf(0.2 + GameState.suspicion / 100.0, 0.0, 1.0)
	add_child(g)
	g.finished.connect(func(result: String):
		GameState.apply_stat_string(CapsuleTrick.RESULT_STATS[result])
		_book_open = false
		_box.show()
		_refresh_debug()
		after.call())


## 물건 3D로 살펴보기 (show_secret = 2회차 숨은 단서)
func _inspect(id: String, secret: bool) -> void:
	_book_open = true
	_menu.hide()
	var v := Inspect3D.new()
	v.item_id = id
	v.show_secret = secret
	add_child(v)
	v.closed.connect(func():
		_book_open = false
		_show_title())


## 그림 그리기 놀이. 다 그리면 채린의 반응 (2회차면 붉은 속마음도)
func _open_sketch(color_loss: bool, loop: int) -> void:
	_menu.hide()
	_box.hide()
	_sketch = Sketchbook.new()
	_sketch.color_loss = color_loss
	add_child(_sketch)
	_sketch.finished.connect(func(_img: Image, empty: bool, _path: String):
		_sketch.queue_free()
		var r := Sketchbook.pick_reaction(empty)
		_clear_choices()
		_box.show()
		_speaker.text = "유채린"
		_text.text = r["text"]
		_inner.text = r["inner"] if loop > 1 else ""
		_after_sketch = true)


func _show_title() -> void:
	_hide_cg(false)
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
	if SaveManager.has_slot(SaveManager.AUTO_SLOT):
		var info := SaveManager.slot_info(SaveManager.AUTO_SLOT)
		_menu_button("이어하기 (%d회차 %s)" % [info.loop, _day_name(info.day)], _continue_from.bind(SaveManager.AUTO_SLOT))

	# 개발용 버튼: 작게 2열로 모아서 화면 밖으로 넘치지 않게
	var dev_label := Label.new()
	dev_label.text = "개발용"
	dev_label.add_theme_font_size_override("font_size", 14)
	dev_label.modulate = Color(1, 1, 1, 0.6)
	dev_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(dev_label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_menu.add_child(grid)
	_dev_button(grid, "2회차로 시작", _start_new.bind(2))
	_dev_button(grid, "일러스트 보기", _open_gallery)
	_dev_button(grid, "그림책 보기", _open_storybook.bind(false))
	_dev_button(grid, "그림책 · 찢긴 장 찾음", _open_storybook.bind(true))
	_dev_button(grid, "읽어 주기 · 첫날 밤 (2~7페이지)", func(): _read_book(1, 3, false, true, _show_title))
	_dev_button(grid, "읽어 주기 · 2회차 (10~13페이지)", func(): _read_book(5, 6, true, true, _show_title))
	_dev_button(grid, "캡슐 숨기기 (2회차 투약)", func(): _play_capsule(_show_title))
	_dev_button(grid, "살펴보기 · 곰돌이", _inspect.bind("teddy", false))
	_dev_button(grid, "살펴보기 · 곰돌이 · 2회차", _inspect.bind("teddy", true))
	_dev_button(grid, "그림 그리기", _open_sketch.bind(false, 1))
	_dev_button(grid, "그림 그리기 · 2회차", _open_sketch.bind(true, 2))
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
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # 화면 클릭이 _unhandled_input까지 오게 (대사 넘기기·일러스트 넘기기)
	_bg = ColorRect.new()
	_bg.color = _garden_color()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# 일러스트: 배경 위, 대사 상자 아래. 화면을 꽉 채우고 넘치는 부분은 잘라냄
	_cg = TextureRect.new()
	_cg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cg.hide()
	add_child(_cg)

	_menu = VBoxContainer.new()
	# 화면 가운데 기준으로 위아래·좌우로 똑같이 늘어남 (버튼 수가 바뀌어도 가운데 유지)
	_menu.set_anchors_preset(Control.PRESET_CENTER)
	_menu.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	_menu.custom_minimum_size = Vector2(420, 0)
	_menu.add_theme_constant_override("separation", 10)
	add_child(_menu)

	_box = PanelContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_box.offset_top = -170           # 대사 두세 줄 높이. 선택지가 많으면 위로 늘어남 (일러스트를 덜 가리게)
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
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
	_gallery_label = Label.new()
	_gallery_label.position = Vector2(12, 40)
	_gallery_label.add_theme_color_override("font_color", Color.WHITE)
	_gallery_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_gallery_label.add_theme_constant_override("outline_size", 4)
	_gallery_label.hide()
	debug_layer.add_child(_gallery_label)


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


func _dev_button(parent: Control, label: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 34)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	parent.add_child(b)


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
