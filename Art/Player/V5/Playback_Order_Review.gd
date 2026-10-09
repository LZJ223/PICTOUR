extends Node2D
## 直接显示实际SpriteFrames图集顺序和统一母图比例，不修改生成原图。

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("f5eee0"))
	var frames: SpriteFrames = load("res://Art/Player/V5/Traveler_V5_Frames.tres")
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Art/Player/V5/Traveler_V5_Metadata.json"))
	_label("V5 实际播放顺序 · 原图相位审阅", Vector2(24, 10), 22)
	_label("每格同一足根线；数字为显示帧 / 原图编号。可见相似姿态、非匀速腿位与衣摆跳变。", Vector2(24, 44), 15)
	for action_index in 2:
		var action := &"walk" if action_index == 0 else &"run"
		for frame in 16:
			var info: Dictionary = metadata.animations[str(action)][frame]
			var root := Vector2((frame % 8) * 160 + 94, 199 + (frame / 8) * 146 + action_index * 296)
			var sprite := Sprite2D.new()
			sprite.texture = frames.get_frame_texture(action, frame)
			sprite.centered = false
			sprite.offset = -Vector2(metadata.canvas_pivot[0], metadata.canvas_pivot[1])
			sprite.position = root
			sprite.scale = Vector2.ONE * float(info.scale) * 1.05
			add_child(sprite)
			var line := Line2D.new()
			line.points = PackedVector2Array([root + Vector2(-62, 0), root + Vector2(60, 0)])
			line.width = 0.7
			line.default_color = Color("b8aba0")
			add_child(line)
			_label("%s %02d / 源%02d" % [action, frame, int(info.source_frame)], root + Vector2(-72, 6), 13)
	if "--review-capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://Exports/Slope_Gait")
		get_viewport().get_texture().get_image().save_png("res://Exports/Slope_Gait/Playback_Order.png")
		get_tree().quit()


func _label(text: String, location: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = location
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("53404a"))
	add_child(label)
