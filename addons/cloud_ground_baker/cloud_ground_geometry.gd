@tool
extends RefCounted

const Profile = preload("res://addons/cloud_ground_baker/cloud_ground_profile.gd")
const EPSILON := 0.00001


static func signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	# Translate before multiplying to avoid cancellation far from the origin.
	for index in range(1, points.size() - 1):
		area += (points[index] - points[0]).cross(points[index + 1] - points[0])
	return area * 0.5


## Area centroid, independent of winding and vertex sampling density.
static func area_centroid(points: PackedVector2Array) -> Vector2:
	var origin := points[0]
	var cross_sum := 0.0
	var weighted_x := 0.0
	var weighted_y := 0.0
	for index in range(points.size()):
		var a := points[index] - origin
		var b := points[(index + 1) % points.size()] - origin
		var cross := a.cross(b)
		cross_sum += cross
		weighted_x += (a.x + b.x) * cross
		weighted_y += (a.y + b.y) * cross
	return origin + Vector2(weighted_x / (3.0 * cross_sum), weighted_y / (3.0 * cross_sum))


static func center_polygon(points: PackedVector2Array) -> Dictionary:
	var error := validate_polygon(points)
	if not error.is_empty():
		return {"error": error}
	var offset := area_centroid(points)
	var centered := points.duplicate()
	for index in range(centered.size()):
		centered[index] -= offset
	return {"error": "", "polygon": centered, "center_offset": offset}


static func validate_polygon(points: PackedVector2Array) -> String:
	if points.size() < 3:
		return "多边形至少需要三个不同的顶点。"
	for index in range(points.size()):
		if not points[index].is_finite():
			return "多边形含有无效坐标。"
		if points[index].distance_to(points[(index + 1) % points.size()]) < EPSILON:
			return "多边形含有零长度边。"
	if absf(signed_area(points)) < EPSILON:
		return "多边形面积为零。"
	for first in range(points.size()):
		var first_end := (first + 1) % points.size()
		for second in range(first + 1, points.size()):
			var second_end := (second + 1) % points.size()
			if first_end == second or second_end == first:
				continue
			if _segments_touch(points[first], points[first_end], points[second], points[second_end]):
				return "多边形第 %d 和第 %d 条边相交或相接。" % [first + 1, second + 1]
	if Geometry2D.triangulate_polygon(points).size() < 3:
		return "多边形无法三角化，请检查轮廓。"
	return ""


static func round_polygon(points: PackedVector2Array, profile: Profile) -> Dictionary:
	var error := profile.validation_error()
	if not error.is_empty():
		return {"error": error}
	for point in points:
		if not point.is_finite():
			return {"error": "多边形含有无效坐标。"}
	# Accept the repeated closing point commonly used when drawing outlines.
	# Repeated adjacent and straight intermediate vertices add no geometry.
	var cleaned := _clean(points)
	error = validate_polygon(cleaned)
	if not error.is_empty():
		return {"error": error}
	if cleaned.size() > profile.max_vertices:
		return {"error": "原轮廓已超过最大顶点数 %d。" % profile.max_vertices}
	var scale_factor := 1.0
	for attempt in range(9):
		var result := _round_once(cleaned, profile, scale_factor)
		if not result.error.is_empty():
			return result
		error = validate_polygon(result.polygon)
		if error.is_empty():
			var warnings: Array[String] = []
			var limited := 0
			for corner in result.corners:
				if corner.effective_radius + EPSILON < corner.requested_radius:
					limited += 1
			if limited > 0:
				warnings.append("%d 处圆角因边长或轮廓间距限制缩小了半径。" % limited)
			if attempt > 0:
				warnings.append("为避免凹槽自交，圆角半径按 %.3f 倍计算。" % scale_factor)
			result["source_polygon"] = cleaned
			result["warnings"] = warnings
			result["radius_scale"] = scale_factor
			return result
		scale_factor *= 0.5
	return {"error": "圆角后轮廓仍有交叉，请减小半径或调整狭窄凹槽。详情：" + error}


static func _round_once(points: PackedVector2Array, profile: Profile, scale_factor: float) -> Dictionary:
	var polygon := PackedVector2Array()
	var corners: Array[Dictionary] = []
	var winding := signf(signed_area(points))
	for index in range(points.size()):
		var vertex := points[index]
		var to_previous := points[posmod(index - 1, points.size())] - vertex
		var to_next := points[(index + 1) % points.size()] - vertex
		var u := to_previous.normalized()
		var v := to_next.normalized()
		var turn := (-u).cross(v)
		var is_outer := turn * winding > 0.0
		var requested: float = profile.outer_radius if is_outer else profile.inner_radius
		var alpha := acos(clampf(u.dot(v), -1.0, 1.0))
		var radius := 0.0
		if absf(turn) > EPSILON and alpha > EPSILON and PI - alpha > EPSILON:
			var tangent := tan(alpha * 0.5)
			var distance := minf(requested * scale_factor / tangent, minf(to_previous.length(), to_next.length()) * 0.49)
			radius = distance * tangent
			if radius > EPSILON:
				var center := vertex + (u + v).normalized() * radius / sin(alpha * 0.5)
				var entry := vertex + u * distance
				var exit := vertex + v * distance
				var start_angle := (entry - center).angle()
				var sweep := wrapf((exit - center).angle() - start_angle, -PI, PI)
				var max_step := minf(PI / 6.0, 2.0 * acos(clampf(1.0 - profile.max_chord_error / radius, -1.0, 1.0)))
				var segments := maxi(1, ceili(absf(sweep) / max_step))
				if polygon.size() + segments + 1 > profile.max_vertices:
					return {"error": "圆角顶点数超过 %d，请提高最大弦误差或最大顶点数。" % profile.max_vertices}
				for sample in range(segments + 1):
					var point := center + Vector2.from_angle(start_angle + sweep * float(sample) / segments) * radius
					if sample == 0:
						point = entry
					elif sample == segments:
						point = exit
					_append_distinct(polygon, point)
		if radius <= EPSILON:
			_append_distinct(polygon, vertex)
		corners.append({"vertex": vertex, "is_outer": is_outer, "requested_radius": requested, "effective_radius": radius})
	if polygon.size() > profile.max_vertices:
		return {"error": "圆角顶点数超过 %d。" % profile.max_vertices}
	return {"error": "", "polygon": polygon, "corners": corners}


static func _clean(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		_append_distinct(result, point)
	if result.size() > 1 and result[0].distance_to(result[-1]) < EPSILON:
		result.remove_at(result.size() - 1)
	var changed := true
	while changed and result.size() > 3:
		changed = false
		for index in range(result.size()):
			var incoming := result[index] - result[posmod(index - 1, result.size())]
			var outgoing := result[(index + 1) % result.size()] - result[index]
			if absf(incoming.normalized().cross(outgoing.normalized())) < EPSILON and incoming.dot(outgoing) > 0.0:
				result.remove_at(index)
				changed = true
				break
	return result


static func _append_distinct(points: PackedVector2Array, point: Vector2) -> void:
	if points.is_empty() or points[-1].distance_to(point) >= EPSILON:
		points.append(point)


static func _segments_touch(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	if maxf(a.x, b.x) + EPSILON < minf(c.x, d.x) or maxf(c.x, d.x) + EPSILON < minf(a.x, b.x) or maxf(a.y, b.y) + EPSILON < minf(c.y, d.y) or maxf(c.y, d.y) + EPSILON < minf(a.y, b.y):
		return false
	if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
		return true
	# Include collinear overlaps and non-adjacent touching vertices.
	return (
		Geometry2D.get_closest_point_to_segment(a, c, d).distance_to(a) < EPSILON
		or Geometry2D.get_closest_point_to_segment(b, c, d).distance_to(b) < EPSILON
		or Geometry2D.get_closest_point_to_segment(c, a, b).distance_to(c) < EPSILON
		or Geometry2D.get_closest_point_to_segment(d, a, b).distance_to(d) < EPSILON
	)


static func bounds(points: PackedVector2Array) -> Rect2:
	var result := Rect2(points[0], Vector2.ZERO)
	for point in points:
		result = result.expand(point)
	return result


static func surface_edges(points: PackedVector2Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var winding := signf(signed_area(points))
	for index in range(points.size()):
		var start := points[index]
		var finish := points[(index + 1) % points.size()]
		var delta := finish - start
		if absf(delta.x) <= EPSILON:
			continue
		var normal := Vector2(delta.y, -delta.x).normalized() * winding
		result.append({"start": start, "end": finish, "normal": normal})
	return result


## Find the first boundary hit by a vertical ray upward. A steep/non-top
## boundary blocks a more distant top surface, preventing dots across a notch.
static func cloud_depth_at(point: Vector2, edges: Array[Dictionary], threshold: float) -> float:
	var nearest := INF
	var depth := INF
	for edge in edges:
		var a: Vector2 = edge.start
		var b: Vector2 = edge.end
		if point.x < minf(a.x, b.x) or point.x > maxf(a.x, b.x):
			continue
		var height := lerpf(a.y, b.y, (point.x - a.x) / (b.x - a.x))
		var vertical := point.y - height
		if vertical >= -EPSILON and vertical < nearest:
			nearest = vertical
			depth = maxf(0.0, vertical) * -float(edge.normal.y) if edge.normal.y <= -threshold else INF
	return depth


static func wobbled_outline(points: PackedVector2Array, profile: Profile) -> Dictionary:
	if profile.outline_width_px == 0.0 or profile.outline_wobble_px == 0.0:
		return {"error": "", "points": points.duplicate()}
	var perimeter := 0.0
	var normals := PackedVector2Array()
	for index in range(points.size()):
		perimeter += points[index].distance_to(points[(index + 1) % points.size()])
		var incoming := (points[index] - points[posmod(index - 1, points.size())]).normalized()
		var outgoing := (points[(index + 1) % points.size()] - points[index]).normalized()
		var tangent := (incoming + outgoing).normalized()
		normals.append(Vector2(-tangent.y, tangent.x))
	var density := profile.pixels_per_unit
	var step := minf(3.0, profile.outline_wavelength_px * 0.25) / density
	var wave_count := maxi(3, roundi(perimeter * density / profile.outline_wavelength_px))
	if perimeter / step + points.size() > 32768 or wave_count > 32768:
		return {"error": "描边采样超过 32768 点，请降低像素密度、缩小轮廓或关闭描边抖动。"}
	var rng := RandomNumberGenerator.new()
	rng.seed = profile.seed
	var noise := PackedFloat32Array()
	for index in range(wave_count):
		noise.append(rng.randf_range(-1.0, 1.0))
	var outline := PackedVector2Array()
	var traveled := 0.0
	for index in range(points.size()):
		var next := (index + 1) % points.size()
		var length := points[index].distance_to(points[next])
		var samples := maxi(1, ceili(length / step))
		for sample in range(samples):
			var t := float(sample) / samples
			var phase := (traveled + length * t) / perimeter * wave_count
			var first := posmod(floori(phase), wave_count)
			var fraction := fposmod(phase, 1.0)
			var smooth := fraction * fraction * (3.0 - 2.0 * fraction)
			var amount := lerpf(noise[first], noise[(first + 1) % wave_count], smooth) * profile.outline_wobble_px / density
			outline.append(points[index].lerp(points[next], t) + normals[index].lerp(normals[next], t).normalized() * amount)
		traveled += length
	return {"error": "", "points": outline}
