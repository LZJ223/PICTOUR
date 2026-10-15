@tool
extends RefCounted

const EPSILON: float = 0.0001


static func signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for index in range(points.size()):
		area += points[index].cross(points[(index + 1) % points.size()])
	return area * 0.5


static func validate_polygon(points: PackedVector2Array) -> String:
	if points.size() < 3:
		return "CollisionBox 至少需要三个顶点。"
	if absf(signed_area(points)) < EPSILON:
		return "CollisionBox 面积为零。"
	for index in range(points.size()):
		if points[index].distance_to(points[(index + 1) % points.size()]) < EPSILON:
			return "CollisionBox 含有重合的相邻顶点。"
	for first in range(points.size()):
		var first_end := (first + 1) % points.size()
		for second in range(first + 1, points.size()):
			var second_end := (second + 1) % points.size()
			if first == second or first_end == second or second_end == first:
				continue
			if Geometry2D.segment_intersects_segment(
				points[first], points[first_end], points[second], points[second_end]
			) != null:
				return "CollisionBox 轮廓自交，无法生成可靠的圆角。"
	return ""


## Sample true tangent circular arcs. Convex and reflex vertices use
## different radii; the source polygon's winding makes this independent of
## the order in which the artist placed points.
static func rounded_contour(
	points: PackedVector2Array, outer_radius: float, inner_radius: float
) -> PackedVector2Array:
	var result := PackedVector2Array()
	var winding := signf(signed_area(points))
	for index in range(points.size()):
		var previous := points[(index - 1 + points.size()) % points.size()]
		var vertex := points[index]
		var following := points[(index + 1) % points.size()]
		var to_previous := previous - vertex
		var to_next := following - vertex
		var incoming := -to_previous.normalized()
		var outgoing := to_next.normalized()
		var turn := incoming.cross(outgoing)
		if absf(turn) < EPSILON:
			result.append(vertex)
			continue
		var desired_radius := outer_radius if turn * winding > 0.0 else inner_radius
		var angle := acos(clampf(to_previous.normalized().dot(to_next.normalized()), -1.0, 1.0))
		if angle < 0.01 or PI - angle < 0.01 or desired_radius < EPSILON:
			result.append(vertex)
			continue
		var tangent_distance := minf(
			desired_radius / tan(angle * 0.5),
			minf(to_previous.length(), to_next.length()) * 0.45
		)
		var radius := tangent_distance * tan(angle * 0.5)
		var bisector := (to_previous.normalized() + to_next.normalized()).normalized()
		var center := vertex + bisector * radius / sin(angle * 0.5)
		var entry := vertex + to_previous.normalized() * tangent_distance
		var exit := vertex + to_next.normalized() * tangent_distance
		var start_angle := (entry - center).angle()
		var end_angle := (exit - center).angle()
		var sweep := wrapf(end_angle - start_angle, -PI, PI)
		if signf(sweep) != signf(turn):
			sweep += TAU * signf(turn)
		var segments := maxi(3, ceili(absf(sweep) * radius / 3.0))
		for sample in range(segments + 1):
			var sample_angle := start_angle + sweep * float(sample) / float(segments)
			result.append(center + Vector2.from_angle(sample_angle) * radius)
	return result


static func upward_edges(points: PackedVector2Array, threshold: float) -> Array[Dictionary]:
	var edges: Array[Dictionary] = []
	var winding := signf(signed_area(points))
	for index in range(points.size()):
		var start := points[index]
		var finish := points[(index + 1) % points.size()]
		var edge := finish - start
		var outward := Vector2(edge.y, -edge.x).normalized() * winding
		if outward.y <= -threshold:
			edges.append({"start": start, "end": finish, "outward": outward})
	return edges


static func bounds(points: PackedVector2Array) -> Rect2:
	var result := Rect2(points[0], Vector2.ZERO)
	for point in points:
		result = result.expand(point)
	return result


static func distance_to_upward_edges(point: Vector2, edges: Array[Dictionary]) -> float:
	var distance := INF
	for edge_data in edges:
		var start: Vector2 = edge_data["start"]
		var finish: Vector2 = edge_data["end"]
		var edge := finish - start
		var projection := (point - start).dot(edge) / edge.length_squared()
		if projection < 0.0 or projection > 1.0:
			continue
		var nearest := start + edge * projection
		if (point - nearest).dot(edge_data["outward"]) < 0.0:
			distance = minf(distance, point.distance_to(nearest))
	return distance
