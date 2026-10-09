extends RefCounted
## 作者化侧视姿态。关节允许投影缩短，剪影、衣形与节奏优先于固定骨长。

const RUN = preload("res://Component/Player/RunStudy/Authored_Run.gd")
const RUN_STRIDE := 211.2
const WALK_STRIDE := 144.0


static func blend_pose(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var result: Dictionary = {}
	for key in a:
		result[key] = Vector2(a[key]).lerp(b[key], weight) if a[key] is Vector2 else lerpf(float(a[key]), float(b[key]), weight)
	return result


static func curve(phase: float, values: Array) -> float:
	return RUN.curve(phase, values)


static func idle(time: float) -> Dictionary:
	var breath := sin(time * 1.45) * 0.34
	var result := {"hip": Vector2(0, -47), "neck": Vector2(0, -80 + breath), "head": Vector2(0.3, -80 + breath), "chest": Vector2(0, -72 + breath), "waist": Vector2(0, -51), "head_angle": 0.0, "tail": 0.0, "hem": 0.0, "volume": 0.0, "fold": 0.0, "hair": 0.0, "hair_curl": 0.0, "page_open": 0.0, "flutter": breath, "sleeve": 0.0, "neck_width": 1.0}
	for side in ["near", "far"]:
		var near: bool = side == "near"
		result[side + "_knee"] = Vector2(1 if near else -2, -25)
		result[side + "_ankle"] = Vector2(4 if near else -4, 0)
		result[side + "_toe"] = Vector2(8 if near else 0, 0)
		result[side + "_elbow"] = Vector2(-2 if near else 1, -61)
		result[side + "_hand"] = Vector2(-1 if near else 2, -48)
	return result


static func foot(phase: float, running: float) -> Vector2:
	var run := RUN.foot(phase) * Vector2(RUN_STRIDE / RUN.STRIDE, 1.20)
	var p := fposmod(phase, 1.0)
	var stance := 0.34
	var reach := WALK_STRIDE * stance * 0.5
	var walking: Vector2
	if p < stance:
		walking = Vector2(reach - WALK_STRIDE * p, 0)
	else:
		var t := (p - stance) / (1.0 - stance)
		var smooth := t * t * (3.0 - 2.0 * t)
		walking = Vector2(lerpf(-reach, reach, smooth), -sin(t * PI) * 13.0)
	return walking.lerp(run, running)


static func gait(phase: float, running: float) -> Dictionary:
	var walk := idle(0)
	var run := idle(0)
	var walk_bob := curve(phase, [0, 0.9, 0, -1.8, 0, 0.9, 0, -1.8])
	walk.hip += Vector2(0, walk_bob)
	walk.neck += Vector2(2.0, walk_bob * 0.5)
	walk.head = walk.neck + Vector2(0.4, 0)
	walk.chest += Vector2(1, walk_bob * 0.6)
	walk.waist = walk.hip + Vector2(0, -4)
	walk.tail = curve(phase - 0.055, [2, 1, 0, 4, 2, 1, 0, 4])
	walk.hem = curve(phase - 0.04, [0, 1, 3, 5, 0, 1, 3, 5])
	walk.volume = curve(phase, [2, 3, 0, 1, 2, 3, 0, 1])
	walk.fold = curve(phase - 0.08, [0, 1, 4, 2, 0, 1, 4, 2])
	walk.hair = curve(phase - 0.11, [1, 0, 3, 4, 1, 0, 3, 4])
	walk.hair_curl = curve(phase - 0.14, [0, -1, 1, 2, 0, -1, 1, 2])
	walk.page_open = curve(phase - 0.03, [0, -1, 1, 3, 0, -1, 1, 3])
	run.hip = Vector2(curve(phase, [0, -0.4, 0.5, 1.0, 0, -0.4, 0.5, 1.0]), curve(phase, [-48, -46.4, -51.5, -54, -48, -46.4, -51.5, -54]))
	run.neck = Vector2(curve(phase - 0.025, [4.5, 6.0, 8.5, 6.2, 4.5, 6.0, 8.5, 6.2]), curve(phase - 0.035, [-80.5, -79.7, -81.7, -82.6, -80.5, -79.7, -81.7, -82.6]))
	run.head = run.neck + Vector2(0.3, 0)
	run.chest = run.neck + Vector2(-1.0, 9)
	run.waist = run.hip + Vector2(curve(phase, [-1, -1.4, 1.5, 2.5, -1, -1.4, 1.5, 2.5]), -4)
	run.head_angle = deg_to_rad(curve(phase - 0.06, [0.5, 1.0, -0.4, -1, 0.5, 1, -0.4, -1]))
	run.tail = curve(phase - 0.025, [3, 1, 10, 26, 3, 1, 10, 26])
	run.hem = curve(phase - 0.025, [-1, 0, 12, 16, -1, 0, 12, 16])
	run.volume = curve(phase - 0.025, [-1, -2, 7, 3, -1, -2, 7, 3])
	run.fold = curve(phase - 0.04, [0, 1, 4, 12, 0, 1, 4, 12])
	run.page_open = curve(phase - 0.02, [-3, -5, 3, 10, -3, -5, 3, 10])
	run.hair = curve(phase - 0.075, [0, -1, 11, 17, 0, -1, 11, 17])
	run.hair_curl = curve(phase - 0.13, [0, -5, -2, 7, 0, -5, -2, 7])
	run.flutter = curve(phase - 0.13, [2, -1, -3, 4, 2, -1, -3, 4])
	run.sleeve = curve(phase - 0.04, [-2, -1, 4, 5, -2, -1, 4, 5])
	var result := blend_pose(walk, run, running)
	for i in 2:
		var side := "near" if i == 0 else "far"
		var p := phase + i * 0.5
		result[side + "_ankle"] = foot(p, running)
		result[side + "_toe"] = result[side + "_ankle"] + Vector2(4.0, curve(p, [-0.3, 0, 1, 2, 1, 0, -0.6, -0.8]))
		var walk_knee := Vector2(curve(p, [13, 10, -5, 6, 12, 17, 20, 17]), curve(p, [-25, -25, -24, -29, -29, -28, -27, -25]))
		var run_knee := Vector2(curve(p, [14, 10, -7, 8, 16, 17, 16, 15]), curve(p, [-25, -25, -26, -37, -39, -36, -30, -25]))
		result[side + "_knee"] = walk_knee.lerp(run_knee, running)
		var arm_x := curve(p - 0.035, [-3, -4, -2, 3, 5, 4, 0, -2]) * lerpf(0.7, 1.45, running)
		result[side + "_elbow"] = result.chest + Vector2(arm_x - 3, 13)
		result[side + "_hand"] = result.chest + Vector2(arm_x * 1.5 + 1, 23 - absf(arm_x) * running * 0.75)
	return result


static func air(vertical_velocity: float, running: float) -> Dictionary:
	var t := clampf((vertical_velocity + 610.0) / 1250.0, 0, 1)
	var result := idle(0)
	result.hip = Vector2(-1, -48)
	result.waist = result.hip + Vector2(0, -4)
	result.neck = Vector2(3 + running * 2, -81)
	result.head = result.neck + Vector2(0.4, 0)
	result.chest = result.neck + Vector2(-1, 8)
	result.tail = lerpf(8, 17, t)
	result.hem = 11 + sin(t * PI) * 8
	result.volume = 3 + sin(t * PI) * 7
	result.fold = 8 + sin(t * PI) * 7
	result.hair = 6 + running * 4 - t * 2
	result.hair_curl = lerpf(3, -3, t)
	result.page_open = 5 + sin(t * PI) * 5
	result.flutter = lerpf(5, -5, t)
	result.head_angle = deg_to_rad(lerpf(-2, 2, t))
	result.near_knee = Vector2(19 - t * 7, -38 + t * 6)
	result.near_ankle = Vector2(4 - t * 9, -20 + t * 15)
	result.far_knee = Vector2(6 - t * 5, -31 + t * 4)
	result.far_ankle = Vector2(-19 + t * 24, -19 + t * 12)
	result.near_toe = result.near_ankle + Vector2(3, 2)
	result.far_toe = result.far_ankle + Vector2(3, 2)
	result.near_elbow = result.chest + Vector2(-7, 12)
	result.near_hand = result.chest + Vector2(-3, 22)
	result.far_elbow = result.chest + Vector2(4, 10)
	result.far_hand = result.chest + Vector2(8, 15)
	return result
