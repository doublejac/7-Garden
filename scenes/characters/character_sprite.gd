# character_sprite.gd
# 4방향 걷기 캐릭터. move_dir를 넣으면 걷기 애니메이션을 고르고, 멈추면 마지막 방향의 서 있는 프레임으로.
# idle 애니메이션은 정면에서만 쓴다.
class_name CharacterSprite
extends AnimatedSprite2D

var facing := "down"


func walk(move_dir: Vector2) -> void:
	if move_dir == Vector2.ZERO:
		stand()
		return
	if absf(move_dir.x) > absf(move_dir.y):
		facing = "right" if move_dir.x > 0 else "left"
	else:
		facing = "down" if move_dir.y > 0 else "up"
	play("walk_" + facing)


func stand() -> void:
	if facing == "down" and sprite_frames.has_animation("idle"):
		play("idle")
	else:
		play("walk_" + facing)
		pause()
		frame = 0
