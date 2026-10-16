extends SceneTree

const Baker = preload("res://addons/soil_baker/soil_baker.gd")
const Geometry = preload("res://addons/soil_baker/soil_geometry.gd")
const Profile = preload("res://addons/soil_baker/soil_profile.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var points := PackedVector2Array([
		Vector2(2000, 200), Vector2(2000, -200),
		Vector2(-2000, -200), Vector2(-2000, 200),
	])
	var profile: Profile = Profile.new()
	var result: Dictionary = Baker.bake_image(points, profile)
	if not result.get("error", "").is_empty():
		push_error(result.error)
		quit(1)
		return
	var image: Image = result.image
	if image.get_width() < 4000 or image.get_height() < 400:
		push_error("Unexpected output dimensions: %s" % image.get_size())
		quit(1)
		return
	if image.get_pixel(0, 0).a > 0.01:
		push_error("Texture padding is not transparent")
		quit(1)
		return
	var lower := image.get_pixel(image.get_width() / 2, image.get_height() - 20)
	if lower.a < 0.9 or lower.g > lower.r:
		push_error("Lower ground does not have an opaque soil fill")
		quit(1)
		return
	var green_pixels := 0
	for x in range(100, image.get_width() - 100, 10):
		var top := image.get_pixel(x, 20)
		if top.g > top.r * 1.3:
			green_pixels += 1
	if green_pixels < 20:
		push_error("Upper edge is missing the green dot pattern")
		quit(1)
		return
	var concave := PackedVector2Array([
		Vector2(0, 0), Vector2(100, 0), Vector2(100, 100),
		Vector2(60, 100), Vector2(60, 40), Vector2(40, 40),
		Vector2(40, 100), Vector2(0, 100),
	])
	var rounded: PackedVector2Array = Geometry.rounded_contour(concave, 20.0, 5.0)
	if not Geometry.validate_polygon(rounded).is_empty():
		push_error("Concave rounding produced an invalid polygon")
		quit(1)
		return
	var concave_bake: Dictionary = Baker.bake_image(concave, profile)
	if not concave_bake.get("error", "").is_empty():
		push_error("Concave ground could not be baked: %s" % concave_bake.error)
		quit(1)
		return
	concave_bake.image.save_png("res://.godot/soil_baker_concave.png")
	var save_error := image.save_png("res://.godot/soil_baker_smoke.png")
	if save_error != OK:
		push_error("Failed to save smoke preview: %d" % save_error)
		quit(1)
		return
	var source: StaticBody2D = (load("res://Component/Object/Ground.tscn") as PackedScene).instantiate()
	if ResourceSaver.save(profile.duplicate(true), "res://.godot/soil_baker_profile.tres") != OK:
		push_error("Bake profile could not be saved")
		quit(1)
		return
	var thumbnail := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	thumbnail.fill(Color.BROWN)
	var texture := ImageTexture.create_from_image(thumbnail)
	var tiles: Array[Dictionary] = [{
		"texture": texture, "origin": Vector2i.ZERO,
		"core_size": Vector2i(8, 8), "region_offset": Vector2i.ZERO
	}, {
		"texture": texture, "origin": Vector2i(8, 0),
		"core_size": Vector2i(6, 8), "region_offset": Vector2i(1, 0)
	}]
	var packed: PackedScene = Baker.make_scene(
		source, result.contour, tiles, result.bounds, result.density,
		profile.soil_color, "Soil_Smoke"
	)
	if packed == null or ResourceSaver.save(packed, "res://.godot/soil_baker_smoke.tscn") != OK:
		push_error("Generated LayerObject scene could not be packed and saved")
		quit(1)
		return
	var restored: Node = packed.instantiate()
	if restored.get_script().resource_path != "res://Component/Object/Layer_Object.gd" or restored.get_node_or_null("VisualRoot/SoilFill") == null or restored.get_node_or_null("VisualRoot/SoilTile_000") == null or restored.get_node_or_null("VisualRoot/SoilTile_001") == null:
		push_error("Generated scene is missing its LayerObject structure")
		quit(1)
		return
	var second_sprite := restored.get_node("VisualRoot/SoilTile_001") as Sprite2D
	if second_sprite.position.x != result.bounds.position.x + 8.0 / result.density or second_sprite.region_rect.position.x != 1.0:
		push_error("The second tile is positioned or cropped incorrectly")
		quit(1)
		return
	var large_points := PackedVector2Array([
		Vector2(0, 0), Vector2(20000, 0),
		Vector2(20000, 1200), Vector2(0, 1200),
	])
	var prepared: Dictionary = Baker.prepare(large_points, profile)
	if not prepared.error.is_empty() or prepared.size.x <= 8192:
		push_error("Large ground preparation failed: %s" % prepared.get("error", ""))
		quit(1)
		return
	var left: Dictionary = Baker.bake_tile(prepared, profile, Vector2i.ZERO)
	var right: Dictionary = Baker.bake_tile(prepared, profile, Vector2i(profile.tile_size_px, 0))
	if not left.error.is_empty() or not right.error.is_empty():
		push_error("Large ground tile render failed")
		quit(1)
		return
	if left.image.get_width() > profile.tile_size_px + Baker.TILE_BLEED_PX * 2:
		push_error("A tile exceeded its size limit")
		quit(1)
		return
	if right.image.get_height() >= 300:
		push_error("Transparent tile area was not cropped")
		quit(1)
		return
	var compared := 0
	for y in range(0, 100):
		var left_pixel: Vector2i = Vector2i(profile.tile_size_px - 1, y) - left.origin + left.region_offset
		var right_pixel: Vector2i = Vector2i(profile.tile_size_px - 1, y) - right.origin + right.region_offset
		if left_pixel.x < 0 or left_pixel.y < 0 or right_pixel.x < 0 or right_pixel.y < 0:
			continue
		if left_pixel.x >= left.image.get_width() or left_pixel.y >= left.image.get_height():
			continue
		if right_pixel.x >= right.image.get_width() or right_pixel.y >= right.image.get_height():
			continue
		var a: Color = left.image.get_pixelv(left_pixel)
		var b: Color = right.image.get_pixelv(right_pixel)
		if not a.is_equal_approx(b):
			push_error("Adjacent tiles disagree at the seam: %s vs %s" % [a, b])
			quit(1)
			return
		compared += 1
	if compared < 5:
		push_error("Too few pixels were compared across the tile seam")
		quit(1)
		return
	var tall_points := PackedVector2Array([
		Vector2(0, 0), Vector2(10000, 0),
		Vector2(10000, 10000), Vector2(0, 10000),
	])
	var tall: Dictionary = Baker.prepare(tall_points, profile)
	if Baker.tile_has_decoration(tall, profile, Vector2i(4096, 4096)):
		push_error("Interior tile was not culled before rendering")
		quit(1)
		return
	var middle: Dictionary = Baker.bake_tile(tall, profile, Vector2i(4096, 4096))
	if not middle.error.is_empty() or middle.image != null:
		push_error("Empty interior tiles should not be saved")
		quit(1)
		return
	print("SOIL_BAKER_SMOKE_OK size=%s contour_points=%d" % [image.get_size(), result.contour.size()])
	restored.free()
	source.free()
	quit(0)
