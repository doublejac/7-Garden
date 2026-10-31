# sprite_viewer.gd
# 캐릭터 스프라이트 확인용. 방향키: 걷기 / 1~5: 특수 모션 / Esc: 끝내기
extends Node2D

const SPEED := 90.0
const SCALE := 1.0
const SPECIAL := {
	KEY_1: "take_pill", KEY_2: "hide_pill", KEY_3: "startle", KEY_4: "cry", KEY_5: "cry_right", KEY_6: "cry_left",
}

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
	help.text = "방향키: 걷기 (Shift: 살금살금, 아직 없음)   1 약 먹기  2 약 숨기기  3 놀람  4 울기  5 울기(오른쪽)  6 울기(왼쪽)   Esc 끝내기"
	help.position = Vector2(16, 12)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	help.size = Vector2(1240, 60)
	add_child(help)


func _process(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if dir != Vector2.ZERO:
		_special = false
		var sneak := Input.is_key_pressed(KEY_SHIFT)
		seoha.position += dir * SPEED * (0.7 if sneak else 1.5) * delta
		seoha.walk(dir, sneak)
	elif not _special:
		seoha.stand()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
		elif SPECIAL.has(event.keycode) and seoha.sprite_frames.has_animation(SPECIAL[event.keycode]):
			_special = true
			seoha.play(SPECIAL[event.keycode])
