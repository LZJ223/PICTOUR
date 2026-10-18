@tool
extends RefCounted

const SOURCE_SCRIPT := "res://Component/Shadowed_Geometry/Shadowed_Geometry.gd"
const EPSILON := 0.0001


static func is_source(node: Object) -> bool:
	if not node is PhysicsBody2D:
		return false
	var script := node.get_script() as Script
	while script != null:
		if script.resource_path == SOURCE_SCRIPT:
			return true
		script = script.get_base_script()
	return false


static func inspect_source(source: Node) -> Dictionary:
	if not is_instance_valid(source) or not is_source(source):
		return {"error": "请选择使用 Shadowed_Geometry.gd 的 ShadowedGeometry 节点。"}
	var collision := source.get_node_or_null("CollisionBox") as CollisionPolygon2D
	var visual := source.get_node_or_null("VisualRoot") as Node2D
	if collision == null or visual == null:
		return {"error": "源节点缺少 CollisionBox 或 VisualRoot。"}
	var bindings: Array[Dictionary] = []
	for path in ["CollisionBox", "VisualRoot/Shape", "VisualRoot/Area2D/CollisionBox", "Shadow"]:
		var node := source.get_node_or_null(NodePath(path))
		var expected_collision: bool = path.ends_with("CollisionBox")
		if (expected_collision and not node is CollisionPolygon2D) or (not expected_collision and not node is Polygon2D):
			return {"error": "源节点缺少正确类型的 %s。" % path}
		bindings.append(_binding(node, path))
	_collect_extra(source, "", collision.polygon, bindings)
	# LayerObject copies CollisionBox.scale onto VisualRoot during play.
	# Keep that collision scale; radii are measured before scaling. The writer
	# recenters the polygon and clears root placement when exporting the asset.
	if not collision.position.is_zero_approx() or not is_zero_approx(collision.rotation) or not is_zero_approx(collision.skew) or collision.scale.x <= 0.0 or collision.scale.y <= 0.0:
		return {"error": "CollisionBox 需保持位置、旋转与斜切为零，缩放为正数；符合现有 LayerObject 的变换约定。"}
	if not visual.position.is_zero_approx() or not is_zero_approx(visual.rotation) or not is_zero_approx(visual.skew) or (not visual.scale.is_equal_approx(Vector2.ONE) and not visual.scale.is_equal_approx(collision.scale)):
		return {"error": "VisualRoot 的变换与现有 LayerObject 的 CollisionBox 缩放约定不一致。"}
	for binding in bindings:
		var node := source.get_node(NodePath(binding.path)) as Node2D
		if node != collision:
			var reference := visual if visual.is_ancestor_of(node) else source as Node2D
			if not _relative_transform(node, reference).is_equal_approx(Transform2D.IDENTITY):
				return {"error": "%s 有额外局部变换，无法直接同步同一份多边形，请先对齐轮廓节点。" % binding.path}
		if node is Polygon2D:
			if not node.offset.is_zero_approx():
				return {"error": "%s 的 Polygon2D.offset 需为零。" % binding.path}
			if not node.uv.is_empty() or not node.vertex_colors.is_empty() or not node.polygons.is_empty() or node.internal_vertex_count != 0 or node.get_bone_count() > 0:
				return {"error": "%s 含手工 UV、顶点色、骨骼或手工三角形数据，需先改为自动多边形映射才能无损更换顶点。贴图缩放和材质可正常保留。" % binding.path}
	return {"error": "", "polygon": collision.polygon.duplicate(), "bindings": bindings}


static func apply_polygon(root: Node, polygon: PackedVector2Array, bindings: Array[Dictionary]) -> void:
	for binding in bindings:
		var node := root.get_node(NodePath(binding.path))
		if node is Line2D:
			var points := polygon.duplicate()
			if not node.closed:
				points.append(points[0])
			node.points = points
		else:
			node.polygon = polygon.duplicate()


static func _binding(node: Node, path: String) -> Dictionary:
	return {"path": path, "property": "points" if node is Line2D else "polygon"}


static func _collect_extra(root: Node, prefix: String, polygon: PackedVector2Array, bindings: Array[Dictionary]) -> void:
	for child in root.get_children():
		var path := str(child.name) if prefix.is_empty() else prefix.path_join(str(child.name))
		var already_bound := false
		for binding in bindings:
			if binding.path == path:
				already_bound = true
		var supports_polygon: bool = child is Polygon2D or child is CollisionPolygon2D or child is Line2D
		if supports_polygon and not already_bound:
			var points: PackedVector2Array = child.points if child is Line2D else child.polygon
			if str(child.name).begins_with("Outline") or _same_contour(points, polygon):
				bindings.append(_binding(child, path))
		_collect_extra(child, path, polygon, bindings)


static func _relative_transform(node: Node2D, ancestor: Node2D) -> Transform2D:
	var result := Transform2D.IDENTITY
	var current: Node = node
	while current != ancestor and current != null:
		if current is Node2D:
			result = current.transform * result
		current = current.get_parent()
	return result


static func _same_contour(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	var points := a.duplicate()
	if points.size() > 1 and points[0].distance_to(points[-1]) < EPSILON:
		points.remove_at(points.size() - 1)
	if points.size() != b.size() or points.is_empty():
		return false
	for start in range(b.size()):
		if points[0].distance_to(b[start]) >= EPSILON:
			continue
		for direction in [-1, 1]:
			var matches := true
			for index in range(points.size()):
				if points[index].distance_to(b[posmod(start + direction * index, b.size())]) >= EPSILON:
					matches = false
					break
			if matches:
				return true
	return false
