@tool
extends RefCounted

const Geometry = preload("res://addons/leaf_baker/leaf_geometry.gd")
const Shadows = preload("res://addons/leaf_baker/leaf_shadows.gd")
const Profile = preload("res://addons/leaf_baker/leaf_profile.gd")
const BLEED_PX := 4
const FILTER_GUARD_PX := 4
const MAX_RENDER_DIMENSION := 8192


static func prepare(points: PackedVector2Array, profile: Profile) -> Dictionary:
	var error := profile.validation_error()
	if not error.is_empty():
		return {"error": error}
	var rectangle := Geometry.rectangle(points)
	if not rectangle.error.is_empty():
		return rectangle
	var snapshot := profile.duplicate(true) as Profile
	var size: Vector2 = rectangle.size
	var density := snapshot.pixels_per_unit
	var radii := Geometry.corner_radii(size, snapshot.corner_radius_min, snapshot.corner_radius_max, snapshot.seed)
	var contour := Geometry.rounded_contour(size, radii)
	var outline := Geometry.wobbled_contour(contour, snapshot.outline_wobble / density, snapshot.outline_wavelength / density, density, snapshot.seed + 2003)
	var padding := ceilf(snapshot.outline_width * 0.5 + snapshot.outline_wobble + 4.0) / density
	var bounds := Rect2(Vector2.ONE * -padding, size + Vector2.ONE * padding * 2.0)
	var pixel_size := Vector2i(ceili(bounds.size.x * density), ceili(bounds.size.y * density))
	var tile_count := ceili(float(pixel_size.x) / snapshot.tile_size_px) * ceili(float(pixel_size.y) / snapshot.tile_size_px)
	if tile_count > 4096:
		return {"error": "素材将产生超过 4096 块纹理，请降低像素密度或缩小矩形。"}
	var shadow := Shadows.build(size, radii, snapshot)
	return {
		"error": "", "profile": snapshot, "frame": rectangle.frame, "size": size,
		"radii": radii, "contour": contour, "root_contour": rectangle.frame * contour,
		"bounds": bounds, "density": density, "pixel_size": pixel_size,
		"path": Geometry.path_data(contour), "outline": Geometry.path_data(outline),
		"shadow": shadow, "shadow_paths": Shadows.region_paths(shadow, padding + 1.0),
		"estimated_bytes": int(pixel_size.x) * int(pixel_size.y) * 4,
	}


static func preview(prepared: Dictionary, limit: int = 960) -> Dictionary:
	var bounds: Rect2 = prepared.bounds
	var density := minf(prepared.density, float(limit) / maxf(bounds.size.x, bounds.size.y))
	var size := Vector2i(maxi(1, ceili(bounds.size.x * density)), maxi(1, ceili(bounds.size.y * density)))
	return _render(prepared, Rect2i(Vector2i.ZERO, size), density)


static func bake_tile(prepared: Dictionary, origin: Vector2i) -> Dictionary:
	var profile: Profile = prepared.profile
	var total: Vector2i = prepared.pixel_size
	var size := Vector2i(mini(profile.tile_size_px, total.x - origin.x), mini(profile.tile_size_px, total.y - origin.y))
	if origin.x < 0 or origin.y < 0 or size.x <= 0 or size.y <= 0:
		return {"error": "无效的分块坐标。"}
	# Extra working pixels are discarded after downsampling, so Lanczos does
	# not sample the temporary image edge when producing the saved gutter.
	var guard := BLEED_PX + FILTER_GUARD_PX
	var result := _render(prepared, Rect2i(origin - Vector2i.ONE * guard, size + Vector2i.ONE * guard * 2), prepared.density)
	if not result.error.is_empty():
		return result
	result["image"] = result.image.get_region(Rect2i(Vector2i.ONE * FILTER_GUARD_PX, size + Vector2i.ONE * BLEED_PX * 2))
	result["origin"] = origin
	result["core_size"] = size
	return result


static func _render(prepared: Dictionary, pixels: Rect2i, density: float) -> Dictionary:
	var profile: Profile = prepared.profile
	if maxi(pixels.size.x, pixels.size.y) * profile.supersampling > MAX_RENDER_DIMENSION:
		return {"error": "单块超出 SVG 栅格化限制，请降低分块尺寸或超采样倍率。"}
	var bounds: Rect2 = prepared.bounds
	var view := Rect2(bounds.position + Vector2(pixels.position) / density, Vector2(pixels.size) / density)
	var parts := PackedStringArray()
	parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">' % [pixels.size.x, pixels.size.y])
	# Translate in output pixel units so every tile has exactly the same
	# sampling phase, including non-integer pixels_per_unit values.
	var offset := -bounds.position * density - Vector2(pixels.position)
	parts.append('<g transform="matrix(%.9f 0 0 %.9f %.9f %.9f)">' % [density, density, offset.x, offset.y])
	parts.append('<defs><clipPath id="leaf"><path d="%s"/></clipPath></defs>' % prepared.path)
	parts.append('<g clip-path="url(#leaf)"><path d="%s" fill="#%s"/>' % [prepared.path, profile.base_color.to_html(false)])
	if profile.dot_radius_ratio > 0.0:
		parts.append('<g fill="#%s">' % profile.dot_color.to_html(false))
		_append_dots(parts, view, prepared.size, profile)
		parts.append('</g>')
	var paths: PackedStringArray = prepared.shadow_paths
	parts.append('<path d="%s" fill="black" fill-opacity="%.6f"/>' % [paths[0], profile.deep_shadow_opacity])
	parts.append('<path d="%s" fill="black" fill-opacity="%.6f"/>' % [paths[1], profile.light_shadow_opacity])
	parts.append('</g>')
	if profile.outline_width > 0.0:
		parts.append('<path d="%s" fill="none" stroke="#%s" stroke-width="%.6f" stroke-linecap="round" stroke-linejoin="round"/>' % [prepared.outline, profile.outline_color.to_html(false), profile.outline_width / prepared.density])
	parts.append('</g></svg>')
	var image := Image.new()
	var error := image.load_svg_from_string("\n".join(parts), float(profile.supersampling))
	if error != OK or image.is_empty():
		return {"error": "Leaf SVG 栅格化失败（错误 %d）。" % error}
	if image.get_size() != pixels.size:
		image.resize(pixels.size.x, pixels.size.y, Image.INTERPOLATE_LANCZOS)
	return {"error": "", "image": image}


static func _append_dots(parts: PackedStringArray, view: Rect2, size: Vector2, profile: Profile) -> void:
	var step := profile.dot_spacing
	var row_step := step * profile.dot_row_spacing_ratio
	var radius := step * profile.dot_radius_ratio
	var x_phase := fposmod(float(profile.seed) * 0.37, step)
	var y_phase := fposmod(float(profile.seed) * 0.19, row_step)
	var region := view.grow(radius).intersection(Rect2(Vector2.ONE * -radius, size + Vector2.ONE * radius * 2.0))
	if not region.has_area():
		return
	for row in range(floori((region.position.y - y_phase) / row_step) - 1, ceili((region.end.y - y_phase) / row_step) + 2):
		var stagger := 0.5 if posmod(row, 2) == 1 else 0.0
		var y := float(row) * row_step + y_phase
		for col in range(floori((region.position.x - x_phase) / step) - 1, ceili((region.end.x - x_phase) / step) + 2):
			var x := (float(col) + stagger) * step + x_phase
			parts.append('<circle cx="%.6f" cy="%.6f" r="%.6f"/>' % [x, y, radius])
