@tool
extends RefCounted

const Geometry = preload("res://addons/soil_baker/soil_geometry.gd")
const Profile = preload("res://addons/soil_baker/soil_profile.gd")
const LAYER_OBJECT_SCRIPT_PATH := "res://Component/Object/Layer_Object.gd"
const MAX_RENDER_DIMENSION: int = 8192
const TILE_BLEED_PX: int = 3


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
	var prepared := prepare(points, profile, preview_limit)
	if not prepared.error.is_empty():
		return prepared
	var output_size: Vector2i = prepared.size
	var render_size := output_size * profile.supersampling
	if render_size.x > MAX_RENDER_DIMENSION or render_size.y > MAX_RENDER_DIMENSION:
		return {"error": "预览超过 %d 像素边长；请使用较小的预览尺寸。" % MAX_RENDER_DIMENSION}
	var image := _render(prepared, profile, Rect2i(Vector2i.ZERO, output_size), true)
	if image == null:
		return {"error": "Godot 无法栅格化生成的 SVG。"}
	prepared["image"] = image
	return prepared


static func prepare(
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
	var outline_points := _wobbled_contour(contour, profile)
	return {
		"error": "", "bounds": image_bounds, "density": density, "size": output_size,
		"contour": contour, "edges": edges, "outline_points": outline_points,
		"path": _path_data(contour),
		"outline": _path_data(outline_points),
	}


## Each tile is rendered from the same global coordinate system. Only its
## decoration is stored; the flat soil color is drawn by a Polygon2D.
static func tile_has_decoration(
	prepared: Dictionary, profile: Profile, origin: Vector2i
) -> bool:
	var size: Vector2i = prepared.size
	var core_size := Vector2i(
		mini(profile.tile_size_px, size.x - origin.x),
		mini(profile.tile_size_px, size.y - origin.y)
	)
	if core_size.x <= 0 or core_size.y <= 0:
		return false
	var density: float = prepared.density
	var view := Rect2(
		prepared.bounds.position + Vector2(origin - Vector2i.ONE * TILE_BLEED_PX) / density,
		Vector2(core_size + Vector2i.ONE * TILE_BLEED_PX * 2) / density
	)
	if profile.outline_width > 0.0:
		var outline: PackedVector2Array = prepared.outline_points
		var outline_view := view.grow(profile.outline_width * 0.5 + 1.0 / density)
		for index in range(outline.size()):
			if _segment_bounds_intersect(
				outline[index], outline[(index + 1) % outline.size()], outline_view
			):
				return true
	if profile.grass_depth > 0.0 and profile.dot_radius_ratio > 0.0:
		var grass_view := view.grow(profile.grass_depth + profile.dot_spacing)
		var edges: Array[Dictionary] = prepared.edges
		for edge in edges:
			if _segment_bounds_intersect(edge.start, edge.end, grass_view):
				return true
	return false


static func _segment_bounds_intersect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	return maxf(a.x, b.x) >= rect.position.x and minf(a.x, b.x) <= rect.end.x \
		and maxf(a.y, b.y) >= rect.position.y and minf(a.y, b.y) <= rect.end.y


static func bake_tile(prepared: Dictionary, profile: Profile, origin: Vector2i) -> Dictionary:
	var size: Vector2i = prepared.size
	var core_size := Vector2i(
		mini(profile.tile_size_px, size.x - origin.x),
		mini(profile.tile_size_px, size.y - origin.y)
	)
	if core_size.x <= 0 or core_size.y <= 0:
		return {"error": "无效的贴图分块坐标。"}
	var raster_rect := Rect2i(
		origin - Vector2i.ONE * TILE_BLEED_PX,
		core_size + Vector2i.ONE * TILE_BLEED_PX * 2
	)
	var render_size := raster_rect.size * profile.supersampling
	if render_size.x > MAX_RENDER_DIMENSION or render_size.y > MAX_RENDER_DIMENSION:
		return {"error": "单块纹理超出 SVG 渲染限制；请降低分块尺寸或超采样倍率。"}
	var image := _render(prepared, profile, raster_rect, false)
	if image == null:
		return {"error": "Godot 无法栅格化第 %s 块贴图。" % origin}
	var core_rect := Rect2i(Vector2i.ONE * TILE_BLEED_PX, core_size)
	var visible_rect := image.get_used_rect().grow(1).intersection(core_rect)
	if visible_rect.size.x <= 0 or visible_rect.size.y <= 0:
		return {"error": "", "image": null}
	var crop_rect := visible_rect.grow(TILE_BLEED_PX).intersection(
		Rect2i(Vector2i.ZERO, image.get_size())
	)
	return {
		"error": "",
		"image": image.get_region(crop_rect),
		"origin": origin + visible_rect.position - Vector2i.ONE * TILE_BLEED_PX,
		"core_size": visible_rect.size,
		"region_offset": visible_rect.position - crop_rect.position,
	}


static func _render(
	prepared: Dictionary, profile: Profile, raster_rect: Rect2i, include_fill: bool
) -> Image:
	var density: float = prepared.density
	var view_bounds := Rect2(
		prepared.bounds.position + Vector2(raster_rect.position) / density,
		Vector2(raster_rect.size) / density
	)
	var svg := _build_svg(prepared, view_bounds, raster_rect.size, profile, include_fill)
	var image := Image.new()
	var load_error := image.load_svg_from_string(svg, float(profile.supersampling))
	if load_error != OK or image.is_empty():
		return null
	if image.get_size() != raster_rect.size:
		image.resize(raster_rect.size.x, raster_rect.size.y, Image.INTERPOLATE_LANCZOS)
	return image


## This is only used while baking. The resulting scene references the PNG,
## and does not include the editor plugin or SVG renderer.
static func make_scene(
	source: Node, contour: PackedVector2Array, tiles: Array[Dictionary],
	image_bounds: Rect2, density: float, soil_color: Color, scene_name: String
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
	var base := Polygon2D.new()
	base.name = "SoilFill"
	base.polygon = contour
	base.color = soil_color
	base.antialiased = true
	visual_root.add_child(base)
	base.owner = root
	for index in range(tiles.size()):
		var tile: Dictionary = tiles[index]
		var sprite := Sprite2D.new()
		sprite.name = "SoilTile_%03d" % index
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = Rect2(
			Vector2(tile.region_offset), Vector2(tile.core_size)
		)
		sprite.position = image_bounds.position + Vector2(tile.origin) / density
		sprite.scale = Vector2.ONE / density
		sprite.texture = tile.texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		visual_root.add_child(sprite)
		sprite.owner = root

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		root.free()
		return null
	root.free()
	return packed


static func _build_svg(
	prepared: Dictionary, view_bounds: Rect2, output_size: Vector2i,
	profile: Profile, include_fill: bool
) -> String:
	var contour: PackedVector2Array = prepared.contour
	var edges: Array[Dictionary] = prepared.edges
	var path: String = prepared.path
	var outline: String = prepared.outline
	var parts := PackedStringArray()
	parts.append(
		'<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%s %s %s %s">' % [
			output_size.x, output_size.y,
			_number(view_bounds.position.x), _number(view_bounds.position.y),
			_number(view_bounds.size.x), _number(view_bounds.size.y)
		]
	)
	parts.append('<defs><clipPath id="ground"><path d="%s"/></clipPath></defs>' % path)
	if include_fill:
		parts.append('<path d="%s" fill="#%s"/>' % [path, profile.soil_color.to_html(false)])
	if profile.grass_depth > 0.0 and profile.dot_radius_ratio > 0.0 and not edges.is_empty():
		parts.append('<g clip-path="url(#ground)" fill="#%s">' % profile.grass_color.to_html(false))
		var step := profile.dot_spacing
		var row_step := step * sqrt(3.0) * 0.5
		var x_shift := fposmod(float(profile.seed) * 0.37, step)
		var y_shift := fposmod(float(profile.seed) * 0.19, row_step)
		var radius_margin := step * profile.dot_radius_ratio
		var first_row := floori((view_bounds.position.y - radius_margin - y_shift) / row_step)
		var last_row := ceili((view_bounds.end.y + radius_margin - y_shift) / row_step)
		var first_col := floori((view_bounds.position.x - radius_margin - x_shift) / step) - 1
		var last_col := ceili((view_bounds.end.x + radius_margin - x_shift) / step) + 1
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
