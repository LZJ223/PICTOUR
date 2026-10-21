## 离线生成 Logo 描边数据，不参与游戏启动；修改 Logo 后用 Godot --headless --script 运行。
## RG：沿闭合轮廓的累计进度（16 位）；B：向内距离 / 64；A：有效距离带。
extends SceneTree

const SOURCE := "res://Texture/Logo/Logo.png"
const OUTPUT := "res://Opening/Logo_Stroke.png"
const DISTANCE_RANGE: float = 64.0

func _initialize() -> void:
	var source := Image.load_from_file(SOURCE)
	if source == null:
		quit(1)
		return
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(source, 0.5)
	var contours: Array[PackedVector2Array] = []
	for polygon in bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, source.get_size()), 0.75):
		# 过滤透明边缘的微小杂点，只描可见外轮廓，不描内部颜色分界。
		if absf(_area(polygon)) >= 64.0:
			contours.append(_start_at_top(polygon))
	contours.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		return a[0].y < b[0].y if not is_equal_approx(a[0].y, b[0].y) else a[0].x < b[0].x
	)
	if contours.is_empty():
		push_error("Logo has no opaque contours")
		quit(1)
		return
	var total_length: float = 0.0
	for contour in contours:
		for index in contour.size():
			total_length += contour[index].distance_to(contour[(index + 1) % contour.size()])
	var size := source.get_size()
	var distances := PackedFloat32Array()
	var progress := PackedFloat32Array()
	distances.resize(size.x * size.y)
	distances.fill(DISTANCE_RANGE * DISTANCE_RANGE)
	progress.resize(distances.size())
	var travelled: float = 0.0
	for contour in contours:
		for index in contour.size():
			var start := contour[index]
			var end := contour[(index + 1) % contour.size()]
			var segment := end - start
			var length: float = segment.length()
			if is_zero_approx(length):
				continue
			var from := Vector2i((start.min(end) - Vector2.ONE * DISTANCE_RANGE).floor()).max(Vector2i.ZERO)
			var to := Vector2i((start.max(end) + Vector2.ONE * DISTANCE_RANGE).ceil()).min(size - Vector2i.ONE)
			for y in range(from.y, to.y + 1):
				for x in range(from.x, to.x + 1):
					var point := Vector2(x + 0.5, y + 0.5)
					var amount: float = clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
					var distance: float = point.distance_squared_to(start + segment * amount)
					var pixel: int = y * size.x + x
					if distance < distances[pixel]:
						distances[pixel] = distance
						progress[pixel] = (travelled + length * amount) / total_length
			travelled += length
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y * 4)
	for index in distances.size():
		# 无数据处保持最大距离，防止线性采样在距离带边界产生第二道虚假描边。
		bytes[index * 4 + 2] = 255
		if distances[index] >= DISTANCE_RANGE * DISTANCE_RANGE:
			continue
		var value: int = clampi(roundi(progress[index] * 65535.0), 0, 65535)
		bytes[index * 4] = value >> 8
		bytes[index * 4 + 1] = value & 255
		bytes[index * 4 + 2] = roundi(sqrt(distances[index]) / DISTANCE_RANGE * 255.0)
		bytes[index * 4 + 3] = 255
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
	var error := image.save_png(OUTPUT)
	print("LOGO_STROKE_BAKE ", JSON.stringify({
		"contours": contours.size(), "length": total_length, "size": [size.x, size.y], "error": error
	}))
	quit(0 if error == OK else 1)

func _area(points: PackedVector2Array) -> float:
	var area: float = 0.0
	for index in points.size():
		area += points[index].cross(points[(index + 1) % points.size()])
	return area * 0.5

func _start_at_top(points: PackedVector2Array) -> PackedVector2Array:
	var first: int = 0
	for index in points.size():
		if points[index].y < points[first].y or (is_equal_approx(points[index].y, points[first].y) and points[index].x < points[first].x):
			first = index
	var rotated := PackedVector2Array()
	for index in points.size():
		rotated.append(points[(first + index) % points.size()])
	return rotated
