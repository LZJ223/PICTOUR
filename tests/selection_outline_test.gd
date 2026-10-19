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

## 从选中前后的实际 RGB 变化还原白边覆盖率，避免只检查节点上的抗锯齿标志。
func _partial_coverage_pixels(before: Image, after: Image) -> int:
	var count := 0
	for y in after.get_height():
		for x in after.get_width():
			var old := before.get_pixel(x, y).r
			if old >= 0.8:
				continue
			var coverage := (after.get_pixel(x, y).r - old) / (1.0 - old)
			if coverage > 0.05 and coverage < 0.95:
				count += 1
	return count

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
	if label in ["06_rotated_zoom", "10_concave_diagonal", "11_subpixel_move"]:
		var partial := _partial_coverage_pixels(before, after)
		_metrics[label + "_partial_coverage_pixels"] = partial
		_check(partial > 100, label + " 白边实际包含亚像素透明度过渡，像素数 %d" % partial)
	for entry in object._selection_outlines:
		_check(entry.outline.z_index == object.owner_layer.z_index - 1, label + " 描边复用父类图层排序")
		_check((entry.outline.visibility_layer & LayerObject.RECEIVER_MASK_BITS) == 0, label + " 选中白边不进入承影覆盖")
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
	var original: ShadowedGeometry
	for child in Global.get_layer_at_slot(2).get_children():
		if child is ShadowedGeometry:
			original = child
			break
	_check(original != null, "Level09 关卡层存在可测试的多边形物体")
	if original == null:
		get_tree().quit(1)
		return
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
	## 此处测量选中前后的一致性，不让切割残影的淡出改变对照画面。
	cutter.cut_afterimage_duration = 0.0
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
	## 固定凹口及斜边，避免关卡美术更新后只剩轴对齐轮廓；闭合边故意位于斜边。
	var concave := _shape(Global.get_layer_at_slot(2), Global.camera.global_position)
	var polygon := PackedVector2Array([
		Vector2(-120, -70), Vector2(80, -90), Vector2(120, -20),
		Vector2(20, -10), Vector2(40, 80), Vector2(-100, 65),
	])
	concave.collision_box.polygon = polygon
	_visual_shape(concave).polygon = polygon
	(concave.get_node("VisualRoot/Outline") as Line2D).points = polygon
	(concave.get_node("VisualRoot/Area2D/CollisionBox") as CollisionPolygon2D).polygon = polygon
	concave.shadow.polygon = polygon
	Global.camera.zoom = Vector2(1.15, 0.9)
	concave.rotation = -0.13
	await _measure_edges(concave, "10_concave_diagonal")
	concave.position += Vector2(0.37, 0.23)
	await _measure_edges(concave, "11_subpixel_move")
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	var report := FileAccess.open(SELECTION_OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	print("SELECTION_OUTLINE_TEST_RESULT ", JSON.stringify(_metrics))
	get_tree().quit(0 if _failures.is_empty() else 1)
