## 真实图层滤镜：亮带、内部 20% 亮度、透明洞口、半透明、缩放、换层与切割。
extends "res://tests/shadow_mask_test.gd"

const FOREGROUND_OUTPUT := "res://.godot/night_foreground_qa/"
var _object: ShadowedGeometry

func _capture(label: String) -> Image:
	var result := get_viewport().get_texture().get_image()
	result.save_png(FOREGROUND_OUTPUT + label + ".png")
	return result

func _enabled(value: bool) -> void:
	Renderer.night_foreground_enabled = value
	Renderer.apply_settings()
	await _frames()

func _gain(before: Image, after: Image, point: Vector2, opacity: float = 1.0) -> float:
	var a := _pixel(before, point)
	var b := _pixel(after, point)
	var background := before.get_pixel(4, 4)
	var offset := background.get_luminance() * (1.0 - opacity)
	return (b.get_luminance() - offset) / maxf(a.get_luminance() - offset, 0.0001)

## 白色测试物体的纹理/模糊边缘并非完全不透明，先从同色内部参考还原覆盖率。
func _covered_gain(before: Image, after: Image, point: Vector2, reference: Vector2, opacity: float = 1.0) -> float:
	var background := before.get_pixel(4, 4)
	var full := _pixel(before, reference) - background
	var edge := _pixel(before, point) - background
	var full_rgb := Vector3(full.r, full.g, full.b)
	var coverage := Vector3(edge.r, edge.g, edge.b).dot(full_rgb) / full_rgb.length_squared()
	return _gain(before, after, point, clampf(coverage * opacity, 0.0, 1.0))

func _bright_width(before: Image, after: Image, left: Vector2) -> float:
	var width := 0.0
	for distance in range(1, 129):
		if _gain(before, after, left + Vector2(distance / Global.camera.zoom.x, 0)) > 0.475:
			width = float(distance)
	return width

func _check_surface(source: Node2D, label: String, opacity: float = 1.0) -> void:
	await _enabled(false)
	var before := _capture(label + "_normal")
	await _enabled(true)
	var after := _capture(label + "_surface")
	var left := source.to_global(Vector2(-20, 0))
	var zoom := Global.camera.zoom.abs()
	var near := left + Vector2(1.5 / zoom.x, 0)
	var center := source.global_position
	var near_gain := _covered_gain(before, after, near, center, opacity)
	var deep_gain := _gain(before, after, center, opacity)
	_metrics[label + "_edge_gain"] = near_gain
	_metrics[label + "_interior_gain"] = deep_gain
	_check(absf(near_gain - 0.75) < 0.04, label + " 表面最高亮度为正常景深配色的 75%")
	_check(absf(deep_gain - 0.2) < 0.04, label + " 内部压暗 80%，不再叠加统一前景压暗")
	_check(before.get_pixel(4, 4) == after.get_pixel(4, 4), label + " 空白背景不受影响")
	## 根据参考图还原边缘覆盖率，检查只调暗 RGB，未修改 Alpha 或背景。
	var outside := left - Vector2(2.0 / zoom.x, 0)
	_metrics[label + "_outside_before"] = str(_pixel(before, outside))
	_metrics[label + "_outside_after"] = str(_pixel(after, outside))
	var background := before.get_pixel(4, 4)
	var full := _pixel(before, center)
	var edge := _pixel(before, outside)
	var actual := _pixel(after, outside)
	var bg := Vector3(background.r, background.g, background.b)
	var full_rgb := Vector3(full.r, full.g, full.b)
	var edge_rgb := Vector3(edge.r, edge.g, edge.b)
	var delta := full_rgb - bg
	var coverage := (edge_rgb - bg).dot(delta) / delta.length_squared() * opacity
	var source_rgb := (full_rgb - bg * (1.0 - opacity)) / opacity
	var expected := source_rgb * (0.75 * coverage) + bg * (1.0 - coverage)
	_check(Vector3(actual.r, actual.g, actual.b).distance_to(expected) < 0.015, label + " 模糊外缘保持原覆盖率并应用 75% 亮度")

func _distance_sample(shape: Polygon2D, distance: float, label: String) -> Vector2:
	await _frames()
	var point := shape.to_global(Vector2(-20, 0)) + Vector2(1.5 / Global.camera.zoom.x, 0)
	var origin := Global.player.get_node("LightOrigin") as Marker2D
	Global.player.global_position += point + Vector2(distance, 0) - origin.global_position
	await _enabled(false)
	var before := _capture(label + "_normal")
	await _enabled(true)
	var after := _capture(label + "_surface")
	var gain := _covered_gain(before, after, point, shape.global_position)
	_metrics[label + "_edge_gain"] = gain
	_check(before.get_pixel(4, 4) == after.get_pixel(4, 4), label + " 距离衰减不影响空白背景")
	_check(absf(_gain(before, after, shape.global_position) - 0.2) < 0.04, label + " 内部暗区仍保留 20% 亮度")
	var other := shape.to_global(Vector2(20, 0)) - Vector2(1.5 / Global.camera.zoom.x, 0)
	return Vector2(gain, _covered_gain(before, after, other, shape.global_position))

func _check_distance_falloff() -> void:
	Global.camera_fixed = false
	var probe := _shape(Global.get_layer_at_slot(0), Global.camera.global_position)
	probe.collision_box.scale = Vector2(14, 9)
	var shape := _visual_shape(probe)
	shape.texture = null
	shape.color = Color.WHITE
	probe.get_node("VisualRoot/Outline").hide()
	Renderer.night_foreground_near_distance = Global.level.night_foreground_near_distance
	Renderer.night_foreground_far_distance = Global.level.night_foreground_far_distance
	var previous := 1.0
	for distance in [0.0, 100.0, 250.0, 400.0, 550.0, 700.0, 950.0]:
		var gain := await _distance_sample(shape, distance, "07_distance_%04d" % distance)
		var expected := lerpf(0.75, 0.2, smoothstep(100.0, 700.0, distance))
		_check(absf(gain.x - expected) < 0.04, "距离 %.0f 的边缘亮度符合平滑衰减，实际 %.3f" % [distance, gain.x])
		_check(gain.x <= previous + 0.01, "距离增加时边缘亮度单调下降")
		previous = gain.x
		if is_zero_approx(distance):
			_check(gain.x - gain.y > 0.15, "同一物体不同位置分别按像素距离衰减")
	get_tree().root.size = Vector2i(1600, 900)
	Global.camera.rotation = 0.2
	for zoom: Vector2 in [Vector2(1.4, 0.9), Vector2(0.65, 0.8)]:
		Global.camera.zoom = zoom
		var gain := await _distance_sample(shape, 400.0, "08_zoom_%s" % zoom)
		_check(absf(gain.x - 0.475) < 0.04, "非等比缩放、相机旋转和窗口变化不改变世界距离")
	Global.camera.rotation = 0.0
	Global.camera.zoom = Vector2.ONE
	Global.player.scale = Vector2.ONE * 0.6
	Renderer.night_foreground_near_distance = 0.0
	Renderer.night_foreground_far_distance = 120.0
	var gain := await _distance_sample(shape, 60.0, "09_head_origin")
	_check(absf(gain.x - 0.475) < 0.04,
		"距离从玩家头部计算，并跟随人物缩放")
	Renderer.night_foreground_near_distance = Global.level.night_foreground_near_distance
	Renderer.night_foreground_far_distance = Global.level.night_foreground_far_distance
	Renderer.apply_settings()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("黑夜前景测试需要真实 GPU 渲染器")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOREGROUND_OUTPUT))
	get_tree().root.size = Vector2i(1440, 810)
	Global.next_level_id = 9
	_game = load("res://Interface/Game.tscn").instantiate() as Node2D
	_game.play_dialogue = false
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	await get_tree().create_timer(1.1, true).timeout
	_capture("00_level09")
	SignalSystem.timer.stop()
	SignalSystem.set_process(false)
	Global.player.set_physics_process(false)
	Global.player.collision_layer = 0
	Global.player.collision_mask = 0
	PhysicsServer2D.set_active(false)
	_game.get_node("NightLightSystem").enabled = false
	var occlusion := _game.get_node_or_null("PlayerOcclusionSystem")
	if occlusion != null:
		occlusion.enabled = false
	Global.player.hide()
	_game.get_node("Camera/MenuUI").hide()
	Global.level.get_node("Background").hide()
	for layer in Global.layers:
		for child in layer.get_children():
			if child is CanvasItem:
				child.hide()
			if child is LayerObject:
				child.collision_layer = 0
				child.collision_mask = 0
	var layer := Global.get_layer_at_slot(0)
	var desired := get_viewport().get_canvas_transform().affine_inverse() * (get_viewport().get_visible_rect().size * 0.5)
	var physical := Global.camera.global_position + (desired - Global.camera.global_position) / layer.visual_scale
	_object = _shape(layer, physical)
	_object.collision_box.scale = Vector2(14, 9)
	var shape := _visual_shape(_object)
	shape.texture = null
	shape.color = Color.WHITE
	_object.get_node("VisualRoot/Outline").hide()
	## 基准是保留偏色/对比度、未统一压暗的原始亮度。
	Renderer.foreground_darkness_step = 0.0
	Renderer.foreground_blur_step = 1.2
	## 原有表面测试固定在近距离平台内，距离相关表现另用真实人物移动检查。
	Renderer.night_foreground_near_distance = 100000.0
	Renderer.night_foreground_far_distance = 200000.0
	await _check_surface(shape, "01_opaque")
	_game.get_node("NightLightSystem").enabled = true
	await _frames()
	var light_on := get_viewport().get_texture().get_image()
	_game.get_node("NightLightSystem").enabled = false
	await _frames()
	var light_off := get_viewport().get_texture().get_image()
	_check(_pixel(light_on, shape.global_position) == _pixel(light_off, shape.global_position), "关卡层灯光开关不改变前景内部亮度")
	_object.visual_root.modulate.a = 0.4
	await _check_surface(shape, "02_translucent", 0.4)
	_object.visual_root.modulate.a = 1.0
	Renderer.foreground_darkness_step = 0.7
	await _enabled(true)
	var strong_uniform := _capture("03_uniform_darkness_ignored")
	Renderer.foreground_darkness_step = 0.0
	Renderer.apply_settings()
	await _frames()
	var no_uniform := _capture("03_no_uniform_darkness")
	_check(strong_uniform.get_data() == no_uniform.get_data(), "黑夜前景表面规则替代旧统一压暗")
	## 使用 Alpha 洞口，黑色纹理花纹不参与轮廓判断。
	shape.hide()
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.fill_rect(Rect2i(48, 48, 32, 32), Color.TRANSPARENT)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(image)
	sprite.scale = Vector2.ONE * (40.0 / 128.0)
	_object.visual_root.add_child(sprite)
	await _enabled(false)
	var before := _capture("04_hole_normal")
	await _enabled(true)
	var after := _capture("04_hole_surface")
	var hole_edge := sprite.to_global(Vector2(-16, 0)) - Vector2(1.5, 0)
	var hole_gain := _covered_gain(before, after, hole_edge, hole_edge - Vector2(30, 0))
	_metrics["hole_edge_gain"] = hole_gain
	_check(absf(hole_gain - 0.75) < 0.04, "透明洞口边缘同样使用 75% 最高亮度")
	_check(_pixel(before, sprite.global_position) == _pixel(after, sprite.global_position), "洞口保持透明，不填色或压暗背景")
	sprite.hide()
	shape.show()
	await _enabled(false)
	before = get_viewport().get_texture().get_image()
	await _enabled(true)
	after = get_viewport().get_texture().get_image()
	var left := shape.to_global(Vector2(-20, 0))
	var transition := _gain(before, after, left + Vector2(5, 0))
	_metrics["transition_gain"] = transition
	_check(transition > 0.24 and transition < 0.71, "缩小后的亮带与内部之间存在平滑过渡")
	var narrow_width := _bright_width(before, after, left)
	Renderer.night_foreground_surface_width = 8.0
	Renderer.night_foreground_fade_width = 4.0
	Renderer.apply_settings()
	await _frames()
	var wide := _capture("04_wide_surface")
	var wide_width := _bright_width(before, wide, left)
	_metrics["bright_width_new"] = narrow_width
	_metrics["bright_width_old"] = wide_width
	_check(wide_width > 0.0 and absf(narrow_width / wide_width - 0.5) < 0.12, "实际亮带范围缩至上一版的约二分之一")
	Renderer.night_foreground_surface_width = Global.level.night_foreground_surface_width
	Renderer.night_foreground_fade_width = Global.level.night_foreground_fade_width
	Renderer.night_foreground_darkness = 0.5
	Renderer.apply_settings()
	await _frames()
	after = get_viewport().get_texture().get_image()
	_check(absf(_gain(before, after, shape.global_position) - 0.5) < 0.04, "内部压暗比例可独立调整")
	Renderer.night_foreground_darkness = 0.8
	Renderer.night_foreground_max_brightness = 0.6
	Renderer.apply_settings()
	await _frames()
	after = get_viewport().get_texture().get_image()
	_check(absf(_covered_gain(before, after, left + Vector2(1.5, 0), shape.global_position) - 0.6) < 0.04, "最高亮度可独立调整")
	_check(absf(_gain(before, after, shape.global_position) - 0.2) < 0.04, "调整最高亮度不改变内部 20% 亮度")
	Renderer.night_foreground_max_brightness = 0.75
	Renderer.apply_settings()
	Global.camera.zoom = Vector2(0.8, 0.8)
	get_tree().root.size = Vector2i(1280, 800)
	await _check_surface(shape, "05_zoom_resized")
	## 关卡层、后景及日间保持旧滤镜；关闭新规则也应逐像素恢复。
	for z in [0.0, -100.0]:
		(layer.material as ShaderMaterial).set_shader_parameter("layer_z_index", z)
		await _enabled(false)
		before = get_viewport().get_texture().get_image()
		await _enabled(true)
		after = get_viewport().get_texture().get_image()
		_check(before.get_data() == after.get_data(), "深度 %.0f 的非前景图层不受新规则影响" % z)
	(layer.material as ShaderMaterial).set_shader_parameter("layer_z_index", 50.0)
	await _enabled(false)
	before = get_viewport().get_texture().get_image()
	await _enabled(true)
	after = get_viewport().get_texture().get_image()
	_check(absf(_gain(before, after, shape.global_position) - 0.6) < 0.04, "整层轮换过渡深度时压暗程度平滑插值")
	(layer.material as ShaderMaterial).set_shader_parameter("layer_z_index", 100.0)
	(layer.material as ShaderMaterial).set_shader_parameter("is_night", false)
	await _enabled(false)
	before = get_viewport().get_texture().get_image()
	await _enabled(true)
	after = get_viewport().get_texture().get_image()
	_check(before.get_data() == after.get_data(), "日间图层保持旧滤镜")
	(layer.material as ShaderMaterial).set_shader_parameter("is_night", true)
	var controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	_check(controller.transfer(-1, _object), "前景物体可实际换入关卡层")
	await get_tree().create_timer(0.2, true).timeout
	await _enabled(false)
	before = get_viewport().get_texture().get_image()
	await _enabled(true)
	after = get_viewport().get_texture().get_image()
	_check(before.get_data() == after.get_data(), "移入关卡层后自动退出前景滤镜")
	_check(controller.transfer(1, _object), "物体可从关卡层移回前景")
	await get_tree().create_timer(0.2, true).timeout
	await _check_surface(shape, "05_returned_to_front")
	## 实际切割后，无需生成或维护额外距离纹理，新切口自动形成亮带。
	var cutter := _game.get_node("ShadowControllerSystem") as ShadowControllerSystem
	cutter.cut_afterimage_duration = 0.0
	var transform := _object.collision_box.global_transform
	var cut_center_x := shape.global_position.x
	var cut := PackedVector2Array([Vector2(-2, -40), Vector2(2, -40), Vector2(2, 40), Vector2(-2, 40)])
	var pieces := cutter._subtract_shadows(transform * _object.collision_box.polygon, [transform * cut])
	var ids: Dictionary = {}
	for child in layer.get_children():
		ids[child.get_instance_id()] = true
	cutter._replace_object_with_fragments(_object, pieces)
	await _frames()
	var fragments: Array[ShadowedGeometry] = []
	for child in layer.get_children():
		if child is ShadowedGeometry and not ids.has(child.get_instance_id()):
			fragments.append(child)
	_check(fragments.size() == 2, "真实切割正常生成两个碎片")
	await _enabled(false)
	before = _capture("06_cut_normal")
	await _enabled(true)
	after = _capture("06_cut_surface")
	for fragment in fragments:
		var visual := _visual_shape(fragment)
		var polygon := visual.polygon
		var bounds := _polygon_bounds(polygon)
		var toward_gap: float = 1.0 if visual.global_position.x < cut_center_x else -1.0
		var at := Vector2(bounds.end.x if toward_gap > 0.0 else bounds.position.x, bounds.get_center().y)
		var point := visual.to_global(at) - Vector2(toward_gap * 1.5 / Global.camera.zoom.x, 0)
		var gain := _covered_gain(before, after, point, visual.to_global(bounds.get_center()))
		_metrics["cut_%d_edge_gain" % fragments.find(fragment)] = gain
		_check(absf(gain - 0.75) < 0.04, "切割后的新切口自动使用窄亮带与 75% 亮度")
	for fragment in fragments:
		fragment.hide()
	await _check_distance_falloff()
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	var report := FileAccess.open(FOREGROUND_OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	print("NIGHT_FOREGROUND_TEST_RESULT ", JSON.stringify(_metrics))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds
