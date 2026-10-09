extends Node2D
## 60Hz真实输入/实体回归，指标证明连续性约束，不替代动态美术审阅。

const PLAYER = preload("res://Component/Player/V6/Traveler_V6.tscn")
var checks := 0
var failures := 0
var player: PlayerController
var visual: Node2D
var ground: StaticBody2D
var degrees := 0.0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TRAVELER_V6_CHECK: " + message)


func _wait(frames: int) -> void:
	for frame in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func _release() -> void:
	for action in ["move_left", "move_right", "sprint", "jump"]:
		Input.action_release(action)


func _set_floor(angle: float) -> void:
	_release()
	degrees = angle
	if is_instance_valid(ground):
		ground.queue_free()
		await _wait(2)
	ground = StaticBody2D.new()
	var shape := CollisionPolygon2D.new()
	var slope := tan(deg_to_rad(angle))
	shape.polygon = PackedVector2Array([Vector2(-10000, -10000 * slope), Vector2(10000, 10000 * slope), Vector2(10000, 10000 * slope + 600), Vector2(-10000, -10000 * slope + 600)])
	ground.add_child(shape)
	add_child(ground)
	player.position = Vector2(0, -12)
	player.reset_motion()
	visual.reset_after_restore()
	player.reset_physics_interpolation()
	await _wait(30)


func _run() -> void:
	Global.allow_layer_cycle = false
	Global.allow_object_transfer = false
	Global.allow_uav = false
	player = PLAYER.instantiate()
	add_child(player)
	player.set_collision_group(1)
	visual = player.get_node("Visual_Body/Traveler")
	_check(Engine.physics_ticks_per_second == 60, "默认60Hz验收")
	_check(visual.skin_ready and visual._parts.size() == 15, "15个原位图分件加载")
	_check(player.move_speed == 180 and player.run_speed == 320 and player.dash_speed == 560 and player.jump_speed == 610, "物理参数未变")
	_check(player.get_node("CollisionBox_Body").shape.size == Vector2(30, 86), "30×86实体尺寸")
	for part in visual._parts:
		_check(part.node.texture.resource_path == "res://Art/Player/Traveler_C/Traveler_C_Rig.png", "皮肤沿用AI原图：" + str(part.definition.name))
	for angle in [0.0, -3.0, 3.0, -18.0, 18.0, -28.0, 28.0]:
		await _set_floor(angle)
		_check(player.is_on_floor(), "坡%.0f实体初始接地" % angle)
		for running in [false, true]:
			for direction in [1.0, -1.0]:
				_release()
				await _wait(15)
				Input.action_press("move_right" if direction > 0 else "move_left")
				if running:
					Input.action_press("sprint")
				await _wait(30)
				var old_events: Dictionary = visual.motion_events.duplicate()
				var max_bone_error := 0.0
				var max_floor_error := 0.0
				var max_lean := 0.0
				var max_hip := -1000.0
				var min_hip := 1000.0
				var max_span := 0.0
				var phase_change := 0.0
				var last_phase: float = visual.stride_phase
				var flight := false
				var loss := 0
				visual._gait.planted_error = 0.0
				for tick in 72:
					await _wait(1)
					var pose: Dictionary = visual.pose
					if not player.is_on_floor():
						loss += 1
					for index in 2:
						var side := "near" if index == 0 else "far"
						max_bone_error = maxf(max_bone_error, absf(Vector2(pose[side + "_hip"]).distance_to(pose[side + "_knee"]) - 28.0))
						max_bone_error = maxf(max_bone_error, absf(Vector2(pose[side + "_knee"]).distance_to(pose[side + "_ankle"]) - 28.0))
						if visual._gait.stance_flags[index]:
							var foot: Vector2 = visual._gait.world_feet[index]
							max_floor_error = maxf(max_floor_error, absf(foot.y - foot.x * tan(deg_to_rad(angle))))
					max_lean = maxf(max_lean, absf(rad_to_deg(float(pose.lean))))
					max_hip = maxf(max_hip, pose.hip.y)
					min_hip = minf(min_hip, pose.hip.y)
					max_span = maxf(max_span, absf(pose.near_ankle.x - pose.far_ankle.x))
					phase_change += fposmod(float(visual.stride_phase) - last_phase, 1.0)
					last_phase = visual.stride_phase
					flight = flight or (not visual._gait.stance_flags[0] and not visual._gait.stance_flags[1])
				var label := "坡%.0f %s 方向%.0f" % [angle, "跑" if running else "走", direction]
				_check(loss == 0 and visual.motion_events == old_events, label + "不失地/不重新起步落地")
				_check(max_bone_error < 0.025, label + "腿骨固定，误差%.4f" % max_bone_error)
				_check(visual._gait.planted_error < 0.025 and max_floor_error < 0.15, label + "世界支撑点稳定/贴地 %.4f/%.4f" % [visual._gait.planted_error, max_floor_error])
				_check(phase_change > 1.0 and max_lean <= 1.5, label + "连续相位/直立")
				if is_zero_approx(angle):
					_check(max_hip - min_hip < 2.1, label + "平地重心变化%.3fpx" % (max_hip - min_hip))
				if running:
					_check(flight, label + "有短双脚离地相位")
				print("V6_MEASURE %s span=%.2f hip_range=%.2f bone=%.5f contact=%.5f" % [label, max_span, max_hip - min_hip, max_bone_error, max_floor_error])
	_release()
	await _set_floor(0)
	Input.action_press("move_right")
	await _wait(35)
	Input.action_release("move_right")
	await _wait(30)
	var stopped: Dictionary = visual.pose.duplicate(true)
	var stopped_cycle: float = visual._gait.cycle
	await _wait(25)
	_check(visual.state_name == "idle" and Vector2(visual.pose.near_ankle).distance_to(stopped.near_ankle) < 0.001 and Vector2(visual.pose.far_ankle).distance_to(stopped.far_ankle) < 0.001 and Vector2(visual.pose.hip).distance_to(stopped.hip) < 0.001 and is_equal_approx(stopped_cycle, visual._gait.cycle), "停步稳定，无碎步/相位空转")
	# 真正的走→跑切换不能清掉接触状态。独立于启动/停止测试。
	Input.action_press("move_right")
	await _wait(25)
	var transition_events: Dictionary = visual.motion_events.duplicate()
	Input.action_press("sprint")
	var maximum_pose_delta := 0.0
	var previous_ankle: Vector2 = visual.pose.near_ankle
	for tick in 30:
		await _wait(1)
		maximum_pose_delta = maxf(maximum_pose_delta, previous_ankle.distance_to(visual.pose.near_ankle))
		previous_ankle = visual.pose.near_ankle
	_check(visual.motion_events == transition_events and maximum_pose_delta < 14.0, "走跑切换不重播、局部足点变化%.3fpx" % maximum_pose_delta)
	_release()
	await _set_floor(0)
	var step := StaticBody2D.new()
	var step_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(120, 8)
	step_shape.shape = rectangle
	step.position = Vector2(150, -4)
	step.add_child(step_shape)
	add_child(step)
	Input.action_press("move_right")
	await _wait(20)
	var step_events: Dictionary = visual.motion_events.duplicate()
	await _wait(75)
	_check(player.position.x > 230 and player.step_count > 0 and visual.motion_events == step_events, "真实8px台沿跨上跨下不重播")
	step.queue_free()
	# 受控故障注入：地面碰撞仅断一帧，不声称正常关卡必然发生。
	var blink_events: Dictionary = visual.motion_events.duplicate()
	ground.collision_layer = 0
	await _wait(1)
	ground.collision_layer = 1
	await _wait(8)
	_check(visual.motion_events == blink_events, "受控1帧失地不触发落地重置")
	_release()
	await _set_floor(0)
	Input.action_press("jump")
	var initial_y := player.position.y
	var maximum_rise := 0.0
	var air_samples: Array[Vector2] = []
	for tick in 70:
		await _wait(1)
		maximum_rise = maxf(maximum_rise, initial_y - player.position.y)
		if visual.state_name == "air":
			air_samples.append(visual.pose.near_ankle)
	Input.action_release("jump")
	_check(maximum_rise > 107 and maximum_rise < 110, "完整跳高仍108.6px：%.3f" % maximum_rise)
	_check(air_samples.size() > 12 and air_samples[8].distance_to(air_samples[-5]) > 0.5, "升降过程有连续柔和收腿，非冻结姿态")
	var cloth: Node2D = player.get_node("Visual_Body/Scarf")
	_check(absf(float(cloth.get_total_length()) - 58.0) < 0.02, "围巾58px定长")
	_check(player.rotation == 0 and visual.rotation == 0, "未用整人旋转伪装坡面")
	_release()
	print("TRAVELER_V6_CHECK: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
