extends Node

const Profile = preload("res://addons/cloud_box_rounder/cloud_round_profile.gd")
const Geometry = preload("res://addons/cloud_box_rounder/cloud_round_geometry.gd")
const Adapter = preload("res://addons/cloud_box_rounder/cloud_node_adapter.gd")
const Writer = preload("res://addons/cloud_box_rounder/cloud_scene_writer.gd")
const TEMPLATE := "res://Component/Shadowed_Geometry/Shadowed_Geometry.tscn"
const TEST_DIRECTORY := "res://.godot/cloud_rounder_tests"
var _failures := 0
var _checks := 0
var _saved_scene: PackedScene


func _ready() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("CLOUD_ROUNDER: " + message)


func _run() -> void:
	# SceneTransition pauses stand-alone scenes on startup. These tests must
	# explicitly simulate physics, including free fall and landing.
	get_tree().paused = false
	PhysicsServer2D.set_active(true)
	_test_geometry()
	_test_centering()
	_test_validation()
	_test_scene()
	_test_custom_center()
	if _saved_scene != null:
		await _test_runtime()
	print("CLOUD_ROUNDER_TEST_RESULT checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _rectangle(width: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(width, 0), Vector2(width, height), Vector2(0, height)])


func _test_geometry() -> void:
	var points := PackedVector2Array([Vector2.ZERO, Vector2(200, 0), Vector2(200, 80), Vector2(80, 80), Vector2(80, 200), Vector2(0, 200)])
	var profile := Profile.new()
	profile.outer_radius = 24.0
	profile.inner_radius = 6.0
	var reference := Geometry.round_polygon(points, profile)
	_check(reference.error.is_empty(), "Concave polygon could not be rounded")
	if not reference.error.is_empty():
		return
	var inner_count := 0
	for corner in reference.corners:
		var expected := 24.0 if corner.is_outer else 6.0
		_check(is_equal_approx(corner.effective_radius, expected), "Convex/reflex radius is incorrect")
		if not corner.is_outer:
			inner_count += 1
			_check(corner.vertex.is_equal_approx(Vector2(80, 80)), "Reflex corner misidentified")
	_check(inner_count == 1, "Expected exactly one reflex corner")
	for offset in range(points.size()):
		for reverse in [false, true]:
			var variant := PackedVector2Array()
			for index in range(points.size()):
				variant.append(points[posmod(offset + (-index if reverse else index), points.size())])
			var result := Geometry.round_polygon(variant, profile)
			_check(result.error.is_empty(), "Winding/start vertex changed validity")
			if not result.error.is_empty():
				continue
			_check(absf(absf(Geometry.signed_area(result.polygon)) - absf(Geometry.signed_area(reference.polygon))) < 0.1, "Winding changed rounded geometry")
			for point in reference.polygon:
				var found := false
				for other in result.polygon:
					if point.distance_to(other) < 0.001:
						found = true
				_check(found, "Reversed winding changed arc sampling")
	var repeated := Geometry.round_polygon(points, profile)
	_check(reference.polygon == repeated.polygon, "Rounding is not deterministic")
	var rectangle := Geometry.round_polygon(_rectangle(200, 120), profile)
	var arc: Array[Vector2] = []
	for point in rectangle.polygon:
		if point.x <= 24.001 and point.y <= 24.001:
			arc.append(point)
			_check(absf(point.distance_to(Vector2(24, 24)) - 24.0) < 0.001, "Outer corner is not circular")
	_check(arc.size() >= 4, "Arc sampling is too coarse")
	for index in range(arc.size() - 1):
		var error := 24.0 - ((arc[index] + arc[index + 1]) * 0.5).distance_to(Vector2(24, 24))
		_check(error <= profile.max_chord_error + 0.001, "Chord error exceeds configured quality")
	var limited := Geometry.round_polygon(_rectangle(40, 40), Profile.new())
	_check(limited.error.is_empty() and not limited.warnings.is_empty(), "Short edges did not reduce radius")
	for corner in limited.corners:
		_check(corner.effective_radius <= 19.6001, "Adjacent arcs overlap on short edges")
	var with_duplicates := _rectangle(200, 120)
	with_duplicates.append(with_duplicates[0])
	with_duplicates.insert(1, with_duplicates[0])
	var cleaned := Geometry.round_polygon(with_duplicates, profile)
	_check(cleaned.error.is_empty() and cleaned.polygon == rectangle.polygon, "Repeated closing/adjacent points were not cleaned")
	var acute := Geometry.round_polygon(PackedVector2Array([Vector2.ZERO, Vector2(400, 0), Vector2(10, 5)]), profile)
	_check(acute.error.is_empty(), "Acute triangle could not be safely rounded")


func _test_centering() -> void:
	var triangle := PackedVector2Array([Vector2.ZERO, Vector2(90, 0), Vector2(0, 60)])
	_check(Geometry.area_centroid(triangle).is_equal_approx(Vector2(30, 20)), "Center is not the area centroid")
	triangle.reverse()
	_check(Geometry.area_centroid(triangle).is_equal_approx(Vector2(30, 20)), "Centroid depends on winding")
	var shifted := PackedVector2Array()
	for point in triangle:
		shifted.append(point + Vector2(10000, -20000))
	var centered := Geometry.center_polygon(shifted)
	_check(centered.error.is_empty() and Geometry.area_centroid(centered.polygon).length() < 0.001, "Translated polygon was not centered")
	_check(not Geometry.center_polygon(PackedVector2Array()).error.is_empty(), "Empty centering input was accepted")
	var concave := PackedVector2Array([Vector2.ZERO, Vector2(200, 0), Vector2(200, 80), Vector2(80, 80), Vector2(80, 200), Vector2(0, 200)])
	var rounded := Geometry.round_polygon(concave, Profile.new())
	centered = Geometry.center_polygon(rounded.polygon)
	_check(centered.error.is_empty() and Geometry.area_centroid(centered.polygon).length() < 0.001, "Rounded concave area centroid is not zero")


func _test_validation() -> void:
	for points in [
		PackedVector2Array([Vector2.ZERO, Vector2.ONE]),
		PackedVector2Array([Vector2.ZERO, Vector2(100, 100), Vector2(0, 100), Vector2(100, 0)]),
		PackedVector2Array([Vector2.ZERO, Vector2(20, 0), Vector2(40, 0)]),
		PackedVector2Array([Vector2.ZERO, Vector2(100, 0), Vector2(NAN, 50), Vector2(0, 100)]),
	]:
		_check(not Geometry.round_polygon(points, Profile.new()).error.is_empty(), "Invalid polygon was accepted")
	var profile := Profile.new()
	profile.inner_radius = 100.0
	_check(not Geometry.round_polygon(_rectangle(200, 120), profile).error.is_empty(), "Inner radius larger than outer was accepted")
	profile = Profile.new()
	profile.max_vertices = 16
	profile.max_chord_error = 0.01
	_check(not Geometry.round_polygon(_rectangle(200, 120), profile).error.is_empty(), "Vertex budget was ignored")
	var source := (load(TEMPLATE) as PackedScene).instantiate()
	var inspected := Adapter.inspect_source(source)
	_check(inspected.error.is_empty() and inspected.bindings.size() == 5, "Current template outline bindings are incorrect")
	source.get_node("VisualRoot/Shape").position = Vector2(1, 0)
	_check(not Adapter.inspect_source(source).error.is_empty(), "Misaligned contour was silently accepted")
	source.get_node("VisualRoot/Shape").position = Vector2.ZERO
	source.get_node("VisualRoot/Shape").uv = _rectangle(64, 64)
	_check(not Adapter.inspect_source(source).error.is_empty(), "Manual UV data would be silently corrupted")
	source.free()


func _test_scene() -> void:
	var original_hash := FileAccess.get_sha256(TEMPLATE)
	var source := (load(TEMPLATE) as PackedScene).instantiate() as RigidBody2D
	var shape := source.get_node("VisualRoot/Shape") as Polygon2D
	print("CLOUD_TEMPLATE_TEXTURE_SCALE ", shape.texture_scale)
	# Simulate live editor overrides that differ from the saved template.
	shape.texture_scale = Vector2(3.25, 1.75)
	shape.texture_offset = Vector2(5, -7)
	shape.texture_rotation = 0.13
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform float multiplier = 1.0; void fragment() { COLOR.rgb *= multiplier; }"
	var material := ShaderMaterial.new()
	material.shader = shader
	material.resource_local_to_scene = true
	material.set_shader_parameter("multiplier", 0.73)
	shape.material = material
	source.position = Vector2(17, 31)
	source.rotation = 0.37
	source.scale = Vector2(1.2, 0.8)
	source.skew = 0.11
	source.mass = 3.25
	source.gravity_scale = 0.0
	source.freeze = true
	source.set("front", true)
	source.set("can_transfer", true)
	source.set("outward_peak_scale", 1.17)
	source.add_to_group("cloud_rounder_fixture", true)
	var input_bindings := Adapter.inspect_source(source)
	var shifted: PackedVector2Array = source.get_node("CollisionBox").polygon.duplicate()
	for index in range(shifted.size()):
		shifted[index] += Vector2(32, -28)
	Adapter.apply_polygon(source, shifted, input_bindings.bindings)
	source.get_node("CollisionBox").scale = Vector2(1.5, 0.8)
	var source_transform := source.transform
	var original_points: PackedVector2Array = source.get_node("CollisionBox").polygon.duplicate()
	var extra := Polygon2D.new()
	extra.name = "ExtraContour"
	extra.polygon = original_points.duplicate()
	source.get_node("VisualRoot").add_child(extra)
	var decoration := Polygon2D.new()
	decoration.name = "Decoration"
	decoration.polygon = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)])
	source.get_node("VisualRoot").add_child(decoration)
	var inspected := Adapter.inspect_source(source)
	_check(inspected.error.is_empty() and inspected.bindings.size() == 6, "Shared extra polygon was not bound")
	var profile := Profile.new()
	var rounded := Geometry.round_polygon(inspected.polygon, profile)
	var centered := Geometry.center_polygon(rounded.polygon)
	var center_offset: Vector2 = centered.center_offset
	var output := Writer.reserve_directory(TEST_DIRECTORY)
	_check(output.error.is_empty() and output.name.begins_with("CloudBox_"), "Default output reservation failed")
	var saved := Writer.save_result(source, rounded, inspected.bindings, profile, output)
	_check(saved.error.is_empty(), "Scene export failed: " + saved.error)
	if not saved.error.is_empty():
		source.free()
		return
	_saved_scene = ResourceLoader.load(saved.scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var instance := _saved_scene.instantiate() as RigidBody2D
	_check(instance != null and instance.get_script() == source.get_script(), "Root type/script changed")
	_check(instance.transform.is_equal_approx(Transform2D.IDENTITY), "Source root placement/rotation/scale/skew leaked into asset")
	_check(is_equal_approx(instance.mass, 3.25) and instance.freeze, "Physics settings were lost")
	_check(instance.get_node("CollisionBox").scale == Vector2(1.5, 0.8), "Collision scale was changed")
	_check(instance.get("front") and instance.get("can_transfer") and is_equal_approx(instance.get("outward_peak_scale"), 1.17), "Exported script overrides were lost")
	_check(instance.is_in_group("cloud_rounder_fixture"), "Persistent group was lost")
	for binding in inspected.bindings:
		var node := instance.get_node(NodePath(binding.path))
		var points: PackedVector2Array = node.points if node is Line2D else node.polygon
		_check(points == centered.polygon, "Centered polygon differs at " + binding.path)
	_check(Geometry.area_centroid(instance.get_node("CollisionBox").polygon).length() < 0.001, "Exported collision centroid is not zero")
	var restored_shape := instance.get_node("VisualRoot/Shape") as Polygon2D
	_check(restored_shape.texture_scale == shape.texture_scale and is_equal_approx(restored_shape.texture_rotation, shape.texture_rotation), "Live texture scale/rotation overrides were lost")
	_check(restored_shape.texture_offset.is_equal_approx(shape.texture_offset + center_offset.rotated(shape.texture_rotation)), "Texture phase was not compensated for centering")
	_check(restored_shape.texture.resource_path == shape.texture.resource_path and restored_shape.texture_repeat == shape.texture_repeat and restored_shape.color == shape.color, "Existing texture/color/repeat settings were lost")
	_check(restored_shape.material is ShaderMaterial and is_equal_approx(restored_shape.material.get_shader_parameter("multiplier"), 0.73), "Material parameter was lost")
	_check(restored_shape.material.resource_local_to_scene, "Material scene-local setting was lost")
	var outline := instance.get_node("VisualRoot/Outline") as Line2D
	_check(outline.closed and is_equal_approx(outline.width, 1.0), "Existing outline settings changed")
	_check(instance.get_node("VisualRoot/Decoration").polygon == decoration.polygon, "Independent decoration was modified")
	_check(instance.get_node("VisualRoot/Decoration").position.is_equal_approx(-center_offset), "Decoration no longer aligns with the centered silhouette")
	_check(not instance.get_node("Shadow").visible, "Shadow mother visibility was changed")
	_check(source.get_node("CollisionBox").polygon == original_points and shape.texture_scale == Vector2(3.25, 1.75), "Source node was mutated")
	_check(source.transform.is_equal_approx(source_transform), "Source root transform was cleared in place")
	_check(FileAccess.get_sha256(TEMPLATE) == original_hash, "Source scene file was changed")
	var scene_hash := FileAccess.get_sha256(saved.scene_path)
	_check(not Writer.save_result(source, rounded, inspected.bindings, profile, output).error.is_empty(), "Existing output was overwritten")
	_check(FileAccess.get_sha256(saved.scene_path) == scene_hash, "Scene changed after refused output")
	_check(not Writer.reserve_directory(TEST_DIRECTORY, output.name).error.is_empty(), "Explicit folder conflict was accepted")
	for file in DirAccess.get_files_at(output.directory):
		_check(not file.ends_with(".png"), "Geometry plugin generated a texture")
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output.base + ".recipe.json"))
	_check(recipe.rounded_polygon.size() == rounded.polygon.size() and recipe.bindings.size() == 6, "Recipe does not match exported geometry")
	_check(recipe.version == 2 and recipe.root_transform_cleared and Vector2(recipe.center_offset_local[0], recipe.center_offset_local[1]).is_equal_approx(center_offset), "Centering record is missing")
	_check(Vector2(recipe.rounded_polygon[0][0], recipe.rounded_polygon[0][1]).is_equal_approx(centered.polygon[0]), "Recipe contains uncentered output coordinates")
	instance.free()
	source.free()


func _test_custom_center() -> void:
	var source := (load(TEMPLATE) as PackedScene).instantiate() as RigidBody2D
	var inspected := Adapter.inspect_source(source)
	var points := _rectangle(96, 96)
	for index in range(points.size()):
		points[index] += Vector2(-16, -76)
	var rounded := Geometry.round_polygon(points, Profile.new())
	var offset := Geometry.area_centroid(rounded.polygon)
	source.get_node("CollisionBox").scale = Vector2(1.5, 0.8)
	source.center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	source.center_of_mass = offset * Vector2(1.5, 0.8) + Vector2(4, -6)
	var original_com := source.center_of_mass
	var built := Writer.build_result(source, rounded.polygon, inspected.bindings, "CloudBox_CustomCOM")
	_check(built.error.is_empty(), "Custom center of mass could not be exported")
	var instance := (built.scene as PackedScene).instantiate() as RigidBody2D
	_check(instance.center_of_mass_mode == RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM and instance.center_of_mass.is_equal_approx(Vector2(4, -6)), "Custom COM did not move with the scaled geometry")
	_check(source.center_of_mass == original_com, "Source custom COM was changed")
	instance.free()
	source.free()


func _test_runtime() -> void:
	var level := Level.new()
	add_child(level)
	Global.level = level
	level.write_to_global()
	for index in range(4):
		var layer := (load("res://Component/Layer/Depth_Layer.tscn") as PackedScene).instantiate() as DepthLayer
		layer.layer_id = index
		layer.slot = index
		layer.visual_scale = pow(0.8, index - 1)
		level.add_child(layer)
		Global.layers.append(layer)
	var object := _saved_scene.instantiate() as ShadowedGeometry
	object.transform = Transform2D.IDENTITY
	object.get_node("CollisionBox").scale = Vector2(2, 2)
	Global.layers[2].add_child(object)
	var polygon := object.collision_box.polygon
	object.apply_visual_transfer(Vector2.ZERO, Vector2.ONE)
	_check(object.shadow_box.size() == 1 and object.shadow_visual.size() == 1, "Runtime shadow pair was not created")
	_check(object.shadow_active[0], "Runtime projection was not activated")
	_check(object.shadow_box[0].polygon == polygon and object.shadow_visual[0].polygon == polygon, "Runtime shadows lost rounded outline")
	_check(object.visual_root.scale.is_equal_approx(Vector2(1.6, 1.6)), "Existing collision/depth scaling no longer works")
	_check(object.get_node("VisualRoot/Shape").texture_scale == Vector2(3.25, 1.75), "Runtime changed preserved texture scale")
	object.set_pick_condition(true)
	_check(not object._selection_outlines.is_empty(), "Selection feedback was not created")
	for entry in object._selection_outlines:
		_check(entry.outline.visible, "Selection outline is hidden")
		_check(entry.outline.polygon == entry.source.polygon, "Selection outline differs from rounded visual")
	for frame in range(3):
		await get_tree().physics_frame
		await get_tree().process_frame
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = object.collision_layer
	query.position = object.global_position
	var center := get_viewport().find_world_2d().direct_space_state.intersect_point(query)
	_check(_contains_object(center, object), "Rounded collision lost its center")
	query.position = object.to_global(Vector2(39, 39))
	var corner := get_viewport().find_world_2d().direct_space_state.intersect_point(query)
	_check(not _contains_object(corner, object), "Trimmed rounded corner is still collidable")
	await _test_dynamic_landing(level)
	Global.clear_scene_nodes()
	level.free()


func _test_dynamic_landing(level: Node2D) -> void:
	# Reproduce the user's off-origin 96x96 box. Keep gravity and rotation free;
	# a frozen fixture cannot detect this regression.
	var points := PackedVector2Array([Vector2(80, 20), Vector2(80, -76), Vector2(-16, -76), Vector2(-16, 20)])
	var source := (load(TEMPLATE) as PackedScene).instantiate() as RigidBody2D
	var inspected := Adapter.inspect_source(source)
	var profile := Profile.new()
	profile.outer_radius = 18.0
	profile.inner_radius = 6.0
	var rounded := Geometry.round_polygon(points, profile)
	var output := Writer.reserve_directory(TEST_DIRECTORY)
	var saved := Writer.save_result(source, rounded, inspected.bindings, profile, output)
	_check(saved.error.is_empty(), "Dynamic regression scene export failed")
	source.free()
	var fixed := (load(saved.scene_path) as PackedScene).instantiate() as RigidBody2D
	_check(fixed.transform.is_equal_approx(Transform2D.IDENTITY) and not fixed.freeze and not fixed.lock_rotation and is_equal_approx(fixed.gravity_scale, 1.0), "Dynamic regression was disabled or still has a root transform")
	fixed.position = Vector2(600, 0)
	Global.layers[2].add_child(fixed)
	var ground := StaticBody2D.new()
	ground.position = Vector2(800, 80)
	ground.collision_layer = fixed.collision_layer
	ground.collision_mask = fixed.collision_mask
	var ground_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1200, 40)
	ground_shape.shape = rectangle
	ground.add_child(ground_shape)
	level.add_child(ground)
	# The uncentered control must tip; this also proves physics is running.
	var control := RigidBody2D.new()
	control.position = Vector2(1000, 38)
	control.collision_layer = fixed.collision_layer
	control.collision_mask = fixed.collision_mask
	var control_shape := CollisionPolygon2D.new()
	control_shape.polygon = rounded.polygon
	control.add_child(control_shape)
	level.add_child(control)
	var maximum_rotation := 0.0
	var maximum_speed := 0.0
	for frame in range(180):
		await get_tree().physics_frame
		await get_tree().process_frame
		maximum_rotation = maxf(maximum_rotation, absf(fixed.rotation_degrees))
		maximum_speed = maxf(maximum_speed, fixed.linear_velocity.length())
	_check(maximum_speed > 1.0 and fixed.position.y > 5.0, "Free fall did not actually run")
	_check(absf(control.rotation_degrees) > 30.0, "Uncentered regression control did not reproduce tipping")
	_check(maximum_rotation < 0.1 and absf(fixed.angular_velocity) < 0.01, "Centered CloudBox tips during landing")
	var state := PhysicsServer2D.body_get_direct_state(fixed.get_rid())
	_check(state != null and state.center_of_mass_local.length() < 0.001, "Automatic physical COM is not at the centered origin")
	print("CLOUD_LANDING fixed_rotation=%f control_rotation=%f max_fixed_rotation=%f" % [fixed.rotation_degrees, control.rotation_degrees, maximum_rotation])


func _contains_object(hits: Array[Dictionary], object: Object) -> bool:
	for hit in hits:
		if hit.collider == object:
			return true
	return false
