# map_test.gd
# 64px 타일 크기 확인용 테스트 맵: 서하 방 + 병동 복도 + 중앙 복도 일부.
# 그림은 임시 색 블록이다. 배치는 아래 LAYOUT 문자열을 고치면 바로 바뀐다.
#   방향키: 걷기   T: 시간대(아침/낮/저녁/밤)   Z: 화면 확대/축소   G: 격자 표시   Esc: 끝내기
extends Node2D

const TILE := 64
const SPEED := 150.0

# 기호: # 벽 윗면  W 벽 앞면  w 창문  G 비상구 유리문  . 나무 바닥  , 복도 바닥  D 문
#       b 침대(2칸 폭)  s 세면대  n 협탁  c 수납장
const LAYOUT := [
	"#######################",
	"#WWWWWWWW#GGG#WWWWWWWW#",
	"#WWwwwwWW#GGG#WWWwwWWW#",
	"#bb.....s#,,,#bb....cc#",
	"#bbn.....#,,,#bbn.....#",
	"#bb......#,,,#bb......#",
	"#........D,,,D........#",
	"#........D,,,D........#",
	"#........#,,,#........#",
	"##########,,,##########",
	"#WWWWWWWW#,,,#WWWWWWWW#",
	"#WWwwwwWW#,,,#WWWWWWWW#",
	"#bb......#,,,#........#",
	"#bbn.....#,,,#........#",
	"#bb......D,,,D........#",
	"#........D,,,D........#",
	"#.......s#,,,#........#",
	"#........#,,,#........#",
	"##########,,,##########",
	"#WWWWWWWWW,,,WWWWWWWWW#",
	"#WWWWWWWWW,,,WWWWWWWWW#",
	"#,,,,,,,,,,,,,,,,,,,,,#",
	"#,,,,,,,,,,,,,,,,,,,,,#",
	"#,,,,,,,,,,,,,,,,,,,,,#",
	"#######################",
]

# 방 이름표 (타일 좌표)
const LABELS := {
	"서하 방": Vector2(5, 8.4), "보호자실": Vector2(18, 8.4),
	"채린 방": Vector2(5, 17.4), "빈 병실": Vector2(18, 17.4),
	"비상구": Vector2(11.5, 1.2), "중앙 복도": Vector2(16, 23.4),
}

# 기호 → (아틀라스 칸, 막힘 여부)
const TILES := {
	"#": [0, true], "W": [1, true], "w": [2, true], ".": [3, false], ",": [4, false],
	"D": [5, false], "G": [6, true], "b": [7, true], "s": [9, true], "n": [10, true], "c": [11, true],
}
const PILLOW := 8

# 임시 타일 그림: 칸 번호 → [x, y, w, h, 색] 사각형 목록
const PAINT := {
	0: [[0, 0, 64, 64, "#4a4440"], [0, 0, 64, 4, "#5a5450"]],
	1: [[0, 0, 64, 64, "#d9cfbf"], [16, 0, 1, 54, "#cfc4b2"], [32, 0, 1, 54, "#cfc4b2"], [48, 0, 1, 54, "#cfc4b2"],
		[0, 54, 64, 10, "#8a7461"]],
	2: [[0, 0, 64, 64, "#d9cfbf"], [6, 6, 52, 44, "#f4efe6"], [10, 10, 44, 36, "#7fa7c4"],
		[10, 34, 44, 12, "#5d87a8"], [31, 10, 2, 36, "#f4efe6"], [0, 54, 64, 10, "#8a7461"]],
	3: [[0, 0, 64, 64, "#b98c62"], [0, 16, 64, 1, "#a37752"], [0, 32, 64, 1, "#a37752"], [0, 48, 64, 1, "#a37752"],
		[20, 0, 1, 16, "#a37752"], [44, 16, 1, 16, "#a37752"], [12, 32, 1, 16, "#a37752"], [36, 48, 1, 16, "#a37752"]],
	4: [[0, 0, 64, 64, "#cfd3cf"], [0, 0, 64, 1, "#b5bab5"], [0, 0, 1, 64, "#b5bab5"],
		[32, 0, 1, 64, "#b5bab5"], [0, 32, 64, 1, "#b5bab5"]],
	5: [[0, 0, 64, 64, "#9c7350"], [4, 0, 56, 64, "#b98c62"]],
	6: [[0, 0, 64, 64, "#6e7f86"], [4, 4, 56, 60, "#a9c3d1"], [30, 4, 4, 60, "#6e7f86"]],
	7: [[0, 0, 64, 64, "#7d5a3c"], [4, 0, 60, 64, "#eef0f2"]],
	8: [[0, 0, 64, 64, "#7d5a3c"], [4, 8, 60, 56, "#eef0f2"], [16, 16, 48, 22, "#ffffff"], [16, 36, 48, 2, "#d5dae0"]],
	12: [[0, 0, 64, 64, "#7d5a3c"], [0, 0, 60, 64, "#eef0f2"]],
	13: [[0, 0, 64, 64, "#7d5a3c"], [0, 8, 60, 56, "#eef0f2"], [0, 16, 48, 22, "#ffffff"], [0, 36, 48, 2, "#d5dae0"]],
	9: [[0, 0, 64, 64, "#b98c62"], [8, 4, 48, 40, "#e9eef1"], [16, 12, 32, 22, "#c7d2d8"], [29, 6, 6, 8, "#9aa5ab"],
		[14, 44, 36, 16, "#d8dde0"]],
	10: [[0, 0, 64, 64, "#b98c62"], [10, 12, 44, 44, "#8a6545"], [14, 30, 36, 2, "#6b4c33"], [26, 18, 12, 8, "#f2e2b8"]],
	11: [[0, 0, 64, 64, "#b98c62"], [4, 4, 56, 56, "#9a7552"], [31, 4, 2, 56, "#7a5a3e"]],
}

const TIMES := [
	["아침", Color("#ffe9d6")], ["낮", Color.WHITE], ["저녁", Color("#ffbf94")], ["밤", Color("#36406a")],
]

var player: CharacterBody2D
var seoha: CharacterSprite
var camera: Camera2D
var modulate_node: CanvasModulate
var moon_lights: Array[PointLight2D] = []
var grid: Node2D
var info: Label
var time_index := 1


func _ready() -> void:
	var map := TileMapLayer.new()
	map.tile_set = _make_tileset()
	add_child(map)
	for y in LAYOUT.size():
		var row: String = LAYOUT[y]
		for x in row.length():
			var ch := row[x]
			var idx: int = TILES[ch][0]
			if ch == "b":   # 침대는 2칸 폭: 왼쪽/오른쪽, 머리맡/이불 그림을 이웃 칸으로 고름
				var head: bool = y == 0 or LAYOUT[y - 1][x] != "b"
				var right: bool = x > 0 and row[x - 1] == "b"
				idx = (13 if head else 12) if right else (PILLOW if head else 7)
			map.set_cell(Vector2i(x, y), 0, Vector2i(idx, 0))

	for text in LABELS:
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", Color(0, 0, 0, 0.45))
		l.position = LABELS[text] * TILE - Vector2(40, 14)
		add_child(l)

	grid = _make_grid()
	grid.visible = false
	add_child(grid)

	player = CharacterBody2D.new()
	player.position = Vector2(5 * TILE, 7.5 * TILE)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 18)
	shape.shape = rect
	shape.position = Vector2(0, -9)
	player.add_child(shape)
	seoha = load("res://scenes/characters/seoha.tscn").instantiate()
	player.add_child(seoha)
	add_child(player)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = LAYOUT[0].length() * TILE
	camera.limit_bottom = LAYOUT.size() * TILE
	camera.position_smoothing_enabled = true
	player.add_child(camera)

	modulate_node = CanvasModulate.new()
	add_child(modulate_node)
	# 달빛: 비상구 유리문과 서하 방 창문
	moon_lights.append(_make_light(Vector2(11.5 * TILE, 4 * TILE), 3.2))
	moon_lights.append(_make_light(Vector2(5 * TILE, 4 * TILE), 2.4))

	var hud := CanvasLayer.new()
	add_child(hud)
	info = Label.new()
	info.position = Vector2(16, 12)
	info.add_theme_color_override("font_color", Color.WHITE)
	info.add_theme_color_override("font_outline_color", Color.BLACK)
	info.add_theme_constant_override("outline_size", 6)
	hud.add_child(info)
	_apply_time()


func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	player.velocity = dir * SPEED
	player.move_and_slide()
	seoha.walk(dir)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_T:
			time_index = (time_index + 1) % TIMES.size()
			_apply_time()
		KEY_Z:
			camera.zoom = Vector2.ONE * (0.75 if camera.zoom.x > 0.9 else 1.0)
			_apply_time()
		KEY_G:
			grid.visible = not grid.visible


func _apply_time() -> void:
	modulate_node.color = TIMES[time_index][1]
	for l in moon_lights:
		l.visible = time_index == 3
	info.text = "시간대: %s   확대: %d%%   (방향키 걷기 · T 시간대 · Z 확대 · G 격자 · Esc)" % [
		TIMES[time_index][0], roundi(camera.zoom.x * 100)]


func _make_light(pos: Vector2, size_scale: float) -> PointLight2D:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	var light := PointLight2D.new()
	light.texture = tex
	light.texture_scale = size_scale
	light.color = Color("#c9dcff")
	light.energy = 1.1
	light.position = pos
	add_child(light)
	return light


func _make_grid() -> Node2D:
	var n := Node2D.new()
	var w: int = LAYOUT[0].length()
	var h: int = LAYOUT.size()
	for x in w + 1:
		var line := Line2D.new()
		line.points = [Vector2(x * TILE, 0), Vector2(x * TILE, h * TILE)]
		line.width = 1
		line.default_color = Color(0, 0, 0, 0.25)
		n.add_child(line)
	for y in h + 1:
		var line := Line2D.new()
		line.points = [Vector2(0, y * TILE), Vector2(w * TILE, y * TILE)]
		line.width = 1
		line.default_color = Color(0, 0, 0, 0.25)
		n.add_child(line)
	return n


# ── 임시 타일 그림 ────────────────────────────────────────────
func _make_tileset() -> TileSet:
	var count := 14
	var img := Image.create(TILE * count, TILE, false, Image.FORMAT_RGBA8)
	for i in PAINT:
		for r in PAINT[i]:
			img.fill_rect(Rect2i(i * TILE + r[0], r[1], r[2], r[3]), Color(r[4]))

	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	var solid := {}
	for ch in TILES:
		solid[TILES[ch][0]] = TILES[ch][1]
	for i in [PILLOW, 12, 13]:
		solid[i] = true
	var half := TILE / 2.0
	for i in count:
		src.create_tile(Vector2i(i, 0))
		if solid.get(i, false):
			var td := src.get_tile_data(Vector2i(i, 0), 0)
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, PackedVector2Array([
				Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]))
	return ts

