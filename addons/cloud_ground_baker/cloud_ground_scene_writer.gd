@tool
extends RefCounted

const Profile = preload("res://addons/cloud_ground_baker/cloud_ground_profile.gd")
const Output = preload("res://addons/texture_baker_common/bake_output.gd")
const SOURCE_SCRIPT := "res://Component/Shadowed_Geometry/Shadowed_Geometry.gd"


static func is_source(node: Object) -> bool:
	if not node is StaticBody2D:
		return false
	var script := node.get_script() as Script
	while script != null:
		if script.resource_path == SOURCE_SCRIPT:
			return true
		script = script.get_base_script()
	return false


static func inspect_source(source: Node) -> Dictionary:
	if not is_instance_valid(source) or not is_source(source):
		return {"error": "请选择 Shadowed_Ground（StaticBody2D / ShadowedGeometry）。"}
	var collision := source.get_node_or_null("CollisionBox") as CollisionPolygon2D
	var visual := source.get_node_or_null("VisualRoot") as Node2D
	var shape := source.get_node_or_null("VisualRoot/Polygon2D") as Polygon2D
	var shadow := source.get_node_or_null("Shadow") as Polygon2D
	if collision == null or visual == null or shape == null or shadow == null:
		return {"error": "需要 CollisionBox、VisualRoot/Polygon2D 和 Shadow；无需 Area2D。"}
	if not collision.position.is_zero_approx() or not is_zero_approx(collision.rotation) or not is_zero_approx(collision.skew) or not collision.scale.is_finite() or collision.scale.x <= 0.0 or collision.scale.y <= 0.0:
		return {"error": "CollisionBox 的位置、旋转和斜切需为零，缩放为正数。"}
	if not visual.position.is_zero_approx() or not is_zero_approx(visual.rotation) or not is_zero_approx(visual.skew) or (not visual.scale.is_equal_approx(Vector2.ONE) and not visual.scale.is_equal_approx(collision.scale)):
		return {"error": "VisualRoot 需与现有 LayerObject 的 CollisionBox 缩放约定一致。"}
	var dots := visual.get_node_or_null("CloudDots")
	if dots != null and not dots.get_meta(&"cloud_ground_generated", false):
		return {"error": "VisualRoot/CloudDots 已被其他节点占用，请先更名。"}
	var border := visual.get_node_or_null("Outline")
	if border != null and not border is Line2D:
		return {"error": "VisualRoot/Outline 需为 Line2D，或先更名。"}
	var bindings: Array[String] = ["CollisionBox", "VisualRoot/Polygon2D", "Shadow"]
	_collect_bindings(source, source, collision.polygon, bindings)
	if border != null and not bindings.has("VisualRoot/Outline"):
		bindings.append("VisualRoot/Outline")
	for path in bindings:
		var node := source.get_node(NodePath(path)) as Node2D
		if node != collision:
			var frame: Node2D = visual if visual.is_ancestor_of(node) else source as Node2D
			if not _relative_transform(node, frame).is_equal_approx(Transform2D.IDENTITY):
				return {"error": "%s 有额外局部变换，请先对齐轮廓节点。" % path}
		if node is Polygon2D:
			if not node.offset.is_zero_approx() or not node.uv.is_empty() or not node.vertex_colors.is_empty() or not node.polygons.is_empty() or node.internal_vertex_count != 0 or node.get_bone_count() > 0 or node.invert_enabled:
				return {"error": "%s 含偏移、手工 UV/顶点色/三角形、骨骼或反转轮廓，无法直接更换轮廓。" % path}
	return {"error": "", "polygon": collision.polygon.duplicate(), "bindings": bindings}


static func capture_source(source: Node) -> Dictionary:
	var inspected := inspect_source(source)
	if not inspected.error.is_empty():
		return inspected
	var root := source.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	if root == null:
		return {"error": "无法复制 Shadowed_Ground。"}
	root.owner = null
	root.scene_file_path = ""
	_own_children(root, root)
	var snapshot := PackedScene.new()
	var error := snapshot.pack(root)
	root.free()
	if error != OK:
		return {"error": "源节点快照失败（错误 %d）。" % error}
	return {
		"error": "", "scene": snapshot, "bindings": inspected.bindings,
		"source_scene": source.scene_file_path,
		"source_node": str(source.get_path()) if source.is_inside_tree() else str(source.name),
		"root_transform": (source as Node2D).transform,
		"collision_scale": (source.get_node("CollisionBox") as CollisionPolygon2D).scale,
	}


static func reserve_directory(parent: String = "", requested_name: String = "") -> Dictionary:
	return Output.reserve_directory(parent, requested_name, "res://Generated/CloudGround", "CloudGround")


static func build_result(snapshot: Dictionary, prepared: Dictionary, tiles: Array[Dictionary], asset_name: String) -> Dictionary:
	var root := (snapshot.scene as PackedScene).instantiate() as StaticBody2D
	if root == null:
		return {"error": "无法实例化 Shadowed_Ground 快照。"}
	root.name = asset_name
	root.scene_file_path = ""
	root.transform = Transform2D.IDENTITY
	root.set("can_leave_shadow", true)
	root.set("can_be_shadowed", false)
	var profile: Profile = prepared.profile
	var contour: PackedVector2Array = prepared.contour
	var visual := root.get_node("VisualRoot") as Node2D
	var old_dots := visual.get_node_or_null("CloudDots")
	if old_dots != null:
		visual.remove_child(old_dots)
		old_dots.free()
	for path: String in snapshot.bindings:
		var node := root.get_node(NodePath(path))
		if node is Line2D:
			node.points = contour.duplicate()
			node.closed = true
		else:
			node.polygon = contour.duplicate()
	_shift_independent_children(root, root, snapshot.bindings, prepared.center_offset, prepared.center_offset * snapshot.collision_scale)
	# Match physical authoring scale in the editor; LayerObject updates it again
	# from CollisionBox and DepthLayer during play.
	visual.scale = snapshot.collision_scale
	var shape := visual.get_node("Polygon2D") as Polygon2D
	shape.texture = null
	shape.color = profile.base_color
	shape.antialiased = true
	(root.get_node("Shadow") as Polygon2D).visible = false
	var dots := Node2D.new()
	dots.name = "CloudDots"
	dots.set_meta(&"cloud_ground_generated", true)
	visual.add_child(dots)
	visual.move_child(dots, shape.get_index() + 1)
	for index in range(tiles.size()):
		var tile: Dictionary = tiles[index]
		var texture := tile.get("texture") as Texture2D
		if texture == null:
			root.free()
			return {"error": "波点分块 %d 缺少已导入的纹理。" % (index + 1)}
		var sprite := Sprite2D.new()
		sprite.name = "CloudDots_%03d" % (index + 1)
		sprite.centered = false
		sprite.texture = texture
		sprite.region_enabled = true
		sprite.region_rect = Rect2(Vector2(tile.region_offset), Vector2(tile.core_size))
		sprite.region_filter_clip_enabled = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.position = prepared.bounds.position + Vector2(tile.origin) / prepared.density
		sprite.scale = Vector2.ONE / prepared.density
		dots.add_child(sprite)
	var outline := visual.get_node_or_null("Outline") as Line2D
	if outline == null:
		outline = Line2D.new()
		outline.name = "Outline"
		visual.add_child(outline)
	outline.set_meta(&"cloud_ground_generated", true)
	outline.points = prepared.outline_points.duplicate()
	outline.closed = true
	outline.width = profile.outline_width_px / prepared.density
	outline.default_color = profile.outline_color
	outline.antialiased = true
	outline.joint_mode = Line2D.LINE_JOINT_ROUND
	outline.round_precision = 12
	outline.gradient = null
	outline.width_curve = null
	outline.texture = null
	outline.visible = profile.outline_width_px > 0.0
	visual.move_child(outline, -1)
	_own_children(root, root)
	var scene := PackedScene.new()
	var error := scene.pack(root)
	root.free()
	if error != OK:
		return {"error": "CloudGround 场景打包失败（错误 %d）。" % error}
	return {"error": "", "scene": scene}


static func save_result(snapshot: Dictionary, prepared: Dictionary, tiles: Array[Dictionary], output: Dictionary) -> Dictionary:
	var conflict := Output.metadata_conflict(output)
	if not conflict.is_empty():
		return {"error": conflict}
	var built := build_result(snapshot, prepared, tiles, output.name)
	if not built.error.is_empty():
		return built
	var scene_path: String = output.base + ".tscn"
	var profile_path: String = output.base + ".tres"
	var error := ResourceSaver.save(prepared.profile, profile_path)
	if error != OK:
		return {"error": "参数保存失败（错误 %d）。" % error}
	error = ResourceSaver.save(built.scene, scene_path)
	if error != OK:
		return {"error": "场景保存失败（错误 %d）。" % error}
	var paths: Array[String] = []
	for tile in tiles:
		paths.append(tile.path)
	var placement: Transform2D = snapshot.root_transform * Transform2D(0.0, prepared.center_offset * snapshot.collision_scale)
	var recipe := {
		"version": 1, "source_scene": snapshot.source_scene, "source_node": snapshot.source_node,
		"source_polygon": _coordinates(prepared.source_polygon), "rounded_polygon": _coordinates(prepared.contour),
		"center_offset_local": [prepared.center_offset.x, prepared.center_offset.y],
		"root_transform_cleared": true, "suggested_placement_transform": _transform_values(placement),
		"profile": profile_path, "textures": paths, "radius_scale": prepared.radius_scale,
		"can_leave_shadow": true, "can_be_shadowed": false, "warnings": prepared.warnings,
	}
	var file := FileAccess.open(output.base + ".recipe.json", FileAccess.WRITE)
	if file == null:
		return {"error": "生成记录打开失败（错误 %d）。" % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(recipe, "  ") + "\n")
	error = file.get_error()
	file.close()
	if error != OK:
		return {"error": "生成记录写入失败（错误 %d）。" % error}
	return {"error": "", "scene_path": scene_path, "profile_path": profile_path}


static func _collect_bindings(parent: Node, root: Node, polygon: PackedVector2Array, bindings: Array[String]) -> void:
	for child in parent.get_children():
		if child.name == &"CloudDots" or child.get_meta(&"selection_outline_visual", false):
			continue
		var path := str(root.get_path_to(child))
		if not bindings.has(path) and (child is Polygon2D or child is CollisionPolygon2D):
			if _same_contour(child.polygon, polygon):
				bindings.append(path)
		_collect_bindings(child, root, polygon, bindings)


static func _same_contour(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size() or a.is_empty():
		return false
	for start in range(b.size()):
		for direction in [-1, 1]:
			var matches := true
			for index in range(a.size()):
				if not a[index].is_equal_approx(b[posmod(start + index * direction, b.size())]):
					matches = false
					break
			if matches:
				return true
	return false


static func _shift_independent_children(parent: Node, root: Node, bindings: Array[String], offset: Vector2, physical_offset: Vector2) -> void:
	var visual := root.get_node("VisualRoot") as Node2D
	for child in parent.get_children():
		var path := str(root.get_path_to(child))
		var structural := false
		for binding in bindings:
			if binding == path or binding.begins_with(path + "/"):
				structural = true
				break
		if child is Node2D and not structural:
			var frame: Node2D = visual if visual.is_ancestor_of(child) else root as Node2D
			var shift := offset if frame == visual else physical_offset
			child.position -= _relative_transform(parent, frame).affine_inverse().basis_xform(shift)
		else:
			_shift_independent_children(child, root, bindings, offset, physical_offset)


static func _relative_transform(node: Node, ancestor: Node) -> Transform2D:
	var result := Transform2D.IDENTITY
	var current := node
	while current != null and current != ancestor:
		if current is Node2D:
			result = current.transform * result
		current = current.get_parent()
	return result


static func _own_children(parent: Node, root: Node) -> void:
	for child in parent.get_children():
		child.owner = root
		_own_children(child, root)


static func _coordinates(points: PackedVector2Array) -> Array:
	var values: Array = []
	for point in points:
		values.append([point.x, point.y])
	return values


static func _transform_values(value: Transform2D) -> Array:
	return [value.x.x, value.x.y, value.y.x, value.y.y, value.origin.x, value.origin.y]
