@tool
extends RefCounted

const Adapter = preload("res://addons/cloud_box_rounder/cloud_node_adapter.gd")
const Geometry = preload("res://addons/cloud_box_rounder/cloud_round_geometry.gd")
const Output = preload("res://addons/texture_baker_common/bake_output.gd")
const Profile = preload("res://addons/cloud_box_rounder/cloud_round_profile.gd")


static func reserve_directory(parent: String = "", requested_name: String = "") -> Dictionary:
	return Output.reserve_directory(parent, requested_name, "res://Generated/CloudBox", "CloudBox")


static func build_result(source: Node, polygon: PackedVector2Array, bindings: Array[Dictionary], name: String) -> Dictionary:
	var centered := Geometry.center_polygon(polygon)
	if not centered.error.is_empty():
		return centered
	# Copy the live editor node, including overrides, rather than re-instantiating
	# its scene file. Do not use DUPLICATE_USE_INSTANTIATION: save a full tree.
	var root := source.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS)
	if root == null:
		return {"error": "无法复制 ShadowedGeometry。"}
	root.name = name
	# Asset placement comes from its eventual level instance. Do not carry the
	# selected editor instance's position, rotation, scale or skew into the asset.
	(root as Node2D).transform = Transform2D.IDENTITY
	root.owner = null
	root.scene_file_path = ""
	_own_children(root, root)
	var offset: Vector2 = centered.center_offset
	Adapter.apply_polygon(root, centered.polygon, bindings)
	for binding in bindings:
		var node := root.get_node(NodePath(binding.path))
		if node is Polygon2D:
			# Polygon2D rotates local coordinates before the texture scale/offset
			# transform. Preserve the existing pattern phase after moving vertices.
			node.texture_offset += offset.rotated(node.texture_rotation)
	var physical_offset: Vector2 = offset * (root.get_node("CollisionBox") as CollisionPolygon2D).scale
	_shift_independent_children(root, root, bindings, offset, physical_offset)
	if root is RigidBody2D and root.center_of_mass_mode == RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM:
		root.center_of_mass -= physical_offset
	var scene := PackedScene.new()
	var error := scene.pack(root)
	root.free()
	if error != OK:
		return {"error": "无法打包 CloudBox 场景（错误 %d）。" % error}
	return {"error": "", "scene": scene, "polygon": centered.polygon, "center_offset": offset}


static func save_result(source: Node, rounded: Dictionary, bindings: Array[Dictionary], profile: Profile, output: Dictionary) -> Dictionary:
	var conflict := Output.metadata_conflict(output)
	if not conflict.is_empty():
		return {"error": conflict}
	var built := build_result(source, rounded.polygon, bindings, output.name)
	if not built.error.is_empty():
		return built
	var scene_path: String = output.base + ".tscn"
	var profile_path: String = output.base + ".tres"
	var error := ResourceSaver.save(profile.duplicate(true), profile_path)
	if error != OK:
		return {"error": "圆角参数保存失败（错误 %d）。" % error}
	error = ResourceSaver.save(built.scene, scene_path)
	if error != OK:
		return {"error": "CloudBox 场景保存失败（错误 %d）。" % error}
	var corners: Array[Dictionary] = []
	for corner in rounded.corners:
		corners.append({
			"vertex": [corner.vertex.x, corner.vertex.y], "is_outer": corner.is_outer,
			"requested_radius": corner.requested_radius, "effective_radius": corner.effective_radius,
		})
	var recipe := {
		"version": 2, "source_scene": source.scene_file_path,
		"source_node": str(source.get_path()) if source.is_inside_tree() else str(source.name),
		"profile": profile_path, "source_polygon": _coordinates(source.get_node("CollisionBox").polygon),
		"rounded_polygon": _coordinates(built.polygon),
		"rounded_polygon_before_centering": _coordinates(rounded.polygon),
		"center_offset_local": [built.center_offset.x, built.center_offset.y],
		"root_transform_cleared": true,
		"corners": corners, "corners_coordinate_space": "source_collision_local",
		"radius_scale": rounded.radius_scale, "bindings": bindings, "warnings": rounded.warnings,
	}
	var file := FileAccess.open(output.base + ".recipe.json", FileAccess.WRITE)
	if file == null:
		return {"error": "生成记录保存失败（错误 %d）。" % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(recipe, "  ") + "\n")
	error = file.get_error()
	file.close()
	if error != OK:
		return {"error": "生成记录写入失败（错误 %d）。" % error}
	return {"error": "", "scene_path": scene_path, "profile_path": profile_path}


## Keep independent decorations in place relative to the recentered silhouette.
## Move each independent branch once; shared contour nodes already moved through
## their vertices. Structural parents of bound nodes retain their transforms.
static func _shift_independent_children(parent: Node, root: Node, bindings: Array[Dictionary], offset: Vector2, physical_offset: Vector2) -> void:
	var visual := root.get_node("VisualRoot") as Node2D
	for child in parent.get_children():
		var path := str(root.get_path_to(child))
		var structural := false
		for binding in bindings:
			if binding.path == path or binding.path.begins_with(path + "/"):
				structural = true
				break
		if child is Node2D and not structural:
			var frame: Node2D = visual if visual.is_ancestor_of(child) else root as Node2D
			var shift := offset if frame == visual else physical_offset
			var parent_transform := _relative_transform(parent, frame)
			child.position -= parent_transform.affine_inverse().basis_xform(shift)
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
	var coordinates: Array = []
	for point in points:
		coordinates.append([point.x, point.y])
	return coordinates
