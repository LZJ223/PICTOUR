## 真实 Level12 / GPU：五点、纹理镂空、暂停、离屏、视差和计时到期边界。
extends "res://tests/shadow_mask_test.gd"

const MOON_OUTPUT := "res://.godot/moon_visibility_qa/"
var _moon: Sprite2D
var _blockers: Array[Polygon2D] = []
var _cuts: int = 0

func _capture(name: String) -> Image:
	var result := get_viewport().get_texture().get_image()
	result.save_png(MOON_OUTPUT + name + ".png")
	return result

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MOON_OUTPUT))
	Global.next_level_id = 12
	_game = load("res://Interface/Game.tscn").instantiate() as Node2D
	_game.play_dialogue = false
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	Global.player.set_physics_process(false)
	Global.player.hide()
	Global.goal.hide()
	_game.get_node("Camera/MenuUI").hide()
	_game.get_node("PlayerOcclusionSystem").enabled = false
	_game.get_node("NightLightSystem").enabled = false
	for layer in Global.layers:
		layer.hide()
	_moon = Global.level.get_node("Sprite2") as Sprite2D
	SignalSystem.shadow_boolean.connect(_on_cut)
	await get_tree().create_timer(1.1, true).timeout
	SignalSystem.timer.wait_time = 0.2
	SignalSystem.timer_reset()
	await _frames(5)
	_check(_moon._is_exposed, "背景和界面不会遮挡月亮")
	_check(_moon._result.size == Vector2i(5, 2), "每帧仅读回保存五个结果的小纹理")
	var offsets := PackedVector2Array([Vector2.ZERO, Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT])
	for offset in offsets:
		var blocker := Polygon2D.new()
		blocker.polygon = PackedVector2Array([Vector2(-12, -12), Vector2(12, -12), Vector2(12, 12), Vector2(-12, 12)])
		Global.level.add_child(blocker)
		blocker.global_position = _moon.to_global(_moon.get_rect().get_center() + offset * _moon.sample_distance)
		_blockers.append(blocker)
	await _frames(3)
	_check(not _moon._is_exposed, "五个采样点全部被遮挡")
	for index in 5:
		_blockers[index].hide()
		await _frames(3)
		_check(_moon._is_exposed, "第 %d 个点单独露出即可重置" % index)
		var cuts := _cuts
		await get_tree().create_timer(0.3, true).timeout
		_check(not SignalSystem.timer.is_stopped() and SignalSystem.timer.time_left > 0.15 and _cuts == cuts, "任一点露出时每帧重置，超过倒计时仍不切割")
		_blockers[index].show()
		await _frames(2)
	_capture("five_blocked")
	SignalSystem.timer_reset()
	var cuts := _cuts
	await get_tree().create_timer(0.3, true).timeout
	_check(SignalSystem.timer.is_stopped() and _cuts == cuts + 1, "全部遮挡后正常到期并触发一次切割")
	await get_tree().create_timer(0.1, true).timeout
	_check(_cuts == cuts + 1, "持续遮挡不会反复触发切割")
	_blockers[0].hide()
	await _frames(3)
	_check(not SignalSystem.is_physics_resting(), "休眠后露出月亮，通过 timer_reset 恢复活动")
	_capture("center_exposed")
	_blockers[0].show()
	await _frames(3)
	# 让同一帧的旧结果仍为遮挡、计时又即将到期，验证等待新 GPU 结果。
	SignalSystem.timer.start(0.001)
	SignalSystem.timer.wait_time = 0.2
	cuts = _cuts
	_blockers[4].hide()
	await _frames(3)
	_check(_moon._is_exposed and _cuts == cuts, "到期同帧露出时取消切割")
	await _alpha_case()
	await _parameter_case()
	await _camera_case()
	await _layer_and_afterimage_case()
	await _pause_and_offscreen_case()
	SignalSystem.timer.wait_time = 5.0
	_blockers[0].show()
	await _frames(3)
	var marked: Array[CanvasItem] = []
	for item in _moon._marked.values():
		marked.append(item)
	var origin: Vector2 = _moon.position
	_moon.queue_free()
	await _frames(2)
	for item in marked:
		if is_instance_valid(item):
			_check((item.visibility_layer & (1 << 15)) == 0, "删除月亮后清理专用可见性位")
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	_metrics["moon_position_before_cleanup"] = str(origin)
	var report := FileAccess.open(MOON_OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	print("MOON_VISIBILITY_TEST_RESULT ", JSON.stringify(_metrics))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _alpha_case() -> void:
	for blocker in _blockers:
		blocker.show()
	_blockers[0].color.a = 0.5
	await _frames(3)
	_check(_moon._is_exposed, "半透明遮挡保留可见月光")
	_blockers[0].hide()
	var pixels := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	pixels.fill(Color.WHITE)
	pixels.fill_rect(Rect2i(12, 12, 8, 8), Color.TRANSPARENT)
	var texture := ImageTexture.create_from_image(pixels)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	Global.level.add_child(sprite)
	sprite.global_position = _blockers[0].global_position
	await _frames(3)
	_check(_moon._is_exposed, "纹理中心镂空会露出月亮")
	pixels.fill(Color.WHITE)
	texture.update(pixels)
	await _frames(3)
	_check(not _moon._is_exposed, "填满纹理镂空后恢复遮挡")
	sprite.queue_free()
	_blockers[0].color.a = 1.0
	_blockers[0].show()
	await _frames(3)

func _parameter_case() -> void:
	_moon.sample_distance = 160.0
	await _frames(3)
	_check(_moon._is_exposed, "调整导出采样距离即时改变检测点")
	_moon.sample_distance = 108.0
	await _frames(3)
	_check(not _moon._is_exposed, "恢复采样距离后五点重新被遮挡")
	var scale := _moon.scale
	var position := _moon.position
	var ratio_x: float = _moon.parallax_ratio_x
	var ratio_y: float = _moon.parallax_ratio_y
	_moon.parallax_ratio_x = 0.1
	_moon.parallax_ratio_y = 0.6
	Global.player.position += Vector2(100, -50)
	await _frames(3)
	_check(_moon.scale == scale, "遮挡检测保留月亮原缩放")
	_check(_moon.position.is_equal_approx(position + Vector2(90, -20)), "横纵视差比例独立生效")
	_check(_moon._is_exposed, "月亮移动后使用更新的位置检测")
	Global.player.position -= Vector2(100, -50)
	_moon.parallax_ratio_x = ratio_x
	_moon.parallax_ratio_y = ratio_y
	await _frames(3)

func _camera_case() -> void:
	for blocker in _blockers:
		blocker.show()
	Global.camera.zoom = Vector2(1.25, 1.25)
	get_tree().root.size = Vector2i(1440, 810)
	await _frames(3)
	_check(not _moon._is_exposed, "相机缩放及窗口拉伸后五点遮挡保持正确")
	_blockers[3].hide()
	await _frames(3)
	_check(_moon._is_exposed, "相机缩放后任一点露出仍正常重置")
	_blockers[3].show()
	Global.camera.zoom = Vector2.ONE
	get_tree().root.size = Vector2i(1280, 720)
	await _frames(3)

func _layer_and_afterimage_case() -> void:
	for blocker in _blockers:
		blocker.hide()
	var layer := Global.get_layer_at_slot(3)
	layer.show()
	layer.haze_plane.show()
	var anchor := Global.camera.global_position
	var source := _shape(layer, anchor + (_moon.global_position - anchor) / layer.visual_scale)
	source.collision_box.scale = Vector2(12, 12)
	_visual_shape(source).texture = null
	await _frames(3)
	_check(not _moon._is_exposed, "真实图层中的实体能够遮住全部五点")
	source.hide()
	await _frames(3)
	_check(_moon._is_exposed, "整屏雾效不算实体遮挡")
	source.show()
	layer.cycle_opacity = 0.5
	(layer.material as ShaderMaterial).set_shader_parameter("cycle_opacity", 0.5)
	await _frames(3)
	_check(_moon._is_exposed, "轮换中的半透明图层允许月亮露出")
	layer.cycle_opacity = 1.0
	(layer.material as ShaderMaterial).set_shader_parameter("cycle_opacity", 1.0)
	await _frames(3)
	_check(not _moon._is_exposed, "图层恢复不透明后重新遮挡")
	(_game.get_node("ShadowControllerSystem") as ShadowControllerSystem)._replace_object_with_fragments(source, [])
	var ghost: ShadowCutAfterimage
	for child in layer.get_children():
		if child is ShadowCutAfterimage:
			ghost = child
	ghost.process_mode = Node.PROCESS_MODE_DISABLED
	await _frames(3)
	_check(not _moon._is_exposed, "独立残影仍按实际视觉 Alpha 遮挡月亮")
	ghost._set_progress(0.5)
	await _frames(3)
	_check(_moon._is_exposed, "残影淡出后月亮重新露出")
	ghost.queue_free()
	layer.hide()
	await _frames(3)

func _pause_and_offscreen_case() -> void:
	for blocker in _blockers:
		blocker.hide()
	await _frames(3)
	get_tree().paused = true
	var remaining: float = SignalSystem.timer.time_left
	await get_tree().create_timer(0.3, true).timeout
	_check(is_equal_approx(SignalSystem.timer.time_left, remaining), "暂停期间停止检测和重置")
	get_tree().paused = false
	await _frames(3)
	var position: Vector2 = _moon.initial_position
	_moon.initial_position += Vector2(10000, 10000)
	await _frames(3)
	_check(not _moon._is_exposed and not _moon._query_pending, "五点全部离屏时不当作露出")
	await get_tree().create_timer(0.3, true).timeout
	_check(SignalSystem.timer.is_stopped(), "离屏后允许原计时器正常到期")
	_moon.initial_position = position
	await _frames(3)
	_check(_moon._is_exposed and not SignalSystem.timer.is_stopped(), "回到屏幕后恢复逐帧重置")

func _on_cut() -> void:
	_cuts += 1
