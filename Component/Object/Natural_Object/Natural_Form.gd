class_name NaturalForm
extends RefCounted

## 四种可搬景物的父轮廓；坐标为根脚锚点，上方为负 Y。
enum Kind { ROCK, SHORT_TREE, ARCH, BRANCH, PLANT }

static func nominal_size(kind: int) -> Vector2:
	match kind:
		Kind.SHORT_TREE: return Vector2(260, 250)
		Kind.ARCH: return Vector2(380, 240)
		Kind.BRANCH: return Vector2(360, 130)
		Kind.PLANT: return Vector2(80, 110)
	return Vector2(140, 90)

static func solid_polygon(kind: int, variation: int = 0) -> PackedVector2Array:
	match kind:
		Kind.SHORT_TREE:
			return PackedVector2Array([
				Vector2(-60, 0), Vector2(-44, -70), Vector2(-82, -96), Vector2(-132, -96),
				Vector2(-132, -116), Vector2(-78, -116), Vector2(-32, -85), Vector2(-24, -160),
				Vector2(5, -194), Vector2(68, -194), Vector2(87, -218), Vector2(83, -250),
				Vector2(137, -250), Vector2(137, -233), Vector2(110, -233), Vector2(99, -196),
				Vector2(74, -176), Vector2(18, -176), Vector2(15, -147), Vector2(47, -121),
				Vector2(65, -117), Vector2(65, -102), Vector2(35, -102), Vector2(24, -119),
				Vector2(39, -56), Vector2(73, 0), Vector2(40, -6), Vector2(8, 0),
			])
		Kind.ARCH:
			return PackedVector2Array([
				Vector2(-190, 0), Vector2(-181, -44), Vector2(-190, -85), Vector2(-136, -85),
				Vector2(-142, -160), Vector2(-88, -160), Vector2(-110, -220), Vector2(-90, -240),
				Vector2(88, -240), Vector2(110, -222), Vector2(88, -160), Vector2(142, -160),
				Vector2(136, -85), Vector2(190, -85), Vector2(188, -40), Vector2(190, 0),
				Vector2(126, 0), Vector2(120, -110), Vector2(92, -157), Vector2(45, -172),
				Vector2(-48, -172), Vector2(-94, -156), Vector2(-122, -110), Vector2(-126, 0),
			])
		Kind.BRANCH:
			return PackedVector2Array([
				Vector2(-180, 0), Vector2(-166, -35), Vector2(-82, -35), Vector2(-55, -82),
				Vector2(38, -82), Vector2(71, -130), Vector2(156, -130), Vector2(169, -108),
				Vector2(133, -108), Vector2(95, -52), Vector2(171, -65), Vector2(180, -47),
				Vector2(92, -27), Vector2(42, -18), Vector2(-42, -16), Vector2(-118, -3),
			])
		Kind.PLANT:
			return PackedVector2Array()
	if variation % 2 == 1:
		return PackedVector2Array([Vector2(-70, 0), Vector2(-61, -49), Vector2(-49, -90), Vector2(49, -90), Vector2(67, -69), Vector2(58, -35), Vector2(70, -9), Vector2(28, 0), Vector2(7, -5), Vector2(-31, 0)])
	return PackedVector2Array([Vector2(-70, 0), Vector2(-62, -43), Vector2(-49, -90), Vector2(49, -90), Vector2(67, -62), Vector2(61, -32), Vector2(70, -5), Vector2(27, 0), Vector2(-4, -7), Vector2(-38, 0)])

static func leaves(kind: int, variation: int = 0) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if kind == Kind.SHORT_TREE:
		result.append(_fan(Vector2(-98, -107), 45, -PI * 0.96, -PI * 0.36))
		result.append(_fan(Vector2(40, -185), 60, -PI * 0.7, -PI * 0.07))
		result.append(_fan(Vector2(105, -239), 34, -PI * 0.9, -PI * 0.1))
		if variation % 2 == 1:
			result.append(_fan(Vector2(-60, -107), 37, -PI * 1.08, -PI * 0.72))
	elif kind == Kind.PLANT:
		result.append(_fan(Vector2(0, -62), 40, -PI * 0.94, -PI * 0.06))
		result.append(_fan(Vector2(-5, -31), 25, -PI * 1.13, -PI * 0.77))
		result.append(_fan(Vector2(8, -42), 29, -PI * 0.31, PI * 0.06))
	return result

static func pick_polygons(kind: int, variation: int = 0) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var solid := solid_polygon(kind, variation)
	if not solid.is_empty():
		result.append(solid)
	result.append_array(leaves(kind, variation))
	if kind == Kind.PLANT:
		result.append(PackedVector2Array([Vector2(-5, 0), Vector2(-6, -76), Vector2(1, -78), Vector2(5, 0)]))
	return result

static func asset_name(kind: int, variation: int = 0) -> String:
	var names: Array[String] = ["Rock", "Short_Tree", "Arch", "Branch", "Plant"]
	return "%s_%02d" % [names[clampi(kind, 0, 4)], variation % 2 + 1]

static func _fan(origin: Vector2, radius: float, start: float, end: float) -> PackedVector2Array:
	var points := PackedVector2Array([origin])
	for index in range(11):
		var angle := lerpf(start, end, float(index) / 10.0)
		points.append(origin + Vector2(cos(angle), sin(angle)) * radius)
	return points
