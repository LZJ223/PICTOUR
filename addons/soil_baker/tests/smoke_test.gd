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
	var packed: PackedScene = Baker.make_scene(
		source, result.contour, texture, result.bounds, result.density, "Soil_Smoke"
	)
	if packed == null or ResourceSaver.save(packed, "res://.godot/soil_baker_smoke.tscn") != OK:
		push_error("Generated LayerObject scene could not be packed and saved")
		quit(1)
		return
	var restored: Node = packed.instantiate()
	if restored.get_script().resource_path != "res://Component/Object/Layer_Object.gd" or restored.get_node_or_null("VisualRoot/SoilSprite") == null:
		push_error("Generated scene is missing its LayerObject structure")
		quit(1)
		return
	print("SOIL_BAKER_SMOKE_OK size=%s contour_points=%d" % [image.get_size(), result.contour.size()])
	restored.free()
	source.free()
	quit(0)
