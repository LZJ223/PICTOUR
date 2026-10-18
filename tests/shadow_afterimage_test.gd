## 真实 GPU：切口首帧、渐隐、半透明叠加、纯黑投影、视差、暂停与资源回收。
extends "res://tests/shadow_mask_test.gd"

const AFTERIMAGE_OUTPUT := "res://.godot/shadow_afterimage_qa/"
var _controller: ShadowControllerSystem
var _layer: DepthLayer

func _capture(name: String) -> Image:
	var result := get_viewport().get_texture().get_image()
	result.save_png(AFTERIMAGE_OUTPUT + name + ".png")
	return result

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AFTERIMAGE_OUTPUT))
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
	_game.get_node("PlayerOcclusionSystem").enabled = false
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
				child.can_be_shadowed = false
				child.can_leave_shadow = false
	Renderer.background_blur_step = 0.0
	Renderer.background_tint_step = 0.0
	Renderer.contrast_falloff = 0.0
	Renderer.apply_settings()
	var background := CanvasLayer.new()
	background.layer = -50
	_game.add_child(background)
	var fill := ColorRect.new()
	fill.size = Vector2(2560, 1440)
	fill.color = Color(0.15, 0.25, 0.4)
	background.add_child(fill)
	_controller = _game.get_node("ShadowControllerSystem") as ShadowControllerSystem
	_layer = Global.get_layer_at_slot(3)
	for alpha in [1.0, 0.5]:
		await _fade_case(alpha)
	await _projection_case()
	await _style_case()
	await _timer_cut_case()
	await _lifecycle_case()
	await _complete_removal_case()
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	var report := FileAccess.open(AFTERIMAGE_OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	print("SHADOW_AFTERIMAGE_TEST_RESULT ", JSON.stringify(_metrics))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _fixture(alpha: float = 1.0) -> ShadowedGeometry:
	var source := _shape(_layer, Global.camera.global_position)
	source.collision_box.scale = Vector2(12, 8)
	source.modulate.a = alpha
	var visual := _visual_shape(source)
	visual.texture = null
	visual.color = Color(0.8, 0.75, 0.65)
	return source

func _split(source: ShadowedGeometry) -> Array[LayerObject]:
	var local_cut := PackedVector2Array([Vector2(-5, -30), Vector2(5, -30), Vector2(5, 30), Vector2(-5, 30)])
	var world := source.collision_box.global_transform
	var pieces := _controller._subtract_shadows(world * source.collision_box.polygon, [world * local_cut])
	var existing := _layer.get_children()
	_controller._replace_object_with_fragments(source, pieces)
	var fragments: Array[LayerObject] = []
	for child in _layer.get_children():
		if child is LayerObject and child not in existing:
			fragments.append(child)
	return fragments

func _ghost() -> ShadowCutAfterimage:
	for child in _layer.get_children():
		if child is ShadowCutAfterimage:
			return child
	return null

func _fade_case(alpha: float) -> void:
	var source := _fixture(alpha)
	await _frames()
	var removed := _visual_shape(source).global_transform * Vector2.ZERO
	var retained := _visual_shape(source).global_transform * Vector2(-12, 0)
	var before := _capture("alpha_%s_before" % alpha)
	get_tree().paused = true
	var fragments := _split(source)
	var ghost := _ghost()
	_check(ghost != null and fragments.size() == 2, "切割立即生成碎片和独立残影")
	_check(ghost.get_class() == "Node2D" and ghost.visibility_layer == 1, "残影仅主画面可见，不参与物理或承影覆盖")
	await _frames(2)
	var first := _capture("alpha_%s_first" % alpha)
	_check(not is_instance_valid(source), "残影存在时原物体已经删除")
	_check(_difference(_pixel(first, removed), _pixel(before, removed)) < 0.012, "消失区域首帧衔接原画面")
	_check(_difference(_pixel(first, retained), _pixel(before, retained)) < 0.012, "保留区域不重复叠加 Alpha")
	var values: Array[float] = []
	for progress in [0.0, 0.25, 0.5, 0.75, 1.0]:
		ghost._set_progress(progress)
		await _frames(2)
		var image := _capture("alpha_%s_progress_%s" % [alpha, progress])
		values.append(_pixel(image, removed).get_luminance())
		_check(_difference(_pixel(image, retained), _pixel(before, retained)) < 0.012, "渐隐不改变真实碎片亮度")
	for index in range(1, values.size()):
		_check(values[index] < values[index - 1], "残影亮度单调接近背景")
	var final := _capture("alpha_%s_final" % alpha)
	_check(_difference(_pixel(final, removed), Color(0.15, 0.25, 0.4)) < 0.012, "残影归零后露出背景")
	# 改变相机和图层的视觉缩放，残影与同一物理位置保持一致。
	var physical := ghost.global_transform * (Vector2(10, -5) * ghost._collision_scale)
	_layer.visual_scale = 0.6
	_layer.apply_slot_state(Global.camera.global_position + Vector2(30, 10), Vector2.ONE)
	var expected := Global.camera.global_position + Vector2(30, 10)
	expected += (physical - expected) * _layer.visual_scale
	_check((ghost._visual.global_transform * Vector2(10, -5)).distance_to(expected) < 0.001, "残影跟随图层视差更新")
	ghost.queue_free()
	for fragment in fragments:
		fragment.queue_free()
	get_tree().paused = false
	_layer.cancel_cycle()
	for layer in Global.layers:
		layer.haze_plane.hide()
	await _frames()

func _lifecycle_case() -> void:
	var source := _fixture()
	await _frames()
	var fragments := _split(source)
	var ghost := _ghost()
	await _frames(2)
	get_tree().paused = true
	var progress: float = ghost._fade_material.get_shader_parameter("progress")
	await get_tree().create_timer(0.3, true).timeout
	_check(is_instance_valid(ghost), "游戏暂停期间残影不被提前释放")
	_check(is_equal_approx(ghost._fade_material.get_shader_parameter("progress"), progress), "暂停保持淡出进度")
	get_tree().paused = false
	await get_tree().create_timer(0.3, true).timeout
	_check(not is_instance_valid(ghost), "物理休眠期间也能按时淡出并释放纹理")
	for fragment in fragments:
		fragment.queue_free()
	await _frames()

func _projection_case() -> void:
	var caster := _shape(Global.get_layer_at_slot(2), Global.camera.global_position + Vector2(0, -100), true)
	caster.collision_box.scale = Vector2(30, 30)
	caster.visual_root.hide()
	await _frames()
	var source := _fixture()
	source.position = caster.shadow_box[0].global_position
	await _frames()
	var removed := _visual_shape(source).global_position
	var before := _capture("projected_before")
	_check(_pixel(before, removed).get_luminance() < 0.005, "真实投影下删除前为纯黑")
	get_tree().paused = true
	var fragments := _split(source)
	var ghost := _ghost()
	await _frames(2)
	var first := _capture("projected_first")
	_check(_pixel(first, removed).get_luminance() < 0.005, "真实投影下首帧保留纯黑外观")
	var coverage := _pixel(_mask(), removed)
	_check(coverage[_layer.layer_id] < 0.005, "残影不让已删除区域继续进入承影覆盖纹理")
	var cached := ghost.get_node("OldAppearance") as SubViewport
	_check(cached.render_target_update_mode == SubViewport.UPDATE_DISABLED, "局部外观只绘制一次")
	_check((cached.get_node("RetainedAppearance") as SubViewport).render_target_update_mode == SubViewport.UPDATE_DISABLED, "局部遮罩只绘制一次")
	_check(ghost._capture_visuals.is_empty(), "首帧后释放复制的视觉节点，仅保留纹理")
	ghost._set_progress(0.5)
	await _frames(2)
	var middle := _capture("projected_middle")
	_check(_difference(_pixel(middle, removed), Color(0.075, 0.125, 0.2)) < 0.012, "纯黑残影通过透明度平滑露出背景")
	ghost.queue_free()
	caster.queue_free()
	for fragment in fragments:
		fragment.queue_free()
	get_tree().paused = false
	await _frames()

func _style_case() -> void:
	var source := _fixture(0.7)
	source.rotation = 0.2
	source.scale = Vector2(1.1, 0.85)
	source.front = true
	var visual := _visual_shape(source)
	visual.texture = load("res://Texture/Others/Gray_Dots_Seamless.png")
	visual.texture_offset = Vector2(11, -7)
	visual.texture_rotation = 0.3
	visual.texture_scale = Vector2(2, 1.5)
	await _frames()
	var transform := visual.global_transform
	var before := _capture("textured_before")
	get_tree().paused = true
	var fragments := _split(source)
	var ghost := _ghost()
	await _frames(2)
	var first := _capture("textured_first")
	var error := 0.0
	for index in range(-10, 11):
		var point := transform * Vector2(0, index)
		error = maxf(error, _difference(_pixel(first, point), _pixel(before, point)))
	_metrics["textured_max_error"] = error
	_check(error < 0.025, "旋转、非等比缩放和循环纹理的切割首帧保持外观")
	_check(ghost.front, "残影保留原 front 排序属性")
	ghost.queue_free()
	for fragment in fragments:
		fragment.queue_free()
	get_tree().paused = false
	await _frames()

func _timer_cut_case() -> void:
	var caster := _shape(Global.get_layer_at_slot(2), Global.camera.global_position + Vector2(0, -100), true)
	caster.collision_box.scale = Vector2(30, 30)
	caster.visual_root.hide()
	await _frames()
	var source := _fixture()
	source.position = caster.shadow_box[0].global_position
	source.can_be_shadowed = true
	await _frames()
	SignalSystem.timer.start(0.05)
	await SignalSystem.timer.timeout
	await _frames(2)
	var ghost := _ghost()
	_check(not is_instance_valid(source) and ghost != null, "真实 timer 到期经 shadow_boolean 自动生成残影")
	_check(SignalSystem.is_physics_resting(), "残影不改变原有夜间物理休眠逻辑")
	SignalSystem.timer.wait_time = 5.0
	await get_tree().create_timer(0.3, true).timeout
	_check(not is_instance_valid(ghost), "真实自动切割的残影按时释放")
	caster.queue_free()
	await _frames()

func _complete_removal_case() -> void:
	var source := _fixture()
	await _frames()
	_controller._replace_object_with_fragments(source, [])
	var ghost := _ghost()
	_check(ghost != null, "完全切除时同样创建残影")
	await get_tree().create_timer(0.3, true).timeout
	_check(not is_instance_valid(ghost), "完全切除的残影正常回收")
	_controller.cut_afterimage_duration = 0.0
	source = _fixture()
	await _frames()
	var fragments := _split(source)
	_check(_ghost() == null, "时长为零可以关闭效果")
	for fragment in fragments:
		fragment.queue_free()

func _difference(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
