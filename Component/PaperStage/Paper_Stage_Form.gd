class_name PaperStageForm
extends RefCounted

enum Profile { HERO_TREE, BROKEN_ARCH, SLANT_ROCK, SEED_PLANT, FALLEN_BOUGH }

static func size_for(profile: int) -> Vector2:
	match profile:
		Profile.HERO_TREE: return Vector2(600, 540)
		Profile.BROKEN_ARCH: return Vector2(420, 310)
		Profile.SEED_PLANT: return Vector2(110, 145)
		Profile.FALLEN_BOUGH: return Vector2(360, 155)
	return Vector2(160, 95)

## 平台来自树的切枝、残拱断口和石脊；树叶不作为隐形实体。
static func solids(profile: int, variation: int = 0) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	match profile:
		Profile.HERO_TREE:
			result.append(PackedVector2Array([
				Vector2(-48,0),Vector2(-25,-76),Vector2(-43,-135),Vector2(-95,-172),
				Vector2(-154,-172),Vector2(-163,-188),Vector2(-94,-188),Vector2(-72,-176),
				Vector2(-124,-250),Vector2(-175,-271),Vector2(-237,-271),Vector2(-245,-288),
				Vector2(-173,-288),Vector2(-133,-267),Vector2(-159,-340),Vector2(-143,-357),
				Vector2(-98,-279),Vector2(-38,-235),Vector2(-20,-290),Vector2(7,-316),
				Vector2(48,-316),Vector2(67,-336),Vector2(75,-330),Vector2(60,-299),
				Vector2(20,-299),Vector2(9,-263),Vector2(36,-205),Vector2(77,-250),
				Vector2(93,-312),Vector2(104,-306),Vector2(96,-241),Vector2(124,-256),
				Vector2(179,-256),Vector2(171,-240),Vector2(120,-239),Vector2(69,-187),
				Vector2(82,-118),Vector2(112,-47),Vector2(128,0),Vector2(57,-8),Vector2(27,0)
			]))
		Profile.BROKEN_ARCH:
			result.append(PackedVector2Array([
				Vector2(-210,0),Vector2(-202,-53),Vector2(-210,-82),Vector2(-173,-92),
				Vector2(-167,-114),Vector2(-196,-114),Vector2(-191,-135),Vector2(-146,-135),
				Vector2(-153,-206),Vector2(-127,-218),Vector2(-139,-266),Vector2(-112,-272),
				Vector2(-96,-310),Vector2(-33,-310),Vector2(-39,-290),Vector2(11,-285),
				Vector2(24,-276),Vector2(14,-251),Vector2(43,-235),Vector2(55,-220),
				Vector2(114,-220),Vector2(119,-205),Vector2(104,-192),Vector2(130,-164),
				Vector2(171,-164),Vector2(171,-145),Vector2(160,-132),Vector2(192,-97),
				Vector2(185,-79),Vector2(209,-78),Vector2(202,-12),Vector2(210,0),
				Vector2(137,0),Vector2(126,-121),Vector2(98,-161),Vector2(61,-182),
				Vector2(16,-192),Vector2(-24,-184),Vector2(-63,-160),Vector2(-92,-117),
				Vector2(-111,-71),Vector2(-111,0)
			]))
		Profile.SLANT_ROCK:
			if variation % 2 == 0:
				result.append(PackedVector2Array([Vector2(-80,0),Vector2(-74,-38),Vector2(-40,-95),Vector2(28,-95),Vector2(66,-76),Vector2(80,-24),Vector2(65,-2),Vector2(31,0),Vector2(2,-6),Vector2(-28,0)]))
			else:
				result.append(PackedVector2Array([Vector2(-80,0),Vector2(-73,-18),Vector2(-54,-48),Vector2(-24,-53),Vector2(-14,-95),Vector2(57,-95),Vector2(47,-64),Vector2(78,-40),Vector2(69,-2),Vector2(19,-9),Vector2(-12,0)]))
		Profile.FALLEN_BOUGH:
			result.append(PackedVector2Array([
				Vector2(-180,0),Vector2(-168,-25),Vector2(-122,-32),Vector2(-88,-68),
				Vector2(-32,-68),Vector2(2,-114),Vector2(49,-114),Vector2(74,-142),
				Vector2(140,-142),Vector2(150,-155),Vector2(162,-144),Vector2(145,-121),
				Vector2(89,-123),Vector2(65,-89),Vector2(120,-74),Vector2(173,-81),
				Vector2(180,-65),Vector2(114,-56),Vector2(60,-67),Vector2(16,-42),
				Vector2(-38,-49),Vector2(-66,-22),Vector2(-129,-6)
			]))
	return result

static func foliage(profile: int, variation: int = 0) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if profile == Profile.HERO_TREE:
		result.append(fan(Vector2(-145,-347),196,-3.0,-2.43,11))
		result.append(fan(Vector2(-145,-347),186,-2.32,-1.82,11))
		result.append(fan(Vector2(-145,-347),191,-1.74,-1.22,11))
		result.append(fan(Vector2(-145,-347),144,-1.12,-0.72,9))
		result.append(fan(Vector2(-173,-282),112,2.55,3.35,9))
		result.append(fan(Vector2(98,-303),168,-2.12,-1.61,9))
		result.append(fan(Vector2(98,-303),154,-1.52,-0.95,9))
		result.append(fan(Vector2(98,-303),170,-0.83,-0.24,10))
		result.append(fan(Vector2(98,-303),118,-0.11,0.51,9))
	elif profile == Profile.SEED_PLANT:
		result.append(fan(Vector2(-18,-84),43,-2.7,-0.4,10))
		result.append(fan(Vector2(27,-116),31,-2.8,-0.33,9))
		if variation % 2 == 1:
			result.append(fan(Vector2(11,-50),24,-0.8,0.7,8))
		else:
			result.append(fan(Vector2(-18,-43),28,-2.9,-1.55,8))
	return result

static func fan(center: Vector2, radius: float, begin: float, end: float, steps: int) -> PackedVector2Array:
	var points := PackedVector2Array([center])
	for i in range(steps+1):
		var angle := lerpf(begin,end,float(i)/steps)
		var ragged_radius := radius * (1.0 + sin(i*2.72+radius)*0.015)
		points.append(center + Vector2.from_angle(angle)*ragged_radius)
	return points
