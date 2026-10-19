@tool
extends RefCounted

const Profile = preload("res://addons/cloud_ground_baker/cloud_ground_profile.gd")
const Geometry = preload("res://addons/cloud_ground_baker/cloud_ground_geometry.gd")
const BLEED := 4
const FILTER_GUARD := 4
const MAX_DOTS := 200000
const MAX_CANDIDATES := 2000000


static func prepare(points: PackedVector2Array, settings: Profile) -> Dictionary:
	var error := settings.validation_error()
	if not error.is_empty():
		return {"error": error}
	var profile := settings.duplicate(true) as Profile
	var rounded := Geometry.round_polygon(points, profile)
	if not rounded.error.is_empty():
		return rounded
	var centered := Geometry.center_polygon(rounded.polygon)
	if not centered.error.is_empty():
		return centered
	var contour: PackedVector2Array = centered.polygon
	var source: PackedVector2Array = rounded.source_polygon.duplicate()
	for index in range(source.size()):
		source[index] -= centered.center_offset
	var outline := Geometry.wobbled_outline(contour, profile)
	if not outline.error.is_empty():
		return outline
	var bounds := Geometry.bounds(contour).grow(2.0 / profile.pixels_per_unit)
	var pixel_size := Vector2i(ceil(bounds.size * profile.pixels_per_unit))
	if pixel_size.x <= 0 or pixel_size.y <= 0 or pixel_size.x > 10000000 or pixel_size.y > 10000000:
		return {"error": "轮廓像素跨度无效或超过 1000 万，请降低像素密度。"}
	var edges := Geometry.surface_edges(source)
	var generated := _make_dots(contour, edges, profile)
	if not generated.error.is_empty():
		return generated
	var dots: PackedVector3Array = generated.dots
	var buckets := _tile_buckets(dots, bounds, pixel_size, profile)
	var origins: Array = buckets.keys()
	origins.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var estimated_bytes := 0
	for origin: Vector2i in origins:
		var used := Rect2()
		var first := true
		for index: int in buckets[origin]:
			var dot := dots[index]
			var rectangle := Rect2((Vector2(dot.x, dot.y) - bounds.position - Vector2.ONE * dot.z) * profile.pixels_per_unit, Vector2.ONE * dot.z * 2.0 * profile.pixels_per_unit)
			used = rectangle if first else used.merge(rectangle)
			first = false
		var core := Rect2(Vector2(origin), Vector2(Vector2i(profile.tile_size_px, profile.tile_size_px).min(pixel_size - origin)))
		used = used.grow(1).intersection(core)
		estimated_bytes += int(ceil(used.size.x + BLEED * 2) * ceil(used.size.y + BLEED * 2)) * 4
	return {
		"error": "", "profile": profile, "contour": contour, "outline_points": outline.points,
		"center_offset": centered.center_offset, "source_polygon": points.duplicate(),
		"bounds": bounds, "pixel_size": pixel_size, "density": profile.pixels_per_unit,
		"dots": dots, "tile_buckets": buckets, "tile_origins": origins,
		"estimated_bytes": estimated_bytes, "warnings": rounded.warnings,
		"radius_scale": rounded.radius_scale,
	}


static func _make_dots(contour: PackedVector2Array, edges: Array[Dictionary], profile: Profile) -> Dictionary:
	var dots := PackedVector3Array()
	if profile.cloud_depth == 0.0 or profile.dot_radius_ratio == 0.0 or profile.dot_color.a == 0.0:
		return {"error": "", "dots": dots}
	var spacing := profile.dot_spacing
	var row_step := spacing * sqrt(3.0) * 0.5
	var phase := Vector2(fposmod(profile.seed * 0.37, spacing), fposmod(profile.seed * 0.19, row_step))
	var radius_max := spacing * profile.dot_radius_ratio
	var visited := {}
	for edge in edges:
		var normal: Vector2 = edge.normal
		if normal.y > -profile.upward_threshold:
			continue
		var a: Vector2 = edge.start
		var b: Vector2 = edge.end
		var first_row := floori((minf(a.y, b.y) - radius_max - phase.y) / row_step)
		var last_row := ceili((maxf(a.y, b.y) + profile.cloud_depth / -normal.y + radius_max - phase.y) / row_step)
		for row in range(first_row, last_row + 1):
			var y := row * row_step + phase.y
			var left := minf(a.x, b.x)
			var right := maxf(a.x, b.x)
			# Intersect this hex-grid row with the sloped strip rather than
			# enumerating the entire slope's rectangular bounding box.
			if absf(b.y - a.y) > Geometry.EPSILON:
				var t0 := (y - profile.cloud_depth / -normal.y - a.y) / (b.y - a.y)
				var t1 := (y - a.y) / (b.y - a.y)
				var lower := maxf(0.0, minf(t0, t1))
				var upper := minf(1.0, maxf(t0, t1))
				if lower > upper:
					continue
				var x0 := lerpf(a.x, b.x, lower)
				var x1 := lerpf(a.x, b.x, upper)
				left = minf(x0, x1)
				right = maxf(x0, x1)
			var shift := phase.x + posmod(row, 2) * spacing * 0.5
			var first_column := floori((left - shift) / spacing)
			var last_column := ceili((right - shift) / spacing)
			for column in range(first_column, last_column + 1):
				var key := Vector2i(column, row)
				if visited.has(key):
					continue
				visited[key] = true
				if visited.size() > MAX_CANDIDATES:
					return {"error": "波点候选数量超过 200 万，请增大间距或降低云层深度。"}
				var point := Vector2(column * spacing + shift, y)
				var depth := Geometry.cloud_depth_at(point, edges, profile.upward_threshold)
				if depth >= profile.cloud_depth or not Geometry2D.is_point_in_polygon(point, contour):
					continue
				var t := clampf(depth / profile.cloud_depth, 0.0, 1.0)
				var radius := radius_max * pow(1.0 - t * t * (3.0 - 2.0 * t), profile.depth_falloff)
				if radius * profile.pixels_per_unit < 0.25:
					continue
				dots.append(Vector3(point.x, point.y, radius))
				if dots.size() > MAX_DOTS:
					return {"error": "波点超过 20 万个，请增大间距或降低云层深度。"}
	var ordered: Array[Vector3] = []
	for dot in dots:
		ordered.append(dot)
	ordered.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return {"error": "", "dots": PackedVector3Array(ordered)}


static func _tile_buckets(dots: PackedVector3Array, bounds: Rect2, size: Vector2i, profile: Profile) -> Dictionary:
	var buckets := {}
	var last := Vector2i(ceil(Vector2(size) / profile.tile_size_px)) - Vector2i.ONE
	for index in range(dots.size()):
		var dot := dots[index]
		var center := (Vector2(dot.x, dot.y) - bounds.position) * profile.pixels_per_unit
		var radius := dot.z * profile.pixels_per_unit + BLEED + FILTER_GUARD
		var first := Vector2i(floor((center - Vector2.ONE * radius) / profile.tile_size_px)).max(Vector2i.ZERO)
		var finish := Vector2i(floor((center + Vector2.ONE * radius) / profile.tile_size_px)).min(last)
		for row in range(first.y, finish.y + 1):
			for column in range(first.x, finish.x + 1):
				var origin := Vector2i(column, row) * profile.tile_size_px
				var indices: PackedInt32Array = buckets.get(origin, PackedInt32Array())
				indices.append(index)
				buckets[origin] = indices
	return buckets


static func preview(prepared: Dictionary, max_size: int = 960) -> Dictionary:
	var bounds: Rect2 = prepared.bounds
	var profile: Profile = prepared.profile
	var margin := (profile.outline_width_px * 0.5 + profile.outline_wobble_px + 2.0) / profile.pixels_per_unit
	var preview_bounds := bounds.grow(margin)
	var density := minf(profile.pixels_per_unit, float(max_size) / maxf(preview_bounds.size.x, preview_bounds.size.y))
	var size := Vector2i(ceil(preview_bounds.size * density))
	return _render(prepared, preview_bounds.position, size, density, range(prepared.dots.size()), true)


static func bake_tile(prepared: Dictionary, origin: Vector2i) -> Dictionary:
	var profile: Profile = prepared.profile
	var size: Vector2i = prepared.pixel_size
	if origin.x < 0 or origin.y < 0 or origin.x >= size.x or origin.y >= size.y or origin.x % profile.tile_size_px != 0 or origin.y % profile.tile_size_px != 0:
		return {"error": "无效的分块原点。"}
	if not prepared.tile_buckets.has(origin):
		return {"error": "", "image": null}
	var core_size := Vector2i(profile.tile_size_px, profile.tile_size_px).min(size - origin)
	var guard := BLEED + FILTER_GUARD
	var bounds: Rect2 = prepared.bounds
	var start: Vector2 = bounds.position + Vector2(origin - Vector2i.ONE * guard) / prepared.density
	var rendered := _render(prepared, start, core_size + Vector2i.ONE * guard * 2, prepared.density, prepared.tile_buckets[origin], false)
	if not rendered.error.is_empty():
		return rendered
	var image: Image = rendered.image
	var visible := image.get_used_rect().grow(1).intersection(Rect2i(Vector2i.ONE * guard, core_size))
	if not visible.has_area():
		return {"error": "", "image": null}
	# Keep neighboring pixels for bilinear filtering, and discard the outer
	# Lanczos guard so adjacent tiles share exactly the same edge samples.
	var crop := visible.grow(BLEED).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return {
		"error": "", "image": image.get_region(crop), "origin": origin + visible.position - Vector2i.ONE * guard,
		"core_size": visible.size, "region_offset": visible.position - crop.position,
	}


static func _render(prepared: Dictionary, start: Vector2, size: Vector2i, density: float, indices, full: bool) -> Dictionary:
	var profile: Profile = prepared.profile
	if maxi(size.x, size.y) * profile.supersampling > 8192:
		return {"error": "单块超采样尺寸超过 8192px，请缩小分块或降低超采样。"}
	var parts := PackedStringArray()
	parts.append('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % [size.x, size.y, size.x, size.y])
	parts.append('<g transform="matrix(%.9f 0 0 %.9f %.9f %.9f)">' % [density, density, -start.x * density, -start.y * density])
	var path := _path(prepared.contour)
	parts.append('<defs><clipPath id="c"><path d="%s"/></clipPath></defs>' % path)
	if full:
		parts.append('<path d="%s" fill="#%s" fill-opacity="%.6f"/>' % [path, profile.base_color.to_html(false), profile.base_color.a])
	parts.append('<g clip-path="url(#c)" fill="#%s" fill-opacity="%.6f">' % [profile.dot_color.to_html(false), profile.dot_color.a])
	var dots: PackedVector3Array = prepared.dots
	for index: int in indices:
		var dot := dots[index]
		parts.append('<circle cx="%.6f" cy="%.6f" r="%.6f"/>' % [dot.x, dot.y, dot.z])
	parts.append('</g>')
	if full and profile.outline_width_px > 0.0:
		parts.append('<path d="%s" fill="none" stroke="#%s" stroke-opacity="%.6f" stroke-width="%.6f" stroke-linejoin="round" stroke-linecap="round"/>' % [_path(prepared.outline_points), profile.outline_color.to_html(false), profile.outline_color.a, profile.outline_width_px / profile.pixels_per_unit])
	parts.append('</g></svg>')
	var image := Image.new()
	var error := image.load_svg_from_string("".join(parts), profile.supersampling)
	if error != OK:
		return {"error": "云朵波点栅格化失败（错误 %d）。" % error}
	if profile.supersampling > 1:
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return {"error": "", "image": image}


static func _path(points: PackedVector2Array) -> String:
	var commands := PackedStringArray()
	for index in range(points.size()):
		commands.append('%s %.6f %.6f' % ["M" if index == 0 else "L", points[index].x, points[index].y])
	commands.append("Z")
	return " ".join(commands)
