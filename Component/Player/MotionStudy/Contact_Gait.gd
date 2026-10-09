extends Node2D
## 独立动作结构灰稿：世界锁脚 + 摆脚弧线 + 连续关节求解。不是最终角色美术。

@export var running := false
@export var speed := 180.0
var distance := 0.0
var previous_pose: Dictionary = {}
var current_pose: Dictionary = {}
var max_support_error := 0.0
var seam_error := 0.0
var saw_flight := false
var samples := 0
var stride: float:
	get: return 152.0 if running else 108.0
var stance_fraction: float:
	get: return 0.37 if running else 0.62


func _ready() -> void:
	current_pose = _pose_at(0.0)
	previous_pose = current_pose.duplicate(true)
	var next := _pose_at(stride)
	for key in ["hip", "head", "near_knee", "far_knee", "near_foot", "far_foot", "near_hand", "far_hand"]:
		seam_error = maxf(seam_error, (Vector2(next[key]) - Vector2(stride, 0)).distance_to(current_pose[key]))


func _physics_process(delta: float) -> void:
	previous_pose = current_pose
	distance += speed * delta
	current_pose = _pose_at(distance)
	for side in ["near", "far"]:
		if bool(current_pose[side + "contact"]) and bool(previous_pose[side + "contact"]):
			max_support_error = maxf(max_support_error, Vector2(current_pose[side + "_foot"]).distance_to(previous_pose[side + "_foot"]))
	saw_flight = saw_flight or (not current_pose.nearcontact and not current_pose.farcontact)
	samples += 1


func _foot(cycle: float, offset: float) -> Dictionary:
	var shifted := cycle + offset
	var phase := fposmod(shifted, 1.0)
	var anchor_x := (floorf(shifted) - offset) * stride + stride * stance_fraction * 0.5
	if phase < stance_fraction:
		return {"point": Vector2(anchor_x, 0.0), "contact": true}
	var u := (phase - stance_fraction) / (1.0 - stance_fraction)
	# 端点位置/速度连续；高度曲线不宣称加速度连续。支撑段没有正弦摆腿近似。
	var travel := u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
	var height := (27.0 if running else 12.0) * 16.0 * u * u * (1.0 - u) * (1.0 - u)
	return {"point": Vector2(anchor_x + stride * travel, -height), "contact": false}


func _loop_curve(phase: float, keys: Array) -> float:
	var value := fposmod(phase, 1.0) * keys.size()
	var index := int(value)
	var t := value - index
	var a: float = keys[posmod(index - 1, keys.size())]
	var b: float = keys[index]
	var c: float = keys[(index + 1) % keys.size()]
	var d: float = keys[(index + 2) % keys.size()]
	return 0.5 * ((2.0 * b) + (-a + c) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t + (-a + 3.0 * b - 3.0 * c + d) * t * t * t)


func _knee(hip: Vector2, foot: Vector2, first: float, second: float) -> Vector2:
	var axis := foot - hip
	var length := clampf(axis.length(), 0.001, first + second - 0.001)
	var forward := axis.normalized()
	var along := (first * first - second * second + length * length) / (2.0 * length)
	var bend := sqrt(maxf(0.0, first * first - along * along))
	return hip + forward * along + Vector2(forward.y, -forward.x) * bend


func _pose_at(world_x: float) -> Dictionary:
	var cycle := world_x / stride
	var near := _foot(cycle, 0.0)
	var far := _foot(cycle, 0.5)
	var hip_y := _loop_curve(cycle, [-53.0, -51.5, -54.5, -56.5, -53.0, -51.5, -54.5, -56.5] if running else [-54.0, -53.0, -55.5, -55.0, -54.0, -53.0, -55.5, -55.0])
	var hip := Vector2(world_x, hip_y)
	var lean := 3.5 if running else 0.7
	var shoulder := hip + Vector2(lean, -22)
	var near_swing := _loop_curve(cycle, [-15.0, 0.0, 15.0, 0.0])
	var far_swing := _loop_curve(cycle + 0.5, [-15.0, 0.0, 15.0, 0.0])
	var near_hand := shoulder + Vector2(near_swing, 10.0 if running else 24.0)
	var far_hand := shoulder + Vector2(far_swing, 10.0 if running else 24.0)
	return {
		"root": Vector2(world_x, 0), "hip": hip, "head": shoulder + Vector2(1, -13), "shoulder": shoulder,
		"near_foot": near.point, "far_foot": far.point, "nearcontact": near.contact, "farcontact": far.contact,
		"near_knee": _knee(hip, near.point, 32, 32), "far_knee": _knee(hip, far.point, 32, 32),
		"near_hand": near_hand, "far_hand": far_hand,
		"near_elbow": _knee(shoulder, near_hand, 16, 15), "far_elbow": _knee(shoulder, far_hand, 16, 15),
	}


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if current_pose.is_empty():
		return
	var alpha := Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0
	var root: Vector2 = Vector2(previous_pose.root).lerp(current_pose.root, alpha)
	var pose: Dictionary = {}
	for key in current_pose:
		if current_pose[key] is Vector2:
			pose[key] = Vector2(previous_pose[key]).lerp(current_pose[key], alpha) - root
	var ground := Color("bcb5a8")
	draw_line(Vector2(-100, 0), Vector2(100, 0), ground, 0.5)
	for index in range(int(floorf((root.x - 100) / 24)), int(ceilf((root.x + 100) / 24))):
		var x := index * 24.0 - root.x
		draw_line(Vector2(x, 0), Vector2(x, 4), ground, 0.4)
	_draw_leg(pose.hip, pose.far_knee, pose.far_foot, Color("aaa09b"), 1.6)
	draw_polyline(PackedVector2Array([pose.shoulder, pose.far_elbow, pose.far_hand]), Color("aaa09b"), 2.0, true)
	# 一体衣、长发仅作重心识别，明确是程序灰稿，不冒充最终C款材质。
	var hem_sway: float = (pose.near_foot.x - pose.far_foot.x) * 0.05
	var dress := PackedVector2Array([pose.shoulder + Vector2(-5, -2), pose.shoulder + Vector2(5, 0), pose.hip + Vector2(10 + hem_sway, 15), pose.hip + Vector2(-16 + hem_sway, 18), pose.hip + Vector2(-7, -3)])
	draw_colored_polygon(dress, Color("ddd6cc"))
	draw_polyline(PackedVector2Array([dress[0], dress[1], dress[2], dress[3], dress[4], dress[0]]), Color("8c8380"), 0.6, true)
	_draw_leg(pose.hip, pose.near_knee, pose.near_foot, Color("51484b"), 1.7)
	var head: Vector2 = pose.head
	var hair := PackedVector2Array([head + Vector2(-5, -7), head + Vector2(-10, 0), head + Vector2(-24 - hem_sway, 20), head + Vector2(-9, 25), head + Vector2(1, 8), head + Vector2(4, -5)])
	draw_colored_polygon(hair, Color("746a6e"))
	draw_circle(head, 7.8, Color("eae4dc"))
	draw_arc(head, 7.8, -2.7, 0.3, 16, Color("746a6e"), 1.0, true)
	draw_circle(head + Vector2(5, -1), 0.65, Color("51484b"))
	draw_polyline(PackedVector2Array([pose.shoulder, pose.near_elbow, pose.near_hand]), Color("51484b"), 1.8, true)
	var neck: Vector2 = pose.shoulder + Vector2(0, -4)
	draw_polyline(PackedVector2Array([neck + Vector2(3, 0), neck + Vector2(-10, 0), neck + Vector2(-28, 3 + hem_sway), neck + Vector2(-40, 2)]), Color("a75b58"), 2.1, true)
	for side in ["far", "near"]:
		var foot: Vector2 = pose[side + "_foot"]
		var knee: Vector2 = pose[side + "_knee"]
		var ink := Color("a79f94") if side == "far" else Color("68636a")
		draw_circle(knee, 1.6, ink, false, 0.5, true)
		if bool(current_pose[side + "contact"]):
			draw_circle(foot + Vector2(0, 2), 2.5, Color("5c9685"), false, 0.7, true)
		else:
			draw_circle(foot, 1.4, Color("b78670"), false, 0.5, true)
	draw_circle(pose.hip, 1.5, Color("b78670"), false, 0.6, true)


func _draw_leg(hip: Vector2, knee: Vector2, foot: Vector2, ink: Color, width: float) -> void:
	draw_polyline(PackedVector2Array([hip, knee, foot]), ink, width, true)
	draw_line(foot, foot + Vector2(4.0, 0), ink, width, true)
