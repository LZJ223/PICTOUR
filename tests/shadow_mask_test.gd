## 真实渲染回归：不修改保存的 Level09 布置，先检查原始节点和原始投影。
extends Node

const OUTPUT := "res://.godot/shadow_mask_qa/"
const SHAPE := preload("res://Component/Shadowed_Geometry/Shadowed_Geometry.tscn")
var _game: Node2D
var _checks: int = 0
var _failures: Array[String] = []
var _metrics: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _frames(count: int = 3) -> void:
	for frame in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("SHADOW_MASK_TEST: " + message)

func _system() -> ShadowMaskSystem:
	return _game.get_node("ShadowMaskSystem") as ShadowMaskSystem

func _projected(physical: Vector2, layer: DepthLayer) -> Vector2:
	return Global.camera.global_position + (physical - Global.camera.global_position) * layer.visual_scale

func _screen(world: Vector2, image: Image) -> Vector2:
	return (get_viewport().get_canvas_transform() * world) / get_viewport().get_visible_rect().size * Vector2(image.get_size())

func _pixel(image: Image, world: Vector2) -> Color:
	var at := _screen(world, image)
	return image.get_pixel(clampi(roundi(at.x), 0, image.get_width() - 1), clampi(roundi(at.y), 0, image.get_height() - 1))

func _capture(name: String) -> Image:
	var image := get_viewport().get_texture().get_image()
	image.save_png(OUTPUT + name + ".png")
	return image

func _mask() -> Image:
	return _system()._packed_viewport.get_texture().get_image()

func _casters() -> Array[ShadowedGeometry]:
	var result: Array[ShadowedGeometry] = []
	for layer in Global.layers:
		for child in layer.get_children():
			if child is ShadowedGeometry and child.can_leave_shadow and not child.is_queued_for_deletion():
				result.append(child)
	return result

func _shape(layer: DepthLayer, at: Vector2, casts: bool = false) -> ShadowedGeometry:
	var object := SHAPE.instantiate() as ShadowedGeometry
	object.freeze = true
	object.can_transfer = true
	object.can_leave_shadow = casts
	object.can_be_shadowed = false
	object.position = at
	layer.add_child(object)
	return object

func _check_disabled(message: String) -> void:
	var probe := CanvasLayer.new()
	probe.layer = 200
	get_tree().root.add_child(probe)
	var rect := ColorRect.new()
	rect.size = Vector2(8, 8)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; global uniform bool render_receiver_mask_enabled; void fragment() { COLOR = render_receiver_mask_enabled ? vec4(1,0,0,1) : vec4(0,1,0,1); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	rect.material = material
	probe.add_child(rect)
	await _frames()
	var color := get_viewport().get_texture().get_image().get_pixel(2, 2)
	_check(color.g > 0.99 and color.r < 0.01, message)
	probe.free()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("覆盖纹理测试需要真实 GPU 渲染器")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_tree().root.size = Vector2i(1440, 810)
	Global.next_level_id = 9
	_game = load("res://Interface/Game.tscn").instantiate() as Node2D
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	await get_tree().create_timer(1.1, true).timeout
	Global.player.set_physics_process(false)
	SignalSystem.timer.stop()
	PhysicsServer2D.set_active(false)
	await _frames()
	var casters := _casters()
	_check(casters.size() == 20, "原始 Level09 保留 20 个投影物体")
	var active: int = 0
	var polygon_count: int = 0
	for caster in casters:
		_check(caster.shadow_box.size() == 1 and caster.shadow_visual.size() == 1, "每个投影物体仍有一对生成的影子")
		_check(caster.shadow_box[0].get_parent() == caster and caster.shadow_visual[0].get_parent() == caster, "两份生成的影子仍直接属于原物体")
		if caster.shadow_active[0]:
			active += 1
		for child in caster.get_children():
			if child is Polygon2D:
				polygon_count += 1
	_check(polygon_count == 60, "20 个物体共保留 60 个 Shadow Polygon2D（含母本）")
	_metrics["initial_shadow_polygons"] = polygon_count
	_check(active == 5, "默认第三层的五个物体激活向第四层的投影")
	_check(_system()._captures.size() == 1 and _system()._captures.has(3), "默认仅绘制第四层的承影覆盖")
	var receiver := Global.get_layer_at_slot(3)
	var point := _projected(Vector2(104, 500), receiver)
	var mask := _mask()
	var coverage := _pixel(mask, point)
	_check(coverage.a > 0.99 and coverage.r + coverage.g + coverage.b < 0.01, "真实箱子覆盖仅写入物理层 3 的 A 通道")
	var empty := _pixel(mask, Vector2(70, 480))
	_check(empty.a < 0.01, "箱子上方空白没有被雾或影子自身写入覆盖")
	var clipped := _capture("01_level09_clipped")
	var black := _pixel(clipped, point)
	_check(maxf(black.r, maxf(black.g, black.b)) < 0.01, "原始站位下真实箱子上的投影输出纯黑")
	var gap := _pixel(clipped, Vector2(70, 480))
	_check(gap.get_luminance() > 0.05, "未投射到物体的影子被裁掉")
	_system().debug_view = 1
	await _frames()
	var raw := _capture("02_level09_full_shadow")
	var raw_gap := _pixel(raw, Vector2(70, 480))
	_check(maxf(raw_gap.r, maxf(raw_gap.g, raw_gap.b)) < 0.01, "完整影子模式证明空白探针确实在原始投影内")
	_system().debug_view = 2
	await _frames()
	_capture("03_receiver_mask")
	_system().debug_view = 0
	await _frames()
	var sync_samples: Array[float] = []
	for index in 60:
		var start: int = Time.get_ticks_usec()
		_system()._sync_frame()
		sync_samples.append((Time.get_ticks_usec() - start) / 1000.0)
		await get_tree().process_frame
	sync_samples.sort()
	_metrics["mask_sync_cpu_p95_ms"] = sync_samples[floori(sync_samples.size() * 0.95)]
	_metrics["level09_draw_calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)

	# 实际贴图镂空；新加入的 Sprite 必须自动进入当前物体的覆盖通道。
	var receiving_box := receiver.get_node("ShadowedGeometry4") as ShadowedGeometry
	receiving_box.can_be_shadowed = false
	var hole_image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	hole_image.fill(Color.WHITE)
	for y in range(5, 11):
		for x in range(5, 11):
			hole_image.set_pixel(x, y, Color.TRANSPARENT)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(hole_image)
	sprite.scale = Vector2(5, 5)
	receiving_box.visual_root.get_node("Polygon2D").hide()
	receiving_box.visual_root.add_child(sprite)
	await _frames()
	mask = _mask()
	_check(_pixel(mask, point).a < 0.01, "贴图透明洞的覆盖值为零")
	var hole_result := _capture("04_texture_hole")
	_check(_pixel(hole_result, point).get_luminance() > 0.05, "透明洞没有被影子填黑")
	var solid_point := _projected(receiving_box.global_position + Vector2(25, 0), receiver)
	_metrics["textured_solid_coverage"] = _pixel(mask, solid_point).a
	_check(_pixel(mask, solid_point).a > 0.95, "运行时加入的 Sprite 实体区域进入覆盖纹理（保留景深边缘）")
	_check(_pixel(hole_result, solid_point).get_luminance() < 0.01, "不能被实体切割的物体也正常接影")
	sprite.free()
	receiving_box.visual_root.get_node("Polygon2D").show()
	await _frames()

	# 摄像机观察位置、缩放和实际窗口尺寸变化。
	Global.camera_fixed = false
	Global.camera.position.x += 180.0
	Global.camera.zoom = Vector2(1.2, 1.2)
	await _frames()
	mask = _mask()
	_check(_pixel(mask, _projected(receiving_box.global_position, receiver)).a > 0.99, "镜头移动和缩放后覆盖仍与实体对齐")
	Global.camera_fixed = true
	Global.camera.zoom = Vector2.ONE
	get_tree().root.size = Vector2i(1280, 800)
	await _frames(5)
	mask = _mask()
	_check(_pixel(mask, point).a > 0.99, "窗口拉伸后覆盖仍与实体对齐")
	_capture("05_resized")
	get_tree().root.size = Vector2i(1440, 810)
	await _frames()

	# 原节点应完整保留；目标通道跟随实际 layer_id，而不是固定第四层编号。
	var node_ids: Dictionary = {}
	for caster in casters:
		node_ids[caster.get_instance_id()] = [caster.shadow_box[0].get_instance_id(), caster.shadow_visual[0].get_instance_id()]
	var controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	for direction in [1, 1, 1, 1, -1, 1]:
		_check(controller.cycle(direction, false), "整层轮换 %d 可执行" % direction)
		while controller.is_cycling():
			await _frames(1)
		await _frames()
		var target := Global.get_layer_at_slot(3)
		var target_box: LayerObject
		for child in target.get_children():
			if child is ShadowedGeometry:
				target_box = child
				break
		mask = _mask()
		var sample := _pixel(mask, _projected(target_box.global_position, target))
		_check(sample[target.layer_id] > 0.99, "轮换后覆盖进入实际承影层 %d 的通道" % target.layer_id)
		for id in 4:
			if id != target.layer_id:
				_check(sample[id] < 0.01, "非承影层 %d 通道清零" % id)
		for caster in casters:
			if caster.shadow_active[0]:
				_check((caster.shadow_visual[0].material as ShaderMaterial).get_shader_parameter("receiver_layer_id") == target.layer_id, "视觉影子读取本帧实际承影图层")
	for caster in casters:
		var before: Array = node_ids[caster.get_instance_id()]
		_check(caster.shadow_box[0].get_instance_id() == before[0] and caster.shadow_visual[0].get_instance_id() == before[1], "整层轮换复用原来的影子节点")
	_check(Global.get_layer_at_slot(3) == receiver, "双向轮换后恢复初始承影层")
	_capture("06_after_cycles")

	# 每次仅等待一帧，验证两级视口链没有延迟或残影。
	var moving := _shape(receiver, Vector2(-300, 400))
	await _frames()
	for index in 6:
		var previous := _projected(moving.position, receiver)
		moving.position.x = -500.0 if index % 2 == 0 else -300.0
		await _frames(1)
		mask = _mask()
		if index == 0:
			var source_image := (_system()._captures[3] as SubViewport).get_texture().get_image()
			_metrics["moving_source_new"] = _pixel(source_image, _projected(moving.position, receiver)).a
			_metrics["moving_pack_new"] = _pixel(mask, _projected(moving.position, receiver)).a
		_check(_pixel(mask, _projected(moving.position, receiver)).a > 0.99, "第 %d 帧显示新覆盖" % index)
		_check(_pixel(mask, previous).a < 0.01, "第 %d 帧没有旧覆盖残留" % index)
	var moving_point := _projected(moving.position, receiver)
	_check(controller.transfer(1, moving), "单物体移出承影层")
	await _frames()
	_check(_pixel(_mask(), moving_point).a < 0.01, "物体换层后原通道覆盖消失")
	_check(controller.transfer(-1, moving), "单物体返回承影层")
	await _frames()
	_check(_pixel(_mask(), _projected(moving.position, receiver)).a > 0.99, "物体返回后覆盖恢复")
	moving.queue_free()
	await _frames()
	_check(_pixel(_mask(), moving_point).a < 0.01, "删除实体后覆盖自动清除")

	# 静止两秒仍读取原 shadow_box 切割，碎片自动进入覆盖纹理。
	for caster in casters:
		caster.can_be_shadowed = false
	var cutting_caster := _shape(Global.get_layer_at_slot(2), Vector2(-100, 410), true)
	await _frames()
	var original_visual_id: int = cutting_caster.shadow_visual[0].get_instance_id()
	_check(controller.transfer(1, cutting_caster), "投影物体单独移入关卡层")
	await get_tree().create_timer(0.2, true).timeout
	await _frames()
	_check(not cutting_caster.shadow_active[0] and not cutting_caster.shadow_visual[0].visible, "投影物体移入关卡层后原影子停用")
	_check(controller.transfer(-1, cutting_caster), "投影物体单独返回投影层")
	await get_tree().create_timer(0.2, true).timeout
	await _frames()
	_check(cutting_caster.shadow_active[0] and cutting_caster.shadow_visual[0].get_instance_id() == original_visual_id, "投影物体换层复用原视觉影子并恢复激活")
	var physical_center := cutting_caster.shadow_box[0].global_position
	var cutting_receiver := _shape(receiver, physical_center, true)
	cutting_receiver.collision_box.scale = Vector2(3, 2)
	cutting_receiver.can_be_shadowed = true
	var receiving_id: int = cutting_receiver.get_instance_id()
	var fragment_prefix := str(cutting_receiver.name) + "_Fragment"
	await _frames()
	var cut_point := _projected(physical_center, receiver)
	_check(_pixel(_mask(), cut_point).a > 0.99, "切割前实体仍完整")
	var before_cut := _capture("07_before_cut")
	_check(_pixel(before_cut, cut_point).get_luminance() < 0.01, "原 shadow_box 对应位置的视觉影子为纯黑")
	SignalSystem.timer.start()
	await get_tree().create_timer(2.15, true).timeout
	await _frames()
	_check(not is_instance_id_valid(receiving_id), "保留原计时器触发的实体切割")
	_check(_pixel(_mask(), cut_point).a < 0.01, "切除位置同步从覆盖纹理消失")
	var after_cut := _capture("08_after_cut")
	_check(_pixel(after_cut, cut_point).get_luminance() > 0.05, "实体切除后影子不会留在空中")
	var fragments: int = 0
	for child in receiver.get_children():
		if child is ShadowedGeometry and child.name.begins_with(fragment_prefix):
			fragments += 1
			_check(child.shadow_box.size() == 1 and child.shadow_visual.size() == 1, "切割碎片仍由原初始化流程生成一对影子")
	_check(fragments > 0, "实体切割生成剩余碎片")
	cutting_caster.queue_free()
	await _frames()

	# 两个承影槽位同时输出，验证 RGBA 数据不因 A 通道为零而丢失其他通道。
	for layer in Global.layers:
		for child in layer.get_children():
			if child is LayerObject:
				child.can_leave_shadow = false
				child.hide()
	Global.level.current_layer_index = 0
	Global.level.write_to_global()
	for layer in Global.layers:
		layer.cancel_cycle()
		layer.haze_plane.hide()
	var multi_caster := _shape(Global.get_layer_at_slot(1), Vector2(-100, 420), true)
	await _frames()
	_check(multi_caster.shadow_box.size() == 2 and multi_caster.shadow_visual.size() == 2, "两个承影槽位生成两对影子")
	var multi_polygon_count: int = 0
	for child in multi_caster.get_children():
		if child is Polygon2D:
			multi_polygon_count += 1
	_check(multi_polygon_count == 5, "两个承影槽位共生成 2n+1=5 个 Shadow Polygon2D")
	var multi_receivers: Array[ShadowedGeometry] = []
	for index in 2:
		multi_receivers.append(_shape(Global.get_layer_at_slot(index + 2), multi_caster.shadow_box[index].global_position))
		multi_receivers[index].collision_box.scale = Vector2(2, 2)
	await _frames()
	mask = _mask()
	for index in 2:
		var target := Global.get_layer_at_slot(index + 2)
		var multi_point := _projected(multi_receivers[index].global_position, target)
		var sample := _pixel(mask, multi_point)
		_check(sample[target.layer_id] > 0.99, "两个承影层同时写入覆盖，图层 %d" % target.layer_id)
		var other_target := Global.get_layer_at_slot(3 if index == 0 else 2)
		_check(sample[other_target.layer_id] < 0.01, "RGBA 不同图层的覆盖相互独立")
		_check(multi_caster.shadow_visual[index].get_parent() == multi_caster, "多承影层视觉节点仍属于原投影物体")
	var multi_image := _capture("09_two_receivers")
	for index in 2:
		var target := Global.get_layer_at_slot(index + 2)
		_check(_pixel(multi_image, _projected(multi_receivers[index].global_position, target)).get_luminance() < 0.01, "两个承影层的实际投影均为纯黑")

	_check(await SceneTransition.enter_level(1) == OK, "正式转场进入日间关卡")
	_game = get_tree().current_scene as Node2D
	await _frames()
	_check(_system()._packed_viewport == null, "无投影物体的关卡不分配遮罩视口")
	await _check_disabled("离开投影关卡后关闭全局遮罩")
	_capture("10_day")
	_check(await SceneTransition.enter_main_menu() == OK, "正式返回主菜单")
	await _frames()
	await _check_disabled("主菜单没有覆盖纹理状态残留")
	_capture("11_menu")
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	var report := FileAccess.open(OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	report.close()
	print("SHADOW_MASK_TEST_RESULT ", JSON.stringify(_metrics))
	get_tree().quit(0 if _failures.is_empty() else 1)

