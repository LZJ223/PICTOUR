extends Node2D
## 在真实碰撞坡面检查贴地、脚步路程和原始位图资源，不以数量替代美术验收。

const TRAVELER = preload("res://Component/Player/V5/Traveler_V5.tscn")
var checks := 0
var failures := 0
var player: PlayerController
var visual: AnimatedSprite2D
var ground: StaticBody2D


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TRAVELER_V5_CHECK: " + message)


func _wait(frames: int) -> void:
	for tick in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func _run() -> void:
	player = TRAVELER.instantiate()
	player.position.y = -10.0
	add_child(player)
	visual = player.get_node("Visual_Body/Traveler")
	_check(bool(visual.get("_art_ready")), "角色资源加载")
	if not bool(visual.get("_art_ready")):
		_finish()
		return
	var metadata: Dictionary = visual.call("get_metadata")
	for action in ["walk", "run"]:
		_check(visual.sprite_frames.get_frame_count(action) == 16, action + "16个原图姿态")
		var unique: Dictionary = {}
		for info: Dictionary in metadata.animations[action]:
			unique[info.pixel_hash] = true
		_check(unique.size() == 16, action + "无复制位图填充帧数")
		_check(metadata.animations[action].size() == 16, action + "逐帧脚点与领口齐全")
	_check(player.floor_snap_length == 8.0 and player.floor_constant_speed, "局部坡面物理设置")
	_check(player.move_speed == 180.0 and player.run_speed == 320.0 and player.dash_speed == 560.0, "沿用V4速度参数")
	for degrees: float in [0.0, -18.0, 18.0, -28.0, 28.0]:
		await _set_slope(degrees)
		_check(player.is_on_floor(), "坡度%.0f初始真实贴地" % degrees)
		var idle_error := _stance_error()
		_check(idle_error < 3.0, "坡度%.0f待机足点误差%.2f" % [degrees, idle_error])
		for direction: float in [1.0, -1.0]:
			Input.action_press("move_right" if direction > 0 else "move_left")
			await _wait(20)
			var loss := 0
			var phase_error := 0.0
			var stance_error := 0.0
			var distance_error := 0.0
			for tick in 45:
				var old_position := player.position
				var old_phase: float = visual.get("stride_phase")
				await _wait(1)
				if not player.is_on_floor():
					loss += 1
				var distance: float = visual.get("measured_distance")
				distance_error = maxf(distance_error, absf(distance - player.position.distance_to(old_position)))
				var expected: float = fposmod(old_phase + distance / float(visual.get("walk_stride")), 1.0)
				phase_error = maxf(phase_error, absf(expected - float(visual.get("stride_phase"))))
				stance_error = maxf(stance_error, _stance_error())
			_check(loss == 0, "坡%.0f方向%.0f连续贴地，失地%d帧" % [degrees, direction, loss])
			_check(distance_error < 0.02 and phase_error < 0.002, "坡面实际路程驱动，距离误差%.4f相位%.4f" % [distance_error, phase_error])
			_check(stance_error < 3.0, "坡%.0f方向%.0f运动足点误差%.2f" % [degrees, direction, stance_error])
			_check(is_zero_approx(visual.rotation) and is_zero_approx(player.rotation), "角色整体保持直立")
			print("V5_SLOPE: %.0f dir %.0f speed %s contact_error %.3f" % [degrees, direction, str(player.get_real_velocity()), stance_error])
			Input.action_release("move_right")
			Input.action_release("move_left")
			await _wait(20)
		Input.action_press("move_right")
		Input.action_press("sprint")
		await _wait(30)
		var run_loss := 0
		var saw_flight := false
		for tick in 45:
			await _wait(1)
			if not player.is_on_floor():
				run_loss += 1
			var current: Dictionary = visual.get("_frame_meta")
			if float(current.get("lowest_pixel_y", 0.0)) < -4.0:
				saw_flight = true
		_check(run_loss == 0 and visual.animation == &"run", "坡%.0f跑步连续贴地" % degrees)
		_check(saw_flight, "坡%.0f跑步保留原图腾空姿态" % degrees)
		Input.action_release("move_right")
		Input.action_release("sprint")
		await _wait(25)
	await _set_slope(0.0)
	var floor_y := player.position.y
	Input.action_press("jump")
	var maximum_rise := 0.0
	var saw_air := false
	for tick in 65:
		await _wait(1)
		maximum_rise = maxf(maximum_rise, floor_y - player.position.y)
		if not player.is_on_floor():
			saw_air = true
			_check(not bool(visual.get("foot_grounded")[0]) and not bool(visual.get("foot_grounded")[1]), "空中不吸附脚部")
	Input.action_release("jump")
	_check(saw_air and player.is_on_floor() and maximum_rise > 105.0 and maximum_rise < 112.0, "跳高保持108.6，实际%.2f" % maximum_rise)
	# 不同碰撞层的水平假地面不能吸引脚点。
	var other := StaticBody2D.new()
	other.collision_layer = 2
	var collider := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(200, 4)
	collider.shape = box
	other.position = player.position + Vector2(0, -14)
	other.add_child(collider)
	add_child(other)
	await _wait(4)
	var hit: Dictionary = visual.call("_ground_at", 0.0)
	_check(not hit.is_empty() and hit.collider == ground, "脚部查询仅命中玩家当前层且排除自身")
	other.queue_free()
	# 上坡接平地与下坡的折线会暴露残留竖直速度造成的无输入弹跳。
	ground.get_child(0).polygon = PackedVector2Array([Vector2(-2000, 650), Vector2.ZERO, Vector2(90, 0), Vector2(2000, 620), Vector2(2000, 1100), Vector2(-2000, 1100)])
	player.position = Vector2(-120, 15)
	player.reset_motion()
	player.reset_physics_interpolation()
	await _wait(30)
	Input.action_press("move_right")
	Input.action_press("sprint")
	var crest_air := 0
	for tick in 80:
		await _wait(1)
		if not player.is_on_floor():
			crest_air += 1
	_check(crest_air == 0, "上坡接平地再下坡无意外起跳，离地%d帧" % crest_air)
	Input.action_release("move_right")
	Input.action_release("sprint")
	ground.get_child(0).polygon = PackedVector2Array([Vector2(-2000, 0), Vector2.ZERO, Vector2(0, 500), Vector2(-2000, 500)])
	player.position = Vector2(-0.5, -0.1)
	player.reset_motion()
	player.reset_physics_interpolation()
	await _wait(35)
	_check(player.is_on_floor() and visual.call("_ground_at", 28.0).is_empty(), "台阶边缘的悬空脚位没有假地面")
	_finish()


func _stance_error() -> float:
	var error := 0.0
	var feet: PackedVector2Array = visual.call("get_visual_feet")
	var targets: PackedVector2Array = visual.get("foot_targets")
	var grounded: Array = visual.get("foot_grounded")
	for i in 2:
		if bool(grounded[i]):
			error = maxf(error, absf(feet[i].y - targets[i].y))
	return error


func _set_slope(degrees: float) -> void:
	if is_instance_valid(ground):
		ground.queue_free()
		await _wait(2)
	ground = StaticBody2D.new()
	var collision := CollisionPolygon2D.new()
	var slope := tan(deg_to_rad(degrees))
	collision.polygon = PackedVector2Array([Vector2(-5000, -5000 * slope), Vector2(5000, 5000 * slope), Vector2(5000, 5000 * slope + 500), Vector2(-5000, -5000 * slope + 500)])
	ground.add_child(collision)
	add_child(ground)
	player.position = Vector2(0, -20)
	player.reset_motion()
	player.reset_physics_interpolation()
	await _wait(35)


func _finish() -> void:
	for action in ["move_right", "move_left", "sprint", "jump"]:
		Input.action_release(action)
	print("TRAVELER_V5_CHECK: %d checks, %d failures." % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
