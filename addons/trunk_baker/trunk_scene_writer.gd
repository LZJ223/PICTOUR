@tool
extends RefCounted

const Baker = preload("res://addons/trunk_baker/trunk_baker.gd")
const Output = preload("res://addons/texture_baker_common/bake_output.gd")
const LAYER_SCRIPT := "res://Component/Object/Layer_Object.gd"


static func capture_source(source: StaticBody2D) -> Dictionary:
	var properties := {}
	# Non-tool LayerObject scripts are placeholders inside the editor; their
	# instance property list need not contain PROPERTY_USAGE_SCRIPT_VARIABLE.
	# Read the declared exported properties from the Script itself.
	var script := source.get_script() as Script
	for property in script.get_script_property_list():
		var usage: int = property.usage
		if usage & PROPERTY_USAGE_EDITOR and usage & PROPERTY_USAGE_STORAGE:
			properties[property.name] = source.get(property.name)
	var area := source.get_node_or_null("VisualRoot/Area2D") as Area2D
	return {
		"properties": properties,
		"collision_layer": source.collision_layer, "collision_mask": source.collision_mask,
		"collision_priority": source.collision_priority,
		"physics_material": source.physics_material_override,
		"pickable": area.input_pickable if area != null else bool(source.get("can_transfer")),
		"pick_layer": area.collision_layer if area != null else 1,
		"source_scene": source.scene_file_path,
		"source_node": str(source.get_path()) if source.is_inside_tree() else str(source.name),
	}


static func reserve_directory(output_directory: String = "", requested_name: String = "") -> Dictionary:
	return Output.reserve_directory(output_directory, requested_name, "res://Generated/Trunk", "Trunk")


## textures must be imported external Texture2D resources; no plugin script
## or bake profile is attached to the generated runtime scene.
static func make_scene(source: Dictionary, prepared: Dictionary, tiles: Array[Dictionary], name: String) -> PackedScene:
	var root := StaticBody2D.new()
	root.name = name
	root.set_script(load(LAYER_SCRIPT))
	for property in source.properties:
		root.set(property, source.properties[property])
	root.collision_layer = source.collision_layer
	root.collision_mask = source.collision_mask
	root.collision_priority = source.collision_priority
	root.physics_material_override = source.physics_material
	var collision := CollisionPolygon2D.new()
	collision.name = "CollisionBox"
	collision.polygon = prepared.root_contour
	_owned_child(root, collision, root)
	var visual := Node2D.new()
	visual.name = "VisualRoot"
	_owned_child(root, visual, root)
	var frame := Node2D.new()
	frame.name = "TrunkTextureFrame"
	frame.transform = prepared.frame
	_owned_child(visual, frame, root)
	for index in range(tiles.size()):
		var tile := tiles[index]
		var sprite := Sprite2D.new()
		sprite.name = "TrunkSprite" if tiles.size() == 1 else "TrunkTile_%03d" % index
		sprite.texture = tile.texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = Rect2(Vector2.ONE * Baker.BLEED_PX, Vector2(tile.core_size))
		sprite.position = prepared.bounds.position + Vector2(tile.origin) / prepared.density
		sprite.scale = Vector2.ONE / prepared.density
		_owned_child(frame, sprite, root)
	var area := Area2D.new()
	area.name = "Area2D"
	area.monitoring = false
	area.monitorable = false
	area.input_pickable = source.pickable
	area.collision_layer = source.pick_layer
	area.collision_mask = 0
	_owned_child(visual, area, root)
	var pick_shape := CollisionPolygon2D.new()
	pick_shape.name = "CollisionShape2D"
	pick_shape.polygon = prepared.root_contour
	_owned_child(area, pick_shape, root)
	var packed := PackedScene.new()
	var error := packed.pack(root)
	root.free()
	return packed if error == OK else null


static func save_result(source: Dictionary, prepared: Dictionary, tiles: Array[Dictionary], output: Dictionary) -> Dictionary:
	var conflict := Output.metadata_conflict(output)
	if not conflict.is_empty():
		return {"error": conflict}
	var packed := make_scene(source, prepared, tiles, output.name)
	if packed == null:
		return {"error": "无法打包树干场景。"}
	var scene_path: String = output.base + ".tscn"
	var profile_path: String = output.base + ".tres"
	var error := ResourceSaver.save(prepared.profile, profile_path)
	if error != OK:
		return {"error": "参数保存失败（错误 %d）。" % error}
	error = ResourceSaver.save(packed, scene_path)
	if error != OK:
		return {"error": "场景保存失败（错误 %d）。" % error}
	var coordinates: Array = []
	for point in prepared.root_contour:
		coordinates.append([point.x, point.y])
	var frame: Transform2D = prepared.frame
	var texture_paths: Array[String] = []
	for tile in tiles:
		texture_paths.append(tile.get("path", ""))
	var recipe := {
		"version": 1, "source_scene": source.source_scene, "source_node": source.source_node,
		"profile": profile_path, "textures": texture_paths,
		"rectangle_size": [prepared.size.x, prepared.size.y],
		"rectangle_frame": [frame.x.x, frame.x.y, frame.y.x, frame.y.y, frame.origin.x, frame.origin.y],
		"material_type": "trunk", "rectangle_polygon_local": coordinates,
		"shadow_divisions_ratio": [1.0 / 3.0, 2.0 / 3.0],
		"shadow_opacities": [prepared.profile.deep_shadow_opacity, prepared.profile.light_shadow_opacity, 0.0],
	}
	var file := FileAccess.open(output.base + ".recipe.json", FileAccess.WRITE)
	if file == null:
		return {"error": "生成记录写入失败（错误 %d）。" % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(recipe, "  ") + "\n")
	file.close()
	return {"error": "", "scene_path": scene_path, "profile_path": profile_path}


static func _owned_child(parent: Node, child: Node, root: Node) -> void:
	parent.add_child(child)
	child.owner = root
