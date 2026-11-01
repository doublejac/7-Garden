# interior_map.gd
# 실내 맵 공용 로더. data/maps/<이름>.json 하나로 바닥·벽, 가구, 문, 달빛을 만든다.
# 맵 씬을 단독 실행(F6)하면 개발용으로 서하·카메라·조작 안내가 붙는다.
#   방향키: 걷기   E: 문   T: 시간대   V: 조명 톤(1회차/평소/2회차)   F: 안개   Z: 확대   G: 격자   L: 방 이름   Esc
#
# JSON 형식
#   layout   : 글자 배열. # 벽 윗면(테두리 자동)  W 벽 앞면(몰딩/회벽/판벽 자동)  나머지는 바닥 (FLOORS 참고)
#   props    : [이름, 가운데 x, 바닥 닿는 y, 막는 영역 [x, y, 폭, 높이] 또는 [], 뒤에 깔림?]   (타일 단위)
#              뒤에 깔림 = 벽에 건 것(창문·액자)이나 바닥 깔개(러그): 언제나 인물 뒤에 그림
#   doors    : {x, y, type: "v"(세로 벽) | "h"(가로 벽) | "f"(정면 벽), swing: 1|-1, open, locked, sprite}
#              v: (x, y)~(x, y+1) 두 칸, swing 1 = 오른쪽 방으로 열림
#              h: (x, y)~(x+1, y) 두 칸, swing 1 = 아래쪽 방으로 열림
#              f: (x, y)~(x+1, y+3) 벽 윗면 1줄 + 벽 앞면 3줄을 뚫은 자리에 정면 문 그림
#   labels   : [글자, x, y]  (개발용 방 이름)
#   moonlights: [x, y, 크기]
#   corridor : 복도 바닥 기본값 (CORRIDORS의 키)
class_name InteriorMap
extends Node2D

const TILE := 64
const SPEED := 150.0
const ATLAS := "res://assets/art/tiles/interior.png"
const PROP_DIR := "res://assets/art/props/interior/"
const WALL_FACE := Vector2i(4, 2)   # 2칸 폭 × 3칸 높이
const WALL_AUTO := Vector2i(6, 5)   # 벽 윗면 16종: 위1 + 오른쪽2 + 아래4 + 왼쪽8 (그쪽도 벽 윗면이면 켜짐)

# 바닥 기호 → [아틀라스 블록 왼쪽 위, 블록 크기, 무늬 기준 x, 기준 y]
const FLOORS := {
	".": [Vector2i(0, 0), 2, 0, 0],   # 나무 마루
	":": [Vector2i(2, 0), 2, 0, 0],   # 나무 마루 (변형)
	"L": [Vector2i(0, 2), 2, 0, 0],   # 로비 체크무늬
	"F": [Vector2i(2, 2), 2, 0, 0],   # 식당 테라코타
	"K": [Vector2i(4, 0), 2, 0, 0],   # 회색 타일 (주방·투약실)
	"B": [Vector2i(6, 0), 2, 0, 0],   # 욕실 흰 육각 타일
}
# 복도 바닥: 세로 복도(,)·가로 복도(_)에 깔린다
const CORRIDORS := {
	"floral": ["꽃무늬 타일", [Vector2i(8, 2), 2, 0, 0], [Vector2i(8, 2), 2, 0, 0]],
}
# 시간대 이름
const TIMES := ["아침", "낮", "저녁", "밤"]
# 조명 톤: 해무 톤 그림 위에 거는 색 (아침, 낮, 저녁, 밤). 그림은 한 벌, 분위기는 조명으로
const TONES := [
	["1회차 (따뜻하게)", [Color("#ffe4c8"), Color("#ffefdc"), Color("#ffc293"), Color("#3c4672")]],
	["평소", [Color("#f2ecea"), Color.WHITE, Color("#e8c6ad"), Color("#343e66")]],
	["2회차 (차갑게)", [Color("#d9e0ec"), Color("#d6dde8"), Color("#bdb3b8"), Color("#28304f")]],
]
const FOG_LEVELS := [0.0, 0.35, 0.7]   # 화면 가장자리 해무 (날이 갈수록 짙게)

@export_file("*.json") var map_file := "res://data/maps/int_main.json"

var data: Dictionary
var layout: Array
var map: TileMapLayer
var objects: Node2D          # 가구·문·인물: 발 위치(y)로 앞뒤 정렬. 인물은 여기에 넣는다
var doors: Array[Dictionary] = []
var corridor_key := "floral"
var moon_lights: Array[PointLight2D] = []
var label_root: Node2D

# 개발용 (단독 실행 때만)
var player: CharacterBody2D
var seoha: CharacterSprite
var camera: Camera2D
var modulate_node: CanvasModulate
var grid: Node2D
var info: Label
var time_index := 1
var tone_index := 0
var fog_index := 1
var fog_rect: ColorRect


func _ready() -> void:
	data = (load(map_file) as JSON).data
	layout = data["layout"]
	corridor_key = data.get("corridor", "floral")
	map = TileMapLayer.new()
	map.tile_set = _make_tileset()
	map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(map)
	paint()

	var wall_deco := Node2D.new()      # 벽에 걸린 것: 언제나 인물 뒤
	add_child(wall_deco)
	objects = Node2D.new()
	objects.y_sort_enabled = true
	add_child(objects)
	var blockers := StaticBody2D.new()
	add_child(blockers)
	for p in data.get("props", []):
		var spr := _sprite(p[0])
		spr.offset = Vector2(-spr.texture.get_width() / 2.0, -spr.texture.get_height())
		spr.position = Vector2(p[1], p[2]) * TILE
		(wall_deco if p[4] else objects).add_child(spr)
		if p[3].size() == 4:
			blockers.add_child(_box(Rect2(Vector2(p[3][0], p[3][1]) * TILE, Vector2(p[3][2], p[3][3]) * TILE)))
	for d in data.get("doors", []):
		_add_door(d)
	for m in data.get("moonlights", []):
		moon_lights.append(_make_light(Vector2(m[0], m[1]) * TILE, m[2]))
	set_night(false)

	label_root = Node2D.new()
	label_root.visible = false
	add_child(label_root)
	for l in data.get("labels", []):
		var lab := Label.new()
		lab.text = l[0]
		lab.add_theme_font_size_override("font_size", 22)
		lab.add_theme_color_override("font_color", Color.WHITE)
		lab.add_theme_color_override("font_outline_color", Color.BLACK)
		lab.add_theme_constant_override("outline_size", 6)
		lab.position = Vector2(l[1], l[2]) * TILE - Vector2(40, 16)
		label_root.add_child(lab)

	if get_tree().current_scene == self:
		_setup_dev()


func size_px() -> Vector2:
	return Vector2(layout[0].length(), layout.size()) * TILE


func set_night(on: bool) -> void:
	for l in moon_lights:
		l.visible = on


# ── 타일 ──────────────────────────────────────────────────
func paint() -> void:
	for y in layout.size():
		var row: String = layout[y]
		for x in row.length():
			map.set_cell(Vector2i(x, y), 0, _atlas_coord(x, y))


func _is_wall_top(x: int, y: int) -> bool:
	if y < 0 or y >= layout.size() or x < 0 or x >= layout[0].length():
		return true
	return layout[y][x] == "#"


func _atlas_coord(x: int, y: int) -> Vector2i:
	var ch: String = layout[y][x]
	if ch == "#":
		var idx := int(_is_wall_top(x, y - 1)) + 2 * int(_is_wall_top(x + 1, y)) \
			+ 4 * int(_is_wall_top(x, y + 1)) + 8 * int(_is_wall_top(x - 1, y))
		return WALL_AUTO + Vector2i(idx % 4, idx / 4)
	if ch == "W":
		var k := 0   # 위로 연속된 벽 앞면 수 → 몰딩(0) / 회벽(1) / 판벽(2)
		while y - k - 1 >= 0 and layout[y - k - 1][x] == "W":
			k += 1
		return WALL_FACE + Vector2i(x % 2, mini(k, 2))
	var f: Array
	if ch == ",":
		f = CORRIDORS[corridor_key][1]
	elif ch == "_":
		f = CORRIDORS[corridor_key][2]
	else:
		f = FLOORS[ch]
	var n: int = f[1]
	return f[0] + Vector2i(posmod(x - f[2], n), posmod(y - f[3], n))


func _make_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_physics_layer()
	var src := TileSetAtlasSource.new()
	src.texture = load(ATLAS)
	src.texture_region_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	var grid_size := src.get_atlas_grid_size()
	var half := TILE / 2.0
	var solid := {}   # 벽 앞면·윗면만 막힘
	for y in 3:
		solid[WALL_FACE + Vector2i(0, y)] = true
		solid[WALL_FACE + Vector2i(1, y)] = true
	for i in 16:
		solid[WALL_AUTO + Vector2i(i % 4, i / 4)] = true
	for y in grid_size.y:
		for x in grid_size.x:
			var c := Vector2i(x, y)
			src.create_tile(c)
			if solid.has(c):
				var td := src.get_tile_data(c, 0)
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, PackedVector2Array([
					Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]))
	return ts


# ── 가구 ──────────────────────────────────────────────────
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


# ── 문 ────────────────────────────────────────────────────
func _add_door(d: Dictionary) -> void:
	var x: int = d["x"]
	var y: int = d["y"]
	var type: String = d.get("type", "v")
	var swing: int = d.get("swing", 1)
	var node := Node2D.new()
	objects.add_child(node)
	var closed: Sprite2D
	var opened: Sprite2D = null
	var rect: Rect2   # 닫혔을 때 막는 영역 (맵 좌표)
	match type:
		"v":
			node.position = Vector2(x, y + 2) * TILE
			closed = _sprite("side_door_closed")
			closed.offset = Vector2((TILE - closed.texture.get_width()) / 2.0, -closed.texture.get_height())
			opened = _sprite("side_door_open")   # 같은 기둥 + 위 기둥에서 방 쪽으로 돌아간 문짝
			opened.offset = Vector2(closed.offset.x, -opened.texture.get_height())
			if swing < 0:
				opened.flip_h = true
				opened.offset.x = closed.offset.x + closed.texture.get_width() - opened.texture.get_width()
			rect = Rect2(Vector2(x, y) * TILE, Vector2(TILE, 2 * TILE))
		"h":
			node.position = Vector2(x, y + 1) * TILE
			closed = _sprite("side_door_closed_h")
			var cy := -TILE + (TILE - closed.texture.get_height()) / 2.0
			closed.offset = Vector2(0, cy)
			opened = _sprite("side_door_open_h")   # 왼쪽 기둥에서 아래 방 쪽으로 열린 문짝
			opened.offset = Vector2(0, cy)
			if swing < 0:
				opened.flip_v = true
				opened.offset.y = cy + closed.texture.get_height() - opened.texture.get_height()
			rect = Rect2(Vector2(x, y) * TILE, Vector2(2 * TILE, TILE))
		"f":
			node.position = Vector2(x + 1, y + 4) * TILE
			closed = _sprite(d.get("sprite", "door"))
			closed.offset = Vector2(-closed.texture.get_width() / 2.0, -closed.texture.get_height())
			rect = Rect2(Vector2(x, y + 3) * TILE, Vector2(2 * TILE, TILE))
			# 닫혀 있을 때는 문 위 벽 윗면도 덮어서 벽이 이어져 보이게 (열리면 통로가 드러남)
			var atlas: Texture2D = load(ATLAS)
			for i in 2:
				var lintel := Sprite2D.new()
				lintel.texture = atlas
				lintel.region_enabled = true
				var c := WALL_AUTO + Vector2i(11 % 4, 11 / 4)   # 위·왼쪽·오른쪽이 벽인 윗면
				lintel.region_rect = Rect2(Vector2(c) * TILE, Vector2(TILE, TILE))
				lintel.centered = false
				lintel.position = Vector2(i - 1, -4) * TILE
				lintel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				closed.add_child(lintel)
	node.add_child(closed)
	if opened:
		node.add_child(opened)
	var body := StaticBody2D.new()
	body.add_child(_box(Rect2(rect.position - node.position, rect.size)))
	node.add_child(body)
	var door := {"closed": closed, "opened": opened, "body": body, "rect": rect,
		"center": rect.get_center(), "locked": d.get("locked", false)}
	doors.append(door)
	_set_door(door, d.get("open", false))


func _set_door(door: Dictionary, open: bool) -> void:
	door["open"] = open
	door["closed"].visible = not open
	if door["opened"]:
		door["opened"].visible = open
	(door["body"].get_child(0) as CollisionShape2D).set_deferred("disabled", open)


## 발 상자(feet)와 가까운 문을 열고 닫는다. 잠긴 문이면 "locked", 아무 문도 없으면 ""
func toggle_door_near(feet: Rect2) -> String:
	var best: Dictionary = {}
	var best_d := 1.8 * TILE
	for door in doors:
		var dist: float = (door["center"] as Vector2).distance_to(feet.get_center())
		if dist < best_d:
			best_d = dist
			best = door
	if best.is_empty():
		return ""
	if best["locked"]:
		return "locked"
	if best["open"] and feet.intersects(best["rect"]):
		return "blocked"   # 문 자리에 서 있으면 닫지 않음 (갇힘 방지)
	_set_door(best, not best["open"])
	return "opened" if best["open"] else "closed"


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


# ── 개발용: 단독 실행 ─────────────────────────────────────
func _setup_dev() -> void:
	grid = _make_grid()
	grid.visible = false
	add_child(grid)
	player = CharacterBody2D.new()
	var sp: Array = data.get("spawn", [2, 2])
	player.position = Vector2(sp[0], sp[1]) * TILE
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
	camera.limit_right = int(size_px().x)
	camera.limit_bottom = int(size_px().y)
	camera.position_smoothing_enabled = true
	player.add_child(camera)
	modulate_node = CanvasModulate.new()
	add_child(modulate_node)
	var hud := CanvasLayer.new()
	add_child(hud)
	info = Label.new()
	info.position = Vector2(16, 12)
	info.add_theme_color_override("font_color", Color.WHITE)
	info.add_theme_color_override("font_outline_color", Color.BLACK)
	info.add_theme_constant_override("outline_size", 6)
	hud.add_child(info)
	var fog_layer := CanvasLayer.new()   # 조명(CanvasModulate)의 영향을 받지 않는 화면 효과
	fog_layer.layer = 5
	add_child(fog_layer)
	fog_rect = ColorRect.new()
	fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sea_fog.gdshader")
	fog_rect.material = mat
	fog_layer.add_child(fog_rect)
	_apply_time()


func feet_rect() -> Rect2:
	return Rect2(player.position + Vector2(-20, -18), Vector2(40, 18))


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	player.velocity = dir * SPEED
	player.move_and_slide()
	seoha.walk(dir)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_E:
			var r := toggle_door_near(feet_rect())
			if r == "locked":
				_update_info("잠겨 있다.")
		KEY_V:
			tone_index = (tone_index + 1) % TONES.size()
			_apply_time()
		KEY_F:
			fog_index = (fog_index + 1) % FOG_LEVELS.size()
			_apply_time()
		KEY_T:
			time_index = (time_index + 1) % TIMES.size()
			_apply_time()
		KEY_Z:
			camera.zoom = Vector2.ONE * (0.75 if camera.zoom.x > 0.9 else (0.5 if camera.zoom.x > 0.6 else 1.0))
			_update_info()
		KEY_G:
			grid.visible = not grid.visible
		KEY_L:
			label_root.visible = not label_root.visible


func _apply_time() -> void:
	modulate_node.color = TONES[tone_index][1][time_index]
	set_night(time_index == 3)
	(fog_rect.material as ShaderMaterial).set_shader_parameter("strength", FOG_LEVELS[fog_index])
	_update_info()


func _update_info(note := "") -> void:
	info.text = "%s   %s · %s   안개 %d단계   확대 %d%%   %s\n방향키 걷기 · E 문 · L 방 이름 · T 시간대 · V 조명 톤 · F 안개 · Z 확대 · G 격자 · Esc" % [
		data.get("name", ""), TONES[tone_index][0], TIMES[time_index], fog_index,
		roundi(camera.zoom.x * 100), note]


func _make_grid() -> Node2D:
	var n := Node2D.new()
	var w: int = layout[0].length()
	var h: int = layout.size()
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
