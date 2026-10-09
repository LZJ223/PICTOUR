@tool
class_name StoryLandformArt
extends RefCounted

static func eroded_edge(points: PackedVector2Array, seed_value: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		result.append(a)
		var count := maxi(1, int(a.distance_to(b) / 11.0))
		for step in range(1, count):
			var p := a.lerp(b, float(step) / count)
			p.y += rng.randf_range(-2.8, 2.8)
			result.append(p)
	result.append(points[-1])
	return result

## 固定地貌的纸墨表面；不生成可辨认但不能搬运的独立树或建筑。
static func add_surface(parent: Node2D, polygon: PackedVector2Array, color: Color, seed_value: int, fade: float) -> void:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		bounds = bounds.expand(point)
	var fill := Polygon2D.new()
	fill.name = "LandInk"
	fill.polygon = polygon
	var uv := PackedVector2Array()
	for point in polygon:
		uv.append((point - bounds.position) / Vector2(maxf(bounds.size.x, 1.0), maxf(bounds.size.y, 1.0)))
	fill.uv = uv
	fill.color = color
	var material := ShaderMaterial.new()
	material.shader = preload("res://Component/StoryWorld/Landform_Ink.gdshader")
	material.set_shader_parameter("grain", preload("res://Art/Materials/Dry_Ink_AI.png"))
	material.set_shader_parameter("grain_offset", Vector2(seed_value * 0.037, seed_value * 0.019))
	material.set_shader_parameter("bottom_fade", fade)
	fill.material = material
	parent.add_child(fill)

static func add_strata(parent: Node2D, edge: PackedVector2Array, polygon: PackedVector2Array, color: Color, seed_value: int) -> void:
	var left := edge[0].x
	var right := edge[-1].x
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for band in range(4):
		var depth := 18.0 + band * 31.0
		var points := PackedVector2Array()
		var start := lerpf(left, right, rng.randf_range(0.02, 0.12))
		var finish := lerpf(left, right, rng.randf_range(0.80, 0.97))
		var segments := maxi(5, int((finish - start) / 35.0))
		for step in range(segments + 1):
			var x := lerpf(start, finish, float(step) / segments)
			var y := edge_height(edge, x) + depth + sin(x * 0.015 + band) * 5.0
			var p := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(p, polygon):
				points.append(p)
			elif points.size() > 0:
				_add_vein(parent, points, color, 0.8 + band * 0.18)
				points = PackedVector2Array()
		_add_vein(parent, points, color, 0.8 + band * 0.18)

static func _add_vein(parent: Node2D, points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.antialiased = true
	parent.add_child(line)

static func edge_height(edge: PackedVector2Array, x: float) -> float:
	for i in range(edge.size() - 1):
		if x >= edge[i].x and x <= edge[i + 1].x:
			return lerpf(edge[i].y, edge[i + 1].y, inverse_lerp(edge[i].x, edge[i + 1].x, x))
	return edge[0].y if x < edge[0].x else edge[-1].y
