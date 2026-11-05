# inspect_3d.gd
# 물건 3D로 살펴보기: 화면 가운데에 물건이 떠서 마우스로 돌려 본다 (2D 게임 위에 작은 3D 창).
#   드래그: 돌리기   휠: 확대·축소   우클릭 / Esc: 닫기
#   3D 창은 낮은 해상도로 그려 크게 늘림(PIXEL배) → 픽셀아트와 같은 결
# 물건은 ITEMS에 등록. "model"에 .glb/.tscn 경로가 있으면 그걸 쓰고, 없으면 build_<id>()로 도형을 빚음
# 숨은 단서(secret): show_secret = true(2회차)일 때만 보이는 부분. 그 면을 카메라 쪽으로 돌리면
#   discovered 신호와 함께 붉은 속마음이 뜬다 (한 번만)
class_name Inspect3D
extends Control

signal closed
signal discovered(item_id: String)

const PIXEL := 3                     # 3D 창 해상도 = 화면 / PIXEL
const VIEW := Vector2i(600, 520)     # 3D 창 크기 (화면 픽셀)
const ITEMS := {
	"teddy": {
		"name": "곰돌이 인형",
		"text": "채린이 늘 안고 다니는 곰돌이. 털이 닳아 군데군데 반들반들하다.",
		"secret_text": "등에… 은빛 바늘땀. 누가 등을 갈라 무언가를 넣고 다시 꿰맸다.",
		"secret_normal": Vector3(0, 0, -1),     # 숨은 단서가 있는 면 (물건 기준)
		"model": "",                            # 나중에 Meshy 등으로 만든 모델: "res://assets/models/teddy.glb"
	},
}

@export var item_id := "teddy"
@export var show_secret := false     # 2회차: 숨은 단서가 보임

var item: Dictionary
var found := false
var _pivot: Node3D
var _camera: Camera3D
var _dragging := false
var _spin := Vector2.ZERO            # 손을 뗀 뒤 남는 회전 속도
var _yaw := 0.4
var _pitch := 0.15
var _dist := 3.2
var _desc: Label
var _inner: Label
var _idle := 0.0


func _ready() -> void:
	item = ITEMS[item_id]
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_build_viewport()
	_build_labels()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.25)


func _build_viewport() -> void:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.stretch_shrink = PIXEL
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.size = VIEW
	box.position = Vector2(640 - VIEW.x / 2.0, 70)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.own_world_3d = true
	box.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.66, 0.72)
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var key := DirectionalLight3D.new()                  # 스탠드 불빛 같은 따뜻한 주광
	key.light_color = Color(1.0, 0.88, 0.72)
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-38, 35, 0)
	vp.add_child(key)
	var rim := DirectionalLight3D.new()                  # 뒤에서 오는 차가운 해무 빛 (윤곽)
	rim.light_color = Color(0.62, 0.74, 0.86)
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-15, 200, 0)
	vp.add_child(rim)
	_camera = Camera3D.new()
	_camera.fov = 32
	vp.add_child(_camera)
	_pivot = Node3D.new()
	vp.add_child(_pivot)
	var model_path: String = item.get("model", "")
	if model_path != "" and ResourceLoader.exists(model_path):
		_pivot.add_child((load(model_path) as PackedScene).instantiate())
	else:
		call("build_" + item_id, _pivot)
	_update_camera()


func _build_labels() -> void:
	var title := Label.new()
	title.text = item["name"]
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 26)
	title.size = Vector2(1280, 36)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	_desc = Label.new()
	_desc.text = item["text"]
	_desc.add_theme_font_size_override("font_size", 19)
	_desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.position = Vector2(0, 600)
	_desc.size = Vector2(1280, 28)
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_desc)
	_inner = Label.new()
	_inner.add_theme_font_size_override("font_size", 19)
	_inner.add_theme_color_override("font_color", Color("#ff5a5a"))
	_inner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inner.position = Vector2(0, 634)
	_inner.size = Vector2(1280, 28)
	_inner.modulate.a = 0.0
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_inner)
	var hint := Label.new()
	hint.text = "드래그: 돌리기 · 휠: 확대 · 오른쪽 클릭 / Esc: 내려놓기"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, 690)
	hint.size = Vector2(1280, 20)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)


# ── 조작 ─────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = event.pressed
				_idle = 0.0
			MOUSE_BUTTON_RIGHT:
				if event.pressed:
					close()
			MOUSE_BUTTON_WHEEL_UP:
				_dist = maxf(2.0, _dist - 0.2)
			MOUSE_BUTTON_WHEEL_DOWN:
				_dist = minf(4.6, _dist + 0.2)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_spin = event.relative * 0.01
		_rotate(_spin)
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _rotate(d: Vector2) -> void:
	_yaw += d.x
	_pitch = clampf(_pitch + d.y, -1.2, 1.2)


func _process(delta: float) -> void:
	if not _dragging:
		_spin = _spin.lerp(Vector2.ZERO, minf(1.0, delta * 4.0))   # 손을 떼면 관성으로 조금 더 돌다 멈춤
		_rotate(_spin)
		_idle += delta
		if _idle > 2.5:
			_yaw += delta * 0.25                                    # 가만두면 천천히 돎
	_update_camera()
	_check_secret()


func _update_camera() -> void:
	_pivot.rotation = Vector3(_pitch, _yaw, 0)
	_camera.position = Vector3(0, 0.05, _dist)
	_camera.look_at(Vector3(0, 0.05, 0))


## 숨은 단서 면이 카메라 쪽을 향하면 발견
func _check_secret() -> void:
	if found or not show_secret:
		return
	var n: Vector3 = _pivot.global_transform.basis * (item["secret_normal"] as Vector3)
	if n.normalized().dot((_camera.global_position - _pivot.global_position).normalized()) > 0.85:
		found = true
		_inner.text = item["secret_text"]
		create_tween().tween_property(_inner, "modulate:a", 1.0, 0.6)
		discovered.emit(item_id)


func close() -> void:
	if not is_inside_tree() or modulate.a < 0.99:
		return
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_callback(func():
		closed.emit()
		queue_free())


# ── 도형으로 빚은 임시 모델 ────────────────────────────────
func _mat(c: Color, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP   # 천처럼 부드럽게 빛을 받음
	return m


func _ball(parent: Node3D, pos: Vector3, scale: Vector3, mat: Material, r := 0.5) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 18
	s.rings = 10
	mi.mesh = s
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	parent.add_child(mi)
	return mi


## 채린의 곰돌이: 바랜 갈색 천, 닳은 주둥이, 단추 눈. 2회차엔 등에 은빛 바늘땀
func build_teddy(root: Node3D) -> void:
	var fur := _mat(Color(0.56, 0.43, 0.34))
	var pale := _mat(Color(0.78, 0.67, 0.55))
	var dark := _mat(Color(0.12, 0.09, 0.08), 0.35)
	var bear := Node3D.new()
	bear.position = Vector3(0, -0.15, 0)
	root.add_child(bear)
	_ball(bear, Vector3(0, -0.05, 0), Vector3(0.95, 1.1, 0.85), fur, 0.42)          # 몸통
	_ball(bear, Vector3(0, -0.02, 0.27), Vector3(0.7, 0.8, 0.35), pale, 0.36)      # 배 (닳아서 옅음)
	_ball(bear, Vector3(0, 0.62, 0), Vector3(1.0, 0.92, 0.92), fur, 0.36)          # 머리
	for sx in [-1.0, 1.0]:
		_ball(bear, Vector3(0.27 * sx, 0.9, -0.02), Vector3(1, 1, 0.6), fur, 0.12)     # 귀
		_ball(bear, Vector3(0.27 * sx, 0.9, 0.04), Vector3(1, 1, 0.4), pale, 0.07)     # 귀 안
		_ball(bear, Vector3(0.13 * sx, 0.7, 0.3), Vector3.ONE, dark, 0.045)           # 단추 눈
		_ball(bear, Vector3(0.43 * sx, 0.05, 0.08), Vector3(0.7, 1.25, 0.7), fur, 0.16).rotation_degrees = Vector3(0, 0, 25 * sx)  # 팔
		_ball(bear, Vector3(0.22 * sx, -0.45, 0.16), Vector3(0.85, 0.75, 1.15), fur, 0.18)   # 다리
		_ball(bear, Vector3(0.22 * sx, -0.47, 0.34), Vector3(0.75, 0.75, 0.25), pale, 0.12)  # 발바닥
	_ball(bear, Vector3(0, 0.55, 0.3), Vector3(1.05, 0.8, 0.75), pale, 0.14)       # 주둥이
	_ball(bear, Vector3(0, 0.6, 0.41), Vector3(1.3, 0.9, 0.8), dark, 0.045)        # 코
	# 목에 맨 바랜 리본
	var ribbon := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.27
	torus.outer_radius = 0.32
	ribbon.mesh = torus
	ribbon.material_override = _mat(Color(0.7, 0.42, 0.42))
	ribbon.position = Vector3(0, 0.33, 0)
	ribbon.scale = Vector3(1, 0.6, 1)
	bear.add_child(ribbon)
	if show_secret:
		_stitches(bear)


## 등 가운데를 세로로 지나는 은빛 바늘땀 (엑스자 땀)
func _stitches(bear: Node3D) -> void:
	var silver := _mat(Color(0.86, 0.88, 0.92), 0.25)
	silver.metallic = 0.7
	silver.emission_enabled = true
	silver.emission = Color(0.55, 0.6, 0.7)
	silver.emission_energy_multiplier = 0.35
	var seam := _mat(Color(0.32, 0.24, 0.19))
	for i in 9:
		var y := 0.28 - i * 0.075
		var a := lerpf(-0.2, 1.9, (y + 0.35) / 0.7)         # 몸통 둥근 면을 따라 살짝 기울임
		var z := -0.36 * cos((y + 0.05) * 1.6) - 0.005
		var cut := MeshInstance3D.new()                      # 갈랐던 자리 (짙은 홈)
		var cb := BoxMesh.new()
		cb.size = Vector3(0.012, 0.08, 0.01)
		cut.mesh = cb
		cut.material_override = seam
		cut.position = Vector3(0, y, z)
		bear.add_child(cut)
		for sgn in [-1.0, 1.0]:
			var st := MeshInstance3D.new()
			var b := BoxMesh.new()
			b.size = Vector3(0.11, 0.014, 0.014)
			st.mesh = b
			st.material_override = silver
			st.position = Vector3(0, y, z - 0.006)
			st.rotation = Vector3(a * 0.15, 0, 0.6 * sgn)
			bear.add_child(st)
