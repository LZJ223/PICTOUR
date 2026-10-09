@tool
extends RefCounted
## 只读取编辑场景，不运行游戏System/Global；修改由EditorUndoRedoManager承载。

static func has_property(object: Object, property: StringName) -> bool:
	for info in object.get_property_list():
		if info.name == property:
			return true
	return false


static func layers_in(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	if root == null:
		return result
	if has_property(root, &"layer_id") and has_property(root, &"slot"):
		result.append(root)
	for child in root.get_children():
		result.append_array(layers_in(child))
	return result


static func is_object(node: Node) -> bool:
	return is_instance_valid(node) and node is Node2D and node.has_node("CollisionBox") and node.has_node("VisualRoot") and has_property(node, &"can_transfer")


static func _script_is(node: Node, name: StringName) -> bool:
	var script: Script = node.get_script()
	while script != null:
		if script.get_global_name() == name: return true
		script = script.get_base_script()
	return false


static func editable(root: Node, node: Node) -> bool:
	return is_instance_valid(root) and is_instance_valid(node) and node != root and node.owner == root and root.is_ancestor_of(node)


static func flat_parent(root: Node, layer: Node) -> bool:
	if not editable(root, layer):
		return false
	var current: Node = layer
	while current != null:
		if current is Node2D and not current.transform.is_equal_approx(Transform2D.IDENTITY):
			return false
		if current == root:
			return true
		current = current.get_parent()
	return false


static func level_for(root: Node) -> Node:
	var layers := layers_in(root)
	return layers[0].get_parent() if not layers.is_empty() else root


static func identity_repairs(root: Node) -> Array[Dictionary]:
	var objects: Array[Node] = []
	var reserved := {}
	for layer in layers_in(root):
		for child in layer.get_children():
			if is_object(child):
				objects.append(child)
				var old := str(child.get_meta("persistent_id", ""))
				if not old.strip_edges().is_empty(): reserved[old] = true
	var seen := {}
	var result: Array[Dictionary] = []
	for object in objects:
		var old := str(object.get_meta("persistent_id", ""))
		if not old.strip_edges().is_empty() and not seen.has(old):
			seen[old] = true
			continue
		var stem := "editor_%d_%d" % [Time.get_ticks_usec(), object.get_instance_id()]
		var fresh := stem
		var suffix := 0
		while reserved.has(fresh):
			suffix += 1
			fresh = stem + "_%d" % suffix
		reserved[fresh] = true
		seen[fresh] = true
		result.append({"object": object, "had_id": object.has_meta("persistent_id"), "old": object.get_meta("persistent_id") if object.has_meta("persistent_id") else null, "new": fresh})
	return result


static func instantiate_asset(entry: Dictionary) -> Node2D:
	var packed := load(str(entry.scene)) as PackedScene
	if packed == null:
		return null
	var object := packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node2D
	if object == null or not is_object(object):
		if object != null: object.free()
		return null
	if not str(entry.get("piece", "")).is_empty():
		object.set("piece", load(str(entry.piece)))
	object.name = str(entry.get("name", "景物")).validate_node_name()
	object.set_meta("persistent_id", "editor_%d_%d" % [Time.get_ticks_usec(), object.get_instance_id()])
	return object


static func polygons(body: Node) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for child in body.get_children():
		if not (child is CollisionPolygon2D or child is CollisionShape2D) or child.disabled:
			continue
		var points := PackedVector2Array()
		if child is CollisionPolygon2D:
			points = child.polygon
		elif child.shape is ConvexPolygonShape2D:
			points = child.shape.points
		elif child.shape is RectangleShape2D:
			var rect: Rect2 = child.shape.get_rect()
			points = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)])
		elif child.shape is CapsuleShape2D:
			var radius: float = child.shape.radius
			var straight: float = child.shape.height * 0.5 - radius
			for index in 17:
				var angle := PI + index * PI / 16.0
				points.append(Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -straight))
			for index in 17:
				var angle := index * PI / 16.0
				points.append(Vector2(cos(angle), sin(angle)) * radius + Vector2(0, straight))
		if points.size() >= 3:
			result.append(child.global_transform * points)
	return result


static func bodies_under(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	if root is PhysicsBody2D:
		result.append(root)
	for child in root.get_children():
		if not child is Area2D:
			result.append_array(bodies_under(child))
	return result


static func walkable_edges(body: Node) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var source := body
	if not source.has_method("get_editor_geometry") and source.get_parent() != null and source.get_parent().has_method("get_editor_geometry"):
		source = source.get_parent()
	if source.has_method("get_editor_geometry"):
		for edge in source.get_editor_geometry().get("walkable", []):
			result.append(source.global_transform * edge)
		return result
	if body.has_method("get_footholds"):
		for edge in body.get_footholds():
			result.append(body.global_transform * edge)
		return result
	# 只标实际实体的朝上边；不添加任何平台或包围盒底面。
	for polygon in polygons(body):
		var clockwise := Geometry2D.is_polygon_clockwise(polygon)
		for index in polygon.size():
			var a := polygon[index]
			var b := polygon[(index + 1) % polygon.size()]
			var edge := b - a
			var normal := Vector2(edge.y, -edge.x).normalized()
			if clockwise: normal = -normal
			if normal.dot(Vector2.UP) > 0.707 and edge.length() > 2:
				result.append(PackedVector2Array([a, b]))
	return result


static func _tolerant(points: PackedVector2Array) -> PackedVector2Array:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points: bounds = bounds.expand(point)
	var scale := Vector2(maxf(0.01, 1.0 - 1.0 / maxf(bounds.size.x, 1)), maxf(0.01, 1.0 - 1.0 / maxf(bounds.size.y, 1)))
	var result := PackedVector2Array()
	for point in points: result.append(bounds.get_center() + (point - bounds.get_center()) * scale)
	return result


static func transfer_preview(root: Node, object: Node2D, target: Node, anchor: Vector2) -> Dictionary:
	var result := {"valid": false, "reason": "请选择本场景直属景物与目标景别。", "outlines": [], "contacts": [], "target_position": Vector2.ZERO}
	if not is_object(object) or not is_instance_valid(target) or target == object.get_parent():
		return result
	var source := object.get_parent()
	if not has_property(source, &"slot") or not has_property(target, &"slot"):
		return result
	if not bool(object.get("can_transfer")):
		result.reason = "这个物件未启用换层。"
		return result
	var level := source.get_parent()
	var layer_scale: float = float(level.get("layer_scale")) if has_property(level, &"layer_scale") else 0.8
	var current_slot: int = int(level.get("current_layer_index")) if has_property(level, &"current_layer_index") else 0
	var ratio := pow(layer_scale, int(source.get("slot")) - int(target.get("slot")))
	result.target_position = anchor + (object.global_position - anchor) * ratio
	for polygon in polygons(object):
		var next := PackedVector2Array()
		for point in polygon: next.append(anchor + (point - anchor) * ratio)
		result.outlines.append(next)
	var blockers := bodies_under(target)
	if int(target.get("slot")) == current_slot:
		for body in bodies_under(root):
			if body is CharacterBody2D and not blockers.has(body): blockers.append(body)
	var allow_overlap := has_property(level, &"allow_scenery_overlap_outside_player_layer") and bool(level.get("allow_scenery_overlap_outside_player_layer")) and int(target.get("slot")) != current_slot and _script_is(object, &"NaturalObject")
	var blocked_names := PackedStringArray()
	for body in blockers:
		if body == object or (allow_overlap and _script_is(body, &"NaturalObject")):
			continue
		for target_polygon in polygons(body):
			for moving_polygon in result.outlines:
				for convex in Geometry2D.decompose_polygon_in_convex(moving_polygon):
					var intersections := Geometry2D.intersect_polygons(_tolerant(convex), target_polygon)
					for overlap in intersections:
						if overlap.size() < 3: continue
						result.contacts.append(overlap)
						if not blocked_names.has(str(body.name)): blocked_names.append(str(body.name))
	result.valid = blocked_names.is_empty()
	result.reason = "该观察点的静态轮廓无占用冲突。" if result.valid else "目标实体重叠：" + "、".join(blocked_names)
	return result
