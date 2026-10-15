@tool
extends RefCounted

const Geometry = preload("res://addons/soil_baker/soil_geometry.gd")
const Profile = preload("res://addons/soil_baker/soil_profile.gd")
const LAYER_OBJECT_SCRIPT_PATH := "res://Component/Object/Layer_Object.gd"
const MAX_RENDER_DIMENSION: int = 8192


static func source_polygon(source: Node) -> PackedVector2Array:
	var collision := source.get_node_or_null("CollisionBox") as CollisionPolygon2D
	if collision == null:
		return PackedVector2Array()
	var points := PackedVector2Array()
	for point in collision.polygon:
		points.append(collision.transform * point)
	return points


static func bake_image(
	points: PackedVector2Array, profile: Profile, preview_limit: int = 0
) -> Dictionary:
	var error: String = Geometry.validate_polygon(points)
	if not error.is_empty():
		return {"error": error}
	var contour: PackedVector2Array = Geometry.rounded_contour(
		points, profile.outer_corner_radius, profile.inner_corner_radius
	)
	if not Geometry.validate_polygon(contour).is_empty():
		return {"error": "圆角轮廓自交；请降低圆角半径或简化地面轮廓。"}
	var edges: Array[Dictionary] = Geometry.upward_edges(points, profile.upward_threshold)
	var original_bounds: Rect2 = Geometry.bounds(points)
	var padding := ceilf(profile.outline_width * 0.5 + profile.outline_wobble + 4.0)
	var image_bounds := Rect2(
		original_bounds.position - Vector2.ONE * padding,
		original_bounds.size + Vector2.ONE * padding * 2.0
	)
	var density := profile.pixels_per_unit
	if preview_limit > 0:
		density = minf(density, float(preview_limit) / maxf(image_bounds.size.x, image_bounds.size.y))
	var output_size := Vector2i(
		maxi(1, ceili(image_bounds.size.x * density)),
		maxi(1, ceili(image_bounds.size.y * density))
	)
	var render_size := output_size * profile.supersampling
	if render_size.x > MAX_RENDER_DIMENSION or render_size.y > MAX_RENDER_DIMENSION:
		return {"error": "输出纹理超过 %d 像素边长；请降低像素密度或超采样倍率。" % MAX_RENDER_DIMENSION}
	var svg := _build_svg(contour, edges, image_bounds, output_size, profile)
	var image := Image.new()
	var load_error := image.load_svg_from_string(svg, float(profile.supersampling))
	if load_error != OK or image.is_empty():
		return {"error": "Godot 无法栅格化生成的 SVG（错误 %d）。" % load_error}
	if image.get_size() != output_size:
		image.resize(output_size.x, output_size.y, Image.INTERPOLATE_LANCZOS)
	return {
		"error": "",
		"image": image,
		"bounds": image_bounds,
		"density": density,
		"contour": contour,
	}


## This is only used while baking. The resulting scene references the PNG,
## and does not include the editor plugin or SVG renderer.
static func make_scene(
	source: Node, contour: PackedVector2Array, texture: Texture2D,
	image_bounds: Rect2, density: float, scene_name: String
) -> PackedScene:
	var source_body := source as StaticBody2D
	var root := StaticBody2D.new()
	root.name = scene_name
	root.set_script(load(LAYER_OBJECT_SCRIPT_PATH))
	root.set("can_transfer", source.get("can_transfer"))
	root.set("can_leave_shadow", source.get("can_leave_shadow"))
	root.set("can_be_shadowed", source.get("can_be_shadowed"))
	root.set("front", source.get("front"))
	root.collision_layer = source_body.collision_layer
	root.collision_mask = source_body.collision_mask
	root.physics_material_override = source_body.physics_material_override

	var collision := CollisionPolygon2D.new()
	collision.name = "CollisionBox"
	collision.polygon = contour
	root.add_child(collision)
	collision.owner = root

	var visual_root := Node2D.new()
	visual_root.name = "VisualRoot"
	root.add_child(visual_root)
	visual_root.owner = root
	var sprite := Sprite2D.new()
	sprite.name = "SoilSprite"
	sprite.centered = false
	sprite.position = image_bounds.position
	sprite.scale = Vector2.ONE / density
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	visual_root.add_child(sprite)
	sprite.owner = root

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return null
	root.free()
	return packed


static func _build_svg(
	contour: PackedVector2Array, edges: Array[Dictionary],
	image_bounds: Rect2, output_size: Vector2i, profile: Profile
) -> String:
	var path := _path_data(contour)
	var outline := _path_data(_wobbled_contour(contour, profile))
	var parts := PackedStringArray()
	parts.append(
		'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%s %s %s %s">' % [
			output_size.x, output_size.y,
			_number(image_bounds.position.x), _number(image_bounds.position.y),
			_number(image_bounds.size.x), _number(image_bounds.size.y)
		]
	)
	parts.append('<defs><clipPath id="ground"><path d="%s"/></clipPath></defs>' % path)
	parts.append('<path d="%s" fill="#%s"/>' % [path, profile.soil_color.to_html(false)])
	if profile.grass_depth > 0.0 and profile.dot_radius_ratio > 0.0 and not edges.is_empty():
		parts.append('<g clip-path="url(#ground)" fill="#%s">' % profile.grass_color.to_html(false))
		var step := profile.dot_spacing
		var row_step := step * sqrt(3.0) * 0.5
		var x_shift := fposmod(float(profile.seed) * 0.37, step)
		var y_shift := fposmod(float(profile.seed) * 0.19, row_step)
		var first_row := floori((image_bounds.position.y - y_shift) / row_step) - 1
		var last_row := ceili((image_bounds.end.y - y_shift) / row_step) + 1
		var first_col := floori((image_bounds.position.x - x_shift) / step) - 1
		var last_col := ceili((image_bounds.end.x - x_shift) / step) + 1
		for row in range(first_row, last_row + 1):
			var y := float(row) * row_step + y_shift
			var stagger := 0.5 if posmod(row, 2) == 1 else 0.0
			for col in range(first_col, last_col + 1):
				var x := (float(col) + stagger) * step + x_shift
				var center := Vector2(x, y)
				if not Geometry2D.is_point_in_polygon(center, contour):
					continue
				var depth: float = Geometry.distance_to_upward_edges(center, edges)
				if depth >= profile.grass_depth:
					continue
				var t := clampf(depth / profile.grass_depth, 0.0, 1.0)
				var fade := 1.0 - t * t * (3.0 - 2.0 * t)
				var radius := step * profile.dot_radius_ratio * fade
				if radius < 0.25:
					continue
				parts.append('<circle cx="%s" cy="%s" r="%s"/>' % [
					_number(x), _number(y), _number(radius)
				])
		parts.append('</g>')
	parts.append(
		'<path d="%s" fill="none" stroke="#%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % [
			outline, profile.outline_color.to_html(false), _number(profile.outline_width)
		]
	)
	parts.append('</svg>')
	return "\n".join(parts)


static func _path_data(points: PackedVector2Array) -> String:
	var parts := PackedStringArray()
	for index in range(points.size()):
		parts.append("%s %s %s" % [
			"M" if index == 0 else "L", _number(points[index].x), _number(points[index].y)
		])
	parts.append("Z")
	return " ".join(parts)


static func _wobbled_contour(points: PackedVector2Array, profile: Profile) -> PackedVector2Array:
	if profile.outline_wobble <= 0.0:
		return points
	var perimeter := 0.0
	for index in range(points.size()):
		perimeter += points[index].distance_to(points[(index + 1) % points.size()])
	var wave_count := maxi(3, roundi(perimeter / profile.wobble_wavelength))
	var wave_length := perimeter / float(wave_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.seed
	var noise := PackedFloat32Array()
	for index in range(wave_count):
		noise.append(rng.randf_range(-1.0, 1.0))
	var result := PackedVector2Array()
	var traveled := 0.0
	for index in range(points.size()):
		var start := points[index]
		var finish := points[(index + 1) % points.size()]
		var direction := (finish - start).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var length := start.distance_to(finish)
		var samples := maxi(1, ceili(length / 3.0))
		for sample in range(samples):
			var distance := traveled + length * float(sample) / float(samples)
			var wave_position := distance / wave_length
			var first := posmod(floori(wave_position), wave_count)
			var second := (first + 1) % wave_count
			var phase := fposmod(wave_position, 1.0)
			var smooth := phase * phase * (3.0 - 2.0 * phase)
			var wobble := lerpf(noise[first], noise[second], smooth) * profile.outline_wobble
			result.append(start.lerp(finish, float(sample) / float(samples)) + normal * wobble)
		traveled += length
	return result


static func _number(value: float) -> String:
	return "%.3f" % value
