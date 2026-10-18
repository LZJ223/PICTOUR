## 用真实渲染测量白边宽度，覆盖凹多边形、非等比缩放、相机缩放、换层和切割。
extends "res://tests/shadow_mask_test.gd"

const SELECTION_OUTPUT := "res://.godot/selection_outline_qa/"

func _capture(name: String) -> Image:
	var result := get_viewport().get_texture().get_image()
	result.save_png(SELECTION_OUTPUT + name + ".png")
	return result

func _at(image: Image, point: Vector2) -> Color:
	var pixel := point / get_viewport().get_visible_rect().size * Vector2(image.get_size())
	return image.get_pixel(clampi(roundi(pixel.x), 0, image.get_width() - 1), clampi(roundi(pixel.y), 0, image.get_height() - 1))

func _measure_edges(object: ShadowedGeometry, label: String) -> void:
	object.set_pick_condition(false)
	await _frames()
	var before := _capture(label + "_before")
	object.set_pick_condition(true)
	await _frames()
	var after := _capture(label + "_selected")
	var shape := _visual_shape(object)
	var polygon := shape.get_global_transform_with_canvas() * shape.polygon
	var widths: Array[float] = []
	for index in polygon.size():
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		if a.distance_to(b) < 20.0:
			continue
		var middle := (a + b) * 0.5
		var normal := Vector2((b - a).y, -(b - a).x).normalized()
		if Geometry2D.is_point_in_polygon(middle + normal * 0.1, polygon):
			normal = -normal
		var first_white: float = -1.0
		var last_white: float = -1.0
		for step in range(121):
			var distance: float = step * 0.25
			var point := middle + normal * distance
			var color := _at(after, point)
			var old := _at(before, point)
			if minf(color.r, minf(color.g, color.b)) > 0.9 and color.r - old.r > 0.15:
				if first_white < 0.0:
					first_white = distance
				last_white = distance
		var width := last_white - first_white if first_white >= 0.0 else 0.0
		widths.append(width)
		_check(absf(width - Renderer.selection_outline_width) <= 1.75, label + " 边 %d 的可见白边保持指定屏幕宽度，实际 %.2f" % [index, width])
	_metrics[label + "_visible_widths"] = widths
	for entry in object._selection_outlines:
		_check(entry.outline.z_index == object.owner_layer.z_index - 1, label + " 描边复用父类图层排序")
		for line in entry.outline.get_children():
			_check((line.visibility_layer & LayerObject.RECEIVER_MASK_BITS) == 0, label + " 选中白边不进入承影覆盖")
	object.set_pick_condition(false)
	await _frames()
	var deselected := get_viewport().get_texture().get_image()
	_check(before.get_data() == deselected.get_data(), label + " 取消选中后恢复原画面")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("选中描边测试需要真实 GPU 渲染器")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SELECTION_OUTPUT))
	get_tree().root.size = Vector2i(1440, 810)
	Global.next_level_id = 9
	_game = load("res://Interface/Game.tscn").instantiate() as Node2D
	_game.play_dialogue = false
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	await get_tree().create_timer(1.1, true).timeout
	SignalSystem.set_process(false)
	SignalSystem.timer.stop()
	Global.player.set_physics_process(false)
	PhysicsServer2D.set_active(false)
	_game.get_node("NightLightSystem").enabled = false
	_game.get_node("Camera/MenuUI").hide()
	Global.level.get_node("Background").hide()
	Global.player.hide()
	for layer in Global.layers:
		layer.haze_plane.hide()
		for child in layer.get_children():
			if child is LayerObject:
				child.hide()
				child.collision_layer = 0
				child.collision_mask = 0
	## 实际关卡对象先保留原景深参数截图，再关闭模糊以精确测量轮廓。
	var original := Global.get_layer_at_slot(2).get_node("ShadowedGeometry") as ShadowedGeometry
	original.show()
	original.set_pick_condition(true)
	await _frames()
	_capture("01_level09")
	original.set_pick_condition(false)
	Renderer.maximum_blur_lod = 0.0
	Renderer.apply_settings()
	await _measure_edges(original, "02_concave")
	original.hide()
	var object := _shape(Global.get_layer_at_slot(2), Global.camera.global_position)
	object.collision_box.scale = Vector2(16, 3)
	await _measure_edges(object, "03_nonuniform")
	var border := object.get_node("VisualRoot/Outline") as Line2D
	border.hide()
	await _measure_edges(object, "04_without_border")
	border.show()
	border.width = 2.5
	await _measure_edges(object, "05_thick_border")
	object.rotation = 0.25
	Global.camera.zoom = Vector2(1.2, 1.4)
	await _measure_edges(object, "06_rotated_zoom")
	Renderer.selection_outline_width = 3.0
	Renderer.apply_settings()
	await _measure_edges(object, "07_width_change")
	Renderer.selection_outline_width = 6.0
	Renderer.apply_settings()
	object.rotation = 0.0
	Global.camera.zoom = Vector2.ONE
	object.set_pick_condition(true)
	var controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	_check(controller.transfer(-1, object), "选中状态下物体可换层")
	await get_tree().create_timer(0.2, true).timeout
	await _measure_edges(object, "08_transferred")
	## 通过真实切割管线建立碎片，检查新切口可选中且几何仍完整。
	var cutter := _game.get_node("ShadowControllerSystem") as ShadowControllerSystem
	var physical := object.collision_box.global_transform
	var cut := PackedVector2Array([Vector2(-2, -40), Vector2(2, -40), Vector2(2, 40), Vector2(-2, 40)])
	var pieces := cutter._subtract_shadows(physical * object.collision_box.polygon, [physical * cut])
	_check(pieces.size() == 2, "切割生成两个连通碎片")
	var ids: Dictionary = {}
	var owner := object.owner_layer
	for child in owner.get_children():
		ids[child.get_instance_id()] = true
	cutter._replace_object_with_fragments(object, pieces)
	await _frames()
	var fragments: Array[ShadowedGeometry] = []
	for child in owner.get_children():
		if child is ShadowedGeometry and not ids.has(child.get_instance_id()):
			fragments.append(child)
			child.hide()
	_check(fragments.size() == 2, "碎片使用新的子类轮廓初始化")
	for index in fragments.size():
		fragments[index].show()
		await _measure_edges(fragments[index], "09_fragment_%d" % index)
		fragments[index].hide()
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	var report := FileAccess.open(SELECTION_OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	print("SELECTION_OUTLINE_TEST_RESULT ", JSON.stringify(_metrics))
	get_tree().quit(0 if _failures.is_empty() else 1)
