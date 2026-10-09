extends Node2D

const Pose = preload("res://Art/Player/V3/Traveler_Pose.gd")
const Traveler = preload("res://Component/Player/V3/Traveler_V3.tscn")

var checks: int = 0
var failures: int = 0
var player: PlayerController
var visual: AnimatedSprite2D
var cloth: Node2D


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TRAVELER_V3_CHECK: " + message)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func _run() -> void:
	# 固定腿骨适用于所有姿态，不只取碰巧正确的接触帧。
	var maximum_bone_error := 0.0
	var maximum_pose := ""
	for action in Pose.STATES:
		for index in 64:
			var pose: Dictionary = Pose.pose(action, float(index) / 64.0)
			for side in ["near", "far"]:
				var hip: Vector2 = pose[side + "_hip"]
				var knee: Vector2 = pose[side + "_knee"]
				var foot: Vector2 = pose[side + "_foot"]
				if absf(knee.distance_to(foot) - Pose.LOWER_LEG) > maximum_bone_error:
					maximum_pose = "%s/%d/%s" % [action, index, side]
				maximum_bone_error = maxf(maximum_bone_error, absf(hip.distance_to(knee) - Pose.UPPER_LEG))
				maximum_bone_error = maxf(maximum_bone_error, absf(knee.distance_to(foot) - Pose.LOWER_LEG))
	_check(maximum_bone_error < 0.01, "所有状态的上下腿骨长应保持不变，误差=" + str(maximum_bone_error) + " 姿态=" + maximum_pose)
	var standing: Dictionary = Pose.pose(&"idle", 0.0)
	_check(standing.near_hip.distance_to(standing.near_foot) / (Pose.UPPER_LEG + Pose.LOWER_LEG) > 0.98, "待机承重腿应接近伸直，不能长时间蹲坐")
	for running in [false, true]:
		var stride: float = Pose.RUN_STRIDE if running else Pose.WALK_STRIDE
		var duty: float = Pose.RUN_STANCE if running else Pose.WALK_STANCE
		var old_foot: Vector2 = Pose.foot_path(duty * 0.20, running) * 0.5
		var new_foot: Vector2 = Pose.foot_path(duty * 0.40, running) * 0.5
		var root_motion: float = stride * duty * 0.20
		_check(absf(new_foot.x - old_foot.x + root_motion) < 0.001, "支撑脚相对地面应保持固定")
		_check(is_equal_approx(old_foot.y, Pose.FOOT_Y * 0.5) and is_equal_approx(new_foot.y, old_foot.y), "支撑期间不假装抬脚")
	var aerial_frames := 0
	var walking_air_frames := 0
	for frame in 16:
		var running_pose: Dictionary = Pose.pose(&"run", float(frame) / 16.0)
		var walking_pose: Dictionary = Pose.pose(&"walk", float(frame) / 16.0)
		if running_pose.near_foot.y < Pose.FOOT_Y - 0.5 and running_pose.far_foot.y < Pose.FOOT_Y - 0.5:
			aerial_frames += 1
		if walking_pose.near_foot.y < Pose.FOOT_Y - 0.5 and walking_pose.far_foot.y < Pose.FOOT_Y - 0.5:
			walking_air_frames += 1
	_check(aerial_frames >= 4, "16 帧奔跑需要明确双脚离地帧")
	_check(walking_air_frames == 0, "步行始终至少有一脚支撑")
	var contact: Dictionary = Pose.pose(&"run", 0.0)
	_check(contact.near_foot.x > contact.hip.x and contact.near_hand.x < contact.shoulder.x, "同侧手臂与前伸支撑腿反相")
	_make_floor()
	player = Traveler.instantiate() as PlayerController
	player.position = Vector2(200, 500)
	add_child(player)
	visual = player.get_node("Visual_Body/Traveler")
	cloth = player.get_node("Visual_Body/Scarf")
	await _wait(40)
	_check(player.is_on_floor(), "角色真实碰撞落地")
	var root_before := player.global_position
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _wait(24)
	var phase_before: float = visual.get("stride_phase")
	var position_before := player.global_position
	await _wait(12)
	var phase_after: float = visual.get("stride_phase")
	var expected_phase: float = fposmod(phase_before + (player.global_position.x - position_before.x) / Pose.RUN_STRIDE, 1.0)
	_check(absf(phase_after - expected_phase) < 0.001, "奔跑动画必须与碰撞后位移相位一致")
	_check(visual.animation == &"run" and player.global_position.x > root_before.x + 100.0, "真实跑动触发run")
	_check(absf(float(cloth.call("get_total_length")) - 63.0) < 0.05, "围巾高速运动不拉长")
	var actual_facing: int = visual.get("visual_facing")
	Input.action_release("move_right")
	Input.action_press("move_left")
	await _wait(1)
	_check(player.velocity.x > 0.0 and int(visual.get("visual_facing")) == actual_facing, "反向输入但速度未过零时不得立即镜像")
	await _wait(24)
	_check(int(visual.get("visual_facing")) == -1, "速度过零后完成转向")
	_check(absf(float(cloth.call("get_total_length")) - 63.0) < 0.05, "急转身围巾不拉长")
	Input.action_release("move_left")
	Input.action_release("sprint")
	await _wait(160)
	var settled: PackedVector2Array = cloth.call("get_ribbon_points")
	await _wait(24)
	var later: PackedVector2Array = cloth.call("get_ribbon_points")
	_check(settled[-1].distance_to(later[-1]) < 3.0, "停止后的围巾应衰减而非持续大幅摆动")
	for point in later:
		_check(point.is_finite(), "围巾质点必须有限")
	# 验证跳起、落地、转向的整个瞬态，不能只检查最终静止的一帧。
	Input.action_press("jump")
	Input.action_press("move_right")
	var cloth_unfolded := true
	for tick in 80:
		if tick == 12:
			Input.action_release("jump")
		if tick == 18:
			Input.action_release("move_right")
			Input.action_press("move_left")
		if tick == 30:
			Input.action_release("move_left")
		await _wait(1)
		var points: PackedVector2Array = cloth.call("get_ribbon_points")
		for index in range(2, points.size()):
			if points[index].distance_to(points[0]) < points[index - 1].distance_to(points[0]) + 2.0:
				cloth_unfolded = false
	_check(cloth_unfolded, "跳跃、落地与反向瞬态布条持续离开领口，不倒卷成小圈")
	player.position = Vector2(1364, 500)
	player.reset_motion()
	player.reset_physics_interpolation()
	await _wait(3)
	Input.action_press("move_right")
	await _wait(35)
	var blocked_phase: float = visual.get("stride_phase")
	await _wait(12)
	_check(player.is_on_wall(), "角色真实被墙阻挡")
	_check(is_equal_approx(blocked_phase, float(visual.get("stride_phase"))), "顶墙时不按输入继续空转跑步")
	Input.action_release("move_right")
	print("TRAVELER_V3_CHECK: %d checks, %d failures; max_bone_error=%.5f; run_air_frames=%d" % [checks, failures, maximum_bone_error, aerial_frames])
	get_tree().quit(1 if failures > 0 else 0)


func _make_floor() -> void:
	var ground := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8000, 100)
	shape.shape = rectangle
	ground.position = Vector2(0, 550)
	ground.add_child(shape)
	add_child(ground)
	var wall := StaticBody2D.new()
	var wall_shape := CollisionShape2D.new()
	var wall_rectangle := RectangleShape2D.new()
	wall_rectangle.size = Vector2(30, 250)
	wall_shape.shape = wall_rectangle
	wall.position = Vector2(1400, 400)
	wall.add_child(wall_shape)
	add_child(wall)
