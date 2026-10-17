@tool
extends RefCounted


static func source_polygon(source: Node) -> PackedVector2Array:
	var collision := source.get_node_or_null("CollisionBox") as CollisionPolygon2D
	var points := PackedVector2Array()
	if collision != null:
		for point in collision.polygon:
			points.append(collision.transform * point)
	return points


## Normalize winding and starting vertex into a frame with its X axis pointing
## along the most horizontal side. The frame also handles rotated rectangles.
static func rectangle(points: PackedVector2Array) -> Dictionary:
	if points.size() != 4:
		return {"error": "CollisionBox 必须是恰好包含四个顶点的矩形。"}
	var winding := 0.0
	var axis := Vector2.ZERO
	for index in range(4):
		var point := points[index]
		if not point.is_finite():
			return {"error": "矩形顶点含有无效数值。"}
		var edge := points[(index + 1) % 4] - point
		var next := points[(index + 2) % 4] - points[(index + 1) % 4]
		if edge.length() < 0.01 or next.length() < 0.01:
			return {"error": "矩形不能包含重合顶点或零长度边。"}
		if absf(edge.normalized().dot(next.normalized())) > 0.0001:
			return {"error": "CollisionBox 不是矩形：相邻边必须垂直。"}
		var turn := signf(edge.cross(next))
		if index > 0 and turn != winding:
			return {"error": "矩形顶点必须沿边界顺序排列。"}
		winding = turn
		var candidate := edge.normalized()
		if candidate.x < 0.0 or (is_zero_approx(candidate.x) and candidate.y < 0.0):
			candidate = -candidate
		if absf(candidate.x) > absf(axis.x) + 0.00001:
			axis = candidate
		elif is_equal_approx(absf(candidate.x), absf(axis.x)) and candidate.y < axis.y:
			axis = candidate
	var down := Vector2(-axis.y, axis.x)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in points:
		var projected := Vector2(point.dot(axis), point.dot(down))
		low = low.min(projected)
		high = high.max(projected)
	var size := high - low
	if size.x < 1.0 or size.y < 1.0:
		return {"error": "矩形的宽和高至少为 1 个本地单位。"}
	return {"error": "", "size": size, "frame": Transform2D(axis, down, axis * low.x + down * low.y)}


static func contour(size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])


## Four corners remain exact. Smooth tapering near each corner keeps the
## adjoining tangents straight, while the middle of every side can wobble.
static func wobbled_outline(size: Vector2, amplitude: float, wavelength: float, density: float, seed_value: int) -> PackedVector2Array:
	var points := contour(size)
	if amplitude <= 0.0:
		return points
	var perimeter := (size.x + size.y) * 2.0
	var wave_count := maxi(3, roundi(perimeter / wavelength))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var noise := PackedFloat32Array()
	for index in range(wave_count):
		noise.append(rng.randf_range(-1.0, 1.0))
	var result := PackedVector2Array()
	var traveled := 0.0
	for edge in range(4):
		var start := points[edge]
		var finish := points[(edge + 1) % 4]
		var length := start.distance_to(finish)
		var direction := (finish - start) / length
		var normal := Vector2(-direction.y, direction.x)
		var samples := maxi(2, ceili(length * density / 2.0))
		var fade_length := minf(length * 0.25, maxf(4.0 / density, wavelength * 0.5))
		for sample in range(samples):
			var distance := length * float(sample) / samples
			var phase := (traveled + distance) / perimeter * wave_count
			var first := posmod(floori(phase), wave_count)
			var fraction := fposmod(phase, 1.0)
			var smooth := fraction * fraction * (3.0 - 2.0 * fraction)
			var t := clampf(minf(distance, length - distance) / fade_length, 0.0, 1.0)
			var envelope := t * t * (3.0 - 2.0 * t)
			var offset := lerpf(noise[first], noise[(first + 1) % wave_count], smooth) * amplitude * envelope
			result.append(start + direction * distance + normal * offset)
		traveled += length
	return result


static func path_data(points: PackedVector2Array) -> String:
	var parts := PackedStringArray()
	for index in range(points.size()):
		parts.append("%s %.6f %.6f" % ["M" if index == 0 else "L", points[index].x, points[index].y])
	parts.append("Z")
	return " ".join(parts)


