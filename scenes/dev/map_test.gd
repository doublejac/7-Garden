# map_test.gd
# 64px 타일 테스트 맵: 서하 방 · 보호자실 · 채린 방 · 빈 병실 · 병동 복도 · 중앙 복도 일부.
# 바닥·벽은 assets/art/tiles/interior.png, 가구는 assets/art/props/interior/ (Gemini 시트를 정리한 것).
# 배치는 LAYOUT(바닥·벽), PROPS(가구), DOORS(옆벽 문) 표만 고치면 바로 바뀐다.
#   방향키: 걷기   E: 문 열기/닫기   C: 복도 바닥 바꾸기   T: 시간대   Z: 확대/축소   G: 격자   Esc: 끝내기
extends Node2D

const TILE := 64
const SPEED := 150.0
const ATLAS := "res://assets/art/tiles/interior.png"
const PROP_DIR := "res://assets/art/props/interior/"

# 기호: # 벽 윗면(이웃에 따라 테두리 자동)   W 벽 앞면(위에서부터 몰딩/회벽/판벽 자동)
#       . 나무 마루  : 나무 마루(변형)  , 세로 복도  _ 가로 복도  L 로비  F 식당  D 옆벽 문 자리
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
	"#_____________________#",
	"#_____________________#",
	"#_____________________#",
	"#######################",
]

# 바닥 기호 → [아틀라스 블록 왼쪽 위, 블록 크기, 무늬 기준 x, 기준 y]
const FLOORS := {
	".": [Vector2i(0, 0), 2, 0, 0], ":": [Vector2i(2, 0), 2, 0, 0],
	"L": [Vector2i(0, 2), 2, 0, 0], "F": [Vector2i(2, 2), 2, 0, 0],
	"D": [Vector2i(0, 0), 2, 0, 0],   # 문턱 자리는 나무 마루
}
# 복도 바닥 후보 (C 키로 바꿔 봄). 세로 복도(,)·가로 복도(_)에 깔린다
const CORRIDORS := [
	["러너 카펫", [Vector2i(0, 5), 3, 10, 0], [Vector2i(3, 5), 3, 0, 24]],
	["헤링본 마루", [Vector2i(10, 0), 2, 0, 0], [Vector2i(10, 0), 2, 0, 0]],
	["대리석", [Vector2i(8, 0), 2, 0, 0], [Vector2i(8, 0), 2, 0, 0]],
	["꽃무늬 타일", [Vector2i(8, 2), 2, 0, 0], [Vector2i(8, 2), 2, 0, 0]],
	["회색 타일 (처음 것)", [Vector2i(4, 0), 2, 0, 0], [Vector2i(4, 0), 2, 0, 0]],
]
const WALL_FACE := Vector2i(4, 2)   # 2칸 폭 × 3칸 높이
const WALL_AUTO := Vector2i(6, 5)   # 벽 윗면 16종: 위1 + 오른쪽2 + 아래4 + 왼쪽8 (그쪽도 벽 윗면이면 켜짐)

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
	["exit_door", 11.5, 4.0, [], true],
	# 중앙 복도: 추억의 벽(사진 + 빈 액자), 소파
	["frame_photo", 14.8, 23.2, [], true],
	["frame_photo", 15.8, 23.2, [], true],
	["frame_photo", 16.8, 23.2, [], true],
	["frame_empty", 17.8, 23.2, [], true],
	["sofa", 5.0, 25.0, [3.3, 24, 3.4, 0.9], false],
	["plant", 7.4, 24.9, [7.0, 24.3, 0.8, 0.6], false],
]

# 옆벽 문: [벽 칸 x, 문 윗칸 y, 열리는 쪽(-1 왼쪽 방 / 1 오른쪽 방), 처음에 열림?]
const DOORS := [
	[9, 7, -1, true], [13, 7, 1, false], [9, 16, -1, false], [13, 16, 1, false],
]

const TIMES := [
	["아침", Color("#ffe9d6")], ["낮", Color.WHITE], ["저녁", Color("#ffbf94")], ["밤", Color("#36406a")],
]

var map: TileMapLayer
var player: CharacterBody2D
var seoha: CharacterSprite
var camera: Camera2D
var modulate_node: CanvasModulate
var moon_lights: Array[PointLight2D] = []
var grid: Node2D
var info: Label
var doors: Array[Dictionary] = []
var time_index := 1
var corridor_index := 0


func _ready() -> void:
	map = TileMapLayer.new()
	map.tile_set = _make_tileset()
	map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(map)
	_paint_map()

	var wall_deco := Node2D.new()      # 벽에 걸린 것: 언제나 서하 뒤
	add_child(wall_deco)
	var objects := Node2D.new()        # 가구·문·서하: 발 위치(y)로 앞뒤 정렬
	objects.y_sort_enabled = true
	add_child(objects)
	var blockers := StaticBody2D.new()
	add_child(blockers)
	for p in PROPS:
		var spr := _sprite(p[0])
		spr.offset = Vector2(-spr.texture.get_width() / 2.0, -spr.texture.get_height())
		spr.position = Vector2(p[1], p[2]) * TILE
		(wall_deco if p[4] else objects).add_child(spr)
		if p[3].size() == 4:
			blockers.add_child(_box(Rect2(Vector2(p[3][0], p[3][1]) * TILE, Vector2(p[3][2], p[3][3]) * TILE)))
	for d in DOORS:
		_add_door(objects, d)

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
	_update_info()
	_apply_time()


func _sprite(name: String) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.texture = load(PROP_DIR + name + ".png")
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return spr


func _box(r: Rect2) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = r.size
	cs.shape = rect
	cs.position = r.position + r.size / 2.0
	return cs


# ── 옆벽 문 ───────────────────────────────────────────────
func _add_door(parent: Node2D, d: Array) -> void:
	var x: int = d[0]
	var y: int = d[1]
	var node := Node2D.new()
	node.position = Vector2(x * TILE, (y + 2) * TILE)   # 문 아래 끝 = 앞뒤 정렬 기준
	parent.add_child(node)
	var closed := _sprite("side_door_closed")
	closed.offset = Vector2((TILE - closed.texture.get_width()) / 2.0, -closed.texture.get_height())
	var opened := _sprite("side_door_open")
	opened.offset = Vector2(0, -opened.texture.get_height())
	if d[2] < 0:   # 왼쪽 방으로 열림: 좌우 반전, 문틀이 벽 칸에 오도록
		opened.flip_h = true
		opened.offset.x = TILE - opened.texture.get_width()
	node.add_child(closed)
	node.add_child(opened)
	var body := StaticBody2D.new()
	body.add_child(_box(Rect2(Vector2(0, -2 * TILE), Vector2(TILE, 2 * TILE))))
	node.add_child(body)
	var door := {"node": node, "closed": closed, "opened": opened, "body": body,
		"center": Vector2(x + 0.5, y + 1.0) * TILE}
	doors.append(door)
	_set_door(door, d[3])


func _set_door(door: Dictionary, open: bool) -> void:
	door["open"] = open
	door["closed"].visible = not open
	door["opened"].visible = open
	door["body"].process_mode = Node.PROCESS_MODE_DISABLED if open else Node.PROCESS_MODE_INHERIT
	(door["body"].get_child(0) as CollisionShape2D).set_deferred("disabled", open)


func _toggle_nearest_door() -> void:
	var best: Dictionary = {}
	var best_d := 1.8 * TILE
	for door in doors:
		var dist: float = (door["center"] as Vector2).distance_to(player.position + Vector2(0, -20))
		if dist < best_d:
			best_d = dist
			best = door
	if not best.is_empty():
		_set_door(best, not best["open"])


# ── 타일 ──────────────────────────────────────────────────
func _paint_map() -> void:
	for y in LAYOUT.size():
		var row: String = LAYOUT[y]
		for x in row.length():
			map.set_cell(Vector2i(x, y), 0, _atlas_coord(x, y))


func _is_wall_top(x: int, y: int) -> bool:
	if y < 0 or y >= LAYOUT.size() or x < 0 or x >= LAYOUT[0].length():
		return true
	return LAYOUT[y][x] == "#"


func _atlas_coord(x: int, y: int) -> Vector2i:
	var ch: String = LAYOUT[y][x]
	if ch == "#":
		var idx := int(_is_wall_top(x, y - 1)) + 2 * int(_is_wall_top(x + 1, y)) \
			+ 4 * int(_is_wall_top(x, y + 1)) + 8 * int(_is_wall_top(x - 1, y))
		return WALL_AUTO + Vector2i(idx % 4, idx / 4)
	if ch == "W":
		var k := 0   # 위로 연속된 벽 앞면 수 → 몰딩(0) / 회벽(1) / 판벽(2)
		while y - k - 1 >= 0 and LAYOUT[y - k - 1][x] == "W":
			k += 1
		return WALL_FACE + Vector2i(x % 2, mini(k, 2))
	var f: Array
	if ch == ",":
		f = CORRIDORS[corridor_index][1]
	elif ch == "_":
		f = CORRIDORS[corridor_index][2]
	else:
		f = FLOORS[ch]
	var n: int = f[1]
	return f[0] + Vector2i(posmod(x - f[2], n), posmod(y - f[3], n))


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
		KEY_E:
			_toggle_nearest_door()
		KEY_C:
			corridor_index = (corridor_index + 1) % CORRIDORS.size()
			_paint_map()
			_update_info()
		KEY_T:
			time_index = (time_index + 1) % TIMES.size()
			_apply_time()
		KEY_Z:
			camera.zoom = Vector2.ONE * (0.75 if camera.zoom.x > 0.9 else 1.0)
			_update_info()
		KEY_G:
			grid.visible = not grid.visible


func _apply_time() -> void:
	modulate_node.color = TIMES[time_index][1]
	for l in moon_lights:
		l.visible = time_index == 3
	_update_info()


func _update_info() -> void:
	if info == null:
		return
	info.text = "시간대: %s   확대: %d%%   복도: %s\n방향키 걷기 · E 문 · C 복도 바닥 · T 시간대 · Z 확대 · G 격자 · Esc" % [
		TIMES[time_index][0], roundi(camera.zoom.x * 100), CORRIDORS[corridor_index][0]]


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
	var solid := {}   # 벽 앞면·윗면만 막힘
	for y in 3:
		solid[WALL_FACE + Vector2i(0, y)] = true
		solid[WALL_FACE + Vector2i(1, y)] = true
	for i in 16:
		solid[WALL_AUTO + Vector2i(i % 4, i / 4)] = true
	for y in size.y:
		for x in size.x:
			var c := Vector2i(x, y)
			src.create_tile(c)
			if solid.has(c):
				var td := src.get_tile_data(c, 0)
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, PackedVector2Array([
					Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]))
	return ts
