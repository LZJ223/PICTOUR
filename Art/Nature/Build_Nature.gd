extends SceneTree

## 原创干墨绘本父素材，透明 PNG 与碰撞共享 NaturalForm 轮廓。
const FORM = preload("res://Component/Object/Natural_Object/Natural_Form.gd")
const ROOT := "res://Art/Nature/"
const PLUM := "#514052"
const DARK := "#3F3448"
const ROSE := "#B49197"
const PAPER := "#F2E7D0"
const SAGE := "#A4AD95"
const BLEED := 24

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "SVG")
	DirAccess.make_dir_recursive_absolute(ROOT + "PNG")
	for kind in range(5):
		for variation in range(2):
			_build(kind, variation)
	print("NATURE_SPRITES: 10 张原创干墨父素材已生成；真实形状与源轮廓一致。")
	quit()

func _build(kind: int, variation: int) -> void:
	var size: Vector2 = FORM.nominal_size(kind)
	var canvas := size + Vector2(BLEED * 2, BLEED * 2)
	var name: String = FORM.asset_name(kind, variation)
	var polygons: Array[PackedVector2Array] = FORM.pick_polygons(kind, variation)
	var solid: PackedVector2Array = FORM.solid_polygon(kind, variation)
	var content := ""
	if not solid.is_empty():
		content += _poly(solid, PLUM)
	match kind:
		0:
			content += _poly(PackedVector2Array([Vector2(-49,-90),Vector2(49,-90),Vector2(43,-74),Vector2(-40,-72)]), ROSE, 0.46)
			content += _poly(PackedVector2Array([Vector2(-49,-88),Vector2(-41,-72),Vector2(-33,-16),Vector2(-60,-7),Vector2(-61,-43)]), "#6C5368", 0.65)
			content += _poly(PackedVector2Array([Vector2(44,-70),Vector2(64,-60),Vector2(59,-34),Vector2(65,-9),Vector2(31,-10)]), DARK, 0.5)
			content += _path("M -39 -67 L -25 -46 L -30 -27 M 22 -39 L 15 -25 L 29 -13", PAPER, 0.8, 0.16)
		1:
			content += _poly(PackedVector2Array([Vector2(5,-194),Vector2(68,-194),Vector2(74,-176),Vector2(18,-176),Vector2(15,-147),Vector2(24,-119),Vector2(39,-56),Vector2(73,0),Vector2(32,-10),Vector2(-6,-95)]), DARK, 0.52)
			content += _path("M -18 -144 L -9 -105 L 4 -36 M 102 -232 L 94 -212 M -45 -65 L -4 -28", ROSE, 2.5, 0.47)
			content += _fans(kind, variation)
			content += _path("M -46 -2 L -44 -31 L -33 -48 M -44 -24 L -57 -31 M -44 -13 L -32 -22", ROSE, 1.3, 0.5)
		2:
			content += _poly(PackedVector2Array([Vector2(-90,-240),Vector2(88,-240),Vector2(108,-224),Vector2(79,-211),Vector2(-87,-214),Vector2(-108,-222)]), ROSE, 0.45)
			content += _poly(PackedVector2Array([Vector2(-190,-85),Vector2(-136,-85),Vector2(-126,0),Vector2(-169,-5)]), "#6B5269", 0.55)
			content += _poly(PackedVector2Array([Vector2(88,-160),Vector2(142,-160),Vector2(136,-85),Vector2(190,-85),Vector2(190,0),Vector2(153,-8)]), DARK, 0.65)
			content += _path("M -154 -8 L -154 -71 L -146 -107 M 161 -16 L 156 -51 M -110 -206 L -99 -197 M 85 -206 L 103 -196", PAPER, 1.2, 0.2)
		3:
			content += _poly(PackedVector2Array([Vector2(-166,-35),Vector2(-82,-35),Vector2(-55,-82),Vector2(38,-82),Vector2(71,-130),Vector2(156,-130),Vector2(162,-116),Vector2(80,-115),Vector2(48,-67),Vector2(-42,-68),Vector2(-70,-22),Vector2(-165,-21)]), ROSE, 0.33)
			content += _path("M -156 -16 Q -53 -37 14 -32 Q 71 -35 150 -59 M -16 -40 L -3 -56 M 99 -86 L 119 -100", PAPER, 1.3, 0.2)
		4:
			content += _path("M 0 0 L -1 -67 M -1 -25 L -6 -34 M 0 -27 L 10 -46", DARK, 5, 1.0)
			content += _fans(kind, variation)
	var grain := _grain(polygons, kind * 71 + variation * 13 + 907, size)
	content += grain
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%.0f %.0f %.0f %.0f">%s</svg>' % [int(canvas.x), int(canvas.y), -size.x / 2 - BLEED, -size.y - BLEED, canvas.x, canvas.y, content]
	var file := FileAccess.open(ROOT + "SVG/" + name + ".svg", FileAccess.WRITE)
	file.store_string(svg + "\n")
	var image := Image.new()
	assert(image.load_svg_from_string(svg, 2.0) == OK, name + " SVG 生成失败")
	assert(image.save_png(ROOT + "PNG/" + name + ".png") == OK)

func _fans(kind: int, variation: int) -> String:
	var output := ""
	var index := 0
	for points in FORM.leaves(kind, variation):
		output += _poly(points, ROSE if index % 2 == variation else DARK, 1.0)
		for ray_index in range(1, points.size()):
			var origin: Vector2 = points[0]
			var edge: Vector2 = points[ray_index]
			var start := origin.lerp(edge, 0.20)
			var end := origin.lerp(edge, 0.95)
			output += _path("M %.1f %.1f L %.1f %.1f" % [start.x, start.y, end.x, end.y], PAPER, 0.7, 0.33)
		index += 1
	return output

func _grain(polygons: Array[PackedVector2Array], seed_value: int, size: Vector2) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var output := ""
	for index in range(int(size.x * size.y * 0.032)):
		var point := Vector2(rng.randf_range(-size.x * 0.55, size.x * 0.55), rng.randf_range(-size.y - 15, 5))
		var inside := false
		for polygon in polygons:
			if Geometry2D.is_point_in_polygon(point, polygon):
				inside = true
				break
		if not inside:
			continue
		var radius := rng.randf_range(0.08, 0.7)
		var opacity := rng.randf_range(0.04, 0.26)
		if index % 7 == 0:
			output += '<path d="M %.2f %.2f l %.2f %.2f" fill="none" stroke="%s" stroke-width="%.2f" opacity="%.2f"/>' % [point.x, point.y, rng.randf_range(0.3, 4.5), rng.randf_range(-1.4, 1.2), PAPER, radius, opacity]
		else:
			output += '<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s" opacity="%.2f"/>' % [point.x, point.y, radius, PAPER, opacity]
	return output

func _poly(points: PackedVector2Array, color: String, opacity: float = 1.0) -> String:
	var coordinates := ""
	for point in points:
		coordinates += "%.1f,%.1f " % [point.x, point.y]
	return '<polygon points="%s" fill="%s" opacity="%.2f"/>' % [coordinates, color, opacity]

func _path(path: String, color: String, width: float = 1.0, opacity: float = 1.0) -> String:
	return '<path d="%s" fill="none" stroke="%s" stroke-width="%.2f" opacity="%.2f" stroke-linecap="round" stroke-linejoin="round"/>' % [path, color, width, opacity]
