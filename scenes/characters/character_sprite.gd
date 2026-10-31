# character_sprite.gd
# 4방향 걷기 캐릭터. move_dir를 넣으면 걷기 애니메이션을 고르고,
# 멈추면 마지막으로 바라본 방향의 대기 동작(idle / idle_up / idle_left / idle_right)을 재생한다.
class_name CharacterSprite
extends AnimatedSprite2D

var facing := "down"


## sneak = true이면 살금살금 걷기 (옆모습만 있음. 위·아래는 보통 걷기로)
func walk(move_dir: Vector2, sneak := false) -> void:
	if move_dir == Vector2.ZERO:
		stand()
		return
	if absf(move_dir.x) > absf(move_dir.y):
		facing = "right" if move_dir.x > 0 else "left"
	else:
		facing = "down" if move_dir.y > 0 else "up"
	var anim := ("sneak_" if sneak else "walk_") + facing
	play(anim if sprite_frames.has_animation(anim) else "walk_" + facing)


func stand() -> void:
	var idle_name := "idle" if facing == "down" else "idle_" + facing
	if sprite_frames.has_animation(idle_name):
		play(idle_name)
	else:
		play("walk_" + facing)
		pause()
		frame = 0
