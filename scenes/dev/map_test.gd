# map_test.gd
# 64px 타일 테스트 맵: 서하 방 · 보호자실 · 채린 방 · 빈 병실 · 병동 복도 · 중앙 복도 일부.
# 바닥·벽은 assets/art/tiles/interior.png, 가구는 assets/art/props/interior/ (Gemini 시트를 정리한 것).
# 배치는 LAYOUT(바닥·벽)과 PROPS(가구) 표만 고치면 바로 바뀐다.
#   방향키: 걷기   T: 시간대(아침/낮/저녁/밤)   Z: 화면 확대/축소   G: 격자 표시   Esc: 끝내기
extends Node2D

const TILE := 64
const SPEED := 150.0
const ATLAS := "res://assets/art/tiles/interior.png"
const PROP_DIR := "res://assets/art/props/interior/"

# 기호: # 벽 윗면   W 벽 앞면(위에서부터 몰딩/회벽/판벽 순으로 자동)
#       . 나무 마루  : 나무 마루(변형)  , 복도  ; 복도(낡은 변형)  L 로비  F 식당  D 문 자리(복도 바닥)
const LAYOUT := [
	"#######################",
	"#WWWWWWWW#WWW#WWWWWWWW#",
	"#WWWWWWWW#WWW#WWWWWWWW#",
	"#WWWWWWWW#WWW#WWWWWWWW#",
	"#........#,,,#::::::::#",
	"#........#,,,#::::::::#",
	"#........#,,,#::::::::#",
	"#........D,,,D::::::::#",
	"#........D,,,D::::::::#",
	"#........#,,,#::::::::#",
	"##########,,,##########",
	"#WWWWWWWW#,,,#WWWWWWWW#",
	"#WWWWWWWW#,,,#WWWWWWWW#",
	"#WWWWWWWW#,,,#WWWWWWWW#",
	"#........#,,,#::::::::#",
	"#........#,,,#::::::::#",
	"#........D,,,D::::::::#",
	"#........D,,,D::::::::#",
	"#........#,,,#::::::::#",
	"#........#,,,#::::::::#",
	"##########,,,##########",
	"#WWWWWWWWW,,,WWWWWWWWW#",
	"#WWWWWWWWW,,,WWWWWWWWW#",
	"#WWWWWWWWW,,,WWWWWWWWW#",
	"#,,,,,,,,,,,,,,,,,,,,,#",
	"#,,,,,,,,,,,,,,,,,,,,,#",
	"#,,,,,,,,,,,,,,,,,,,,,#",
	"#######################",
]

# 바닥 기호 → 아틀라스의 2×2 블록 왼쪽 위 (타일 단위)
const FLOORS := {
	".": Vector2i(0, 0), ":": Vector2i(2, 0), ",": Vector2i(4, 0), ";": Vector2i(6, 0),
	"L": Vector2i(0, 2), "F": Vector2i(2, 2), "D": Vector2i(4, 0),
}
const WALL_FACE := Vector2i(4, 2)   # 2칸 폭 × 3칸 높이
const WALL_TOP := Vector2i(6, 2)

# 가구: [이름, 가운데 x, 바닥 닿는 y, 막는 영역 [x, y, 폭, 높이] 또는 [], 벽에 걸림?]  (모두 타일 단위)
const PROPS := [
	# 서하 방
	["window", 5.0, 3.75, [], true],
	["bed", 2.0, 7.0, [1, 4, 2, 3], false],
	["nightstand", 3.5, 4.9, [3, 4, 1, 0.9], false],
	["mirror", 7.6, 3.0, [], true],
	["sink", 7.6, 4.7, [7.1, 4, 1, 0.7], false],
	["plant", 1.5, 9.9, [1.1, 9.3, 0.8, 0.6], false],
	# 보호자실
	["window", 18.0, 3.75, [], true],
	["bed", 15.0, 7.0, [14, 4, 2, 3], false],
	["nightstand", 16.5, 4.9, [16, 4, 1, 0.9], false],
	["wardrobe", 21.0, 4.9, [20, 4, 2, 0.9], false],
	# 채린 방
	["window", 5.0, 13.75, [], true],
	["bed", 2.0, 17.0, [1, 14, 2, 3], false],
	["nightstand", 3.5, 14.9, [3, 14, 1, 0.9], false],
	["plant", 7.6, 14.9, [7.2, 14.3, 0.8, 0.6], false],
	["armchair", 7.0, 19.6, [6.3, 18.9, 1.4, 0.7], false],
	# 빈 병실 (옷장 = 밤 순찰 때 숨을 곳 가안)
	["window", 18.0, 13.75, [], true],
	["desk", 16.0, 15.6, [15.2, 14, 1.6, 1.3], false],
	["wardrobe", 21.0, 14.9, [20, 14, 2, 0.9], false],
	# 병동 복도 끝 비상구
	["glass_door", 11.5, 4.0, [], true],
	# 중앙 복도: 추억의 벽(사진 + 빈 액자), 소파
	["frame_photo", 14.8, 23.2, [], true],
	["frame_photo", 15.8, 23.2, [], true],
	["frame_photo", 16.8, 23.2, [], true],
	["frame_empty", 17.8, 23.2, [], true],
	["sofa", 5.0, 25.0, [3.3, 24, 3.4, 0.9], false],
	["plant", 7.4, 24.9, [7.0, 24.3, 0.8, 0.6], false],
]

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
	map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(map)
	for y in LAYOUT.size():
		var row: String = LAYOUT[y]
		for x in row.length():
			map.set_cell(Vector2i(x, y), 0, _atlas_coord(x, y))

	var wall_deco := Node2D.new()      # 벽에 걸린 것: 언제나 서하 뒤
	add_child(wall_deco)
	var objects := Node2D.new()        # 가구 + 서하: 발 위치(y)로 앞뒤 정렬
	objects.y_sort_enabled = true
	add_child(objects)
	var blockers := StaticBody2D.new()
	add_child(blockers)
	for p in PROPS:
		var spr := Sprite2D.new()
		spr.texture = load(PROP_DIR + p[0] + ".png")
		spr.centered = false
		spr.offset = Vector2(-spr.texture.get_width() / 2.0, -spr.texture.get_height())
		spr.position = Vector2(p[1], p[2]) * TILE
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		(wall_deco if p[4] else objects).add_child(spr)
		if p[3].size() == 4:
			var cs := CollisionShape2D.new()
			var rect := RectangleShape2D.new()
			rect.size = Vector2(p[3][2], p[3][3]) * TILE
			cs.shape = rect
			cs.position = (Vector2(p[3][0], p[3][1]) + Vector2(p[3][2], p[3][3]) / 2.0) * TILE
			blockers.add_child(cs)

	grid = _make_grid()
	grid.visible = false
	add_child(grid)

	player = CharacterBody2D.new()
	player.position = Vector2(5 * TILE, 8 * TILE)
	var shape := CollisionShape2D.new()
	var prect := RectangleShape2D.new()
	prect.size = Vector2(40, 18)
	shape.shape = prect
	shape.position = Vector2(0, -9)
	player.add_child(shape)
	seoha = load("res://scenes/characters/seoha.tscn").instantiate()
	player.add_child(seoha)
	objects.add_child(player)

	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = LAYOUT[0].length() * TILE
	camera.limit_bottom = LAYOUT.size() * TILE
	camera.position_smoothing_enabled = true
	player.add_child(camera)

	modulate_node = CanvasModulate.new()
	add_child(modulate_node)
	# 달빛: 비상구 유리문과 각 방 창문
	moon_lights.append(_make_light(Vector2(11.5, 5.0) * TILE, 3.4))
	moon_lights.append(_make_light(Vector2(5.0, 5.2) * TILE, 2.6))
	moon_lights.append(_make_light(Vector2(5.0, 15.2) * TILE, 2.6))

	var hud := CanvasLayer.new()
	add_child(hud)
	info = Label.new()
	info.position = Vector2(16, 12)
	info.add_theme_color_override("font_color", Color.WHITE)
	info.add_theme_color_override("font_outline_color", Color.BLACK)
	info.add_theme_constant_override("outline_size", 6)
	hud.add_child(info)
	_apply_time()


func _atlas_coord(x: int, y: int) -> Vector2i:
	var ch: String = LAYOUT[y][x]
	if ch == "#":
		return WALL_TOP
	if ch == "W":
		var k := 0   # 위로 연속된 벽 앞면 수 → 몰딩(0) / 회벽(1) / 판벽(2)
		while y - k - 1 >= 0 and LAYOUT[y - k - 1][x] == "W":
			k += 1
		return WALL_FACE + Vector2i(x % 2, mini(k, 2))
	return FLOORS[ch] + Vector2i(x % 2, y % 2)


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


func _make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	var src := TileSetAtlasSource.new()
	src.texture = load(ATLAS)
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	var size := src.get_atlas_grid_size()
	var half := TILE / 2.0
	var solid_rows := {}   # 벽 앞면·윗면만 막힘
	for y in 3:
		solid_rows[WALL_FACE + Vector2i(0, y)] = true
		solid_rows[WALL_FACE + Vector2i(1, y)] = true
	solid_rows[WALL_TOP] = true
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			if not src.has_room_for_tile(c, Vector2i.ONE, 1, Vector2i.ZERO, 1):
				continue
			src.create_tile(c)
			if solid_rows.has(c):
				var td := src.get_tile_data(c, 0)
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, PackedVector2Array([
					Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]))
	return ts
