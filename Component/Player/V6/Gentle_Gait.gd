extends RefCounted
## 分件皮肤共用的动作结构。近/远腿身份固定，脚点在支撑期保留世界位置。

const WALK_STRIDE := 90.0
const RUN_STRIDE := 124.0
const THIGH := 28.0
const SHIN := 28.0
var phase := 0.0
var cycle := 0.0
var legs: Array[Dictionary] = [{}, {}]
var planted_error := 0.0
var stance_flags := [false, false]
var world_feet := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])


func reset() -> void:
	legs = [{}, {}]
	planted_error = 0.0


func advance(distance: float, blend: float, tangent: Vector2 = Vector2.RIGHT) -> void:
	cycle += distance / (lerpf(WALK_STRIDE, RUN_STRIDE, blend) * slope_stride(tangent))
	phase = fposmod(cycle, 1.0)


func slope_stride(tangent: Vector2) -> float:
	return 1.0 - clampf(absf(tangent.y) * 0.38, 0.0, 0.18)


func swing_progress(u: float) -> float:
	# 短促但平滑的离地加速，随后匀速收脚；端点位置/速度/加速度连续。
	var a := 0.16
	if u > 1.0 - a:
		return 1.0 - swing_progress(1.0 - u)
	if u < a:
		var x := u / a
		return a * (x * x * x - 0.5 * x * x * x * x) / (1.0 - a)
	return (u - a * 0.5) / (1.0 - a)


func smooth01(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)


func periodic(phase_value: float, keys: Array) -> float:
	var value := fposmod(phase_value, 1.0) * keys.size()
	var index := int(value)
	var t := value - index
	var a: float = keys[posmod(index - 1, keys.size())]
	var b: float = keys[index]
	var c: float = keys[(index + 1) % keys.size()]
	var d: float = keys[(index + 2) % keys.size()]
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t)


func knee(hip: Vector2, foot: Vector2, direction: float) -> Vector2:
	var gap := foot - hip
	var length := clampf(gap.length(), 0.001, THIGH + SHIN - 0.001)
	var axis := gap.normalized()
	var along := (THIGH * THIGH - SHIN * SHIN + length * length) / (2.0 * length)
	var bend := sqrt(maxf(0.0, THIGH * THIGH - along * along))
	return hip + axis * along + Vector2(axis.y, -axis.x) * bend * direction


func sample(root: Vector2, facing: int, blend: float, activity: float, supported: bool, floor_y: float, body_offset: float, ground_query: Callable, tangent: Vector2 = Vector2.RIGHT) -> Dictionary:
	var length := lerpf(WALK_STRIDE, RUN_STRIDE, blend) * slope_stride(tangent)
	var incline := clampf((absf(tangent.y) - 0.08) / 0.40, 0.0, 1.0)
	var stance := lerpf(0.55 - incline * 0.07, 0.34 - incline * 0.07, blend)
	var horizontal_length := length * tangent.x
	var reach := horizontal_length * stance * 0.5
	var hip_y := -50.0 + periodic(phase, [0.0, 0.3, -1.3, -0.5, 0.0, 0.3, -1.3, -0.5]) * activity
	var hip := Vector2(0.0, floor_y + hip_y + body_offset)
	var lean := deg_to_rad(lerpf(0.15, 1.4, blend)) * activity * facing
	var chest := hip + Vector2(sin(lean) * 24.0, -24.0)
	var neck := chest + Vector2(1.5 * facing, -7.0)
	var head := neck + Vector2(1.0 * facing, -8.0)
	var result: Dictionary = {"hip": hip, "chest": chest, "neck": neck, "head": head, "lean": lean, "hem": 0.0, "hair": 0.0}
	for side in 2:
		var name := "near" if side == 0 else "far"
		var shifted := cycle + side * 0.5
		var leg_phase := fposmod(shifted, 1.0)
		var contact := false
		var id := int(floorf(shifted))
		var state: Dictionary = legs[side]
		var nominal := root + Vector2((reach - leg_phase * horizontal_length) * facing, floor_y)
		if state.is_empty() or int(state.get("id", -999999)) != id:
			var hit: Dictionary = ground_query.call(nominal.x)
			var base_y: float = float(hit.position.y) if not hit.is_empty() else root.y + floor_y
			state = {"id": id, "anchor": Vector2(nominal.x, base_y), "last_contact": false, "contact_end": stance}
		state.contact_end = minf(float(state.contact_end), stance)
		var contact_end: float = float(state.contact_end)
		contact = leg_phase < contact_end and supported and activity > 0.05
		var foot: Vector2
		if contact:
			foot = state.anchor
			if bool(state.last_contact) and bool(state.get("full_activity", false)) and activity > 0.999:
				planted_error = maxf(planted_error, foot.distance_to(world_feet[side]))
		else:
			var u := clampf((leg_phase - contact_end) / (1.0 - contact_end), 0.0, 1.0)
			var destination_x: float = root.x + facing * ((1.0 - leg_phase) * horizontal_length + reach)
			var hit: Dictionary = ground_query.call(destination_x)
			var destination_y: float = float(hit.position.y) if not hit.is_empty() else float(state.anchor.y)
			var lift := lerpf(3.0, 5.0, blend) * 64.0 * pow(u, 3.0) * pow(1.0 - u, 3.0)
			foot = Vector2(state.anchor).lerp(Vector2(destination_x, destination_y), swing_progress(u)) - Vector2(0, lift)
		var resting := root + Vector2((-3.0 if side == 0 else 3.0) * facing, floor_y)
		var resting_hit: Dictionary = ground_query.call(resting.x)
		if not resting_hit.is_empty():
			resting.y = resting_hit.position.y
		foot = resting.lerp(foot, activity)
		if not supported:
			foot = root + Vector2((-8.0 if side == 0 else 9.0) * facing, -5.0 if side == 0 else -9.0)
		if supported and not contact and activity > 0.99:
			# 摆动脚允许柔和提跟让开坡面；不能为了低抬脚而拉长腿或压低整个人。
			var relative := foot - root - hip
			var reach_y := sqrt(maxf(0.001, pow(THIGH + SHIN - 0.8, 2.0) - relative.x * relative.x))
			foot.y = minf(foot.y, root.y + hip.y + reach_y)
		stance_flags[side] = contact
		world_feet[side] = foot
		state.last_contact = contact
		state.full_activity = activity > 0.999
		legs[side] = state
		var ankle := foot - root
		result[name + "_hip"] = hip
		result[name + "_knee"] = knee(hip, ankle, facing)
		result[name + "_ankle"] = ankle
		var roll := 0.0
		if contact:
			roll = lerpf(-0.09, 0.12, smooth01(leg_phase / contact_end))
		result[name + "_toe"] = ankle + Vector2(4.3 * facing, 4.3 * sin(roll))
		var swing := periodic(phase + side * 0.5, [-1.0, 0.0, 1.0, 0.0]) * lerpf(5.0, 7.5, blend) * activity
		var shoulder := chest + Vector2((-4.5 if side == 0 else 0.5) * facing, -0.5)
		# 手保持髋上方附近，不举拳、不做大幅前冲摆臂。
		var hand := shoulder + Vector2(swing * facing, 24.0 - absf(swing) * 0.09)
		var elbow := shoulder.lerp(hand, 0.53) + Vector2(-2.0 * facing, 0)
		result[name + "_shoulder"] = shoulder
		result[name + "_elbow"] = elbow
		result[name + "_hand"] = hand
	# 坡面以真实足点反解可达髋高，禁止拉长小腿掩盖坡度误差。
	# 平地保持1.6px重心变化；坡面会按踏面高差有限屈腿。
	var corrected_hip := hip
	for side in ["near", "far"]:
		var ankle: Vector2 = result[side + "_ankle"]
		var dx := ankle.x - hip.x
		var vertical_reach := sqrt(maxf(0.001, pow(THIGH + SHIN - 0.15, 2.0) - dx * dx))
		corrected_hip.y = maxf(corrected_hip.y, ankle.y - vertical_reach)
	var body_shift := corrected_hip - hip
	for key in ["hip", "chest", "neck", "head", "near_hip", "far_hip", "near_shoulder", "far_shoulder", "near_elbow", "far_elbow", "near_hand", "far_hand"]:
		result[key] += body_shift
	for side in ["near", "far"]:
		result[side + "_knee"] = knee(corrected_hip, result[side + "_ankle"], facing)
	result.waist = corrected_hip + Vector2(0, -1.8)
	result.hem = (result.near_ankle.x - result.far_ankle.x) * 0.025
	result.hair = lerpf(0.4, 1.5, blend) * activity
	return result
