## 复用真实场景渲染测试的坐标与像素工具，验证低强度大范围的原生 Light2D。
extends "res://tests/shadow_mask_test.gd"

const NIGHT_OUTPUT := "res://.godot/night_light_qa/"

func _night() -> NightLightSystem:
	return _game.get_node("NightLightSystem") as NightLightSystem

func _capture(name: String) -> Image:
	var image := get_viewport().get_texture().get_image()
	image.save_png(NIGHT_OUTPUT + name + ".png")
	return image

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("NIGHT_LIGHT_TEST: " + message)

func _check_disabled(message: String) -> void:
	var probe := CanvasLayer.new()
	probe.layer = 200
	get_tree().root.add_child(probe)
	var rect := ColorRect.new()
	rect.size = Vector2(8, 8)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; global uniform bool render_night_light_enabled; void fragment() { COLOR = render_night_light_enabled ? vec4(1,0,0,1) : vec4(0,1,0,1); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	probe.add_child(rect)
	await _frames()
	var color := get_viewport().get_texture().get_image().get_pixel(2, 2)
	_check(color.g > 0.99 and color.r < 0.01, message)
	probe.free()

## 在真实背景场景中换贴图，对照灯光开关；透明区域和背景不能发生颜色变化。
func _check_background_isolation(surface: LayerObject, reference: Color) -> void:
	var original := Global.level.get_node("Background") as CanvasLayer
	original.hide()
	var background := load("res://Component/Background/Background.tscn").instantiate() as CanvasLayer
	_game.add_child(background)
	var sprite := background.get_node("Frame/Sprite") as Sprite2D
	var previous := Color.TRANSPARENT
	for color: Color in [Color(0.05, 0.1, 0.2), Color(0.9, 0.85, 0.7), Color(0.4, 0.1, 0.3)]:
		var texture := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		texture.fill(color)
		sprite.texture = ImageTexture.create_from_image(texture)
		_night().enabled = false
		await _frames()
		var unlit := get_viewport().get_texture().get_image()
		_night().enabled = true
		await _frames()
		var lit := get_viewport().get_texture().get_image()
		for at: Vector2 in [Vector2(350, 350), Vector2(350, 435), Vector2(-250, 200)]:
			var before := _pixel(unlit, at)
			var after := _pixel(lit, at)
			_check(_color_difference(before, after) < 0.005, "更换背景后，透明区域不受灯光开关影响：%s" % color)
		var surface_color := _pixel(lit, surface.global_position + Vector2(-18, 0))
		_check(_color_difference(surface_color, reference) < 0.005, "背景贴图不会混入关卡层实体照明")
		var background_color := _pixel(lit, Vector2(350, 350))
		if previous.a > 0.0:
			_check(_color_difference(previous, background_color) > 0.1, "背景替换确实显示不同颜色")
		previous = background_color
	background.free()
	original.show()
	await _frames()
	_capture("04_background_isolated")

func _color_difference(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("夜间照明测试需要真实 GPU 渲染器")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(NIGHT_OUTPUT))
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
	await _frames()
	_check(_night()._light is PointLight2D and _night()._light.shadow_enabled, "使用带原生阴影的 PointLight2D")
	_check(_night()._light.range_z_min == 0 and _night()._light.range_z_max == 0, "灯光仅作用于关卡层的 Z=0")
	_check(_night()._light.range_layer_min == 0 and _night()._light.range_layer_max == 0, "灯光不跨 CanvasLayer 影响背景和界面")
	_check(_night().get_node_or_null("NightAir") == null, "不再创建覆盖背景的全屏空气面")
	_check(is_equal_approx(_night()._light.energy, 0.28), "默认光强为 0.28")
	_check(is_equal_approx(_level_radius(), 1600.0), "默认照明半径为 1600")
	_check(_night()._light.global_position.is_equal_approx(Global.player.global_position + Vector2(0, -85)), "光源位于玩家头部")
	_capture("01_level09")
	var sync_samples: Array[float] = []
	for index in 60:
		var start: int = Time.get_ticks_usec()
		_night()._sync_frame()
		sync_samples.append((Time.get_ticks_usec() - start) / 1000.0)
		await get_tree().process_frame
	sync_samples.sort()
	_metrics["light_sync_cpu_p95_ms"] = sync_samples[floori(sync_samples.size() * 0.95)]
	_metrics["level09_draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)

	# 所有原始箱子和地面仅在内存中隐藏，让照明和背景探针独立可见。
	for layer in Global.layers:
		layer.haze_plane.hide()
		for child in layer.get_children():
			if child is LayerObject:
				child.hide()
	var current := Global.get_layer_at_slot(1)
	var lit := _shape(current, Vector2(200, 435))
	var blocked := _shape(current, Vector2(400, 435))
	var foreground := _shape(Global.get_layer_at_slot(0), Vector2(-300, 380))
	var rear := _shape(Global.get_layer_at_slot(2), Vector2(-300, 500))
	var casting := _shape(Global.get_layer_at_slot(2), Vector2(-200, 410), true)
	await _frames()
	var receiver := _shape(Global.get_layer_at_slot(3), casting.shadow_box[0].global_position)
	receiver.collision_box.scale = Vector2(3, 2)
	await _frames()
	var illuminated := _capture("02_surface_only")
	var facing := _pixel(illuminated, lit.global_position + Vector2(-18, 0))
	var away := _pixel(illuminated, lit.global_position + Vector2(18, 0))
	var occluded := _pixel(illuminated, blocked.global_position + Vector2(-18, 0))
	_metrics["facing_luminance"] = facing.get_luminance()
	_metrics["away_luminance"] = away.get_luminance()
	_metrics["occluded_luminance"] = occluded.get_luminance()
	_check(facing.get_luminance() > away.get_luminance() * 1.06, "朝光面温和地亮于背光面")
	_check(facing.get_luminance() > occluded.get_luminance() * 1.1, "原生阴影阻止光穿过前一个实体")
	var pure_black := _pixel(illuminated, _projected(receiver.global_position, receiver.owner_layer))
	_check(maxf(pure_black.r, maxf(pure_black.g, pure_black.b)) < 0.01, "关卡层照明不会把跨层纯黑影子照灰")
	_night().enabled = false
	await _frames()
	var baseline := _capture("03_lighting_disabled")
	var unlit_base := _pixel(baseline, lit.global_position + Vector2(-18, 0))
	_check(facing.get_luminance() > unlit_base.get_luminance() * 1.01, "朝光表面比原始颜色略亮")
	_check(facing.get_luminance() < unlit_base.get_luminance() * 1.2, "朝光表面提亮幅度受限")
	_check(away.get_luminance() < _pixel(baseline, lit.global_position + Vector2(18, 0)).get_luminance(), "背光表面保留温和暗部")
	for object: LayerObject in [foreground, rear]:
		var at := _projected(object.global_position, object.owner_layer)
		_check(absf(_pixel(illuminated, at).get_luminance() - _pixel(baseline, at).get_luminance()) < 0.01, "非关卡层 %d 保持原亮度" % object.owner_layer.layer_id)
	await _check_background_isolation(lit, facing)
	_night().enabled = true
	Global.camera.zoom = Vector2(0.5, 0.5)
	var far_surface := _shape(current, Vector2(1100, 100))
	await _frames()
	var wide := _capture("04_wide_range")
	var far_light := _pixel(wide, far_surface.global_position + Vector2(-18, 0))
	_night().enabled = false
	await _frames()
	var wide_baseline := get_viewport().get_texture().get_image()
	var far_original := _pixel(wide_baseline, far_surface.global_position + Vector2(-18, 0))
	_metrics["far_surface_color_change"] = _color_difference(far_light, far_original)
	_check(far_light.get_luminance() > far_original.get_luminance() * 1.01, "距光源超过 1100 单位的关卡层表面仍能受光")
	_night().enabled = true
	Global.camera.zoom = Vector2.ONE
	await _frames()
	var controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	_check(controller.cycle(1, false), "照明期间整层轮换正常")
	while controller.is_cycling():
		await _frames(1)
	await _frames()
	_check((_night()._occluders[foreground.get_instance_id()].node as LightOccluder2D).visible, "新关卡层物体进入原生遮光")
	_check(not (_night()._occluders[lit.get_instance_id()].node as LightOccluder2D).visible, "退出关卡层的物体不再遮挡当前层光源")
	var cycled := _capture("05_after_cycle")
	_night().enabled = false
	await _frames()
	baseline = get_viewport().get_texture().get_image()
	var former_at := _projected(lit.global_position, lit.owner_layer)
	_check(absf(_pixel(cycled, former_at).get_luminance() - _pixel(baseline, former_at).get_luminance()) < 0.01, "退出关卡层后恢复原景深亮度")
	_night().enabled = true
	_check(controller.transfer(1, lit), "单物体进入关卡层")
	await _frames()
	_check((_night()._occluders[lit.get_instance_id()].node as LightOccluder2D).visible, "单物体换层后自动更新遮光归属")
	_check(controller.transfer(-1, lit), "单物体离开关卡层")
	await _frames()
	var deleted_id: int = blocked.get_instance_id()
	blocked.queue_free()
	await _frames()
	_check(not _night()._occluders.has(deleted_id), "删除物体后清理遮光体记录")
	Global.player.UAV_activate()
	await _frames()
	_check(Global.player.current_state == PlayerController.PlayerState.UAV, "无人机状态仍可正常进入")
	Global.player.position = Vector2(120, 480)
	Global.player.scale = Vector2(0.8, 0.8)
	await _frames()
	_check(_night()._light.global_position.is_equal_approx((Global.player.get_node("LightOrigin") as Marker2D).global_position), "无人机移动和缩放后灯跟随头部")
	get_tree().root.size = Vector2i(1280, 800)
	await _frames(5)
	_capture("06_uav_resized")
	for level_id in [10, 11, 12, 1]:
		_check(await SceneTransition.enter_level(level_id) == OK, "加载关卡 %d" % level_id)
		_game = get_tree().current_scene as Node2D
		await _frames()
		_check((_night()._light != null) == (level_id >= 9), "关卡 %d 的夜间灯启用条件正确" % level_id)
	await _check_disabled("日间关卡没有夜间照明残留")
	_capture("07_day")
	_check(await SceneTransition.enter_main_menu() == OK, "返回主菜单")
	await _frames()
	await _check_disabled("主菜单没有夜间照明残留")
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	var report := FileAccess.open(NIGHT_OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	report.close()
	print("NIGHT_LIGHT_TEST_RESULT ", JSON.stringify(_metrics))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _level_radius() -> float:
	return Global.level.night_light_radius
