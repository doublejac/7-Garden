# storybook.gd
# 채린의 그림동화 「누비각시와 아홉 개의 껍데기」를 책처럼 펼쳐 읽는 화면.
#   닫힌 표지 → 클릭하면 표지가 넘어가며 펼쳐짐 → 왼쪽 쪽 그림, 오른쪽 쪽 글 → 쪽 넘김
#   클릭·→·스페이스·엔터: 다음   오른쪽 클릭·←·백스페이스: 앞   Esc: 덮기
# 1회차(found_torn = false): 14쪽 다음은 제본선에 찢긴 자국만 남은 쪽 + 뒤표지 안쪽 글 한 줄
# 찢긴 장을 찾은 뒤(found_torn = true): 15·16쪽이 접혔던 자국과 찢긴 가장자리가 있는 누런 종이로 붙음
# 글·그림: data/storybook/nubi.json, assets/art/storybook/<이름>.jpg
#
# 밤에 읽어 주기 (page_from·page_to > 0): 그날 읽을 쪽만 펼쳐짐
#   page_from > 1이면 표지 아래로 가름끈이 나와 있고, 펼치면 가름끈 꽂힌 쪽부터 시작
#   page_to 쪽을 다 읽고 넘기면 책을 덮음 (오늘은 여기까지)
#   reactions = true면 책이 조금 위로 물러나고 아래에 채린의 반응 한마디 (show_inner면 붉은 속마음도)
# 처음 읽는 쪽(SaveManager.meta.book_seen에 없는 쪽)은 글이 천천히 나타남. 클릭하면 바로 다 보임
class_name Storybook
extends Control

signal closed

const DATA := "res://data/storybook/nubi.json"
const ART := "res://assets/art/storybook/"
const PAGE := Vector2(580, 640)
const SPINE_X := 640.0
const TOP := 40.0
const BOARD_PAD := 14.0
const TURN := 0.3                       # 쪽 넘김 반쪽 시간(초)
const PAPER := Color("#fdf0de")         # 그림 속 종이색과 같게
const ENDPAPER := Color("#c6d1cd")      # 앞뒤 면지 (바랜 바다색)
const CLOTH := Color("#2c4146")         # 표지 천
const INK := Color("#3b342e")
const SHELL := Color("#e8743b")

@export var found_torn := false
@export var page_from := 0             # 0 = 처음부터 (표지 → 면지·속표지)
@export var page_to := 0               # 0 = 끝까지
@export var reactions := false         # 채린에게 읽어 주는 중 (반응 대사)
@export var show_inner := false        # 반응 아래 붉은 속마음
@export var always_reveal := false      # 개발용: 읽은 쪽도 글이 천천히 나타나게

const REVEAL_CPS := 26.0               # 처음 읽을 때 글 나타나는 속도 (글자/초)
const RIBBON := Color("#8e4a3a")       # 가름끈 (바랜 주홍)
const READ_SCALE := 0.84               # 반응 대사 자리를 내려고 책을 줄이는 비율

var furthest := 0                      # 이번에 글을 끝까지 본 마지막 쪽 번호

var data: Dictionary
var spreads: Array = []                 # [[왼쪽 쪽, 오른쪽 쪽], ...]  각 쪽 = {kind, ...}
var index := -1                         # -1 = 닫힌 표지
var busy := false
var font: FontFile
var font_bold: FontFile

var _book: Control
var _left_board: Panel
var _right_board: Panel
var _stacks: Control
var _left_slot: Control
var _right_slot: Control
var _anim: Control
var _cover: Control
var _hint: Label
var _lo := 0                            # 넘길 수 있는 펼침면 범위
var _hi := 0
var _ribbon: Control
var _reveal: Tween
var _reveal_body: RichTextLabel
var _reveal_page := 0
var _react_box: PanelContainer
var _react_text: Label
var _react_inner: Label
var _react_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	data = (load(DATA) as JSON).data
	font = load("res://assets/fonts/NotoSerifKR-Regular.otf")
	font_bold = load("res://assets/fonts/NotoSerifKR-SemiBold.otf")
	_build_spreads()
	_build_scene()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)


# ── 펼침면 목록 ────────────────────────────────────────────
func _build_spreads() -> void:
	spreads.append([{"kind": "endpaper"}, {"kind": "title"}])
	var n := 0
	var last_story := 0
	for i in data["pages"].size():
		var p: Dictionary = data["pages"][i]
		if p.get("torn", false) and not found_torn:
			continue
		n += 1
		last_story = i + 1
		var torn: bool = p.get("torn", false)
		spreads.append([
			{"kind": "image", "image": p["image"], "num": n * 2, "torn": torn},
			{"kind": "text", "text": p["text"], "num": n * 2 + 1, "torn": torn, "page": i + 1,
				"react": p.get("react", ""), "react_inner": p.get("react_inner", "")}])
	if found_torn:
		spreads.append([{"kind": "endpaper"}, {"kind": "back"}])
	else:
		spreads.append([{"kind": "stub"}, {"kind": "back"}])
	# 쪽 번호 k(1~16)의 펼침면은 spreads[k] (찢긴 장이 빠져도 앞 14쪽은 그대로)
	_lo = clampi(page_from, 0, last_story) if page_from > 1 else 0
	_hi = spreads.size() - 1
	if page_to > 0 and page_to < last_story:
		_hi = page_to


# ── 화면 ──────────────────────────────────────────────────
func _build_scene() -> void:
	var table := ColorRect.new()                     # 책을 올려 둔 어두운 탁자
	table.color = Color(0.08, 0.07, 0.06, 0.94)
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(table)
	var lamp := TextureRect.new()                    # 책 위로 떨어지는 스탠드 불빛
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.45)
	g.fill_to = Vector2(1.0, 0.45)
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.86, 0.62, 0.16))
	grad.set_color(1, Color(1.0, 0.86, 0.62, 0.0))
	g.gradient = grad
	lamp.texture = g
	lamp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lamp)

	_book = Control.new()
	_book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_book)
	_left_board = _board(Rect2(SPINE_X - PAGE.x - BOARD_PAD, TOP - BOARD_PAD, PAGE.x + BOARD_PAD, PAGE.y + BOARD_PAD * 2), true)
	_right_board = _board(Rect2(SPINE_X, TOP - BOARD_PAD, PAGE.x + BOARD_PAD, PAGE.y + BOARD_PAD * 2), false)
	_stacks = Control.new()
	_stacks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stacks.draw.connect(_draw_stacks)
	_book.add_child(_stacks)
	_left_slot = _slot(Vector2(SPINE_X - PAGE.x, TOP))
	_right_slot = _slot(Vector2(SPINE_X, TOP))
	var gutter := ColorRect.new()                    # 제본선의 깊은 그늘
	gutter.color = Color(0, 0, 0, 0.0)
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gutter.position = Vector2(SPINE_X - 3, TOP)
	gutter.size = Vector2(6, PAGE.y)
	gutter.draw.connect(func():
		for i in 6:
			gutter.draw_line(Vector2(i + 0.5, 0), Vector2(i + 0.5, PAGE.y), Color(0.1, 0.07, 0.05, 0.28 - absf(i - 2.5) * 0.08), 1.0))
	_book.add_child(gutter)
	_anim = Control.new()
	_anim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(_anim)
	_left_board.visible = false
	_left_slot.visible = false
	gutter.visible = false
	gutter.set_meta("gutter", true)
	_ribbon = Control.new()                         # 가름끈: 오늘 읽기 시작하는 쪽 제본선에 끼워 둔 끈
	_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ribbon.draw.connect(_draw_ribbon)
	_ribbon.visible = false
	_book.add_child(_ribbon)
	_cover = _make_cover()
	_book.add_child(_cover)
	_set_spread_content(_lo)
	if reactions:
		_book.pivot_offset = Vector2(SPINE_X, 0)
		_book.scale = Vector2.ONE * READ_SCALE
		_book.position.y = 8
		_build_reaction_box()

	_hint = Label.new()
	_hint.text = "클릭: 넘기기 · 오른쪽 클릭: 앞으로 · Esc: 덮기"
	_hint.add_theme_font_override("font", font)
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_hint.position = Vector2(0, 4 if reactions else 694)
	_hint.size = Vector2(1280, 20)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)


func _board(r: Rect2, left: bool) -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CLOTH
	sb.corner_radius_top_left = 6 if left else 0
	sb.corner_radius_bottom_left = 6 if left else 0
	sb.corner_radius_top_right = 0 if left else 6
	sb.corner_radius_bottom_right = 0 if left else 6
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 8)
	p.add_theme_stylebox_override("panel", sb)
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(p)
	return p


func _slot(pos: Vector2) -> Control:
	var c := Control.new()
	c.position = pos
	c.size = PAGE
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(c)
	return c


## 책 옆면에 보이는 종이 겹: 읽은 쪽은 왼쪽에, 남은 쪽은 오른쪽에 두꺼워짐
func _draw_stacks() -> void:
	if index < 0:
		return
	var total := spreads.size() - 1
	var left_n := clampi(roundi(float(index) / total * 7.0), 1, 7)
	var right_n := clampi(roundi(float(total - index) / total * 7.0), 1, 7)
	for k in range(left_n, 0, -1):
		var r := Rect2(SPINE_X - PAGE.x - k * 1.6, TOP + k * 0.9, PAGE.x, PAGE.y)
		_stacks.draw_rect(r, PAPER.darkened(0.12 + k * 0.02))
		_stacks.draw_rect(r, Color(0, 0, 0, 0.12), false, 1.0)
	for k in range(right_n, 0, -1):
		var r := Rect2(SPINE_X + k * 1.6, TOP + k * 0.9, PAGE.x, PAGE.y)
		_stacks.draw_rect(r, PAPER.darkened(0.12 + k * 0.02))
		_stacks.draw_rect(r, Color(0, 0, 0, 0.12), false, 1.0)


func _set_spread_content(i: int) -> void:
	_fill(_left_slot, _make_page(spreads[i][0], -1))
	_fill(_right_slot, _make_page(spreads[i][1], 1))


func _fill(slot: Control, page: Control) -> void:
	for c in slot.get_children():
		c.queue_free()
	slot.add_child(page)


# ── 쪽 만들기 ─────────────────────────────────────────────
## side: -1 왼쪽 쪽(제본선이 오른쪽), 1 오른쪽 쪽(제본선이 왼쪽)
func _make_page(spec: Dictionary, side: int) -> Control:
	var page := Control.new()
	page.size = PAGE
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kind: String = spec["kind"]
	var torn: bool = spec.get("torn", false)
	var paper := ColorRect.new()
	paper.size = PAGE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.material = _paper_mat(ENDPAPER if kind in ["endpaper", "back"] else PAPER, side, false, 0.55 if torn else 0.0, spec.get("num", 0))
	page.add_child(paper)
	match kind:
		"image":
			var img := TextureRect.new()
			img.texture = load(ART + spec["image"] + ".jpg")
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.position = Vector2(30, 120)
			img.size = Vector2(PAGE.x - 60, (PAGE.x - 60) * 0.7464)
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if torn:
				img.modulate = Color(0.97, 0.92, 0.84)
			var im := ShaderMaterial.new()        # 종이에 스며든 그림 (사각 테두리 없이)
			im.shader = load("res://shaders/book_image.gdshader")
			im.set_shader_parameter("seed", float(spec.get("num", 0)))
			img.material = im
			page.add_child(img)
		"text":
			_add_text_page(page, spec["text"])
			if _needs_reveal(spec.get("page", 0)):
				_body_of(page).visible_ratio = 0.0
		"title":
			_add_title_page(page)
		"endpaper":
			page.add_child(_pattern())
		"back":
			page.add_child(_pattern())
			_add_back_line(page)
	if kind == "stub":
		var stubs := Control.new()
		stubs.size = PAGE
		stubs.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stubs.draw.connect(_draw_stub.bind(stubs))
		page.add_child(stubs)
	var shade := ColorRect.new()
	shade.size = PAGE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.material = _paper_mat(PAPER, side, true, 0.0, 0)
	page.add_child(shade)
	if spec.has("num"):
		var num := _label(str(spec["num"]), 14, Color(INK, 0.6), font)
		num.position = Vector2(40 if side < 0 else PAGE.x - 80, PAGE.y - 44)
		num.size = Vector2(40, 20)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side < 0 else HORIZONTAL_ALIGNMENT_RIGHT
		page.add_child(num)
	if torn:
		var marks := Control.new()
		marks.size = PAGE
		marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marks.draw.connect(_draw_torn_marks.bind(marks, side))
		page.add_child(marks)
	return page


func _paper_mat(c: Color, side: int, overlay: bool, age: float, seed: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/book_paper.gdshader")
	m.set_shader_parameter("base_color", c)
	m.set_shader_parameter("spine_side", float(side))
	m.set_shader_parameter("overlay", overlay)
	m.set_shader_parameter("age", age)
	m.set_shader_parameter("size_px", PAGE)
	m.set_shader_parameter("seed", float(seed))
	return m


func _label(t: String, size: int, col: Color, f: Font) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _add_text_page(page: Control, text: String) -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(72, 60)
	box.size = Vector2(PAGE.x - 144, PAGE.y - 130)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(box)
	box.add_child(_ornament(false))
	var body := RichTextLabel.new()
	body.text = _keep_words(text)
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(PAGE.x - 144, 0)
	body.add_theme_font_override("normal_font", font)
	body.add_theme_font_size_override("normal_font_size", 22)
	body.add_theme_color_override("default_color", INK)
	body.add_theme_constant_override("line_separation", 11)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	body.set_meta("story_body", true)
	box.add_child(body)
	box.add_child(_ornament(true))


## 한국어 책처럼 낱말 중간이 아니라 띄어쓰기에서만 줄을 바꿈 (글자 사이에 줄바꿈 금지 문자 U+2060)
func _keep_words(t: String) -> String:
	var out := ""
	for i in t.length():
		var ch := t[i]
		if i > 0 and not (ch in [" ", "\n"]) and not (t[i - 1] in [" ", "\n"]):
			out += "\u2060"
		out += ch
	return out


func _add_title_page(page: Control) -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(50, 70)
	box.size = Vector2(PAGE.x - 100, PAGE.y - 170)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(box)
	var sub := _label(data["subtitle"], 18, Color(INK, 0.6), font)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	var title := _label("누비각시와\n아홉 개의 껍데기", 38, INK, font_bold)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("line_spacing", 6)
	box.add_child(title)
	box.add_child(_ornament(false))
	# 책 주인이 연필로 적어 둔 이름
	var owner := _label("유채린", 20, Color("#6e7a86"), font)
	owner.position = Vector2(PAGE.x - 170, PAGE.y - 120)
	owner.rotation = -0.09
	page.add_child(owner)
	var line := Control.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.position = owner.position + Vector2(-6, 30)
	line.draw.connect(func(): line.draw_line(Vector2(0, 2), Vector2(84, -6), Color("#6e7a86", 0.6), 1.2))
	page.add_child(line)


func _add_back_line(page: Control) -> void:
	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = Color(INK, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.12)
	sb.shadow_size = 3
	card.add_theme_stylebox_override("panel", sb)
	card.position = Vector2(110, 230)
	card.size = Vector2(PAGE.x - 220, 170)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(card)
	var l := _label(data["back_inside"], 21, INK, font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("line_spacing", 10)
	l.position = Vector2.ZERO
	l.size = card.size
	card.add_child(l)


## 글 위아래 장식: 가는 잉크 선 사이에 작은 주황 조개
func _ornament(bottom: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 22)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var w := c.size.x
		var mid := Vector2(w / 2.0, 12)
		var ink := Color(INK, 0.45)
		c.draw_line(Vector2(w / 2.0 - 90, 12), Vector2(w / 2.0 - 16, 12), ink, 1.0)
		c.draw_line(Vector2(w / 2.0 + 16, 12), Vector2(w / 2.0 + 90, 12), ink, 1.0)
		if bottom:
			c.draw_circle(mid, 2.2, ink)
		else:
			_draw_shell(c, mid + Vector2(0, 5), 10.0))
	return c


func _draw_shell(c: CanvasItem, base: Vector2, r: float) -> void:
	var pts := PackedVector2Array([base])
	var n := 9
	for i in n + 1:
		var a := PI + PI * float(i) / n
		var bump := 1.0 + 0.08 * (1.0 if i % 2 == 0 else -1.0)
		pts.append(base + Vector2(cos(a), sin(a)) * r * bump)
	c.draw_colored_polygon(pts, SHELL)
	for i in range(1, n, 2):
		var a := PI + PI * float(i) / n
		c.draw_line(base, base + Vector2(cos(a), sin(a)) * r * 0.92, Color(0.55, 0.25, 0.1, 0.55), 1.0)
	c.draw_rect(Rect2(base + Vector2(-3, -1), Vector2(6, 3)), SHELL.darkened(0.2))


## 면지 무늬: 바랜 물결과 작은 조개가 번갈아
func _pattern() -> Control:
	var c := Control.new()
	c.size = PAGE
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var col := Color(0.2, 0.33, 0.36, 0.13)
		for row in range(0, 14):
			var y := 26.0 + row * 46.0
			var off := 0.0 if row % 2 == 0 else 34.0
			for col_i in range(0, 10):
				var x := 20.0 + off + col_i * 68.0
				if (row + col_i) % 3 == 0:
					var pts := PackedVector2Array()
					for k in 7:
						var a := PI + PI * k / 6.0
						pts.append(Vector2(x, y + 6) + Vector2(cos(a), sin(a)) * 9.0)
					c.draw_polyline(pts, col, 1.2)
					c.draw_line(Vector2(x - 9, y + 6), Vector2(x + 9, y + 6), col, 1.2)
				else:
					var wave := PackedVector2Array()
					for k in 9:
						wave.append(Vector2(x - 12 + k * 3.0, y + 4 + sin(k * 0.9) * 2.5))
					c.draw_polyline(wave, col, 1.1))
	return c


## 1회차: 찢겨 나간 두 장이 제본선에 남긴 들쭉날쭉한 종이 밑동
func _draw_stub(page: Control) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 915
	for layer in 2:
		var base_w := 40.0 - layer * 16.0
		var pts := PackedVector2Array([Vector2(PAGE.x, 0)])
		var y := 0.0
		while y < PAGE.y:
			pts.append(Vector2(PAGE.x - base_w - rng.randf_range(-8, 10), y))
			y += rng.randf_range(6, 18)
		pts.append(Vector2(PAGE.x - base_w, PAGE.y))
		pts.append(Vector2(PAGE.x, PAGE.y))
		var sh := PackedVector2Array()       # 밑동이 종이 위에 떠 있는 그림자
		for q in pts:
			sh.append(q + Vector2(-3, 2))
		page.draw_colored_polygon(sh, Color(0, 0, 0, 0.12))
		page.draw_colored_polygon(pts, PAPER.lightened(0.02).darkened(layer * 0.05))
		page.draw_polyline(pts.slice(1, pts.size() - 1), Color(0.35, 0.28, 0.2, 0.45), 1.0)


## 찾아낸 찢긴 장: 제본선 쪽 찢긴 가장자리 + 네 번 접혔던 자국
func _draw_torn_marks(c: Control, side: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + side
	var edge_x := PAGE.x if side < 0 else 0.0
	var dir := -1.0 if side < 0 else 1.0
	var pts := PackedVector2Array([Vector2(edge_x, 0)])
	var y := 0.0
	while y < PAGE.y:
		pts.append(Vector2(edge_x + dir * rng.randf_range(1, 7), y))
		y += rng.randf_range(5, 15)
	pts.append(Vector2(edge_x + dir * 6, PAGE.y))
	pts.append(Vector2(edge_x, PAGE.y))
	c.draw_colored_polygon(pts, CLOTH.darkened(0.15))
	c.draw_polyline(pts.slice(1, pts.size() - 1), Color(1, 1, 1, 0.35), 1.0)
	# 접힌 자국: 가로 한 줄, 세로 한 줄 (밝은 선 + 그늘)
	var fx := PAGE.x * 0.5
	var fy := PAGE.y * 0.47
	c.draw_line(Vector2(fx, 0), Vector2(fx + 2, PAGE.y), Color(0, 0, 0, 0.13), 2.0)
	c.draw_line(Vector2(fx + 2, 0), Vector2(fx + 4, PAGE.y), Color(1, 1, 1, 0.3), 1.0)
	c.draw_line(Vector2(0, fy), Vector2(PAGE.x, fy - 3), Color(0, 0, 0, 0.12), 2.0)
	c.draw_line(Vector2(0, fy + 2), Vector2(PAGE.x, fy - 1), Color(1, 1, 1, 0.3), 1.0)


# ── 닫힌 표지 ─────────────────────────────────────────────
func _make_cover() -> Control:
	var cover := Control.new()
	cover.position = Vector2(SPINE_X, TOP - BOARD_PAD)
	cover.size = Vector2(PAGE.x + BOARD_PAD, PAGE.y + BOARD_PAD * 2)
	cover.pivot_offset = Vector2(0, cover.size.y / 2.0)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _lo > 0:                     # 덮인 책 아래로 삐져나온 가름끈 끝
		var tail := Control.new()
		tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tail.draw.connect(func():
			var x := 120.0
			var y0 := cover.size.y - 20.0
			var pts := PackedVector2Array([Vector2(x, y0), Vector2(x + 14, y0), Vector2(x + 16, y0 + 46),
				Vector2(x + 8, y0 + 38), Vector2(x + 1, y0 + 47)])
			tail.draw_colored_polygon(pts, RIBBON)
			tail.draw_line(Vector2(x + 7, y0), Vector2(x + 8, y0 + 38), Color(0, 0, 0, 0.18), 1.0))
		cover.add_child(tail)
	var cloth := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CLOTH
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_right = 6
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 8)
	cloth.add_theme_stylebox_override("panel", sb)
	cloth.size = cover.size
	cloth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(cloth)
	var deco := Control.new()       # 책등 홈, 금박 테두리
	deco.size = cover.size
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func():
		var gold := Color("#c9b27c")
		deco.draw_rect(Rect2(0, 0, 26, cover.size.y), CLOTH.darkened(0.25))
		deco.draw_line(Vector2(26, 0), Vector2(26, cover.size.y), Color(0, 0, 0, 0.35), 2.0)
		deco.draw_rect(Rect2(48, 22, cover.size.x - 70, cover.size.y - 44), gold, false, 1.5)
		deco.draw_rect(Rect2(54, 28, cover.size.x - 82, cover.size.y - 56), Color(gold, 0.5), false, 1.0)
		_draw_shell(deco, Vector2(cover.size.x / 2.0 + 13, cover.size.y - 62), 13.0))
	cover.add_child(deco)
	var title := _label(data["title"], 34, Color("#e8d9b5"), font_bold)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(26, 56)
	title.size = Vector2(cover.size.x - 26, 50)
	cover.add_child(title)
	var sub := _label(data["subtitle"], 18, Color("#e8d9b5", 0.75), font)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(26, 106)
	sub.size = Vector2(cover.size.x - 26, 30)
	cover.add_child(sub)
	var frame := Panel.new()        # 표지 그림을 붙인 자리
	var fs := StyleBoxFlat.new()
	fs.bg_color = Color("#e8d9b5")
	fs.set_corner_radius_all(2)
	fs.shadow_color = Color(0, 0, 0, 0.35)
	fs.shadow_size = 4
	frame.add_theme_stylebox_override("panel", fs)
	frame.position = Vector2(76, 156)
	frame.size = Vector2(cover.size.x - 126, (cover.size.x - 126) * 0.7464)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(frame)
	var img := TextureRect.new()
	img.texture = load(ART + data["cover"] + ".jpg")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.position = Vector2(6, 6)
	img.size = frame.size - Vector2(12, 12)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(img)
	# 오래 만진 책: 천 모서리가 닳은 자국
	var wear := Control.new()
	wear.size = cover.size
	wear.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wear.draw.connect(func():
		var w := Color(1, 1, 1, 0.05)
		for k in 3:
			wear.draw_arc(Vector2(cover.size.x - 7, 7), 4.0 + k * 3.0, PI * 0.5, PI, 8, w, 2.0)
			wear.draw_arc(Vector2(cover.size.x - 7, cover.size.y - 7), 4.0 + k * 3.0, PI, PI * 1.5, 8, w, 2.0)
		for i in 40:
			var y := float(i) * cover.size.y / 40.0
			wear.draw_line(Vector2(cover.size.x - 2, y), Vector2(cover.size.x - 6, y + 4), Color(1, 1, 1, 0.04), 1.0))
	cover.add_child(wear)
	return cover


# ── 넘기기 ────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			next_page()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			prev_page()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_RIGHT, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			next_page()
		KEY_LEFT, KEY_BACKSPACE:
			prev_page()
		KEY_ESCAPE:
			close_book()
	get_viewport().set_input_as_handled()


func next_page() -> void:
	if busy:
		return
	if _reveal:
		_finish_reveal()
	elif index < 0:
		_open_cover()
	elif index < _hi:
		_turn(1)
	else:
		close_book()


func prev_page() -> void:
	if busy:
		return
	if _reveal:
		_finish_reveal()
	elif index > _lo:
		_turn(-1)


func close_book() -> void:
	if busy:
		return
	busy = true
	if _reveal:
		_reveal.kill()
		_reveal = null
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.35)
	t.tween_callback(func():
		closed.emit()
		queue_free())


func _open_cover() -> void:
	busy = true
	var inside := _make_page(spreads[_lo][0], -1)
	inside.position = Vector2(SPINE_X - PAGE.x, TOP)
	inside.pivot_offset = Vector2(PAGE.x, PAGE.y / 2.0)
	inside.scale.x = 0.0
	var board_l := _left_board
	board_l.pivot_offset = Vector2(board_l.size.x, board_l.size.y / 2.0)
	board_l.scale.x = 0.0
	board_l.visible = true
	var t := create_tween()
	t.tween_property(_cover, "scale:x", 0.0, TURN * 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_cover, "modulate", Color(0.6, 0.6, 0.6), TURN * 1.2)
	t.tween_callback(func():
		_cover.visible = false
		_anim.add_child(inside))
	t.tween_property(board_l, "scale:x", 1.0, TURN * 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(inside, "scale:x", 1.0, TURN * 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		inside.queue_free()
		_left_slot.visible = true
		for c in _book.get_children():
			if c.has_meta("gutter"):
				c.visible = true
		index = _lo
		_ribbon.visible = _lo > 0
		_stacks.queue_redraw()
		busy = false
		_arrive())


## dir 1: 오른쪽 쪽이 제본선을 축으로 넘어가 왼쪽에 내려앉음. dir -1은 그 반대
func _turn(dir: int) -> void:
	busy = true
	_ribbon.visible = false
	_hide_reaction()
	var cur: Array = spreads[index]
	var nxt: Array = spreads[index + dir]
	var from_side := 1 if dir > 0 else -1
	var lift := _make_page(cur[1] if dir > 0 else cur[0], from_side)
	var land := _make_page(nxt[0] if dir > 0 else nxt[1], -from_side)
	var from_pos := Vector2(SPINE_X, TOP) if dir > 0 else Vector2(SPINE_X - PAGE.x, TOP)
	var to_pos := Vector2(SPINE_X - PAGE.x, TOP) if dir > 0 else Vector2(SPINE_X, TOP)
	lift.position = from_pos
	lift.pivot_offset = Vector2(0 if dir > 0 else PAGE.x, PAGE.y / 2.0)
	land.position = to_pos
	land.pivot_offset = Vector2(PAGE.x if dir > 0 else 0, PAGE.y / 2.0)
	land.scale.x = 0.0
	# 넘어가는 쪽 아래로 드러나는 새 쪽, 그 위에 지는 그늘
	if dir > 0:
		_fill(_right_slot, _make_page(nxt[1], 1))
	else:
		_fill(_left_slot, _make_page(nxt[0], -1))
	var shadow := ColorRect.new()
	shadow.color = Color(0, 0, 0, 0.32)
	shadow.position = from_pos
	shadow.size = PAGE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anim.add_child(shadow)
	_anim.add_child(lift)
	var t := create_tween()
	t.tween_property(lift, "scale:x", 0.0, TURN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(lift, "modulate", Color(0.7, 0.68, 0.65), TURN)
	t.parallel().tween_property(shadow, "color:a", 0.12, TURN)
	t.tween_callback(func():
		lift.queue_free()
		land.modulate = Color(0.7, 0.68, 0.65)
		_anim.add_child(land))
	t.tween_property(land, "scale:x", 1.0, TURN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(land, "modulate", Color.WHITE, TURN)
	t.parallel().tween_property(shadow, "color:a", 0.0, TURN * 0.6)
	t.tween_callback(func():
		if dir > 0:
			_fill(_left_slot, _make_page(nxt[0], -1))
		else:
			_fill(_right_slot, _make_page(nxt[1], 1))
		land.queue_free()
		shadow.queue_free()
		index += dir
		_stacks.queue_redraw()
		busy = false
		_arrive())


# ── 읽기: 처음 읽는 쪽은 글이 천천히, 다 읽으면 채린의 반응 ─────────────
var _revealed := {}                     # always_reveal일 때 이번에 이미 다 본 쪽


func _needs_reveal(k: int) -> bool:
	if k <= 0 or _revealed.has(k):
		return false
	return always_reveal or not SaveManager.is_book_page_seen(k)


func _body_of(n: Node) -> RichTextLabel:
	for c in n.get_children():
		if c.is_queued_for_deletion():
			continue
		if c.has_meta("story_body"):
			return c
		var r := _body_of(c)
		if r:
			return r
	return null


func _arrive() -> void:
	var spec: Dictionary = spreads[index][1]
	if spec.get("kind") != "text":
		_update_hint()
		return
	var body := _body_of(_right_slot)
	if body and body.visible_ratio < 1.0:
		_reveal_body = body
		_reveal_page = spec["page"]
		_reveal = create_tween()
		_reveal.tween_property(body, "visible_ratio", 1.0, String(spec["text"]).length() / REVEAL_CPS)
		_reveal.tween_callback(_finish_reveal)
		_update_hint()
	else:
		_page_done(spec)


func _finish_reveal() -> void:
	if _reveal:
		_reveal.kill()
	_reveal = null
	if is_instance_valid(_reveal_body):
		_reveal_body.visible_ratio = 1.0
	_revealed[_reveal_page] = true
	_page_done(spreads[index][1])


func _page_done(spec: Dictionary) -> void:
	var k: int = spec["page"]
	SaveManager.mark_book_page_seen(k)
	furthest = maxi(furthest, k)
	_update_hint()
	if reactions:
		_show_reaction(spec)


func _update_hint() -> void:
	if _reveal:
		_hint.text = "클릭: 글 다 보기"
	elif index >= _hi and page_to > 0:
		_hint.text = "클릭: 오늘은 여기까지 · 덮기" if reactions else "읽은 데까지 다 봤다 · 클릭: 덮기"
	else:
		_hint.text = "클릭: 넘기기 · 오른쪽 클릭: 앞으로 · Esc: 덮기"


## 가름끈: 펼친 쪽 제본선 골을 따라 내려와 책 아래로 살짝 늘어짐 (그림을 가리지 않게)
func _draw_ribbon() -> void:
	var a := Vector2(SPINE_X - 5, TOP - 4)
	var b := Vector2(SPINE_X - 9, TOP + PAGE.y * 0.7)
	var c := Vector2(SPINE_X - 34, TOP + PAGE.y + 46)
	var pts := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		pts.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	_ribbon.draw_polyline(pts.duplicate(), Color(0, 0, 0, 0.2), 12.0)        # 종이 위에 지는 그늘
	for i in pts.size():
		pts[i] += Vector2(-2, -1)
	_ribbon.draw_polyline(pts, RIBBON, 10.0)
	_ribbon.draw_polyline(pts, RIBBON.lightened(0.18), 2.0)                   # 끈의 결
	var end := pts[pts.size() - 1]                                          # 끝은 제비꼬리로 자름
	var dir := (end - pts[pts.size() - 2]).normalized()
	var nrm := Vector2(-dir.y, dir.x) * 5.0
	_ribbon.draw_colored_polygon(PackedVector2Array([end + nrm, end - nrm, end - nrm + dir * 10, end - dir * 0.5 + dir * 3, end + nrm + dir * 10]), RIBBON)


func _build_reaction_box() -> void:
	_react_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.07, 0.86)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	_react_box.add_theme_stylebox_override("panel", sb)
	_react_box.position = Vector2(170, 600)
	_react_box.size = Vector2(940, 0)
	_react_box.custom_minimum_size = Vector2(940, 0)
	_react_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_react_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_react_box.add_child(v)
	var who := Label.new()
	who.text = "유채린"
	who.add_theme_font_size_override("font_size", 17)
	who.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	v.add_child(who)
	_react_text = Label.new()
	_react_text.add_theme_font_size_override("font_size", 21)
	_react_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_react_text)
	_react_inner = Label.new()
	_react_inner.add_theme_font_size_override("font_size", 18)
	_react_inner.add_theme_color_override("font_color", Color("#ff5a5a"))
	_react_inner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_react_inner)
	_react_box.modulate.a = 0.0


func _show_reaction(spec: Dictionary) -> void:
	var say: String = spec.get("react", "")
	if say == "" or _react_box == null:
		return
	_react_text.text = _keep_words(say)
	var inner: String = spec.get("react_inner", "")
	_react_inner.text = _keep_words(inner)
	_react_inner.visible = show_inner and inner != ""
	if _react_tween:
		_react_tween.kill()
	_react_tween = create_tween()
	_react_tween.tween_interval(0.35)
	_react_tween.tween_property(_react_box, "modulate:a", 1.0, 0.4)


func _hide_reaction() -> void:
	if _react_box:
		if _react_tween:
			_react_tween.kill()
		_react_tween = create_tween()
		_react_tween.tween_property(_react_box, "modulate:a", 0.0, 0.15)
