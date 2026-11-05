# 맵 가구 충돌 점검 (개발용): 모든 가구 그림의 바닥 부분에 발 상자를 겹쳐 놓아 막히는지, 방마다 길이 있는지.
# 실행: godot --path . res://tests/map_collision_check.tscn  (창이 잠깐 떴다 닫히며 결과를 출력)
extends Node
func wait(t): await get_tree().create_timer(t).timeout
func _ready():
	var tree := get_tree()
	await tree.process_frame
	reparent(tree.root)
	tree.current_scene = null
	tree.change_scene_to_file("res://scenes/maps/int_main.tscn")
	await wait(1.0)
	var m = tree.current_scene
	m.player.position = Vector2(-500, -500)   # 점검에 방해되지 않게 치워 둠
	await wait(0.2)
	var space: PhysicsDirectSpaceState2D = m.get_world_2d().direct_space_state
	var shape := RectangleShape2D.new()
	shape.size = Vector2(56, 20)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.exclude = [m.player.get_rid()]
	var fails := 0
	var checked := 0
	for p in m.data["props"]:
		if p[3].size() != 4 or p[4]:
			continue
		var tex: Texture2D = load(m.PROP_DIR + p[0] + ".png")
		var ext: Vector2 = m._base_extent(tex, (p[2] - p[3][1]) * 64)
		var left: float = p[1] * 64 - tex.get_width() / 2.0
		var bottom: float = p[2] * 64
		var misses := []
		var x := left + ext.x + 6
		while x <= left + ext.y - 6:
			# 발 상자 위 끝이 그림 아래 끝에서 6px 위에 오도록 (그림 바닥 부분에 발을 겹침)
			q.transform = Transform2D(0, Vector2(x, bottom - 6 + 10))
			checked += 1
			if space.intersect_shape(q, 1).is_empty():
				misses.append(int(x - left))
			x += 8
		if not misses.is_empty():
			fails += 1
			print("뚫림: ", p[0], " @", Vector2(p[1], p[2]), " 그림 x=", misses)
	print("가구 바닥 점검 ", checked, "곳, 뚫리는 가구 ", fails, "개")
	# 방마다 서하 방에서 걸어서 갈 수 있는지
	var from := Vector2(5, 8) * 64
	for l in m.data["labels"]:
		var to: Vector2 = Vector2(l[1], l[2] - 1.2) * 64
		var path: PackedVector2Array = m.find_path(from, to)
		print(("길 OK  " if path.size() > 0 else "길 없음 ") , l[0], " (", path.size(), ")")
	tree.quit()
