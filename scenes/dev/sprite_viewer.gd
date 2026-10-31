# sprite_viewer.gd
# 캐릭터 스프라이트 확인용. 방향키: 걷기 / 1~5: 특수 모션 / Esc: 끝내기
extends Node2D

const SPEED := 90.0
const SCALE := 1.0
const SPECIAL := {KEY_1: "wave", KEY_2: "point", KEY_3: "worry", KEY_4: "sit_draw", KEY_5: "sit_bench"}

var seoha: CharacterSprite
var _special := false


func _ready() -> void:
	var floor_rect := ColorRect.new()
	floor_rect.color = Color("#6f8f74")
	floor_rect.size = Vector2(1280, 720)
	add_child(floor_rect)
	seoha = load("res://scenes/characters/seoha.tscn").instantiate()
	seoha.position = Vector2(640, 460)
	seoha.scale = Vector2(SCALE, SCALE)
	add_child(seoha)
	var help := Label.new()
	help.text = "방향키: 걷기    1 손 흔들기  2 가리키기  3 걱정  4 그림 그리기  5 벤치    Esc: 끝내기"
	help.position = Vector2(16, 12)
	add_child(help)


func _process(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if dir != Vector2.ZERO:
		_special = false
		seoha.position += dir * SPEED * 1.5 * delta
		seoha.walk(dir)
	elif not _special:
		seoha.stand()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif SPECIAL.has(event.keycode):
			_special = true
			seoha.play(SPECIAL[event.keycode])
