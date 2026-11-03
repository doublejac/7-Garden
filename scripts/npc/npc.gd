# npc.gd
# 맵 위를 스스로 걷는 인물. InteriorMap의 길찾기(find_path)로 벽·가구를 돌아가고, 닫힌 문은 다가가서 직접 연다.
#
# 행동(mode)
#   "stay"   제자리. target이 있으면 그쪽을 바라봄
#   "film"   그 자리에 서서 target을 캠코더로 찍음: 따라다니지는 않고 몸만 target 쪽으로 돌림.
#            머리 위 ● REC는 target이 보일 때(벽에 안 가릴 때)만 켜짐. 장면(이벤트)에서 잠깐 쓰는 용도
#   "wander" 집(home) 근처를 천천히 돌아다님
#   "patrol" route(발 위치 목록)를 차례로 돌며 걸음
#
# 쓰는 법
#   var npc := Npc.new(); npc.map = 맵; npc.sprite_scene = "res://scenes/characters/doyun.tscn"
#   npc.position = 발 위치; 맵.objects.add_child(npc); npc.target = 서하(CharacterBody2D); npc.mode = "film"
class_name Npc
extends CharacterBody2D

const REPATH := 0.35         # 목표가 움직이면 이 간격(초)마다 길을 다시 찾음

@export var sprite_scene := "res://scenes/characters/doyun.tscn"
@export var display_name := "도윤"
@export var walk_speed := 125.0     # 평소 걸음 (서하 150보다 조금 느림)
@export var mode := "stay":
	set(v):
		mode = v
		_path = PackedVector2Array()
		_wait = 0.0
		if rec:
			rec.visible = v == "film"

var map: InteriorMap
var target: Node2D
var home := Vector2.ZERO
var route: Array[Vector2] = []

var sprite: CharacterSprite
var rec: Label
var _path := PackedVector2Array()
var _goal := Vector2.INF
var _repath_t := 0.0
var _wait := 0.0
var _route_i := 0
var _stuck_t := 0.0
var _last_pos := Vector2.ZERO
var _rec_t := 0.0
var _face := Vector2.DOWN


func _ready() -> void:
	collision_layer = 2          # 서하(층 1)는 NPC에 막히지 않음 → 문간에서 서로 갇히지 않게
	collision_mask = 1           # NPC는 벽·가구·문에 막힘
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(48, 16)     # 길찾기 상자(56×20)보다 살짝 작게: 모서리에 걸리지 않게
	shape.shape = r
	shape.position = Vector2(0, -10)
	add_child(shape)
	sprite = load(sprite_scene).instantiate()
	add_child(sprite)
	rec = Label.new()
	rec.text = "● REC"
	rec.add_theme_color_override("font_color", Color("#ff3b3b"))
	rec.add_theme_color_override("font_outline_color", Color.BLACK)
	rec.add_theme_constant_override("outline_size", 4)
	rec.add_theme_font_size_override("font_size", 14)
	rec.position = Vector2(-24, -212)
	rec.visible = mode == "film"
	add_child(rec)
	if home == Vector2.ZERO:
		home = position
	_last_pos = position


func _physics_process(delta: float) -> void:
	if map == null:
		return
	_rec_t += delta
	if rec.visible:
		rec.modulate.a = 1.0 if fmod(_rec_t, 1.0) < 0.6 else 0.25
	match mode:
		"film":
			_do_film()
		"wander":
			_do_wander(delta)
		"patrol":
			_do_patrol(delta)
		_:
			_stand_facing_target()


# ── 행동 ─────────────────────────────────────────────────
func _do_film() -> void:
	_stand_facing_target()
	rec.visible = target != null and _can_see(target.position)


func _do_wander(delta: float) -> void:
	if _path.is_empty():
		_wait -= delta
		if _wait > 0.0:
			return _stand()
		for i in 12:   # 집 근처(반지름 4칸)에서 걸어갈 수 있는 곳을 고름
			var p := home + Vector2(randf_range(-4, 4), randf_range(-3, 3)) * InteriorMap.TILE
			if map.is_walkable(p):
				_set_goal(p)
				break
		_wait = randf_range(2.0, 4.5)
		if _path.is_empty():
			return _stand()
	_follow_path(delta, walk_speed * 0.8)


func _do_patrol(delta: float) -> void:
	if route.is_empty():
		return _stand()
	if _path.is_empty():
		_wait -= delta
		if _wait > 0.0:
			return _stand()
		_route_i = (_route_i + 1) % route.size()
		_set_goal(route[_route_i])
		_wait = 1.2
	_follow_path(delta, walk_speed)


# ── 걷기 ─────────────────────────────────────────────────
func _chase(goal: Vector2, delta: float, speed: float, repath := true) -> void:
	_repath_t -= delta
	if _path.is_empty() or (repath and _repath_t <= 0.0 and goal.distance_to(_goal) > 24.0):
		_set_goal(goal)
		_repath_t = REPATH
	_follow_path(delta, speed)


func _set_goal(goal: Vector2) -> void:
	_goal = goal
	_path = map.find_path(position, goal)
	if _path.size() > 0:
		_path.remove_at(0)   # 첫 점 = 지금 서 있는 칸


func _follow_path(delta: float, speed: float) -> void:
	while _path.size() > 0 and position.distance_to(_path[0]) < 6.0:
		_path.remove_at(0)
	if _path.is_empty():
		return _stand()
	var next := _path[0]
	var door := map.closed_door_near(next, 40.0)   # 가는 길에 닫힌 문 → 앞에서 엶
	if not door.is_empty() and position.distance_to((door["rect"] as Rect2).get_center()) < 120.0:
		map.open_door(door)
	var dir := (next - position).normalized()
	velocity = dir * speed
	move_and_slide()
	_walk_anim(dir, speed)
	# 걸리면(0.6초 동안 거의 못 움직임) 길을 새로 찾음
	if position.distance_to(_last_pos) < 1.0:
		_stuck_t += delta
		if _stuck_t > 0.6:
			_stuck_t = 0.0
			if _goal != Vector2.INF:
				_set_goal(_goal)
	else:
		_stuck_t = 0.0
	_last_pos = position


func _walk_anim(dir: Vector2, speed: float) -> void:
	# 대각선으로 갈 때 위·옆 그림이 깜빡이지 않게: 한쪽이 확실히 클 때만 방향을 바꿈
	var ax := absf(dir.x)
	var ay := absf(dir.y)
	if ax > ay * 1.3:
		_face = Vector2(signf(dir.x), 0)
	elif ay > ax * 1.3:
		_face = Vector2(0, signf(dir.y))
	sprite.speed_scale = speed / 150.0
	sprite.walk(_face)


func _stand() -> void:
	velocity = Vector2.ZERO
	sprite.speed_scale = 1.0
	sprite.stand()


func _stand_facing_target() -> void:
	if target:
		var v := target.position - position
		if absf(v.x) > absf(v.y):
			sprite.facing = "right" if v.x > 0 else "left"
		else:
			sprite.facing = "down" if v.y > 0 else "up"
	_stand()


func _can_see(p: Vector2) -> bool:
	var q := PhysicsRayQueryParameters2D.create(position + Vector2(0, -40), p + Vector2(0, -40), 1)
	q.exclude = [get_rid()]
	if target is CollisionObject2D:
		q.exclude.append((target as CollisionObject2D).get_rid())
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()
