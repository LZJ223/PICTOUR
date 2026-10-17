## 用真实渲染器验证 GPU 图集、透明裁切、换层、实体切割和场景生命周期。
## godot --path . res://tests/night_render_test.tscn --max-fps 60
extends Node

const SHAPE := preload("res://Component/Shadowed_Geometry/Shadowed_Geometry.tscn")
const OUTPUT := "res://.godot/night_qa/"
var _game: Node2D
var _checks: int = 0
var _failures: Array[String] = []
var _metrics: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("NIGHT_TEST: " + message)

func _frames(count: int = 3) -> void:
	for index in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _night() -> NightRenderSystem:
	return _game.get_node("NightRenderSystem") as NightRenderSystem

func _screen(world: Vector2, image_size: Vector2) -> Vector2:
	return (get_viewport().get_canvas_transform() * world) / get_viewport().get_visible_rect().size * image_size

func _projected(point: Vector2, layer: DepthLayer) -> Vector2:
	return Global.camera.global_position + (point - Global.camera.global_position) * layer.visual_scale

func _pixel(image: Image, position: Vector2) -> Color:
	return image.get_pixel(clampi(roundi(position.x), 0, image.get_width() - 1), clampi(roundi(position.y), 0, image.get_height() - 1))

func _mask_pixel(image: Image, physical: Vector2, layer: DepthLayer) -> Color:
	var screen := _screen(_projected(physical, layer), Vector2(_night()._tile_size))
	var tile := Vector2(layer.layer_id % 2, layer.layer_id / 2) * Vector2(_night()._tile_size)
	return _pixel(image, screen + tile)

func _shape(layer: DepthLayer, at: Vector2, caster: bool) -> ShadowedGeometry:
	var object := SHAPE.instantiate() as ShadowedGeometry
	object.freeze = true
	object.can_leave_shadow = caster
	object.can_be_shadowed = false
	object.position = at
	layer.add_child(object)
	return object

func _capture(name: String) -> Image:
	var image := get_viewport().get_texture().get_image()
	image.save_png(OUTPUT + name + ".png")
	return image

func _mask_count(image: Image) -> int:
	var count: int = 0
	for y in range(0, image.get_height(), 4):
		for x in range(0, image.get_width(), 4):
			if image.get_pixel(x, y).r > 0.5:
				count += 1
	return count

func _measure_fps() -> float:
	await _frames(10)
	var start: int = Time.get_ticks_usec()
	for frame in 60:
		await get_tree().process_frame
	return 60000000.0 / (Time.get_ticks_usec() - start)

## 通过实际 Shader 验证全局开关，不调用会强制同步渲染线程的 getter。
func _check_night_disabled(message: String) -> void:
	var probe := CanvasLayer.new()
	probe.layer = 200
	get_tree().root.add_child(probe)
	var rect := ColorRect.new()
	rect.size = Vector2(16, 16)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; global uniform bool render_night_enabled; void fragment() { COLOR = render_night_enabled ? vec4(1,0,0,1) : vec4(0,1,0,1); }"
	material.shader = shader
	rect.material = material
	probe.add_child(rect)
	await _frames()
	var color := get_viewport().get_texture().get_image().get_pixel(2, 2)
	_check(color.g > 0.9 and color.r < 0.01, message)
	probe.free()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if DisplayServer.get_name() == "headless":
		push_error("此测试需要真实 GPU 渲染器，不能使用 --headless")
		get_tree().quit(1)
		return
	var tree := get_tree()
	tree.root.size = Vector2i(1440, 810)
	Global.next_level_id = 9
	_game = load("res://Interface/Game.tscn").instantiate()
	tree.root.add_child(_game)
	tree.current_scene = _game
	await tree.create_timer(1.2, true).timeout
	await _frames()
	_check(_night()._casters.size() == 20, "Level09 的 20 个投影物体均已注册")
	_capture("01_level09")
	Global.player.set_physics_process(false)
	SignalSystem.timer.stop()
	PhysicsServer2D.set_active(false)
	# 原场景里的箱子稍微抬高，让真实接影箱露出投影；保存的关卡布局不变。
	var real_caster := Global.get_layer_at_slot(2).get_node("ShadowedGeometry5") as ShadowedGeometry
	var real_receiver := Global.get_layer_at_slot(3)
	var real_position := real_caster.position
	real_caster.position.y -= 40.0
	await _frames()
	var real_image := _capture("01b_level09_visible_shadow")
	var real_probe := _screen(_projected(Vector2(104, 500), real_receiver), real_image.get_size())
	var real_black := _pixel(real_image, real_probe)
	_check(maxf(real_black.r, maxf(real_black.g, real_black.b)) < 0.01, "真实 Level09 箱子上的可见投影是纯黑")
	RenderingServer.global_shader_parameter_set(&"render_shadow_mask", NightRenderSystem.empty_mask())
	await _frames()
	var real_without_mask := _pixel(get_viewport().get_texture().get_image(), real_probe)
	_check(real_without_mask.get_luminance() > 0.1, "关闭遮罩后同一真实箱子像素恢复原色")
	RenderingServer.global_shader_parameter_set(&"render_shadow_mask", _night()._mask_viewport.get_texture())
	# 普通 Soil 也接影；让前面的地面临时退出视线，避免把遮挡误判成未渲染。
	Global.get_layer_at_slot(0).hide()
	Global.get_layer_at_slot(1).hide()
	var nearer_soil := Global.get_layer_at_slot(2).get_node("Soil_001") as LayerObject
	nearer_soil.hide()
	await _frames()
	real_image = _capture("01c_level09_ground_shadow")
	real_black = _pixel(real_image, _screen(_projected(Vector2(100, 530), real_receiver), real_image.get_size()))
	_check(maxf(real_black.r, maxf(real_black.g, real_black.b)) < 0.01, "真实 Level09 普通地面接收纯黑投影")
	Global.get_layer_at_slot(0).show()
	Global.get_layer_at_slot(1).show()
	nearer_soil.show()
	real_caster.position = real_position
	await _frames(30)
	var sync_samples: Array[float] = []
	var benchmark_start: int = Time.get_ticks_usec()
	for index in 90:
		var sync_start: int = Time.get_ticks_usec()
		_night()._sync_frame()
		sync_samples.append((Time.get_ticks_usec() - sync_start) / 1000.0)
		await tree.process_frame
	sync_samples.sort()
	_metrics["level09_measured_fps"] = 90000000.0 / (Time.get_ticks_usec() - benchmark_start)
	_metrics["night_sync_cpu_p95_ms"] = sync_samples[floori(sync_samples.size() * 0.95)]
	_metrics["level09_draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_night()._rays.hide()
	_metrics["surface_only_fps"] = await _measure_fps()
	RenderingServer.global_shader_parameter_set(&"render_night_enabled", false)
	_metrics["depth_only_fps"] = await _measure_fps()
	RenderingServer.global_shader_parameter_set(&"render_night_enabled", true)
	for layer in Global.layers:
		(layer.material as ShaderMaterial).set_shader_parameter("is_night", false)
	_night()._rays.show()
	_metrics["air_only_fps"] = await _measure_fps()
	for layer in Global.layers:
		(layer.material as ShaderMaterial).set_shader_parameter("is_night", true)

	# 隔离验证：仍使用 Level09 的真实图层、相机、材质和渲染系统。
	for layer in Global.layers:
		layer.haze_plane.hide()
		for child in layer.get_children():
			if child is LayerObject:
				child.hide()
				if child is RigidBody2D:
					child.freeze = true
	var casting_layer := Global.get_layer_at_slot(2)
	var receiving_layer := Global.get_layer_at_slot(3)
	var caster := _shape(casting_layer, Vector2(-100, 435), true)
	var receiver := _shape(receiving_layer, Vector2(-245, 435), false)
	receiver.collision_box.scale = Vector2(3, 2)
	var lit_object := _shape(Global.get_layer_at_slot(1), Vector2(120, 435), false)
	var foreground_object := _shape(Global.get_layer_at_slot(0), Vector2(280, 400), false)
	await _frames()
	var mask := _night()._mask_viewport.get_texture().get_image()
	var light_origin := Global.player.get_node("LightOrigin") as Marker2D
	var center: Vector2 = caster.get_projection_transform(receiving_layer, light_origin.global_position).origin
	_check(_mask_pixel(mask, center, receiving_layer).r > 0.99, "GPU 遮罩与头部光源的物理投影吻合")
	var image := _capture("02_receiver_and_lighting")
	var black := _pixel(image, _screen(_projected(center, receiving_layer), image.get_size()))
	_check(maxf(black.r, maxf(black.g, black.b)) < 0.01, "覆盖区域输出纯黑")
	var uncovered := _pixel(image, _screen(_projected(Vector2(-290, 435), receiving_layer), image.get_size()))
	_check(uncovered.r + uncovered.g + uncovered.b > 0.08, "接影物体未覆盖部分保留正常颜色")
	var gap := Vector2(-220, 478)
	_check(_mask_pixel(mask, gap, receiving_layer).r > 0.99, "空白裁切探针位于完整投影内部")
	var gap_color := _pixel(image, _screen(_projected(gap, receiving_layer), image.get_size()))
	_check(gap_color.r + gap_color.g + gap_color.b > 0.3, "无目标物体的投影部分不显示黑色")
	for id in 3:
		var tile := Rect2i(Vector2i(id % 2, id / 2) * _night()._tile_size, _night()._tile_size)
		_check(_mask_count(mask.get_region(tile)) == 0, "遮罩不污染物理图层 %d" % id)
	var facing := _pixel(image, _screen(lit_object.global_position + Vector2(-18, 0), image.get_size()))
	var away := _pixel(image, _screen(lit_object.global_position + Vector2(18, 0), image.get_size()))
	_check(facing.get_luminance() > away.get_luminance() * 1.15, "关卡层朝光面比背光面更亮")
	_metrics["facing_luminance"] = facing.get_luminance()
	_metrics["away_luminance"] = away.get_luminance()
	# 关闭夜间效果作同像素基准，所有非关卡层的原有景深亮度必须一致。
	RenderingServer.global_shader_parameter_set(&"render_night_enabled", false)
	_night()._rays.hide()
	await _frames()
	var baseline := get_viewport().get_texture().get_image()
	for object: LayerObject in [caster, receiver, foreground_object]:
		var probe: Vector2 = object.global_position
		if object == receiver:
			probe = Vector2(-290, 435) # 投影以外的接影部分
		var screen_point := _screen(_projected(probe, object.owner_layer), image.get_size())
		var actual := _pixel(image, screen_point)
		var expected := _pixel(baseline, screen_point)
		_check(absf(actual.get_luminance() - expected.get_luminance()) < 0.015, "非关卡层 %d 保持原亮度" % object.owner_layer.layer_id)
	RenderingServer.global_shader_parameter_set(&"render_night_enabled", true)
	_night()._rays.show()
	await _frames()
	var air_lit := _pixel(image, _screen(Vector2(220, 350), image.get_size()))
	var air_blocked := _pixel(image, _screen(Vector2(220, 435), image.get_size()))
	_check(air_lit.get_luminance() > air_blocked.get_luminance() + 0.08, "透明空气区域有明显的照亮和遮挡分界")
	var blocked_object := _shape(Global.get_layer_at_slot(1), Vector2(220, 435), false)
	await _frames()
	var blocked_image := _capture("02b_surface_occlusion")
	var blocked_face := _pixel(blocked_image, _screen(blocked_object.global_position + Vector2(-18, 0), image.get_size()))
	_check(facing.get_luminance() > blocked_face.get_luminance() * 1.8, "被前一物体挡住的表面不会穿透受光")
	blocked_object.queue_free()
	await _frames()

	# 目标贴图的透明洞直接由 CanvasGroup Alpha 裁切。
	var hole_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	hole_image.fill(Color.WHITE)
	for y in range(5, 11):
		for x in range(5, 11):
			hole_image.set_pixel(x, y, Color.TRANSPARENT)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(hole_image)
	sprite.scale = Vector2(3, 3)
	receiver.visual_root.get_node("Polygon2D").hide()
	receiver.visual_root.add_child(sprite)
	await _frames()
	image = _capture("03_texture_hole")
	var hole := _pixel(image, _screen(_projected(receiver.global_position, receiving_layer), image.get_size()))
	_check(hole.r + hole.g + hole.b > 0.3, "透明贴图镂空不被影子填黑")
	sprite.free()
	receiver.visual_root.get_node("Polygon2D").show()

	# 观察镜头只能改变显示投影，不得移动真实光源。
	var original_projection := caster.get_projection_transform(receiving_layer, light_origin.global_position)
	Global.camera_fixed = false
	Global.camera.position.x += 180.0
	await _frames()
	mask = _night()._mask_viewport.get_texture().get_image()
	_check(original_projection.is_equal_approx(caster.get_projection_transform(receiving_layer, light_origin.global_position)), "相机移动不改变物理投影")
	_check(_mask_pixel(mask, center, receiving_layer).r > 0.99, "相机改变后遮罩仍与目标层对齐")
	Global.camera_fixed = true
	await _frames()
	light_origin.position.y = 0.0
	await _frames()
	mask = _night()._mask_viewport.get_texture().get_image()
	_check(_mask_pixel(mask, center, receiving_layer).r < 0.01, "光源改为脚部后投影离开原位置")
	light_origin.position.y = -85.0
	await _frames()
	# 每次只等待一帧，检查新投影已经出现且上一帧的旧位置没有拖影。
	for step_index in 6:
		var previous_center := caster.get_projection_transform(receiving_layer, light_origin.global_position).origin
		caster.position.x = -200.0 if step_index % 2 == 0 else -100.0
		await _frames(1)
		mask = _night()._mask_viewport.get_texture().get_image()
		var current_center := caster.get_projection_transform(receiving_layer, light_origin.global_position).origin
		_check(_mask_pixel(mask, current_center, receiving_layer).r > 0.99, "移动第 %d 帧采样本帧遮罩" % step_index)
		_check(_mask_pixel(mask, previous_center, receiving_layer).r < 0.01, "移动第 %d 帧没有旧影子残留" % step_index)

	var controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	for direction in [-1, 1]:
		_check(controller.cycle(direction, false), "双向图层轮换 %d" % direction)
		while controller.is_cycling():
			await _frames(1)
		await _frames()
	for turn in 4:
		_check(controller.cycle(1, false), "第 %d 次整层轮换成功" % turn)
		while controller.is_cycling():
			await _frames(1)
		await _frames()
		mask = _night()._mask_viewport.get_texture().get_image()
		if caster.can_project_on(receiving_layer):
			center = caster.get_projection_transform(receiving_layer, light_origin.global_position).origin
			_check(_mask_pixel(mask, center, receiving_layer).r > 0.99, "轮换后的物理图层仍读取自身遮罩")
	_check(casting_layer.slot == 2 and receiving_layer.slot == 3, "完整轮换保持物理图层身份")
	_check(_night()._casters.size() == 1, "轮换不重复注册或遗留投影物体")
	_check(controller.transfer(1, caster), "投影物体单独前移成功")
	await _frames()
	_check(_mask_count(_night()._mask_viewport.get_texture().get_image()) == 0, "投影物进入关卡层后原遮罩清空")
	_check(controller.transfer(-1, caster), "投影物体返回原层成功")
	await _frames()
	_check(_mask_count(_night()._mask_viewport.get_texture().get_image()) > 0, "物体换层后投影连接恢复")
	_check(controller.transfer(1, receiver), "接影物体单独前移成功")
	await _frames()
	_check(receiver.owner_layer == casting_layer, "接影物体物理归属更新")
	_check(controller.transfer(-1, receiver), "接影物体返回原层成功")
	await _frames()

	# 调用实际玩法切割；显示此前没有逐帧改变实体。
	var before_area: float = absf((_game.get_node("ShadowControllerSystem") as ShadowControllerSystem)._polygon_area(receiver.collision_box.polygon)) * absf(receiver.collision_box.global_transform.determinant())
	receiver.can_be_shadowed = true
	var original_id: int = receiver.get_instance_id()
	(_game.get_node("ShadowControllerSystem") as ShadowControllerSystem).shadow_boolean()
	await _frames()
	_check(not is_instance_id_valid(original_id), "静止切割替换原接影物体")
	var after_area: float = 0.0
	var fragments: int = 0
	for child in receiving_layer.get_children():
		if child is ShadowedGeometry and child.visible and child.can_be_shadowed:
			fragments += 1
			after_area += absf((_game.get_node("ShadowControllerSystem") as ShadowControllerSystem)._polygon_area(child.collision_box.polygon))
	_check(fragments > 0 and after_area > 0.0 and after_area < before_area, "实体切割保留正确剩余片段和碰撞轮廓")
	_capture("04_after_cut")
	caster.queue_free()
	await _frames()
	_check(_night()._casters.size() == 0, "删除投影物体清理注册记录")
	_check(_mask_count(_night()._mask_viewport.get_texture().get_image()) == 0, "删除投影物体清空 GPU 遮罩")
	var timed_caster := _shape(casting_layer, Vector2(-100, 435), true)
	var timed_receiver := _shape(receiving_layer, Vector2(-245, 435), false)
	timed_receiver.collision_box.scale = Vector2(3, 2)
	timed_receiver.can_be_shadowed = true
	var timed_id: int = timed_receiver.get_instance_id()
	await _frames()
	_check(is_instance_id_valid(timed_id), "静止计时前实体保持完整")
	_check(is_equal_approx(SignalSystem.timer.wait_time, 2.0), "保留原有两秒切割计时")
	SignalSystem.timer.start()
	await tree.create_timer(2.15, true).timeout
	await _frames()
	_check(not is_instance_id_valid(timed_id), "实际计时器触发实体切割")
	timed_caster.queue_free()
	await _frames()

	# 用正式转场验证每个黑夜关卡和日间/菜单清理。
	for level_id in [10, 11, 12, 9]:
		_check(await SceneTransition.enter_level(level_id) == OK, "加载关卡 %d" % level_id)
		_game = tree.current_scene as Node2D
		await _frames()
		_check(Global.level.is_night and _night()._mask_viewport != null, "关卡 %d 启用黑夜系统" % level_id)
	var paused_time: float = _night()._time
	var pause_menu := _game.get_node("Camera/MenuUI/Screen/Pause")
	pause_menu.open()
	await _frames(5)
	_check(is_equal_approx(_night()._time, paused_time), "暂停菜单冻结光束动画时间")
	pause_menu.resume()
	await _frames()
	# 非限帧运行时，几个渲染帧可能还不到一个物理帧；先等待落地判定。
	await tree.create_timer(0.10, true).timeout
	Global.player.UAV_activate()
	await _frames()
	_check(Global.player.current_state == PlayerController.PlayerState.UAV, "无人机状态可正常进入")
	Global.player.set_physics_process(false)
	Global.player.position = Vector2(0, 570)
	Global.player.velocity = Vector2.ZERO
	SignalSystem.timer.stop()
	PhysicsServer2D.set_active(false)
	await _frames()
	_capture("05_level09_uav")
	_check((Global.player.get_node("LightOrigin") as Marker2D).global_position.is_equal_approx(Vector2(0, 485)), "无人机光源跟随头部")
	get_tree().root.size = Vector2i(1280, 800)
	await _frames(5)
	_capture("06_resized")
	_check(_night()._mask_viewport.size == _night()._tile_size * 2, "窗口变化同步遮罩图集尺寸")
	_check(await SceneTransition.enter_level(1) == OK, "切回白天关卡")
	_game = tree.current_scene as Node2D
	await _frames()
	_check(not Global.level.is_night and _night()._mask_viewport == null, "白天关卡不分配黑夜视口")
	await _check_night_disabled("离开黑夜关闭全局效果")
	_capture("07_day")
	_check(await SceneTransition.enter_main_menu() == OK, "返回主菜单")
	await _frames()
	_check(Global.level == null, "返回主菜单释放关卡引用")
	await _check_night_disabled("主菜单没有黑夜状态残留")
	_capture("08_menu")
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	var report := FileAccess.open(OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	report.close()
	print("NIGHT_TEST_RESULT ", JSON.stringify(_metrics))
	tree.quit(0 if _failures.is_empty() else 1)
