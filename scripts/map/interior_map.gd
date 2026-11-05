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
#   npcs     : {id, name, scene, x, y, mode, route} 스스로 걷는 인물 (scripts/npc/npc.gd). 단독 실행 때만 생김
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
	"B": [Vector2i(6, 0), 2, 0, 0],   # 화장실 흰 육각 타일
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
var nav_blocks: Array[Rect2] = []   # 길찾기용 막힌 영역 (벽 제외: 벽은 layout에서 바로 읽음)
var nav: AStarGrid2D                # 인물(NPC) 길찾기: NAV px 칸, 칸 가운데 = 발 위치
const NAV := 32

# 개발용 (단독 실행 때만)
var player: CharacterBody2D
var avatar: CharacterSprite
const CHARACTERS := [["서하", "res://scenes/characters/seoha.tscn"], ["채린", "res://scenes/characters/chaerin.tscn"], ["도윤", "res://scenes/characters/doyun.tscn"]]
var char_index := 0
var npcs: Array[Npc] = []
const NPC_MODES := [["wander", "배회"], ["stay", "가만히"], ["film", "촬영"]]
var npc_mode_i := 0
var camera: Camera2D
var modulate_node: CanvasModulate
var grid: Node2D
var info: Label
var time_index := 1
var tone_index := 0
var fog_index := 1
var fog_rect: ColorRect
var interactables: Array = []        # data["interact"]: E로 살펴보는 곳 (예: 그림책을 넣어 둔 협탁 서랍)
var hint: Label                      # 가까이 가면 뜨는 "E 협탁 서랍" 안내
var _book: Storybook                 # 서랍에서 꺼내 보는 그림책 (열려 있는 동안 걷기·단축키 멈춤)
const BOOK_DEV_STEPS := [0, 3, 5, 7, 9, 11, 14]   # B 키(개발용): 읽은 쪽 바꾸기 = 밤마다 읽는 분량


func _ready() -> void:
	data = (load(map_file) as JSON).data
	layout = data["layout"]
	corridor_key = data.get("corridor", "floral")
	map = TileMapLayer.new()
	map.tile_set = _make_tileset()
	map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(map)
	paint()
	add_child(_make_floor_trim())

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
			# 좌우는 그림 폭(90%)에 맞춰 옆에서 다가가도 팔이 파고들지 않게, 앞뒤 깊이는 데이터 값 사용
			var w := spr.texture.get_width() * 0.9
			var r := Rect2(Vector2(p[1] * TILE - w / 2.0, p[3][1] * TILE), Vector2(w, p[3][3] * TILE))
			blockers.add_child(_box(r))
			nav_blocks.append(r)
	for d in data.get("doors", []):
		_add_door(d)
	interactables = data.get("interact", [])
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
	var closed: Node2D = Node2D.new()   # 닫혔을 때만 보이는 것
	var leaf: Sprite2D                   # 열리고 닫히며 움직이는 문짝 (경첩이 원점)
	var rect: Rect2                      # 닫혔을 때 막는 영역 (맵 좌표)
	var leaf_rect := Rect2()             # 열렸을 때 문짝이 막는 영역 (맵 좌표)
	var posts: Array[Rect2] = []         # 언제나 막는 문틀 기둥 (맵 좌표)
	var axis := "x"
	match type:
		"v":   # 세로 벽 문: 위에서 본 문짝이 위 경첩을 축으로 돌아, 방 쪽 벽면에 납작하게 붙으며 열림
			node.position = Vector2(x, y) * TILE + Vector2(0, 4)   # 앞뒤 정렬 기준 = 경첩 (열린 문짝은 지나가는 서하 뒤에)
			var sill := _sprite("side_threshold_v")   # 문 자리 바닥의 문지방
			sill.position = Vector2(x, y) * TILE - node.position
			sill.z_index = -1
			node.add_child(sill)
			leaf = _sprite("side_leaf_v")
			var lw := leaf.texture.get_width()
			# 경첩 = 문 자리 위 끝, 방 쪽 벽 가장자리 (닫히면 문짝이 벽 선에 맞춰 섬)
			var hinge := Vector2((x + 0.5) * TILE + swing * (TILE / 2.0 - lw / 2.0 - 4), y * TILE + 4)
			leaf.position = hinge - node.position
			leaf.offset = Vector2(-lw / 2.0, 0)
			leaf.set_meta("open_rot", -PI if swing > 0 else PI)
			for py in [y * TILE, (y + 2) * TILE - 12]:
				posts.append(Rect2(Vector2(x * TILE, py), Vector2(TILE, 12)))
			axis = "rot"
			rect = Rect2(Vector2(x * TILE, y * TILE), Vector2(TILE, 2 * TILE))
		"h":   # 가로 벽 문(아래 방으로 들어가는 문): 옆문 부품을 눕혀 씀. 왼쪽 경첩을 축으로 돌아 벽면에 붙음
			var sill := _sprite("side_threshold_h")
			var leaf_tex: Texture2D = load(PROP_DIR + "side_leaf_h.png")
			var lh := leaf_tex.get_height()
			var hinge := Vector2(x * TILE + 4, (y + 0.5) * TILE + swing * (TILE / 2.0 - lh / 2.0 - 4))
			node.position = Vector2(x * TILE, maxf(hinge.y, y * TILE + 8))
			sill.position = Vector2(x, y) * TILE - node.position
			sill.z_index = -1
			node.add_child(sill)
			leaf = _sprite("side_leaf_h")
			leaf.position = hinge - node.position
			leaf.offset = Vector2(0, -lh / 2.0)
			leaf.set_meta("open_rot", PI if swing > 0 else -PI)
			for px in [x * TILE, (x + 2) * TILE - 12]:
				posts.append(Rect2(Vector2(px, y * TILE), Vector2(12, TILE)))
			axis = "rot"
			rect = Rect2(Vector2(x * TILE, y * TILE), Vector2(2 * TILE, TILE))
		"f":   # 정면 문: 닫힘 → 반쯤 열림 → 열림 세 장을 바꿔 보여 줌. 그림 위쪽에 벽(몰딩·회벽)까지 포함
			var dw: int = d.get("w", 2)   # 문 자리 폭(칸)
			node.position = Vector2(x + dw / 2.0, y + 4) * TILE
			var base: String = d.get("sprite", "glass_door")
			var frames: Array[Texture2D] = []
			for i in 3:
				var path := PROP_DIR + "%s_%d.png" % [base, i]
				if ResourceLoader.exists(path):
					frames.append(load(path))
			if frames.is_empty():
				frames.append(load(PROP_DIR + base + ".png"))
			leaf = Sprite2D.new()
			leaf.texture = frames[0]
			leaf.centered = false
			leaf.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			leaf.scale.x = dw * TILE / float(frames[0].get_width())   # 문 자리 폭에 꼭 맞게
			var fh := frames[0].get_height()   # 닫힌 문 높이 (문틀 위 ~ 바닥)
			leaf.position = Vector2(-dw * TILE / 2.0, -fh)
			# 열린 문 그림에서 실제로 비어 있는(지나갈 수 있는) 폭을 재서, 양옆 문틀·열린 문짝 자리는 막음
			# (안 그러면 문 자리 안에서 옆으로 걸어 문틀·문짝을 뚫고 지나가 보임)
			var clear := _front_door_clear(frames[frames.size() - 1])
			var sx := dw * TILE / float(frames[0].get_width())
			var x0 := x * TILE
			for pr in [Rect2(x0, y * TILE, clear.x * sx, 4 * TILE),
					Rect2(x0 + clear.y * sx, y * TILE, dw * TILE - clear.y * sx, 4 * TILE)]:
				if pr.size.x > 1.0:
					posts.append(pr)
			# 문틀 위쪽은 옆 벽과 같은 벽 앞면 타일을 이어 그림 (몰딩·판벽 선이 옆 벽과 맞게)
			var atlas_face: Texture2D = load(ATLAS)
			for i in dw:
				var top_wall := Sprite2D.new()
				top_wall.texture = atlas_face
				top_wall.region_enabled = true
				top_wall.region_rect = Rect2(Vector2(WALL_FACE.x + (x + i) % 2, WALL_FACE.y) * TILE, Vector2(TILE, 3 * TILE - fh))
				top_wall.centered = false
				top_wall.position = Vector2(i * TILE - dw * TILE / 2.0, -3 * TILE)
				top_wall.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				node.add_child(top_wall)
			leaf.set_meta("frames", frames)
			rect = Rect2(Vector2(x, y + 3) * TILE, Vector2(dw * TILE, TILE))
			# 문 위 벽 윗면 (언제나): 열린 문으로 지나갈 때도 문 위 벽이 이어져 보이게
			var atlas: Texture2D = load(ATLAS)
			var lintels := Node2D.new()
			for i in dw:
				var lintel := Sprite2D.new()
				lintel.texture = atlas
				lintel.region_enabled = true
				var c := WALL_AUTO + Vector2i(11 % 4, 11 / 4)   # 위·왼쪽·오른쪽이 벽인 윗면
				lintel.region_rect = Rect2(Vector2(c) * TILE, Vector2(TILE, TILE))
				lintel.centered = false
				lintel.position = Vector2(i * TILE - dw * TILE / 2.0, -4 * TILE)
				lintel.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				lintels.add_child(lintel)
			node.add_child(lintels)
	node.add_child(closed)
	node.add_child(leaf)
	# 문틀 기둥: 그림은 벽 윗면 테두리가 대신하고, 충돌만 언제나 막음 (모서리로 빠져나가지 않게)
	var fixed := StaticBody2D.new()
	for pr in posts:
		fixed.add_child(_box(Rect2(pr.position - node.position, pr.size)))
	node.add_child(fixed)
	var body := StaticBody2D.new()   # 닫혔을 때
	body.add_child(_box(Rect2(rect.position - node.position, rect.size)))
	node.add_child(body)
	var leaf_body := StaticBody2D.new()   # 열렸을 때 문짝
	if leaf_rect.has_area():
		leaf_body.add_child(_box(Rect2(leaf_rect.position - node.position, leaf_rect.size)))
	node.add_child(leaf_body)
	nav_blocks.append_array(posts)
	if leaf_rect.has_area() and not (AUTO_DOORS and not d.get("locked", false) and not d.get("manual", false)):
		nav_blocks.append(leaf_rect)   # 손으로 여는 문: 열린 문짝 자리는 늘 피해 감
	if d.get("locked", false):
		nav_blocks.append(rect)
	var door := {"type": type, "closed": closed, "leaf": leaf, "axis": axis, "body": body, "leaf_body": leaf_body,
		"rect": rect, "leaf_rect": leaf_rect, "center": rect.get_center(), "locked": d.get("locked", false),
		"manual": d.get("manual", false), "tween": null}
	doors.append(door)
	_set_door(door, d.get("open", false), false)


## 열린 정면 문 그림의 아래쪽 줄에서 가장 넓게 비어(트여) 있는 구간 [시작, 끝] (그림 픽셀)
func _front_door_clear(tex: Texture2D) -> Vector2:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var y := img.get_height() - 40
	var best := Vector2(0, img.get_width())
	var best_w := -1
	var start := -1
	for x in img.get_width() + 1:
		var empty := x < img.get_width() and img.get_pixel(x, y).a < 0.8   # 열린 문 안쪽은 반투명 어둠, 문틀·문짝은 불투명
		if empty and start < 0:
			start = x
		elif not empty and start >= 0:
			if x - start > best_w:
				best_w = x - start
				best = Vector2(start, x)
			start = -1
	return best


func _set_door(door: Dictionary, open: bool, animate := true) -> void:
	door["open"] = open
	var leaf: Sprite2D = door["leaf"]
	var type: String = door["type"]
	if door["tween"]:
		(door["tween"] as Tween).kill()
	if type == "f":
		# 정면 문: 그림 세 장(닫힘·반쯤·열림)을 차례로
		var frames: Array = leaf.get_meta("frames")
		var last := frames.size() - 1
		if last == 0:
			pass
		elif animate:
			var order := [0, 1, last] if open else [last, 1, 0]
			var tw := create_tween()
			for i in order.size():
				var tex: Texture2D = frames[order[i]]
				tw.tween_callback(func(): leaf.texture = tex)
				if i < order.size() - 1:
					tw.tween_interval(0.08)
			door["tween"] = tw
		else:
			leaf.texture = frames[last if open else 0]
	elif door["axis"] == "rot":
		var to: float = leaf.get_meta("open_rot") if open else 0.0
		if animate:
			var tw := create_tween()
			tw.tween_property(leaf, "rotation", to, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			door["tween"] = tw
		else:
			leaf.rotation = to
	else:
		# 가로 문: 문짝이 경첩 쪽으로 접히며 흐려짐
		var prop := "scale:x" if door["axis"] == "x" else "scale:y"
		var target := 0.25 if open else 1.0
		var alpha := 0.0 if open else 1.0
		if animate:
			var tw := create_tween().set_parallel(true)
			tw.tween_property(leaf, prop, target, 0.2).set_trans(Tween.TRANS_SINE)
			tw.tween_property(leaf, "modulate:a", alpha, 0.2)
			door["tween"] = tw
		else:
			leaf.set_indexed(NodePath(prop), target)
			leaf.modulate.a = alpha
	(door["body"].get_child(0) as CollisionShape2D).set_deferred("disabled", open)
	if door["leaf_body"].get_child_count() > 0:
		# 자동문의 열린 문짝은 그림만 (벽에 붙은 문짝에 몸이 걸리지 않게)
		(door["leaf_body"].get_child(0) as CollisionShape2D).set_deferred("disabled", not open or _is_auto(door))


## 발 상자(feet)와 가까운 문을 열고 닫는다. 잠긴 문이면 "locked", 아무 문도 없으면 ""
## 문 여닫기. 범위는 넉넉하게(문 가운데에서 2.4칸). 닫을 때 몸이 문 자리에 살짝 걸쳐 있으면
## 밀어낼 거리를 door_push에 담아 돌려줌 (부르는 쪽에서 인물을 그만큼 옮김). 문 자리 한가운데면 닫지 않음
var door_push := Vector2.ZERO

# ── 자동문: 누가(서하·NPC) 문 가까이 오면 저절로 열리고, 모두 멀어지면 닫힘 ──
# 열린 문짝은 그림만 있고 몸에 걸리지 않음. 잠긴 문과 data의 "manual": true 문은 예전처럼 E로
const AUTO_DOORS := true
const AUTO_OPEN_GAP := 0.7 * TILE      # 발 상자와 문 자리 사이가 이만큼 가까워지면 엶
const AUTO_CLOSE_GAP := 1.3 * TILE     # 모두 이만큼 멀어지면 닫음 (사이 구간은 그대로 → 깜빡임 방지)


func _is_auto(door: Dictionary) -> bool:
	return AUTO_DOORS and not door["locked"] and not door.get("manual", false)


## 문틀 모서리에 걸렸을 때: 문을 향해 걷는 중이면 문 가운데 쪽으로 옆걸음 시켜 자연스럽게 빠져들어 가게
func _door_slide(dir: Vector2, delta: float) -> void:
	var f := feet_rect()
	for door in doors:
		if not door["open"]:
			continue
		var r: Rect2 = door["rect"]
		if _rect_gap(r, f) > 0.6 * TILE:
			continue
		var c := r.get_center()
		if door["type"] == "v" and absf(dir.x) > 0.5 and absf(dir.y) < 0.5:
			var dy := c.y - (f.get_center().y)
			if absf(dy) > 2.0:
				player.move_and_collide(Vector2(0, signf(dy) * minf(absf(dy), SPEED * delta)))
			return
		if door["type"] != "v" and absf(dir.y) > 0.5 and absf(dir.x) < 0.5:
			var dx := c.x - f.get_center().x
			if absf(dx) > 2.0:
				player.move_and_collide(Vector2(signf(dx) * minf(absf(dx), SPEED * delta), 0))
			return


func _feet_of(body: Node2D) -> Rect2:
	return Rect2(body.position + Vector2(-28, -20), Vector2(56, 20))


func _update_auto_doors() -> void:
	var feet: Array[Rect2] = []
	if player:
		feet.append(feet_rect())
	for npc in npcs:
		if npc.visible and npc.process_mode != Node.PROCESS_MODE_DISABLED:
			feet.append(_feet_of(npc))
	for door in doors:
		if not _is_auto(door):
			continue
		var r: Rect2 = door["rect"]
		var lr: Rect2 = door["leaf_rect"]
		var near := INF
		var inside := false
		for f in feet:
			near = minf(near, _rect_gap(r, f))
			inside = inside or f.intersects(r) or (lr.has_area() and f.intersects(lr))
		if not door["open"] and near <= AUTO_OPEN_GAP:
			_set_door(door, true)
		elif door["open"] and near >= AUTO_CLOSE_GAP and not inside:
			_set_door(door, false)

func toggle_door_near(feet: Rect2) -> String:
	door_push = Vector2.ZERO
	var best: Dictionary = {}
	var best_d := 2.4 * TILE
	for door in doors:
		if _is_auto(door):
			continue   # 자동문은 E로 여닫지 않음
		var r: Rect2 = door["rect"]
		var dist: float = r.get_center().distance_to(feet.get_center())
		dist = minf(dist, _rect_gap(r, feet) + TILE * 0.5)   # 긴 문(2칸)은 가장자리까지 거리도 봄
		if dist < best_d:
			best_d = dist
			best = door
	if best.is_empty():
		return ""
	if best["locked"]:
		return "locked"
	if best["open"] and feet.intersects(best["rect"]):
		var push := _push_out(best["rect"], feet, best["type"])
		if push == Vector2.ZERO:
			return "blocked"   # 문 자리 한가운데에 서 있으면 닫지 않음 (갇힘 방지)
		door_push = push
	if not best["open"] and (best["leaf_rect"] as Rect2).has_area() and feet.intersects(best["leaf_rect"]):
		return "blocked"   # 문짝이 펼쳐질 자리에 서 있으면 열지 않음
	_set_door(best, not best["open"])
	return "opened" if best["open"] else "closed"


func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return Vector2(dx, dy).length()


## 문 자리(rect)에 걸친 발을 문을 가로지르는 방향으로 가까운 쪽으로 빼낼 거리.
## 36px 넘게 밀어야 하면(문 자리 한가운데) ZERO → 닫지 않음
func _push_out(r: Rect2, feet: Rect2, type: String) -> Vector2:
	var p: Vector2
	if type == "v":
		var left := r.position.x - feet.end.x - 1
		var right := r.end.x - feet.position.x + 1
		p = Vector2(left if absf(left) < absf(right) else right, 0)
	else:
		var up := r.position.y - feet.end.y - 1
		var down := r.end.y - feet.position.y + 1
		p = Vector2(0, up if absf(up) < absf(down) else down)
	return p if p.length() <= 36.0 else Vector2.ZERO


# ── 길찾기 (NPC) ──────────────────────────────────────────
## 발 위치 격자. 각 칸 가운데에 발(56×20 상자)을 놓았을 때 벽·가구·문틀·잠긴 문에 닿으면 막힌 칸.
## 잠기지 않은 문은 닫혀 있어도 지나갈 수 있는 칸으로 둠 (NPC가 다가가서 직접 엶)
func build_nav() -> void:
	var w := int(size_px().x) / 8
	var h := int(size_px().y) / 8
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in layout.size():
		var row: String = layout[y]
		for x in row.length():
			if row[x] == "#" or row[x] == "W":
				_fill(solid, w, Rect2(x * TILE, y * TILE, TILE, TILE))
	for r in nav_blocks:
		_fill(solid, w, r)
	nav = AStarGrid2D.new()
	nav.region = Rect2i(0, 0, int(size_px().x) / NAV, int(size_px().y) / NAV)
	nav.cell_size = Vector2(NAV, NAV)
	nav.offset = Vector2(NAV / 2.0, NAV / 2.0)
	nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	nav.update()
	for cy in nav.region.size.y:
		for cx in nav.region.size.x:
			var c := Vector2(cx * NAV + NAV / 2.0, cy * NAV + NAV / 2.0)
			var x0 := int(c.x - 28) / 8
			var x1 := int(c.x + 27) / 8
			var y0 := int(c.y - 20) / 8
			var y1 := int(c.y - 1) / 8
			var blocked := x0 < 0 or y0 < 0 or x1 >= w or y1 >= h
			if not blocked:
				for yy in range(y0, y1 + 1):
					for xx in range(x0, x1 + 1):
						if solid[yy * w + xx]:
							blocked = true
							break
					if blocked:
						break
			nav.set_point_solid(Vector2i(cx, cy), blocked)


func _fill(solid: PackedByteArray, w: int, r: Rect2) -> void:
	var h := solid.size() / w
	for yy in range(maxi(0, int(r.position.y) / 8), mini(h, int(ceil(r.end.y / 8.0)))):
		for xx in range(maxi(0, int(r.position.x) / 8), mini(w, int(ceil(r.end.x / 8.0)))):
			solid[yy * w + xx] = 1


func _nav_cell(pos: Vector2) -> Vector2i:
	var c := Vector2i(int(pos.x) / NAV, int(pos.y) / NAV)
	c = c.clamp(Vector2i.ZERO, nav.region.size - Vector2i.ONE)
	if not nav.is_point_solid(c):
		return c
	for rad in range(1, 5):   # 막힌 칸이면 가장 가까운 빈칸
		var best := Vector2i(-1, -1)
		var bd := INF
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				var n := c + Vector2i(dx, dy)
				if nav.is_in_boundsv(n) and not nav.is_point_solid(n):
					var d := (Vector2(n) * NAV + Vector2.ONE * NAV / 2.0).distance_to(pos)
					if d < bd:
						bd = d
						best = n
		if best.x >= 0:
			return best
	return c


## from → to 발 위치 경로 (맵 좌표). 못 가면 갈 수 있는 데까지
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if nav == null:
		build_nav()
	return nav.get_point_path(_nav_cell(from), _nav_cell(to), true)


func is_walkable(pos: Vector2) -> bool:
	if nav == null:
		build_nav()
	var c := Vector2i(int(pos.x) / NAV, int(pos.y) / NAV)
	return nav.is_in_boundsv(c) and not nav.is_point_solid(c)


## pos(발)가 닫힌 문 자리 근처면 그 문 (NPC가 열 때 씀)
func closed_door_near(pos: Vector2, margin := 24.0) -> Dictionary:
	for door in doors:
		if not door["open"] and not door["locked"] and (door["rect"] as Rect2).grow(margin).has_point(pos):
			return door
	return {}


func open_door(door: Dictionary) -> void:
	if not door["open"]:
		_set_door(door, true)


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
	prect.size = Vector2(56, 20)   # 서하 몸 폭에 가깝게: 벽·가구에 팔이 파고들지 않게
	shape.shape = prect
	shape.position = Vector2(0, -10)
	player.add_child(shape)
	objects.add_child(player)
	_spawn_npcs()
	_set_character(0)
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
	hint = Label.new()
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color.WHITE)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 6)
	hint.visible = false
	hud.add_child(hint)
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


## 맵 데이터의 npcs: {id, name, scene, x, y, mode, route: [[x, y], ...]}  (타일 단위, 발 위치)
func _spawn_npcs() -> void:
	for n in data.get("npcs", []):
		var npc := Npc.new()
		npc.map = self
		npc.sprite_scene = n["scene"]
		npc.display_name = n.get("name", n["id"])
		npc.position = Vector2(n["x"], n["y"]) * TILE
		npc.home = npc.position
		for r in n.get("route", []):
			npc.route.append(Vector2(r[0], r[1]) * TILE)
		npc.target = player
		npc.mode = n.get("mode", "stay")
		objects.add_child(npc)
		npcs.append(npc)


## 개발용: 조종하는 인물 바꾸기 (C 키). 바라보던 방향은 그대로
func _set_character(i: int) -> void:
	var facing := "down"
	if avatar:
		facing = avatar.facing
		avatar.queue_free()
	char_index = i
	avatar = load(CHARACTERS[i][1]).instantiate()
	avatar.facing = facing
	player.add_child(avatar)
	avatar.stand()
	for npc in npcs:   # 지금 조종하는 인물과 같은 NPC는 숨김
		var me: bool = npc.display_name == CHARACTERS[i][0]
		npc.visible = not me
		npc.process_mode = Node.PROCESS_MODE_DISABLED if me else Node.PROCESS_MODE_INHERIT
		npc.collision_layer = 0 if me else 2


func feet_rect() -> Rect2:
	return Rect2(player.position + Vector2(-28, -20), Vector2(56, 20))


func _physics_process(_delta: float) -> void:
	if player == null:
		return
	_update_auto_doors()
	if _book:
		player.velocity = Vector2.ZERO
		avatar.walk(Vector2.ZERO)
		return
	var it := interactable_near()
	hint.visible = not it.is_empty()
	if hint.visible:
		hint.text = "E  " + String(it.get("name", "살펴보기"))
		var p := get_viewport().get_canvas_transform() * (Vector2(it.x, it.y) * TILE)
		hint.position = p + Vector2(-hint.size.x / 2.0, -110)
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	player.velocity = dir * SPEED
	player.move_and_slide()
	if player.get_slide_collision_count() > 0:
		_door_slide(dir, _delta)
	avatar.walk(dir)


func _unhandled_input(event: InputEvent) -> void:
	if _book or player == null or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE:
			get_tree().quit()
		KEY_C:
			_set_character((char_index + 1) % CHARACTERS.size())
			_update_info()
		KEY_N:
			npc_mode_i = (npc_mode_i + 1) % NPC_MODES.size()
			for npc in npcs:
				npc.mode = NPC_MODES[npc_mode_i][0]
			_update_info()
		KEY_B:
			var i := BOOK_DEV_STEPS.find(GameState.book_read)
			GameState.book_read = BOOK_DEV_STEPS[(i + 1) % BOOK_DEV_STEPS.size()]
			_update_info("(개발용) 읽은 그림책: %s" % ("없음" if GameState.book_read == 0 else "%d페이지까지" % (GameState.book_read * 2 + 1)))
		KEY_E:
			var it := interactable_near()
			if not it.is_empty():
				_interact(it)
				return
			var r := toggle_door_near(feet_rect())
			if door_push != Vector2.ZERO:
				player.move_and_collide(door_push)
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


## 발 위치에서 가장 가까운, 범위 안의 살펴볼 곳 (없으면 빈 Dictionary)
func interactable_near() -> Dictionary:
	var feet := player.position
	var best := {}
	var best_d := INF
	for it in interactables:
		var d := feet.distance_to(Vector2(it.x, it.y) * TILE)
		if d <= float(it.get("range", 1.5)) * TILE and d < best_d:
			best = it
			best_d = d
	return best


func _interact(it: Dictionary) -> void:
	match String(it.id):
		"book_drawer":
			open_book_drawer()


## 협탁 서랍: 지금까지 채린에게 읽어 준 데까지(GameState.book_read) 그림책을 한꺼번에 다시 봄. 반응 대사 없음
func open_book_drawer() -> void:
	if GameState.book_read <= 0:
		_update_info("서랍 안은 비어 있다.")
		return
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_book = Storybook.new()
	_book.found_torn = GameState.flags.get("found_torn", false)
	_book.page_to = GameState.book_read
	layer.add_child(_book)
	hint.visible = false
	_book.closed.connect(func():
		_book = null
		layer.queue_free()
		_update_info("그림책을 서랍에 다시 넣었다."))


func _apply_time() -> void:
	modulate_node.color = TONES[tone_index][1][time_index]
	set_night(time_index == 3)
	(fog_rect.material as ShaderMaterial).set_shader_parameter("strength", FOG_LEVELS[fog_index])
	_update_info()


func _update_info(note := "") -> void:
	info.text = "[%s]%s  %s   %s · %s   안개 %d단계   확대 %d%%   %s\n방향키 걷기 · C 인물 바꾸기 · N 도윤 행동 · 문은 다가가면 자동 · E 살펴보기·잠긴 문 · B 읽은 그림책 페이지(개발용) · L 방 이름 · T 시간대 · V 조명 톤 · F 안개 · Z 확대 · G 격자 · Esc" % [
		CHARACTERS[char_index][0], _npc_info(), data.get("name", ""), TONES[tone_index][0], TIMES[time_index], fog_index,
		roundi(camera.zoom.x * 100), note]


func _npc_info() -> String:
	var parts := PackedStringArray()
	for npc in npcs:
		if npc.visible:
			for m in NPC_MODES:
				if m[0] == npc.mode:
					parts.append("%s: %s" % [npc.display_name, m[1]])
	return ("  · " + ", ".join(parts)) if parts.size() > 0 else ""


# ── 바닥 경계 마감: 바닥 재질이 바뀌는 선마다 나무 마감 띠 (실제 건물의 전환 몰딩처럼) ──
const TRIM_W := 10
const TRIM_W_WIDE := 16
const TRIM_EDGE := Color8(74, 62, 54)
const TRIM_FILL := Color8(122, 104, 90)
const TRIM_HI := Color8(154, 136, 118)


## 바닥 칸의 재질 (벽은 ""). 두 복도 기호(, _)는 같은 바닥이라 하나로 봄
func _floor_kind(x: int, y: int) -> String:
	if y < 0 or y >= layout.size() or x < 0 or x >= String(layout[y]).length():
		return ""
	var c := String(layout[y])[x]
	if c == "#" or c == "W":
		return ""
	return "corr" if c in [",", "_"] else c


## 재질이 다른 이웃 칸 사이의 선분들 [시작, 끝] (픽셀). 이어진 선은 하나로 합침
func floor_seams() -> Array:
	var segs: Array = []
	var h := layout.size()
	var w := String(layout[0]).length()
	for y in h:                                   # 가로로 이웃 → 세로 선
		var x := 0
		while x < w:
			var a := _floor_kind(x, y)
			var b := _floor_kind(x + 1, y)
			if a != "" and b != "" and a != b:
				segs.append([Vector2(x + 1, y) * TILE, Vector2(x + 1, y + 1) * TILE, _trim_side(a, b)])
			x += 1
	for y in h:                                   # 세로로 이웃 → 가로 선
		var x := 0
		while x < w:
			var a := _floor_kind(x, y)
			var b := _floor_kind(x, y + 1)
			if a != "" and b != "" and a != b:
				segs.append([Vector2(x, y + 1) * TILE, Vector2(x + 1, y + 1) * TILE, _trim_side(a, b)])
			x += 1
	# 같은 직선 위에서 끝이 맞닿은 선분 합치기
	var merged: Array = []
	for s in segs:
		var joined := false
		for m in merged:
			if m[1] == s[0] and m[2] == s[2] and (m[1] - m[0]).normalized() == (s[1] - s[0]).normalized():
				m[1] = s[1]
				joined = true
				break
		if not joined:
			merged.append([s[0], s[1], s[2]])
	return merged


## 띠를 어느 쪽에 붙일지: 복도 쪽으로 삐져나오지 않게 방(복도가 아닌 쪽)으로. -1 = 선의 앞(왼쪽·위), 1 = 뒤(오른쪽·아래), 0 = 가운데
func _trim_side(a: String, b: String) -> int:
	if b == "corr":
		return -1
	if a == "corr":
		return 1
	return 0


func _make_floor_trim() -> Node2D:
	var n := Node2D.new()
	var seams := floor_seams()
	n.draw.connect(func():
		for sg in seams:
			var a: Vector2 = sg[0]
			var b: Vector2 = sg[1]
			var vertical := is_equal_approx(a.x, b.x)
			var tw := TRIM_W if a.distance_to(b) <= 3 * TILE else TRIM_W_WIDE   # 넓게 트인 경계(로비 등)는 굵게
			var side: int = sg[2]
			var off := -tw / 2.0 + side * (tw / 2.0)       # 선을 기준으로 띠의 시작 (방 쪽으로 밀기)
			var r := Rect2(a + Vector2(off, 0), Vector2(tw, b.y - a.y)) if vertical \
				else Rect2(a + Vector2(0, off), Vector2(b.x - a.x, tw))
			n.draw_rect(r, TRIM_EDGE)
			n.draw_rect(r.grow(-1), TRIM_FILL)
			var hi := Rect2(r.position + Vector2(2, 1), Vector2(2, r.size.y - 2)) if vertical \
				else Rect2(r.position + Vector2(1, 2), Vector2(r.size.x - 2, 2))
			n.draw_rect(hi, TRIM_HI)
			if tw == TRIM_W_WIDE:                     # 굵은 띠는 가운데 홈 한 줄
				var mid := Rect2(r.position + Vector2(tw / 2.0 - 1, 1), Vector2(2, r.size.y - 2)) if vertical \
					else Rect2(r.position + Vector2(1, tw / 2.0 - 1), Vector2(r.size.x - 2, 2))
				n.draw_rect(mid, TRIM_EDGE)
			# 띠 아래(앞) 쪽에 아주 옅은 그늘
			var sh := Rect2(r.position + Vector2(r.size.x, 0), Vector2(2, r.size.y)) if vertical \
				else Rect2(r.position + Vector2(0, r.size.y), Vector2(r.size.x, 2))
			n.draw_rect(sh, Color(0, 0, 0, 0.12)))
	return n


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
