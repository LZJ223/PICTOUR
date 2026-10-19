extends Node

const Baker = preload("res://addons/cloud_ground_baker/cloud_ground_baker.gd")
const Geometry = preload("res://addons/cloud_ground_baker/cloud_ground_geometry.gd")
const Profile = preload("res://addons/cloud_ground_baker/cloud_ground_profile.gd")
const Writer = preload("res://addons/cloud_ground_baker/cloud_ground_scene_writer.gd")
const TEMPLATE := "res://Component/Shadowed_Geometry/Shadowed_Ground.tscn"
var checks := 0
var failures := 0
var saved_scene: PackedScene


func _ready() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("CLOUD_GROUND: " + message)


func _run() -> void:
	get_tree().paused = false
	PhysicsServer2D.set_active(true)
	_test_geometry()
	_test_sparse_tiles()
	_test_scene()
	if saved_scene != null:
		await _test_runtime()
	print("CLOUD_GROUND_TEST_RESULT checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func rectangle(width: float, height: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(width, 0), Vector2(width, height), Vector2(0, height)])


func _test_geometry() -> void:
	var profile := Profile.new()
	var source := PackedVector2Array([Vector2(0, 140), Vector2(300, 140), Vector2(300, 0), Vector2(700, 0), Vector2(700, 400), Vector2(0, 400)])
	var rounded := Geometry.round_polygon(source, profile)
	check(rounded.error.is_empty(), "Stepped contour failed")
	if not rounded.error.is_empty():
		return
	var reflex := 0
	for corner in rounded.corners:
		check(is_equal_approx(corner.effective_radius, profile.outer_radius if corner.is_outer else profile.inner_radius), "Wrong convex/reflex radius")
		if not corner.is_outer:
			reflex += 1
	check(reflex == 1, "Expected one reflex corner")
	var prepared := Baker.prepare(source, profile)
	check(prepared.error.is_empty(), "Preparation failed")
	if not prepared.error.is_empty():
		return
	check(Geometry.area_centroid(prepared.contour).length() < 0.001, "Area centroid is not at origin")
	check(prepared.outline_points.size() > prepared.contour.size(), "Missing hand drawn outline samples")
	var left := 0
	var right := 0
	var edges := Geometry.surface_edges(source)
	for dot: Vector3 in prepared.dots:
		var point := Vector2(dot.x, dot.y) + Vector2(prepared.center_offset)
		var depth := Geometry.cloud_depth_at(point, edges, profile.upward_threshold)
		check(depth >= -0.001 and depth < profile.cloud_depth, "Dots outside top strip")
		if point.x < 290:
			left += 1
		elif point.x > 310:
			right += 1
	check(left > 100 and right > 100, "Both upper platforms must receive dots")
	var repeated := Baker.prepare(source, profile)
	check(prepared.dots == repeated.dots and prepared.outline_points == repeated.outline_points, "Same seed must reproduce output")
	var reverse := source.duplicate()
	reverse.reverse()
	var reversed := Baker.prepare(reverse, profile)
	check(reversed.error.is_empty(), "Reversed winding failed")
	var matches: bool = reversed.dots.size() == prepared.dots.size()
	if matches:
		for index in range(prepared.dots.size()):
			if prepared.dots[index].distance_to(reversed.dots[index]) > 0.001:
				matches = false
	check(matches, "Winding must not alter dots")
	profile.base_color = Color.RED
	check(prepared.profile.base_color != profile.base_color, "Prepared parameters were not snapshotted")
	profile.inner_radius = profile.outer_radius + 1
	check(not Baker.prepare(source, profile).error.is_empty(), "Invalid parameters accepted")
	var crossed := PackedVector2Array([Vector2.ZERO, Vector2(100, 100), Vector2(0, 100), Vector2(100, 0)])
	check(not Baker.prepare(crossed, Profile.new()).error.is_empty(), "Crossed polygon accepted")
	var preview := Baker.preview(prepared, 600)
	check(preview.error.is_empty() and preview.image.get_width() <= 600, "Preview render failed")
	if preview.error.is_empty():
		preview.image.save_png("res://.godot/cloud_ground_preview.png")


func _test_sparse_tiles() -> void:
	var profile := Profile.new()
	var large := Baker.prepare(rectangle(20000, 10000), profile)
	check(large.error.is_empty(), "Large ground rejected instead of sparse tiling")
	if not large.error.is_empty():
		return
	check(large.tile_origins.size() <= 21, "Large empty body generated extra tiles")
	check(large.estimated_bytes < 12 * 1048576, "Sparse memory estimate scales with body height")
	var tile := Baker.bake_tile(large, large.tile_origins[0])
	check(tile.error.is_empty() and tile.image != null, "Top tile missing")
	if tile.error.is_empty() and tile.image != null:
		check(tile.image.get_height() <= 100, "Transparent body rows were not cropped")
		check(tile.image.get_width() <= 1032, "Tile exceeds configured size plus gutter")
		print("CLOUD_GROUND_LARGE tiles=%d first=%s estimated_MiB=%.2f full_MiB=%.2f" % [large.tile_origins.size(), tile.image.get_size(), float(large.estimated_bytes) / 1048576, 20000.0 * 10000 * 4 / 1048576])
	profile.cloud_depth = 0
	var plain := Baker.prepare(rectangle(4000, 400), profile)
	check(plain.error.is_empty() and plain.tile_origins.is_empty(), "Zero depth should generate no PNG")
	var slope := PackedVector2Array([Vector2(0, 5000), Vector2(10000, 0), Vector2(10000, 10000), Vector2(0, 10000)])
	var sloped := Baker.prepare(slope, Profile.new())
	check(sloped.error.is_empty(), "Sloped strip scanned the full bounding rectangle")
	if sloped.error.is_empty():
		check(sloped.dots.size() > 1000 and sloped.tile_origins.size() < 30, "Sloped strip is not sparse")
	for density in [1.0, 0.75]:
		profile = Profile.new()
		profile.pixels_per_unit = density
		profile.tile_size_px = 256
		var prepared := Baker.prepare(rectangle(1600, 600), profile)
		check(prepared.error.is_empty(), "Seam preparation failed")
		if not prepared.error.is_empty():
			continue
		var previous: Dictionary = {}
		var max_delta := 0.0
		var compared := 0
		for origin: Vector2i in prepared.tile_origins:
			var current := Baker.bake_tile(prepared, origin)
			check(current.error.is_empty(), "Seam tile failed")
			if not current.error.is_empty() or current.image == null:
				continue
			current["image_origin"] = current.origin - current.region_offset
			if not previous.is_empty():
				var a := Rect2i(previous.image_origin, previous.image.get_size())
				var b := Rect2i(current.image_origin, current.image.get_size())
				var overlap := a.intersection(b)
				for y in range(overlap.position.y, overlap.end.y):
					for x in range(overlap.position.x + 1, overlap.end.x - 1):
						var pa := Vector2i(x, y) - a.position
						var pb := Vector2i(x, y) - b.position
						var ca: Color = previous.image.get_pixelv(pa)
						var cb: Color = current.image.get_pixelv(pb)
						# Compare premultiplied color, since RGB at alpha zero is immaterial.
						max_delta = maxf(max_delta, absf(ca.a - cb.a))
						max_delta = maxf(max_delta, absf(ca.r * ca.a - cb.r * cb.a))
						compared += 1
			previous = current
		check(compared > 100 and max_delta <= 2.0 / 255.0, "Neighboring tile gutter mismatch: %.5f" % max_delta)
		print("CLOUD_GROUND_SEAM density=%.2f pixels=%d delta=%.6f" % [density, compared, max_delta])


func _test_scene() -> void:
	var original_hash := FileAccess.get_sha256(TEMPLATE)
	var source := load(TEMPLATE).instantiate() as StaticBody2D
	var profile := Profile.new()
	var points := rectangle(620, 350)
	source.get_node("CollisionBox").polygon = points
	source.get_node("CollisionBox").scale = Vector2(1.4, 0.8)
	source.get_node("VisualRoot/Polygon2D").polygon = points
	source.get_node("Shadow").polygon = points
	source.transform = Transform2D(0.25, Vector2(1.1, 0.9), 0.08, Vector2(1200, 800))
	source.set("can_leave_shadow", false)
	source.set("can_be_shadowed", true)
	source.set("front", true)
	var decoration := Marker2D.new()
	decoration.name = "Marker"
	decoration.position = Vector2(300, 180)
	source.get_node("VisualRoot").add_child(decoration)
	var snapshot := Writer.capture_source(source)
	check(snapshot.error.is_empty(), "Static source with no Area2D was rejected")
	if not snapshot.error.is_empty():
		source.free()
		return
	var prepared := Baker.prepare(points, profile)
	var tiles: Array[Dictionary] = []
	for origin: Vector2i in prepared.tile_origins:
		var tile := Baker.bake_tile(prepared, origin)
		if tile.error.is_empty() and tile.image != null:
			tile["texture"] = ImageTexture.create_from_image(tile.image)
			tile["path"] = "unit_test.png"
			tiles.append(tile)
	# Mutating the live source after capture must not affect the exported result.
	source.set("front", false)
	var result := Writer.build_result(snapshot, prepared, tiles, "CloudGround_Test")
	check(result.error.is_empty(), "Scene build failed")
	if not result.error.is_empty():
		source.free()
		return
	saved_scene = result.scene
	var root := saved_scene.instantiate() as StaticBody2D
	check(root.transform.is_equal_approx(Transform2D.IDENTITY), "Root transform not cleared")
	check(root.get("can_leave_shadow") and not root.get("can_be_shadowed"), "Wrong shadow flags")
	check(root.get("front") and not root.get("can_transfer"), "Source properties lost")
	check(root.get_node_or_null("VisualRoot/Area2D") == null, "Unneeded picking area added")
	check(root.get_node("CollisionBox").scale.is_equal_approx(Vector2(1.4, 0.8)), "Collision scale lost")
	check(root.get_node("VisualRoot").scale == root.get_node("CollisionBox").scale, "Editor visual scale is not aligned")
	for path in ["CollisionBox", "VisualRoot/Polygon2D", "Shadow"]:
		check(root.get_node(NodePath(path)).polygon == prepared.contour, "Mismatched contour: " + path)
	check(root.get_node("Shadow") is Polygon2D and not root.get_node("Shadow").visible, "Runtime Shadow mother changed type/visibility")
	check(root.get_node("VisualRoot/Polygon2D").texture == null, "Base should not consume a full texture")
	check(root.get_node("VisualRoot/Polygon2D").color == profile.base_color, "Incorrect base color")
	check(root.get_node("VisualRoot/Outline").width == 2.0, "Incorrect default outline width")
	check(root.get_node("VisualRoot/Outline").closed, "Outline is not closed")
	check(root.get_node("VisualRoot/CloudDots").get_child_count() == tiles.size(), "Missing dot sprites")
	check(root.get_node("VisualRoot/Marker").position.is_equal_approx(Vector2(300, 180) - prepared.center_offset), "Decoration did not follow recentering")
	check(source.position == Vector2(1200, 800) and source.get("can_be_shadowed"), "Source mutated")
	check(FileAccess.get_sha256(TEMPLATE) == original_hash, "Source file modified")
	check(Writer.inspect_source(root).error.is_empty(), "Generated result cannot be baked again")
	root.free()
	source.free()


func _test_runtime() -> void:
	var level := Level.new()
	add_child(level)
	Global.level = level
	level.write_to_global()
	for index in range(4):
		var layer := load("res://Component/Layer/Depth_Layer.tscn").instantiate() as DepthLayer
		layer.layer_id = index
		layer.slot = index
		layer.visual_scale = pow(0.8, index - 1)
		level.add_child(layer)
		Global.layers.append(layer)
	var layer: DepthLayer = Global.layers[2]
	var ground := saved_scene.instantiate() as StaticBody2D
	layer.add_child(ground)
	await get_tree().physics_frame
	check(ground.get("shadow_box").size() == 1, "Runtime projection collisions were not created")
	check(ground.get("shadow_visual").size() == 1, "Runtime projection visuals were not created")
	check(ground.get_node("ShadowBox_3").polygon == ground.get_node("CollisionBox").polygon, "Runtime shadow has a different contour")
	var query := PhysicsPointQueryParameters2D.new()
	query.position = ground.global_position
	query.collision_mask = ground.collision_layer
	var hits := ground.get_world_2d().direct_space_state.intersect_point(query)
	var found := false
	for hit in hits:
		found = found or hit.collider == ground
	check(found, "Static rounded collision is not active")
	ground.apply_visual_transfer(Vector2(100, 40), Vector2.ONE)
	check(ground.get_node("VisualRoot").scale.is_equal_approx(ground.get_node("CollisionBox").scale * layer.visual_scale), "Layer projection did not preserve visual scale")
	Global.clear_scene_nodes()
	level.queue_free()
	await get_tree().process_frame
