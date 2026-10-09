extends RefCounted
## 以脚底为物理基准的侧视双骨姿态。坐标是 2 倍像素精灵源坐标。

const CELL := Vector2i(256, 256)
const FOOT_Y := 236.0
const UPPER_LEG := 42.0
const LOWER_LEG := 42.0
const WALK_STRIDE := 96.0
const RUN_STRIDE := 160.0
const WALK_STANCE := 0.51
const RUN_STANCE := 0.30
const STATES: Array[StringName] = [&"idle", &"walk", &"run", &"rise", &"fall", &"dash", &"takeoff", &"land", &"brake", &"turn"]
const COUNTS: Array[int] = [8, 16, 16, 6, 6, 4, 4, 4, 4, 4]


static func stride(action: StringName) -> float:
	return RUN_STRIDE if action == &"run" else WALK_STRIDE


static func foot_path(phase: float, running: bool) -> Vector2:
	phase = fposmod(phase, 1.0)
	var duty: float = RUN_STANCE if running else WALK_STANCE
	var distance: float = RUN_STRIDE if running else WALK_STRIDE
	# world distance * 2 gives source distance. A planted foot moves backwards
	# exactly as fast as the root advances, rather than following a sine wave.
	var reach: float = distance * duty
	if phase < duty:
		return Vector2(reach - 2.0 * distance * phase, FOOT_Y)
	var swing: float = (phase - duty) / (1.0 - duty)
	var recovery: float = smoothstep(0.0, 1.0, swing)
	var lift: float = 54.0 if running else 23.0
	return Vector2(lerpf(-reach, reach, recovery), FOOT_Y - pow(sin(PI * swing), 1.15) * lift)


static func knee(hip: Vector2, foot: Vector2) -> Vector2:
	var difference := foot - hip
	var distance := clampf(difference.length(), 0.01, UPPER_LEG + LOWER_LEG - 0.001)
	var forward := difference.normalized()
	var along := (UPPER_LEG * UPPER_LEG - LOWER_LEG * LOWER_LEG + distance * distance) / (2.0 * distance)
	var bend := sqrt(maxf(0.0, UPPER_LEG * UPPER_LEG - along * along))
	# The knee bends forwards in the sagittal plane for BOTH legs.
	var side := Vector2(forward.y, -forward.x)
	return hip + forward * along + side * bend


static func pose(action: StringName, phase: float) -> Dictionary:
	phase = clampf(phase, 0.0, 0.999999)
	var lean: float = 0.0
	var hip_y := 169.0
	var foot_near := Vector2(134, FOOT_Y)
	var foot_far := Vector2(122, FOOT_Y)
	var shoulder_swing := 0.0
	var body_lift := 0.0
	if action == &"walk" or action == &"run":
		var running: bool = action == &"run"
		var contact_phase: float = fposmod(phase * 2.0, 1.0)
		# Compression in stance, rising into the aerial interval; never y-shift feet.
		if running:
			var half_phase := fposmod(phase, 0.5)
			body_lift = 5.0 * sin(PI * half_phase / RUN_STANCE) if half_phase < RUN_STANCE else -11.0 * sin(PI * (half_phase - RUN_STANCE) / (0.5 - RUN_STANCE))
			hip_y = 172.0 + body_lift
		else:
			body_lift = -2.4 * (1.0 - cos(contact_phase * TAU))
			hip_y = 170.0 + body_lift
		lean = 14.0 if running else 4.0
		foot_near = foot_path(phase, running) + Vector2(128, 0)
		foot_far = foot_path(fposmod(phase + 0.5, 1.0), running) + Vector2(128, 0)
		shoulder_swing = -(27.0 if running else 17.0) * cos(phase * TAU)
	elif action == &"idle":
		body_lift = sin(phase * TAU) * 0.9
		hip_y = 153.0 + body_lift
	elif action == &"brake" or action == &"turn":
		lean = lerpf(-11.0, -2.0, phase)
		hip_y += 5.0 * sin(PI * phase)
		foot_near = Vector2(158 - 18 * phase, FOOT_Y)
		foot_far = Vector2(105 + 17 * phase, FOOT_Y)
		shoulder_swing = -18 * (1.0 - phase)
	elif action == &"land":
		hip_y += 12.0 * (1.0 - phase)
		foot_near.x = 151
		foot_far.x = 111
		lean = 7.0 * (1.0 - phase)
	elif action == &"dash":
		lean = 23.0
		hip_y += 8.0
		foot_near = Vector2(172 - phase * 8, 231)
		foot_far = Vector2(75 + phase * 10, 223)
		shoulder_swing = 27
	elif action == &"rise" or action == &"takeoff":
		lean = 11.0
		hip_y -= 3.0
		foot_near = Vector2(151 - 8 * phase, 215 + 7 * phase)
		foot_far = Vector2(86 + 10 * phase, 226 - 9 * phase)
		shoulder_swing = -26
	elif action == &"fall":
		lean = 3.0
		foot_near = Vector2(146, 229 + 6 * phase)
		foot_far = Vector2(110, 215 + 16 * phase)
		shoulder_swing = -19
	var hip := Vector2(128, hip_y)
	var shoulder := hip + Vector2(lean, -55)
	var head := shoulder + Vector2(4.0 + lean * 0.15, -33)
	# Hip origins overlap in side view; far limbs are distinguished by ink value.
	var far_hip := hip + Vector2(-2, 0)
	var near_hip := hip + Vector2(2, 0)
	var near_elbow := shoulder + Vector2(shoulder_swing * 0.72, 22)
	var near_hand := near_elbow + Vector2(14 + shoulder_swing * 0.34, 17 - absf(shoulder_swing) * 0.35)
	var far_elbow := shoulder + Vector2(-shoulder_swing * 0.72 - 3, 22)
	var far_hand := far_elbow + Vector2(12 - shoulder_swing * 0.34, 17 - absf(shoulder_swing) * 0.35)
	return {"hip": hip, "near_hip": near_hip, "far_hip": far_hip,
		"near_foot": foot_near, "far_foot": foot_far,
		"near_knee": knee(near_hip, foot_near), "far_knee": knee(far_hip, foot_far),
		"shoulder": shoulder, "head": head, "near_elbow": near_elbow, "near_hand": near_hand,
		"far_elbow": far_elbow, "far_hand": far_hand,
		"collar": shoulder + Vector2(-9, -6), "lean": lean}
