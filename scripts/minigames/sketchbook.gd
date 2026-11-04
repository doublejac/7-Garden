# sketchbook.gd
# 그림 그리기 놀이: 스케치북에 마우스로 크레용 그림을 그린다.
#   왼쪽 버튼 끌기: 그리기   오른쪽 버튼 끌기: 지우기   크레용·굵기·지우개·전부 지우기·다 그렸어 버튼
#   color_loss = true면 도화지와 크레용이 흑백으로 보인다 (실제 칠한 색은 그대로 저장됨: 색채 상실 연출)
# 다 그리면 finished(그림, 비었는지)를 보내고, 그림은 user://drawings/ 에 PNG로 남긴다.
# 채린의 반응은 pick_reaction()으로 data/minigames/chaerin_drawing.json에서 무작위로 고른다.
class_name Sketchbook
extends Control

signal finished(drawing: Image, empty: bool, saved_path: String)

const CANVAS_SIZE := Vector2i(880, 560)
const PAPER := Color("#fbf8f0")
const CRAYONS := [
	["빨강", Color("#d83a3a")], ["주황", Color("#f08a2c")], ["노랑", Color("#f2cf2e")],
	["연두", Color("#8cc63e")], ["초록", Color("#2f8f4e")], ["하늘", Color("#5cb8e6")],
	["파랑", Color("#2f5fb8")], ["보라", Color("#8a55c0")], ["분홍", Color("#f29ab8")],
	["갈색", Color("#8a5a32")], ["회색", Color("#8c8c8c")], ["검정", Color("#2a2a2a")],
]
const SIZES := [["가늘게", 4], ["보통", 9], ["굵게", 18]]
const REACTIONS := "res://data/minigames/chaerin_drawing.json"

@export var color_loss := false
@export var prompt_text := "채린: 언니, 우리 같이 그림 그리자! 아무거나 좋아."

var canvas: Image
var canvas_tex: ImageTexture
var canvas_rect: TextureRect
var color := Color("#2f5fb8")
var radius := 9
var erasing := false
var strokes := 0
var _drawing := false
var _last := Vector2.ZERO
var _dirty := false
var _brushes := {}                 # (색, 반지름) → 크레용 붓 그림
var _swatches: Array[Button] = []
var _size_buttons: Array[Button] = []
var _eraser_button: Button
var _gray: ShaderMaterial
static var _last_reaction := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gray = ShaderMaterial.new()
	_gray.shader = load("res://shaders/grayscale.gdshader")
	_gray.set_shader_parameter("amount", 1.0 if color_loss else 0.0)
	canvas = Image.create_empty(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(PAPER)   # 도화지를 불투명하게 깔고 그 위에 섞음 (투명 위에 섞으면 색이 탁해짐)
	canvas_tex = ImageTexture.create_from_image(canvas)
	_build_ui()
	_select_color(6)
	_select_size(1)


func _process(_delta: float) -> void:
	if _dirty:
		canvas_tex.update(canvas)
		_dirty = false


# ── 그리기 ────────────────────────────────────────────────
func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if event.pressed:
			_drawing = true
			var erase_now: bool = erasing or event.button_index == MOUSE_BUTTON_RIGHT
			set_meta("erase_now", erase_now)
			_last = _to_canvas(event.position)
			_stamp(_last, erase_now)
			if not erase_now:
				strokes += 1
		else:
			_drawing = false
	elif event is InputEventMouseMotion and _drawing:
		var p := _to_canvas(event.position)
		var erase_now: bool = get_meta("erase_now", false)
		var step := maxf(1.0, radius * 0.35)
		var d := _last.distance_to(p)
		var n := int(d / step)
		for i in range(1, n + 1):
			_stamp(_last.lerp(p, float(i) / n), erase_now)
		if n > 0:
			_last = p


func _to_canvas(local: Vector2) -> Vector2:
	return local / canvas_rect.size * Vector2(CANVAS_SIZE)


func _stamp(p: Vector2, erase_now: bool) -> void:
	var r := radius * (2 if erase_now else 1)
	var pos := Vector2i(int(p.x) - r, int(p.y) - r)
	var m := _mask(r, not erase_now, randi() % 3)
	var src := _solid(PAPER if erase_now else color, m.get_width())
	# 색을 섞지 않고 그대로 찍음 (반투명으로 섞으면 색이 탁해짐). 빈틈 있는 모양이라 겹칠수록 꽉 차서 크레용처럼 보임
	canvas.blit_rect_mask(src, m, Rect2i(Vector2i.ZERO, m.get_size()), pos)
	_dirty = true


## 붓 모양: 동그라미. 크레용이면 가장자리가 거칠고 안쪽에 종이 결 같은 빈틈 (세 가지 무늬를 번갈아)
func _mask(r: int, crayon: bool, variant: int) -> Image:
	var key := "m_%d_%s_%d" % [r, crayon, variant]
	if _brushes.has(key):
		return _brushes[key]
	var s := r * 2 + 1
	var img := Image.create_empty(s, s, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for y in s:
		for x in s:
			var d := Vector2(x - r, y - r).length()
			var edge := r - (rng.randf() * 1.8 if crayon else 0.0)
			if d <= edge and (not crayon or rng.randf() < 0.72):
				img.set_pixel(x, y, Color.WHITE)
	_brushes[key] = img
	return img


func _solid(c: Color, size: int) -> Image:
	var key := "s_%s_%d" % [c.to_html(), size]
	if not _brushes.has(key):
		var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		img.fill(c)
		_brushes[key] = img
	return _brushes[key]


func clear_all() -> void:
	canvas.fill(PAPER)
	strokes = 0
	_dirty = true


func is_empty() -> bool:
	return strokes == 0


func _finish() -> void:
	var out: Image = canvas.duplicate()
	var path := ""
	if not is_empty():
		DirAccess.make_dir_recursive_absolute("user://drawings")
		path = "user://drawings/drawing_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
		out.save_png(path)
	finished.emit(out, is_empty(), path)


## 채린의 반응 하나: {text, inner}. 방금 나온 칭찬은 연달아 나오지 않게
static func pick_reaction(empty: bool) -> Dictionary:
	var data: Dictionary = (load(REACTIONS) as JSON).data
	var pool: Array = data["empty" if empty else "praise"]
	if empty:
		return pool[randi() % pool.size()]
	var i := randi() % pool.size()
	if pool.size() > 1 and i == _last_reaction:
		i = (i + 1 + randi() % (pool.size() - 1)) % pool.size()
	_last_reaction = i
	return pool[i]


# ── 화면 ──────────────────────────────────────────────────
func _select_color(i: int) -> void:
	color = CRAYONS[i][1]
	erasing = false
	for j in _swatches.size():
		_swatches[j].custom_minimum_size = Vector2(64, 40) if j == i else Vector2(52, 40)
	_eraser_button.button_pressed = false


func _select_size(i: int) -> void:
	radius = SIZES[i][1]
	for j in _size_buttons.size():
		_size_buttons[j].button_pressed = j == i


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	center.add_child(root)

	# 스케치북: 위쪽 스프링 + 도화지
	var book := VBoxContainer.new()
	book.add_theme_constant_override("separation", 0)
	root.add_child(book)
	var tip := Label.new()
	tip.text = prompt_text
	tip.add_theme_font_size_override("font_size", 20)
	tip.add_theme_color_override("font_color", Color.WHITE)
	tip.add_theme_color_override("font_outline_color", Color.BLACK)
	tip.add_theme_constant_override("outline_size", 5)
	book.add_child(tip)
	var spiral := _rings()
	book.add_child(spiral)
	var paper := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = PAPER
	ps.border_color = Color("#c9bfa8")
	ps.set_border_width_all(2)
	ps.shadow_color = Color(0, 0, 0, 0.35)
	ps.shadow_size = 10
	paper.add_theme_stylebox_override("panel", ps)
	paper.custom_minimum_size = Vector2(CANVAS_SIZE)
	if color_loss:
		paper.material = _gray
	book.add_child(paper)
	canvas_rect = TextureRect.new()
	canvas_rect.texture = canvas_tex
	canvas_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas_rect.stretch_mode = TextureRect.STRETCH_SCALE
	canvas_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	if color_loss:
		canvas_rect.material = _gray
	canvas_rect.gui_input.connect(_on_canvas_input)
	paper.add_child(canvas_rect)

	# 오른쪽 도구: 크레용 · 굵기 · 지우개 · 전부 지우기 · 다 그렸어
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	root.add_child(tools)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	tools.add_child(grid)
	for i in CRAYONS.size():
		var b := Button.new()
		b.tooltip_text = CRAYONS[i][0]
		var sb := StyleBoxFlat.new()
		sb.bg_color = CRAYONS[i][1]
		sb.set_corner_radius_all(6)
		sb.corner_radius_top_right = 16   # 크레용 끝 모양
		sb.border_color = Color(0, 0, 0, 0.35)
		sb.set_border_width_all(1)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, sb)
		if color_loss:
			b.material = _gray
		b.pressed.connect(_select_color.bind(i))
		grid.add_child(b)
		_swatches.append(b)
	tools.add_child(HSeparator.new())
	for i in SIZES.size():
		var b := Button.new()
		b.text = SIZES[i][0]
		b.toggle_mode = true
		b.pressed.connect(_select_size.bind(i))
		tools.add_child(b)
		_size_buttons.append(b)
	_eraser_button = Button.new()
	_eraser_button.text = "지우개"
	_eraser_button.toggle_mode = true
	_eraser_button.toggled.connect(func(on): erasing = on)
	tools.add_child(_eraser_button)
	var clear := Button.new()
	clear.text = "전부 지우기"
	clear.pressed.connect(clear_all)
	tools.add_child(clear)
	tools.add_child(HSeparator.new())
	var done := Button.new()
	done.text = "다 그렸어!"
	done.custom_minimum_size = Vector2(0, 52)
	done.pressed.connect(_finish)
	tools.add_child(done)


## 스케치북 위쪽 스프링 고리
func _rings() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(CANVAS_SIZE.x, 22)
	c.draw.connect(func():
		c.draw_rect(Rect2(0, 8, CANVAS_SIZE.x, 14), Color("#3d4a5c"))
		for i in range(24, CANVAS_SIZE.x - 10, 34):
			c.draw_arc(Vector2(i, 10), 8, PI, TAU, 12, Color("#c8c8c8"), 3.0)
	)
	return c
