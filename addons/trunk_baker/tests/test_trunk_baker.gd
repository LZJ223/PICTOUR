extends Node

const Baker = preload("res://addons/trunk_baker/trunk_baker.gd")
const Geometry = preload("res://addons/trunk_baker/trunk_geometry.gd")
const Profile = preload("res://addons/trunk_baker/trunk_profile.gd")
const Writer = preload("res://addons/trunk_baker/trunk_scene_writer.gd")
const TEST_DIR := "res://.godot/trunk_baker_tests"
var _failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_DIR))
	_test_geometry()
	_test_shading()
	_test_tiles()
	_test_scene()
	_make_contact_sheet()
	if _failures == 0:
		print("TRUNK_BAKER_TESTS_OK rectangle=true square_corners=true shade_thirds=true shaded_dots=true tile_seams=true scene=true")
	get_tree().quit(0 if _failures == 0 else 1)


func _test_geometry() -> void:
	var points := Geometry.contour(Vector2(240, 480))
	var normalized := Geometry.rectangle(points)
	for offset in range(4):
		for reverse in [false, true]:
			var variant := PackedVector2Array()
			for index in range(4):
				variant.append(points[posmod(offset + (-index if reverse else index), 4)])
			var result := Baker.prepare(variant, Profile.new())
			_check(result.error.is_empty() and result.frame.is_equal_approx(normalized.frame), "Rectangle depends on winding or starting vertex")
	var invalid := PackedVector2Array([Vector2.ZERO, Vector2(100, 0), Vector2(80, 50), Vector2(0, 50)])
	_check(not Geometry.rectangle(invalid).error.is_empty(), "Trapezoid was accepted")
	_check(not Geometry.rectangle(PackedVector2Array([points[0], points[2], points[1], points[3]])).error.is_empty(), "Crossed polygon was accepted")
	var transform := Transform2D(0.31, Vector2(45, -23))
	var rotated := Baker.prepare(transform * points, Profile.new())
	_check(rotated.error.is_empty() and rotated.size.is_equal_approx(Vector2(240, 480)), "Rotated rectangle normalization failed")
	_check(rotated.root_contour.size() == 4, "Collision rectangle acquired rounded corners")
	for seed_value in [7, 1429, 90001]:
		var outline := Geometry.wobbled_outline(Vector2(240, 480), 0.6, 18.0, 1.0, seed_value)
		for corner in points:
			_check(corner in outline, "Hand-drawn outline moved a corner")
		_check(outline != points, "Hand-drawn variation is missing")
	var profile := Profile.new()
	profile.light_shadow_opacity = 0.9
	_check(not Baker.prepare(points, profile).error.is_empty(), "Invalid shadow order was accepted")


func _pixel(prepared: Dictionary, tile: Dictionary, point: Vector2) -> Color:
	var pixel: Vector2i = Vector2i((point - prepared.bounds.position) * prepared.density) - tile.origin + Vector2i.ONE * Baker.BLEED_PX
	return tile.image.get_pixelv(pixel)


func _color_close(actual: Color, expected: Color, message: String) -> void:
	_check(absf(actual.r - expected.r) <= 2.0 / 255.0 and absf(actual.g - expected.g) <= 2.0 / 255.0 and absf(actual.b - expected.b) <= 2.0 / 255.0 and actual.a > 0.99, message + ": " + str(actual))


func _test_shading() -> void:
	var profile := Profile.new()
	profile.dot_radius_ratio = 0.0
	profile.outline_width = 0.0
	profile.outline_wobble = 0.0
	var prepared := Baker.prepare(Geometry.contour(Vector2(300, 200)), profile)
	var tile := Baker.bake_tile(prepared, Vector2i.ZERO)
	_check(tile.error.is_empty(), "Trunk rasterization failed")
	if not tile.error.is_empty():
		return
	var base := Color(profile.base_color.to_html(false))
	for y in [10.0, 100.0, 190.0]:
		for x in [10.0, 97.0, 103.0, 197.0, 203.0, 290.0]:
			var factor := 0.70 if x < 100 else (0.85 if x < 200 else 1.0)
			_color_close(_pixel(prepared, tile, Vector2(x, y)), base * factor, "Shade bands are not fixed at width thirds")
	_check(_pixel(prepared, tile, Vector2(1, 1)).a > 0.99, "Square corner was rounded away")
	_check(tile.image.get_pixel(0, 0).a == 0.0, "Texture padding is not transparent")
	var repeated := Baker.bake_tile(prepared, Vector2i.ZERO)
	_check(repeated.image.get_data() == tile.image.get_data(), "Baking is not deterministic")
	profile.dot_radius_ratio = 0.32
	prepared = Baker.prepare(Geometry.contour(Vector2(300, 200)), profile)
	var dots := Baker.bake_tile(prepared, Vector2i.ZERO)
	var x := fposmod(float(profile.seed) * 0.37, 4.0) + 20.0
	var row_step := profile.dot_spacing * profile.dot_row_spacing_ratio
	var y := fposmod(float(profile.seed) * 0.19, row_step) + row_step * 4.0
	var unshaded := _pixel(prepared, dots, Vector2(x + 200, y))
	_check(base.r - unshaded.r > 0.1, "Brown dots are missing")
	_color_close(_pixel(prepared, dots, Vector2(x, y)), unshaded * 0.70, "Deep shadow did not cover dots")
	_color_close(_pixel(prepared, dots, Vector2(x + 100, y)), unshaded * 0.85, "Light shadow did not cover dots")


func _seam_error(a: Image, b: Image, vertical: bool) -> float:
	var maximum := 0.0
	var span := mini(a.get_width(), b.get_width()) if vertical else mini(a.get_height(), b.get_height())
	for coordinate in range(span):
		for gutter in range(4):
			var p := a.get_pixel(coordinate, 256 + Baker.BLEED_PX + gutter) if vertical else a.get_pixel(256 + Baker.BLEED_PX + gutter, coordinate)
			var q := b.get_pixel(coordinate, Baker.BLEED_PX + gutter) if vertical else b.get_pixel(Baker.BLEED_PX + gutter, coordinate)
			maximum = maxf(maximum, maxf(absf(p.a - q.a), maxf(absf(p.r * p.a - q.r * q.a), maxf(absf(p.g * p.a - q.g * q.a), absf(p.b * p.a - q.b * q.a)))))
	return maximum


func _test_tiles() -> void:
	var profile := Profile.new()
	profile.tile_size_px = 256
	profile.pixels_per_unit = 0.75
	# The first shadow boundary falls exactly on the first tile boundary.
	var prepared := Baker.prepare(Geometry.contour(Vector2(1000, 350)), profile)
	var a := Baker.bake_tile(prepared, Vector2i.ZERO)
	var b := Baker.bake_tile(prepared, Vector2i(256, 0))
	var c := Baker.bake_tile(prepared, Vector2i(0, 256))
	if not a.error.is_empty() or not b.error.is_empty() or not c.error.is_empty():
		_check(false, "Tile rasterization failed")
		return
	var horizontal_error := _seam_error(a.image, b.image, false)
	var vertical_error := _seam_error(a.image, c.image, true)
	_check(maxf(horizontal_error, vertical_error) <= 4.0 / 255.0, "Tile seams disagree across pattern, outline or shade boundary")
	print("TRUNK_TILE_SEAM_ERROR horizontal=%f vertical=%f" % [horizontal_error, vertical_error])
	profile = Profile.new()
	var long_trunk := Baker.prepare(Geometry.contour(Vector2(120, 10000)), profile)
	var strip := Baker.bake_tile(long_trunk, Vector2i(0, 8192))
	_check(strip.error.is_empty() and strip.image.get_width() == long_trunk.pixel_size.x + Baker.BLEED_PX * 2, "Narrow trunk was padded into a square texture")
	_check(strip.image.get_height() <= 1024 + Baker.BLEED_PX * 2, "Large trunk exceeded per-tile size")


func _test_scene() -> void:
	var source := StaticBody2D.new()
	source.set_script(load(Writer.LAYER_SCRIPT))
	source.set("can_transfer", true)
	source.set("front", true)
	source.set("outward_peak_scale", 1.17)
	source.collision_layer = 16
	source.collision_mask = 8
	var collision := CollisionPolygon2D.new()
	collision.name = "CollisionBox"
	collision.position = Vector2(-50, 27)
	collision.scale = Vector2(1.5, 0.8)
	collision.polygon = Geometry.contour(Vector2(120, 300))
	source.add_child(collision)
	var prepared := Baker.prepare(Geometry.source_polygon(source), Profile.new())
	var tile := Baker.bake_tile(prepared, Vector2i.ZERO)
	var tiles: Array[Dictionary] = [{"texture": ImageTexture.create_from_image(tile.image), "origin": tile.origin, "core_size": tile.core_size}]
	var output := Writer.reserve_directory(TEST_DIR.path_join("outputs"))
	var saved := Writer.save_result(Writer.capture_source(source), prepared, tiles, output)
	_check(saved.error.is_empty(), "Scene, profile or recipe save failed")
	if not saved.error.is_empty():
		source.free()
		return
	var instance := (load(saved.scene_path) as PackedScene).instantiate()
	_check(instance.get_script().resource_path == Writer.LAYER_SCRIPT, "Output lost its LayerObject script")
	_check(instance.get("front") and instance.get("can_transfer") and is_equal_approx(instance.get("outward_peak_scale"), 1.17), "Exported parameters were not preserved")
	_check(instance.collision_layer == 16 and instance.collision_mask == 8, "Physics masks were not preserved")
	_check(instance.get_node("CollisionBox").transform == Transform2D.IDENTITY and instance.get_node("CollisionBox").polygon == prepared.root_contour, "Collision transform was applied twice")
	_check(instance.get_node("VisualRoot/Area2D/CollisionShape2D").polygon == prepared.root_contour, "Picking shape does not match collision")
	_check(instance.get_node("VisualRoot/TrunkTextureFrame").transform.is_equal_approx(prepared.frame), "Texture frame does not align with collision")
	_check(str(instance.name).begins_with("Trunk_"), "Trunk default numbering prefix is incorrect")
	instance.free()
	source.free()


func _make_contact_sheet() -> void:
	var contact := Image.create_empty(1280, 1000, false, Image.FORMAT_RGBA8)
	contact.fill(Color("313d38"))
	var sizes := [Vector2(120, 580), Vector2(500, 160), Vector2(260, 400), Vector2(400, 260)]
	for index in range(sizes.size()):
		var profile := Profile.new()
		profile.seed += index * 41
		var prepared := Baker.prepare(Geometry.contour(sizes[index]), profile)
		var result := Baker.preview(prepared, 460)
		if not result.error.is_empty():
			_check(false, result.error)
			continue
		var image: Image = result.image
		var offset := Vector2i(index % 2 * 640 + (640 - image.get_width()) / 2, index / 2 * 500 + (500 - image.get_height()) / 2)
		contact.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), offset)
	contact.save_png(TEST_DIR.path_join("preview.png"))
