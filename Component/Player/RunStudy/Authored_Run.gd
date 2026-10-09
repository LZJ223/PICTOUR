extends RefCounted
## 独立候选：先设计姿态和timing，再以接触窗约束足点。不是量产控制器。

const PERIOD := 0.64
const SPEED := 320.0
const STRIDE := PERIOD * SPEED
const STANCE := 0.20
const REACH := STRIDE * STANCE * 0.5
const TIMES := [0.0, 0.08, 0.20, 0.35, 0.50, 0.58, 0.70, 0.85]


static func curve(t: float, values: Array) -> float:
	var phase := fposmod(t, 1.0)
	var index := 7
	for i in 7:
		if phase < TIMES[i + 1]:
			index = i
			break
	var left: float = TIMES[index]
	var right: float = TIMES[index + 1] if index < 7 else 1.0
	var u := (phase - left) / (right - left)
	var a: float = values[posmod(index - 1, 8)]
	var b: float = values[index]
	var c: float = values[(index + 1) % 8]
	var d: float = values[(index + 2) % 8]
	var previous_time: float = TIMES[index - 1] if index > 0 else TIMES[7] - 1.0
	var following_time: float = TIMES[index + 2] if index < 6 else TIMES[(index + 2) % 8] + 1.0
	var m0: float = (c - a) / (right - previous_time)
	var m1: float = (d - b) / (following_time - left)
	var span := right - left
	return b * (2 * u * u * u - 3 * u * u + 1) + m0 * span * (u * u * u - 2 * u * u + u) + c * (-2 * u * u * u + 3 * u * u) + m1 * span * (u * u * u - u * u)


static func foot(phase: float) -> Vector2:
	var t := fposmod(phase, 1.0)
	if t < STANCE:
		return Vector2(REACH - STRIDE * t, 0)
	# 收膝发生于支撑之后，后跟先折回衣内，随后展开小腿准备下一步。
	var times := [0.20, 0.35, 0.50, 0.65, 0.82, 1.0]
	var points := [Vector2(-REACH, 0), Vector2(-20, -24), Vector2(-4, -27), Vector2(14, -22), Vector2(27, -9), Vector2(REACH, 0)]
	var velocities := [Vector2(-STRIDE, -35), Vector2(70, -120), Vector2(112, 0), Vector2(100, 60), Vector2(0, 80), Vector2(-STRIDE, 0)]
	var i := 0
	for next in range(1, times.size()):
		if t <= float(times[next]):
			i = next - 1
			break
	var span: float = float(times[i + 1]) - float(times[i])
	var u: float = (t - float(times[i])) / span
	return Vector2(points[i]) * (2 * u * u * u - 3 * u * u + 1) + Vector2(velocities[i]) * span * (u * u * u - 2 * u * u + u) + Vector2(points[i + 1]) * (-2 * u * u * u + 3 * u * u) + Vector2(velocities[i + 1]) * span * (u * u * u - u * u)


static func sample(phase: float) -> Dictionary:
	var hip := Vector2(curve(phase, [0, 0.8, 0, -0.8, 0, 0.8, 0, -0.8]), curve(phase, [-49, -46.5, -50.5, -53, -49, -46.5, -50.5, -53]))
	var chest := hip + Vector2(curve(phase - 0.025, [2.5, 3.2, 2.5, 1.2, 2.5, 3.2, 2.5, 1.2]), -25)
	var neck := chest + Vector2(1.3, -7)
	# 头部比身体稍迟地沉浮，避免将头、胸、髋绑成同一块刚板。
	neck.y = curve(phase - 0.035, [-49, -47.6, -50.2, -51.4, -49, -47.6, -50.2, -51.4]) - 32
	var result := {"hip": hip, "chest": chest, "neck": neck, "head": neck + Vector2(1, -8), "waist": hip + Vector2(0, -1.8), "lean": deg_to_rad(curve(phase, [3, 4.5, 2.5, 1.2, 3, 4.5, 2.5, 1.2])), "head_lean": deg_to_rad(curve(phase - 0.035, [0, 1.5, -1, -2, 0, 1.5, -1, -2])), "hem": curve(phase, [0, 2, 6, 4, 0, 2, 6, 4]), "hair": curve(phase - 0.1, [1, 3, 6, 3, 1, 3, 6, 3]), "front_lift": curve(phase - 0.045, [0, 1, 4, 2, 0, 1, 4, 2]), "rear_lift": curve(phase - 0.07, [5, 3, 10, 14, 5, 3, 10, 14]), "scarf_bend": curve(phase - 0.12, [4, 8, 2, -3, 4, 8, 2, -3]), "volume": curve(phase, [5, 4, 1, 3, 5, 4, 1, 3]), "spine": curve(phase - 0.04, [1, -2, 0, 2, 1, -2, 0, 2])}
	for i in 2:
		var side := "near" if i == 0 else "far"
		var p := phase + i * 0.5
		var ankle := foot(p)
		# 膝的朝向与时序直接来自关键姿态；没有从足点反解整段动作。
		var knee := Vector2(curve(p, [14, 12, -7, 8, 18, 21, 21, 17]), curve(p, [-24, -23, -24, -32, -32, -31, -26, -24]))
		result[side + "_hip"] = hip
		result[side + "_knee"] = knee
		result[side + "_ankle"] = ankle
		result[side + "_toe"] = ankle + Vector2(4.0, curve(p, [-0.6, 0, 1.3, 2.0, 1.2, 0.3, -0.6, -1.0]))
		var shoulder := chest + Vector2(-3.5 if i == 0 else 1, 0)
		var hand := shoulder + Vector2(curve(p, [-6, -7, -3, 3, 7, 6, 2, -3]), curve(p, [23, 23, 22, 20, 21, 22, 23, 24]))
		result[side + "_shoulder"] = shoulder
		result[side + "_elbow"] = shoulder.lerp(hand, 0.52) + Vector2(-2, 0)
		result[side + "_hand"] = hand
	return result
