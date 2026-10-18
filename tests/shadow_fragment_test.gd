## 真实切割与渲染对照：缩放、描边、纹理相位、重复切割及换层。
extends "res://tests/shadow_mask_test.gd"

const FRAGMENT_OUTPUT := "res://.godot/shadow_fragment_qa/"
var _controller: ShadowControllerSystem
var _fixtures: Array[ShadowedGeometry] = []

func _capture(name: String) -> Image:
	var result := get_viewport().get_texture().get_image()
	result.save_png(FRAGMENT_OUTPUT + name + ".png")
	return result

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("碎片外观测试需要真实 GPU 渲染器")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAGMENT_OUTPUT))
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
	var background := Global.level.get_node("Background")
	background.set_process(false)
	if background.has_node("SkyColor"):
		(background.get_node("SkyColor") as ColorRect).color = Color(0.05, 0.05, 0.05, 1.0)
	PhysicsServer2D.set_active(false)
	_game.get_node("NightLightSystem").enabled = false
	Global.player.hide()
	_game.get_node("Camera/MenuUI").hide()
	for layer in Global.layers:
		layer.haze_plane.hide()
		for child in layer.get_children():
			if child is LayerObject:
				child.hide()
				child.collision_layer = 0
				child.collision_mask = 0
	_controller = _game.get_node("ShadowControllerSystem") as ShadowControllerSystem
	var layer_controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	var source := _source()
	var fragments := await _cut_and_check(source, "01_scaled")
	if not fragments.is_empty():
		var parent := fragments[0]
		var material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = "shader_type canvas_item; uniform float tint = 0.9; void fragment() { COLOR = texture(TEXTURE, UV) * COLOR * tint; }"
		material.shader = shader
		_visual_shape(parent).material = material
		var children := await _cut_and_check(parent, "02_repeated")
		if not children.is_empty():
			var shape := _visual_shape(children[0])
			_check(shape.material != material and (shape.material as ShaderMaterial).shader == shader, "碎片独立材质参数，共享 Shader")
			material.set_shader_parameter("tint", 0.3)
			_check(is_equal_approx((shape.material as ShaderMaterial).get_shader_parameter("tint"), 0.9), "修改母物体材质不会串改碎片")
			var offset := shape.texture_offset
			var scale := shape.texture_scale
			children[0].position += Vector2(40, 20)
			await _frames()
			_check(shape.texture_offset == offset and shape.texture_scale == scale, "碎片移动时纹理随物体移动，不重新按世界坐标定位")
			var before_transfer := shape.global_transform
			_check(layer_controller.transfer(-1, children[0]), "连续切割后的碎片仍可以换层")
			await get_tree().create_timer(0.2, true).timeout
			await _frames()
			_check(shape.global_transform.is_equal_approx(before_transfer), "碎片换层缩放后保持原视觉尺寸与描边缩放")
			_check(shape.texture_offset == offset and shape.texture_scale == scale, "碎片换层时纹理继续随本地坐标缩放")
	await _clear_fixtures()
	source = _source()
	_check(layer_controller.transfer(-1, source), "切割前可以将物体移到后景层")
	await get_tree().create_timer(0.2, true).timeout
	await _cut_and_check(source, "03_after_transfer")
	await _clear_fixtures()
	var layer := Global.get_layer_at_slot(2)
	layer.position = Vector2(70, -30)
	layer.scale = Vector2(0.9, 0.9)
	source = _source()
	await _cut_and_check(source, "04_parent_transform")
	await _clear_fixtures()
	layer.position = Vector2.ZERO
	layer.scale = Vector2.ONE
	_metrics["checks"] = _checks
	_metrics["failures"] = _failures
	var report := FileAccess.open(FRAGMENT_OUTPUT + "report.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(_metrics, "\t"))
	print("SHADOW_FRAGMENT_TEST_RESULT ", JSON.stringify(_metrics))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _source() -> ShadowedGeometry:
	var source := _shape(Global.get_layer_at_slot(2), Vector2(0, 440), true)
	source.collision_box.scale = Vector2(5, 3)
	source.scale = Vector2(1.1, 0.9)
	source.rotation = 0.12
	source.front = true
	source.modulate = Color(0.9, 0.95, 1.0, 0.9)
	var shape := _visual_shape(source)
	shape.texture_scale = Vector2(2.0, 1.5)
	shape.texture_offset = Vector2(11, -7)
	shape.texture_rotation = 0.3
	shape.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var outline := source.get_node("VisualRoot/Outline") as Line2D
	outline.width = 1.75
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.round_precision = 12
	outline.default_color = Color(0.02, 0.04, 0.06, 1)
	_fixtures.append(source)
	return source

func _clear_fixtures() -> void:
	for fixture in _fixtures:
		if is_instance_valid(fixture):
			fixture.queue_free()
	_fixtures.clear()
	await _frames()

func _texture_transform(shape: Polygon2D) -> Transform2D:
	return Transform2D(shape.texture_rotation, shape.texture_offset).scaled(shape.texture_scale)

func _cut_and_check(source: ShadowedGeometry, label: String) -> Array[ShadowedGeometry]:
	await _frames()
	var shape := _visual_shape(source)
	var outline := source.get_node("VisualRoot/Outline") as Line2D
	var physical := source.collision_box.global_transform
	var inverse := physical.affine_inverse()
	var visual := shape.global_transform
	var root := source.global_transform
	var texture_frame := _texture_transform(shape)
	var texture := shape.texture
	var texture_scale := shape.texture_scale
	var texture_rotation := shape.texture_rotation
	var collision_transform := source.collision_box.transform
	var width := outline.width
	var outline_color := outline.default_color
	var owner: DepthLayer = source.owner_layer
	var before_ids: Dictionary = {}
	for child in owner.get_children():
		before_ids[child.get_instance_id()] = true
	var bounds := _controller._polygon_bounds(source.collision_box.polygon)
	var middle: float = bounds.get_center().x
	var gap: float = bounds.size.x * 0.08
	var cut := PackedVector2Array([
		Vector2(middle - gap, bounds.position.y - 50), Vector2(middle + gap, bounds.position.y - 50),
		Vector2(middle + gap, bounds.end.y + 50), Vector2(middle - gap, bounds.end.y + 50),
	])
	var source_polygon := _controller._polygon_to_world(source.collision_box.polygon, physical)
	var pieces := _controller._subtract_shadows(source_polygon, [_controller._polygon_to_world(cut, physical)])
	_check(pieces.size() == 2, label + " 实际布尔运算得到两块碎片")
	var before := _capture(label + "_before")
	_controller._replace_object_with_fragments(source, pieces)
	var fragments: Array[ShadowedGeometry] = []
	for child in owner.get_children():
		if child is ShadowedGeometry and not before_ids.has(child.get_instance_id()):
			fragments.append(child)
			_fixtures.append(child)
	await _frames()
	var after := _capture(label + "_after")
	_check(fragments.size() == pieces.size(), label + " 完整生成全部连通结果")
	var image_error: float = 0.0
	for index in fragments.size():
		var fragment := fragments[index]
		var fragment_shape := _visual_shape(fragment)
		var fragment_line := fragment.get_node("VisualRoot/Outline") as Line2D
		var pick := fragment.get_node("VisualRoot/Area2D/CollisionBox") as CollisionPolygon2D
		var polygon := fragment.collision_box.polygon
		_check(polygon == fragment_shape.polygon and polygon == fragment_line.points and polygon == pick.polygon and polygon == fragment.shadow.polygon, label + " 五份轮廓完全一致")
		_check(fragment_line.closed and is_equal_approx(fragment_line.width, width), label + " 新切口闭合描边，线宽保留")
		_check(fragment_line.default_color == outline_color and fragment_line.joint_mode == Line2D.LINE_JOINT_ROUND and fragment_line.round_precision == 12, label + " 描边样式保留")
		_check(fragment.collision_box.transform.is_equal_approx(collision_transform), label + " 保留碰撞箱缩放")
		_check(fragment.global_transform.x.is_equal_approx(root.x) and fragment.global_transform.y.is_equal_approx(root.y), label + " 保留根节点变换基底")
		_check(fragment.front and fragment.modulate == Color(0.9, 0.95, 1.0, 0.9), label + " 保留前置排序与整体调制")
		_check(fragment_shape.texture == texture and fragment_shape.texture_scale == texture_scale and is_equal_approx(fragment_shape.texture_rotation, texture_rotation), label + " 共享纹理且保留纹理密度与旋转")
		_check(fragment.shadow_box.size() == 1 and fragment.shadow_visual.size() == 1, label + " 原初始化仍生成一对影子")
		var world_piece: PackedVector2Array = pieces[index]
		var geometry_error: float = 0.0
		var uv_error: float = 0.0
		var visual_error: float = 0.0
		var fragment_texture := _texture_transform(fragment_shape)
		for vertex in polygon.size():
			var world_point: Vector2 = world_piece[vertex]
			var old_local: Vector2 = inverse * world_point
			geometry_error = maxf(geometry_error, (fragment.collision_box.global_transform * polygon[vertex]).distance_to(world_point))
			uv_error = maxf(uv_error, (fragment_texture * polygon[vertex]).distance_to(texture_frame * old_local))
			visual_error = maxf(visual_error, (fragment_shape.global_transform * polygon[vertex]).distance_to(visual * old_local))
		_check(geometry_error < 0.001, label + " 碰撞几何保持世界位置")
		_check(uv_error < 0.001, label + " 纹理采样坐标在切割前后连续")
		_check(visual_error < 0.001, label + " 视差后的视觉几何保持位置")
		var center := _controller._polygon_centroid(world_piece)
		_check(fragment.collision_box.global_position.distance_to(center) < 0.001, label + " 碰撞锚点位于新重心")
		var local_center := inverse * center
		for shift in [Vector2.ZERO, Vector2(0, 3), Vector2(0, -3)]:
			var at: Vector2 = visual * (local_center + shift)
			var a := _pixel(before, at)
			var b := _pixel(after, at)
			image_error = maxf(image_error, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
	_metrics[label + "_max_pixel_error"] = image_error
	_check(image_error < 0.025, label + " 实际 GPU 渲染的保留区域没有纹理跳变")
	return fragments
