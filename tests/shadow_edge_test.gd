## 将受影白色物体与无影黑色物体逐像素对照，验证半透明、模糊和镂空边缘。
extends "res://tests/shadow_mask_test.gd"

const EDGE_OUTPUT := "res://.godot/shadow_edge_qa/"

func _capture(name: String) -> Image:
	var result := get_viewport().get_texture().get_image()
	result.save_png(EDGE_OUTPUT + name + ".png")
	return result

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("影子边缘测试需要真实 GPU 渲染器")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EDGE_OUTPUT))
	get_tree().root.size = Vector2i(1440, 810)
	Global.next_level_id = 9
	_game = load("res://Interface/Game.tscn").instantiate() as Node2D
	_game.play_dialogue = false
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	await get_tree().create_timer(1.1, true).timeout
	Global.player.set_physics_process(false)
	SignalSystem.timer.stop()
	PhysicsServer2D.set_active(false)
	_game.get_node("NightLightSystem").enabled = false
	Global.player.hide()
	_game.get_node("Camera/MenuUI").hide()
	Global.level.get_node("Background").hide()
	for layer in Global.layers:
		layer.haze_plane.hide()
		for child in layer.get_children():
			if child is LayerObject:
				child.hide()
	# 中性色滤镜使“纯黑参考”保持纯黑；仍保留实际的景深模糊。
	RenderingServer.global_shader_parameter_set(&"render_contrast_falloff", 0.0)
	RenderingServer.global_shader_parameter_set(&"render_background_tint_step", 0.0)
	var background := CanvasLayer.new()
	background.layer = -50
	_game.add_child(background)
	var fill := ColorRect.new()
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.color = Color(0.16, 0.26, 0.4, 1.0)
	background.add_child(fill)
	var caster := _shape(Global.get_layer_at_slot(2), Vector2(0, 350), true)
	caster.collision_box.scale = Vector2(12, 12)
	caster.visual_root.hide()
	await _frames()
	var receiver := _shape(Global.get_layer_at_slot(3), caster.shadow_box[0].global_position)
	receiver.collision_box.scale = Vector2(6, 6)
	var visual := _visual_shape(receiver)
	visual.antialiased = true
	visual.color = Color.WHITE
	await _frames()
	await _compare(caster, visual, "01_opaque_blurred")
	visual.color.a = 0.5
	await _compare(caster, visual, "02_half_transparent")
	visual.hide()
	var texture := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	texture.fill(Color.WHITE)
	texture.fill_rect(Rect2i(20, 20, 24, 24), Color(1, 1, 1, 0))
	for index in 4:
		var alpha: float = float(index + 1) / 5.0
		texture.fill_rect(Rect2i(index, index, 64 - index * 2, 1), Color(1, 1, 1, alpha))
		texture.fill_rect(Rect2i(index, 63 - index, 64 - index * 2, 1), Color(1, 1, 1, alpha))
		texture.fill_rect(Rect2i(index, index, 1, 64 - index * 2), Color(1, 1, 1, alpha))
		texture.fill_rect(Rect2i(63 - index, index, 1, 64 - index * 2), Color(1, 1, 1, alpha))
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(texture)
	receiver.visual_root.add_child(sprite)
	await _compare(caster, sprite, "03_texture_hole")
	Global.camera.zoom = Vector2(1.35, 1.35)
	await _compare(caster, sprite, "04_camera_zoom")
	get_tree().root.size = Vector2i(1280, 800)
	await _compare(caster, sprite, "05_resized")
	receiver.owner_layer.cycle_opacity = 0.5
	(receiver.owner_layer.material as ShaderMaterial).set_shader_parameter("cycle_opacity", 0.5)
	await _compare(caster, sprite, "06_layer_fade")
	receiver.owner_layer.cycle_opacity = 1.0
	(receiver.owner_layer.material as ShaderMaterial).set_shader_parameter("cycle_opacity", 1.0)
	Global.camera.zoom = Vector2.ONE
	get_tree().root.size = Vector2i(1440, 810)
	sprite.hide()
	visual.show()
	visual.color = Color.WHITE
	caster.collision_box.scale = Vector2.ONE
	await _frames()
	for index in 6:
		var previous: Vector2 = caster.shadow_visual[0].global_position
		caster.position.x = -30.0 if index % 2 == 0 else 30.0
		await _frames(1)
		var moved := get_viewport().get_texture().get_image()
		_check(_pixel(moved, caster.shadow_visual[0].global_position).get_luminance() < 0.01, "移动投影第 %d 帧立即染黑新位置" % index)
		_check(_pixel(moved, previous).get_luminance() > 0.1, "移动投影第 %d 帧无旧位置残影" % index)
	_check(caster.shadow_box.size() == 1 and caster.shadow_visual.size() == 1, "原有一对影子保留")
	_check(caster.shadow_visual[0].get_parent() == caster, "视觉影子仍归投影物体管理")
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	var report := FileAccess.open(EDGE_OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	print("SHADOW_EDGE_TEST_RESULT ", JSON.stringify(_metrics))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _compare(caster: ShadowedGeometry, visual: CanvasItem, label: String) -> void:
	var visual_root := visual.get_parent() as CanvasItem
	visual_root.modulate = Color.WHITE
	visual.modulate = Color.WHITE
	caster.can_leave_shadow = true
	await _frames()
	var actual := _capture(label + "_shadow")
	var coverage := _mask()
	coverage.resize(actual.get_width(), actual.get_height(), Image.INTERPOLATE_BILINEAR)
	# 正确结果应等于保持相同 Alpha 的黑色物体，不含额外叠黑。
	# 描边同样属于承影物体，参考图应将整个 VisualRoot 染黑并保留 Alpha。
	visual_root.modulate = Color(0, 0, 0, 1)
	caster.can_leave_shadow = false
	await _frames()
	var reference := _capture(label + "_reference")
	var maximum: float = 0.0
	var edge_pixels: int = 0
	for y in actual.get_height():
		for x in actual.get_width():
			var alpha := coverage.get_pixel(x, y).a
			if alpha > 0.01 and alpha < 0.99:
				edge_pixels += 1
				var a := actual.get_pixel(x, y)
				var b := reference.get_pixel(x, y)
				maximum = maxf(maximum, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
	_metrics[label + "_edge_pixels"] = edge_pixels
	_metrics[label + "_max_edge_error"] = maximum
	_check(edge_pixels > 100, label + " 包含足够多的半透明边缘像素")
	_check(maximum <= 0.01, label + " 受影边缘与同 Alpha 黑色物体一致，没有亮边或额外背景压暗")
	visual_root.modulate = Color.WHITE
	visual.modulate = Color.WHITE
	caster.can_leave_shadow = true
