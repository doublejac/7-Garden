# build_spriteframes.gd
# 캐릭터 폴더의 애니메이션 시트(PNG)와 frames.json을 읽어 SpriteFrames 리소스(.tres)를 만든다.
# 실행 (프로젝트 폴더에서):
#   godot --headless --path . -s res://tools/build_spriteframes.gd -- seoha
# 결과: res://assets/art/characters/<이름>/<이름>_frames.tres
extends SceneTree


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("캐릭터 폴더 이름을 넘겨주세요. 예: -- seoha")
		quit(1)
		return
	for character in args:
		_build(character)
	quit()


func _build(character: String) -> void:
	var dir := "res://assets/art/characters/%s" % character
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir + "/frames.json"))
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for anim_name in meta.animations:
		var info: Dictionary = meta.animations[anim_name]
		var tex: Texture2D = load("%s/%s.png" % [dir, anim_name])
		var cell: Array = info.cell
		frames.add_animation(anim_name)
		frames.set_animation_speed(anim_name, info.fps)
		frames.set_animation_loop(anim_name, info.loop)
		for i in int(info.frames):
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * cell[0], 0, cell[0], cell[1])
			frames.add_frame(anim_name, atlas)
	var out := "%s/%s_frames.tres" % [dir, character]
	var err := ResourceSaver.save(frames, out)
	print("%s → %s (%s)" % [character, out, "OK" if err == OK else error_string(err)])
