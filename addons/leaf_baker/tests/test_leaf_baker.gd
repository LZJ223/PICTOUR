extends Node

const Baker = preload("res://addons/leaf_baker/leaf_baker.gd")
const Geometry = preload("res://addons/leaf_baker/leaf_geometry.gd")
const Shadows = preload("res://addons/leaf_baker/leaf_shadows.gd")
const Profile = preload("res://addons/leaf_baker/leaf_profile.gd")
const Writer = preload("res://addons/leaf_baker/leaf_scene_writer.gd")
const TEST_DIR := "res://.godot/leaf_baker_tests"
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _rectangle(size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	_test_rectangle()
	_test_curves()
	_test_raster_and_tiles()
	_test_scene()
	_make_contact_sheet()
	if _failures == 0:
		print("LEAF_BAKER_TESTS_OK rectangle=true perpendicular_tangents=true shade_levels=true tile_seams=true scene=true")
	get_tree().quit(0 if _failures == 0 else 1)


func _test_rectangle() -> void:
	var points := _rectangle(Vector2(600, 340))
	var normalized := Geometry.rectangle(points)
	for offset in range(4):
		for reverse in [false, true]:
			var variant := PackedVector2Array()
			for index in range(4):
				variant.append(points[posmod(offset + (-index if reverse else index), 4)])
			var result := Geometry.rectangle(variant)
			_check(result.error.is_empty() and result.frame.is_equal_approx(normalized.frame), "Rectangle depends on winding or starting vertex")
	var trapezoid := PackedVector2Array([Vector2.ZERO, Vector2(100, 0), Vector2(80, 50), Vector2(0, 50)])
	_check(not Geometry.rectangle(trapezoid).error.is_empty(), "Trapezoid was accepted as a rectangle")
	_check(not Geometry.rectangle(PackedVector2Array([points[0], points[2], points[1], points[3]])).error.is_empty(), "Crossed rectangle was accepted")
	var transform := Transform2D(0.31, Vector2(50, -27))
	var rotated := Geometry.rectangle(transform * points)
	_check(rotated.error.is_empty() and rotated.size.is_equal_approx(Vector2(600, 340)), "Rotated rectangle normalization failed")
	var invalid := Profile.new()
	invalid.light_boundary_ratio = invalid.deep_boundary_ratio
	_check(not Baker.prepare(points, invalid).error.is_empty(), "Invalid shadow parameter ordering was accepted")


func _test_curves() -> void:
	for size in [Vector2(600, 340), Vector2(900, 100), Vector2(100, 900), Vector2(2, 3)]:
		for seed_value in [17, 1429, 70001]:
			for bend in [-0.6, 0.0, 0.6]:
				var profile := Profile.new()
				profile.seed = seed_value
				profile.shadow_bend_ratio = bend
				profile.corner_radius_min = 0.05
				profile.corner_radius_max = 0.45
				var prepared := Baker.prepare(_rectangle(size), profile)
				_check(prepared.error.is_empty(), "Valid rectangle preparation failed")
				if not prepared.error.is_empty():
					continue
				for curve in [prepared.shadow.left, prepared.shadow.right]:
					var start := Shadows.value_and_slope(curve, 0.0)
					_check(is_equal_approx(start.x, curve.start) and start.y == 0.0, "Shadow top tangent is not exactly vertical")
					var first_point: Vector2 = curve.points[0]
					var first_control := first_point + Vector2(curve.slopes[0], 1.0)
					_check(first_control.x == first_point.x, "SVG top control point breaks perpendicular entry")
				for index in range(101):
					var y: float = size.y * float(index) / 100.0
					var left := Shadows.value_and_slope(prepared.shadow.left, y).x
					var right := Shadows.value_and_slope(prepared.shadow.right, y).x
					_check(left > 0.0 and left < right and right < size.x, "Shadow boundaries crossed or left the rectangle")
	var profile := Profile.new()
	profile.shadow_wobble = 0.0
	var prepared := Baker.prepare(_rectangle(Vector2(600, 340)), profile)
	var curve: Dictionary = prepared.shadow.left
	var center := Vector2(curve.start + signf(curve.travel) * curve.radius, 0)
	for index in range(11):
		var y := 34.0 * index
		var point := Vector2(Shadows.value_and_slope(curve, y).x, y)
		_check(absf(point.distance_to(center) - curve.radius) < 0.001, "Unperturbed shadow is not a circular arc")


func _pixel(prepared: Dictionary, tile: Dictionary, point: Vector2) -> Color:
	var pixel: Vector2i = Vector2i((point - prepared.bounds.position) * prepared.density) - tile.origin + Vector2i.ONE * Baker.BLEED_PX
	return tile.image.get_pixelv(pixel)


func _test_raster_and_tiles() -> void:
	var profile := Profile.new()
	profile.dot_radius_ratio = 0.0
	profile.outline_width = 0.0
	profile.outline_wobble = 0.0
	var prepared := Baker.prepare(_rectangle(Vector2(600, 340)), profile)
	var tile := Baker.bake_tile(prepared, Vector2i.ZERO)
	_check(tile.error.is_empty(), "Leaf rasterization failed")
	if not tile.error.is_empty():
		return
	var left := Shadows.value_and_slope(prepared.shadow.left, 170.0).x
	var right := Shadows.value_and_slope(prepared.shadow.right, 170.0).x
	var xs := [left * 0.5, (left + right) * 0.5, (right + 600.0) * 0.5]
	var factors := [0.70, 0.85, 1.0]
	var base := Color(profile.base_color.to_html(false))
	for index in range(3):
		var actual := _pixel(prepared, tile, Vector2(xs[index], 170))
		var expected: Color = base * factors[index]
		_check(absf(actual.r - expected.r) < 2.0 / 255.0 and absf(actual.g - expected.g) < 2.0 / 255.0 and absf(actual.b - expected.b) < 2.0 / 255.0 and actual.a > 0.99, "Shading must be 30%%, 15%%, 0%% without stacked opacity: %s" % actual)
	_check(tile.image.get_pixel(0, 0).a == 0.0, "Padding should be transparent")
	var repeat := Baker.bake_tile(prepared, Vector2i.ZERO)
	_check(repeat.image.get_data() == tile.image.get_data(), "Repeated baking is not deterministic")
	profile = Profile.new()
	profile.pixels_per_unit = 0.75
	profile.tile_size_px = 256
	prepared = Baker.prepare(_rectangle(Vector2(10000, 400)), profile)
	var a := Baker.bake_tile(prepared, Vector2i.ZERO)
	var b := Baker.bake_tile(prepared, Vector2i(256, 0))
	_check(a.error.is_empty() and b.error.is_empty(), "Large rectangle tile render failed")
	if not a.error.is_empty() or not b.error.is_empty():
		return
	var maximum_error := 0.0
	for y in range(a.image.get_height()):
		for x in range(4):
			var p: Color = a.image.get_pixel(256 + Baker.BLEED_PX + x, y)
			var q: Color = b.image.get_pixel(Baker.BLEED_PX + x, y)
			maximum_error = maxf(maximum_error, maxf(absf(p.a - q.a), maxf(absf(p.r * p.a - q.r * q.a), maxf(absf(p.g * p.a - q.g * q.a), absf(p.b * p.a - q.b * q.a)))))
	print("LEAF_TILE_SEAM_ERROR=%f" % maximum_error)
	_check(maximum_error <= 4.0 / 255.0, "Tile patterns or shadow curves disagree at seam: %f" % maximum_error)
	_check(a.image.get_width() <= 256 + Baker.BLEED_PX * 2, "Tile exceeds configured dimensions")
	var variant := Profile.new()
	prepared = Baker.prepare(_rectangle(Vector2(240, 180)), variant)
	var dots := Baker.bake_tile(prepared, Vector2i.ZERO)
	var dot_count := 0
	for y in range(20, 160, 2):
		for x in range(30, 210, 2):
			var color := _pixel(prepared, dots, Vector2(x, y))
			if color.r > 0.25 and color.g > 0.4:
				dot_count += 1
	_check(dot_count > 50, "Yellow-green dots are missing")


func _test_scene() -> void:
	var source := StaticBody2D.new()
	source.set_script(load(Writer.LAYER_SCRIPT))
	source.set("can_transfer", true)
	source.set("front", true)
	source.set("outward_peak_scale", 1.17)
	var collision := CollisionPolygon2D.new()
	collision.name = "CollisionBox"
	collision.position = Vector2(-150, 27)
	collision.scale = Vector2(1.5, 0.8)
	collision.polygon = _rectangle(Vector2(240, 180))
	source.add_child(collision)
	var prepared := Baker.prepare(Geometry.source_polygon(source), Profile.new())
	var raster := Baker.bake_tile(prepared, Vector2i.ZERO)
	var texture := ImageTexture.create_from_image(raster.image)
	var tiles: Array[Dictionary] = [{"texture": texture, "origin": raster.origin, "core_size": raster.core_size}]
	var output := Writer.reserve_directory(TEST_DIR.path_join("outputs"))
	var captured := Writer.capture_source(source)
	var saved := Writer.save_result(captured, prepared, tiles, output)
	_check(saved.error.is_empty(), "Leaf scene or recipe could not be saved: %s" % saved.error)
	var packed := load(saved.scene_path) as PackedScene
	var instance := packed.instantiate()
	_check(instance.get_script().resource_path == Writer.LAYER_SCRIPT, "Output lost the LayerObject script")
	_check(instance.get("front") and instance.get("can_transfer") and is_equal_approx(instance.get("outward_peak_scale"), 1.17), "LayerObject exported values were not preserved")
	_check(instance.get_node("CollisionBox").transform == Transform2D.IDENTITY, "Source collision transform was applied twice")
	_check(instance.get_node("CollisionBox").polygon == prepared.root_contour, "Collision contour does not match the visual frame")
	_check(instance.get_node("VisualRoot/Area2D/CollisionShape2D").polygon == prepared.root_contour, "Selection shape does not match the leaf")
	_check(instance.get_node("VisualRoot/LeafTextureFrame").transform.is_equal_approx(prepared.frame), "Texture frame normalization failed")
	instance.free()
	source.free()


func _make_contact_sheet() -> void:
	var contact := Image.create_empty(1280, 800, false, Image.FORMAT_RGBA8)
	contact.fill(Color("313d38"))
	var sizes := [Vector2(600, 340), Vector2(260, 340), Vector2(900, 220), Vector2(340, 340)]
	for index in range(sizes.size()):
		var profile := Profile.new()
		profile.seed += index * 41
		var prepared := Baker.prepare(_rectangle(sizes[index]), profile)
		var preview := Baker.preview(prepared, 580)
		if not preview.error.is_empty():
			_check(false, preview.error)
			continue
		var image: Image = preview.image
		var offset := Vector2i(index % 2 * 640 + (640 - image.get_width()) / 2, index / 2 * 400 + (400 - image.get_height()) / 2)
		contact.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), offset)
	contact.save_png(TEST_DIR.path_join("preview.png"))
