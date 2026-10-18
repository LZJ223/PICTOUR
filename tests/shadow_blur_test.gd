## 可控硬边投影 + 真实 DepthLayer：验证合影后模糊、纯黑、透明覆盖与动态更新。
extends "res://tests/shadow_mask_test.gd"

const BLUR_OUTPUT := "res://.godot/shadow_blur_qa/"
var _receiver: ShadowedGeometry
var _material: ShaderMaterial
var _projection: ImageTexture
var _show_shadow := true
var _edge: float
var _backdrop := Color(0.16, 0.26, 0.4)

func _capture(name: String) -> Image:
	var result := get_viewport().get_texture().get_image()
	result.save_png(BLUR_OUTPUT + name + ".png")
	return result

func _apply_projection() -> void:
	_material.set_shader_parameter("shadow_projection", _projection)
	_material.set_shader_parameter("shadow_projection_enabled", _show_shadow)

func _screen_color(image: Image, point: Vector2) -> Color:
	var pixel := point / get_viewport().get_visible_rect().size * Vector2(image.get_size())
	return image.get_pixel(clampi(roundi(pixel.x), 0, image.get_width() - 1), clampi(roundi(pixel.y), 0, image.get_height() - 1))

func _make_projection(edge: float) -> void:
	_edge = edge
	var size := Vector2i(get_viewport().get_visible_rect().size)
	var mask := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	mask.fill(Color.TRANSPARENT)
	mask.fill_rect(Rect2i(0, 0, roundi(edge), size.y), Color.WHITE)
	_projection = ImageTexture.create_from_image(mask)

func _center() -> Vector2:
	return _visual_shape(_receiver).get_global_transform_with_canvas() * Vector2.ZERO

func _transition(lod: float, label: String) -> float:
	Renderer.background_blur_step = lod * 0.5 # 接影层 z=-200，即两个景深单位。
	Renderer.apply_settings()
	_show_shadow = false
	await _frames()
	var before := _capture(label + "_unshadowed")
	_show_shadow = true
	await _frames()
	var after := _capture(label + "_shadow")
	var center := _center()
	var first := -1000.0
	var last := -1000.0
	for index in range(161):
		var x: float = _edge - 20.0 + index * 0.25
		var point := Vector2(x, center.y)
		var reference := _screen_color(before, point).get_luminance()
		var value := _screen_color(after, point).get_luminance() / maxf(reference, 0.0001)
		if value > 0.1 and value < 0.9:
			if first < -999.0:
				first = x
			last = x
	var width := maxf(last - first, 0.0)
	_metrics[label + "_transition_width"] = width
	_check(_screen_color(after, Vector2(_edge - 25, center.y)).get_luminance() < 0.005, label + " 完整受影内部保持纯黑，不被调色抬亮")
	var lit := Vector2(_edge + 25, center.y)
	_check(_screen_color(before, lit).is_equal_approx(_screen_color(after, lit)), label + " 未受影区域保持原滤镜颜色")
	var empty := Vector2(center.x, center.y - 220)
	_check(_screen_color(before, empty).is_equal_approx(_screen_color(after, empty)), label + " 空白背景不被影子压暗")
	return width

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("联合模糊测试需要真实 GPU 渲染器")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BLUR_OUTPUT))
	get_tree().root.size = Vector2i(1440, 810)
	Global.next_level_id = 9
	_game = load("res://Interface/Game.tscn").instantiate() as Node2D
	_game.play_dialogue = false
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	await get_tree().create_timer(1.1, true).timeout
	Global.player.set_physics_process(false)
	SignalSystem.timer.stop()
	SignalSystem.set_process(false)
	PhysicsServer2D.set_active(false)
	_game.get_node("NightLightSystem").enabled = false
	var occlusion := _game.get_node_or_null("PlayerOcclusionSystem")
	if occlusion != null:
		occlusion.enabled = false
	Global.player.hide()
	_game.get_node("Camera/MenuUI").hide()
	Global.level.get_node("Background").hide()
	for layer in Global.layers:
		layer.haze_plane.hide()
		for child in layer.get_children():
			if child is LayerObject:
				child.hide()
				child.collision_layer = 0
				child.collision_mask = 0
	var background := CanvasLayer.new()
	background.layer = -50
	_game.add_child(background)
	var fill := ColorRect.new()
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.color = _backdrop
	background.add_child(fill)
	_receiver = _shape(Global.get_layer_at_slot(3), Global.camera.global_position)
	_receiver.collision_box.scale = Vector2(18, 9)
	var shape := _visual_shape(_receiver)
	shape.texture = null
	shape.color = Color.WHITE
	_material = _receiver.owner_layer.material as ShaderMaterial
	await _frames()
	_make_projection(_center().x)
	# 后于真实管理器绑定可控投影，只隔离输入，不替换生产着色器或滤镜。
	RenderingServer.frame_pre_draw.connect(_apply_projection)
	var sharp := await _transition(0.0, "01_sharp")
	var normal := await _transition(1.6, "02_default")
	var strong := await _transition(3.0, "03_strong")
	_check(normal > sharp + 1.0, "默认景深下影子边界不再保持清晰硬边")
	_check(strong > normal + 2.0, "模糊强度增加时影子边界同步变宽")
	## 透明度只在实体合成时使用一次，阴影内应等于同 Alpha 的黑色物体。
	_receiver.visual_root.modulate.a = 0.4
	await _frames()
	var translucent := _capture("04_translucent_shadow")
	_show_shadow = false
	_receiver.visual_root.modulate = Color(0, 0, 0, 0.4)
	RenderingServer.global_shader_parameter_set(&"render_contrast_falloff", 0.0)
	RenderingServer.global_shader_parameter_set(&"render_background_tint_step", 0.0)
	await _frames()
	var reference := _capture("04_translucent_reference")
	var sample := Vector2(_edge - 25, _center().y)
	_check(_screen_color(translucent, sample).is_equal_approx(_screen_color(reference, sample)), "半透明阴影与相同 Alpha 的黑色参考一致")
	_receiver.visual_root.modulate = Color.WHITE
	Renderer.apply_settings()
	Renderer.background_blur_step = 0.8
	Renderer.apply_settings()
	_show_shadow = true
	for index in 4:
		var previous := _edge
		_make_projection(_center().x + (-40.0 if index % 2 == 0 else 40.0))
		await _frames(1)
		var moved := _capture("05_move_%d" % index)
		var point := Vector2(minf(previous, _edge) - 15, _center().y)
		_check(_screen_color(moved, point).get_luminance() < 0.005, "移动遮罩第 %d 帧内部即时成影" % index)
		if _edge < previous:
			point.x = (previous + _edge) * 0.5
			_check(_screen_color(moved, point).get_luminance() > 0.1, "移动遮罩第 %d 帧旧区域即时恢复" % index)
	Global.camera.zoom = Vector2(1.3, 1.3)
	get_tree().root.size = Vector2i(1280, 800)
	await _frames()
	_make_projection(_center().x)
	var resized := await _transition(1.6, "06_zoom_resized")
	_check(absf(resized - normal) < 2.0, "相机缩放及窗口拉伸后，影子模糊保持屏幕尺度")
	var controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	_check(controller.transfer(1, _receiver), "接影物体可切换至更近的图层")
	_material = _receiver.owner_layer.material as ShaderMaterial
	await get_tree().create_timer(0.2, true).timeout
	_make_projection(_center().x)
	var transferred := await _transition(1.6, "07_transferred")
	_check(transferred < resized, "移近一个图层后，影子与实体的景深模糊同步减弱")
	RenderingServer.frame_pre_draw.disconnect(_apply_projection)
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	var report := FileAccess.open(BLUR_OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	print("SHADOW_BLUR_TEST_RESULT ", JSON.stringify(_metrics))
	get_tree().quit(0 if _failures.is_empty() else 1)
