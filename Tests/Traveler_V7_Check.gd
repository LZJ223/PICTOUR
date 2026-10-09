extends Node2D
## 正常60Hz的实体、状态连续性与恢复检查。美术质量另看GPU视频。

const PLAYER = preload("res://Component/Player/V7/Traveler_V7.tscn")
var checks := 0
var failures := 0
var player: PlayerController
var visual: Node2D
var ground: StaticBody2D


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TRAVELER_V7_CHECK: " + label)


func _wait(frames: int) -> void:
	for frame in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func _release() -> void:
	for action in ["move_left", "move_right", "sprint", "jump"]:
		Input.action_release(action)


func _floor(angle: float) -> void:
	_release()
	if is_instance_valid(ground):
		ground.queue_free()
		await _wait(2)
	ground = StaticBody2D.new()
	var contour := CollisionPolygon2D.new()
	var slope := tan(deg_to_rad(angle))
	contour.polygon = PackedVector2Array([Vector2(-10000, -10000 * slope), Vector2(10000, 10000 * slope), Vector2(10000, 10000 * slope + 600), Vector2(-10000, -10000 * slope + 600)])
	ground.add_child(contour)
	add_child(ground)
	player.position = Vector2(0, -12)
	player.reset_motion()
	visual.reset_after_restore()
	player.get_node("Visual_Body/Scarf").reset_cloth()
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
	_check(Engine.physics_ticks_per_second == 60, "正常60Hz")
	_check(visual.skin_ready, "原头部皮肤加载")
	_check(player.move_speed == 180 and player.run_speed == 320 and player.dash_speed == 560 and player.jump_speed == 610, "实体移动参数保持")
	_check(player.get_node("CollisionBox_Body").shape.size == Vector2(30, 86), "实体30×86")
	for angle in [0.0, -3.0, 3.0, -18.0, 18.0, -28.0, 28.0]:
		await _floor(angle)
		_check(player.is_on_floor(), "坡%.0f接地" % angle)
		for running in [false, true]:
			for direction in [1.0, -1.0]:
				_release()
				await _wait(20)
				Input.action_press("move_right" if direction > 0 else "move_left")
				if running:
					Input.action_press("sprint")
				await _wait(15)
				var start_phase: float = visual.cycle_total
				var start_events: Dictionary = visual.motion_events.duplicate()
				var finite := true
				var maximum_heel := 0.0
				for tick in 80:
					await _wait(1)
					for key in visual.pose:
						var value: Variant = visual.pose[key]
						finite = finite and (value.is_finite() if value is Vector2 else is_finite(float(value)))
					maximum_heel = maxf(maximum_heel, -float(visual.pose.near_ankle.y))
				var label := "坡%.0f %s %s" % [angle, "跑" if running else "走", "右" if direction > 0 else "左"]
				_check(finite, label + "姿态有限值")
				_check(visual.cycle_total > start_phase + 1.0 and visual.motion_events == start_events, label + "连续周期，不因微坡重播")
				_check(visual.visual_facing == int(direction), label + "朝向")
				_check(visual.state_name == ("run" if running else "walk"), label + "状态")
				if running and is_zero_approx(angle):
					_check(maximum_heel > 26, label + "明确收腿")
	_release()
	await _floor(0)
	var step := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(120, 8)
	shape.shape = rect
	step.position = Vector2(150, -4)
	step.add_child(shape)
	add_child(step)
	Input.action_press("move_right")
	await _wait(20)
	var events: Dictionary = visual.motion_events.duplicate()
	await _wait(75)
	_check(player.position.x > 230 and player.step_count > 0 and visual.motion_events == events, "8px石头跨上跨下不重播")
	step.queue_free()
	ground.collision_layer = 0
	await _wait(1)
	ground.collision_layer = 1
	await _wait(8)
	_check(visual.motion_events == events, "1帧失地宽限")
	_release()
	await _floor(0)
	Input.action_press("jump")
	var start_y := player.position.y
	var rise := 0.0
	var air_count := 0
	var air_variation := 0.0
	var first_air := Vector2.ZERO
	for tick in 75:
		await _wait(1)
		rise = maxf(rise, start_y - player.position.y)
		if visual.state_name == "air":
			air_count += 1
			if air_count == 1:
				first_air = visual.pose.near_ankle
			air_variation = maxf(air_variation, first_air.distance_to(visual.pose.near_ankle))
	Input.action_release("jump")
	_check(rise > 107 and rise < 110, "满跳108.6px %.3f" % rise)
	_check(air_count > 20 and air_variation > 8, "起跳/空中/下降连续变化")
	_check(visual.motion_events.land > 0, "真实落地事件")
	Input.action_press("move_right")
	await _wait(20)
	Input.action_press("sprint")
	await _wait(4)
	Input.action_release("sprint")
	await _wait(1)
	_check(player.dash_active and visual.state_name == "dash", "短按Shift原实体短冲及视觉舒展")
	await _wait(20)
	_release()
	await _wait(20)
	player.position += Vector2(25, 0)
	player.reset_motion()
	visual.reset_after_restore()
	player.get_node("Visual_Body/Scarf").reset_cloth()
	_check(visual.pose == visual.previous_pose and visual.activity == 0 and visual._last_position == player.position, "近距离恢复重置插值/姿态/位移历史")
	_check(visual._step_offset == 0 and visual._hair_response == 0 and visual._unsupported_time == 0, "恢复清除布发/微坡状态")
	_check(player.rotation == 0 and visual.rotation == 0, "没有旋转实体适配坡面")
	# 第二内容层另有地面，第一层的假平台不能污染坡面读数。
	ground.collision_layer = 2
	player.set_collision_group(2)
	var decoy := StaticBody2D.new()
	var decoy_shape := CollisionShape2D.new()
	var decoy_rect := RectangleShape2D.new()
	decoy_rect.size = Vector2(200, 8)
	decoy_shape.shape = decoy_rect
	decoy.position = Vector2(player.position.x, -14)
	decoy.add_child(decoy_shape)
	add_child(decoy)
	await _wait(15)
	var hit: Dictionary = visual._ground_at(player.position.x)
	_check(player.collision_mask == 2 and player.is_on_floor(), "非默认第二层真实接地")
	_check(not hit.is_empty() and hit.collider == ground, "地形读数排除角色和其他内容层")
	Input.action_press("move_right")
	await _wait(30)
	_check(visual.state_name == "walk" and visual.cycle_total > 0.3, "非默认第二层作者化步态")
	_release()
	print("TRAVELER_V7_CHECK: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
