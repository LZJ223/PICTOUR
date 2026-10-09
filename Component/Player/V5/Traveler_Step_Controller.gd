extends PlayerController
## V5 专用自然跨步。旧角色仍使用原 PlayerController。
## 三段完整身体扫掠只修正接地低凸起，不改变跳跃、空中控制或碰撞层。

@export_range(0.0, 24.0, 0.5) var max_step_height: float = 12.0
## 查询与 CharacterBody 的接缝容差保持一致，避免12px台沿被浮点余量误拒。
@export_range(0.01, 0.5, 0.01) var step_probe_margin: float = 0.08

## 只在成功跨步的物理帧非零，供视觉平滑上身；跨矮石陡棱时允许短暂真实离地。
var step_up_height: float = 0.0
var step_count: int = 0
var _step_settle_time: float = 0.0
var _step_direction: float = 0.0
var _last_floor_y: float = 0.0


func _process_body(delta: float) -> void:
	step_up_height = 0.0
	# 保留共享控制器的输入与速度计算，局部替换 move_and_slide 前的接地处理。
	var grounded: bool = is_on_floor() or _step_settle_time > 0.0
	if is_on_floor():
		_last_floor_y = global_position.y
	var direction: float = Input.get_axis("move_left", "move_right")
	if is_zero_approx(direction) or (not is_zero_approx(_step_direction) and signf(direction) != _step_direction):
		_step_settle_time = 0.0
	if not is_zero_approx(direction):
		facing_direction = int(sign(direction))
	_dash_cooldown_time = maxf(0.0, _dash_cooldown_time - delta)
	_dash_time = maxf(0.0, _dash_time - delta)
	_jump_buffer_time = maxf(0.0, _jump_buffer_time - delta)
	if grounded:
		_coyote_time = coyote_duration
		_air_speed_limit = move_speed
	else:
		_coyote_time = maxf(0.0, _coyote_time - delta)
		if _was_on_floor:
			_air_speed_limit = maxf(move_speed, absf(velocity.x))

	_update_sprint(delta, grounded)
	dash_active = _dash_time > 0.0
	var speed_limit: float = run_speed if is_running else move_speed
	if dash_active:
		velocity.x = _dash_direction * dash_speed
	else:
		if not grounded:
			speed_limit = maxf(speed_limit, _air_speed_limit)
		var change_rate: float = acceleration if grounded else air_acceleration
		if is_zero_approx(direction):
			change_rate = friction_deceleration if grounded else air_friction_deceleration
		velocity.x = move_toward(velocity.x, direction * speed_limit, change_rate * delta)

	if not grounded:
		velocity.y += gravity_acceleration * delta
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_time = jump_buffer_duration
	var jumping: bool = _jump_buffer_time > 0.0 and _coyote_time > 0.0
	if jumping:
		_step_settle_time = 0.0
		velocity.y = -jump_speed
		_air_speed_limit = maxf(move_speed, absf(velocity.x))
		_jump_buffer_time = 0.0
		_coyote_time = 0.0
	if variable_jump_height and Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_release_speed_factor

	_was_on_floor = grounded
	if grounded and not jumping and not is_zero_approx(direction) and _step_settle_time <= 0.0:
		_try_step(Vector2(velocity.x * delta, 0.0))
	# 低矮不规则石头的陡侧面只占几像素；身体先越过侧棱，再落到已验证的顶部。
	# 暂停原生向陡侧面的吸附，最多0.10秒，不改变横向速度或增加前移距离。
	var normal_snap := floor_snap_length
	if _step_settle_time > 0.0:
		floor_snap_length = 0.0
	move_and_slide()
	floor_snap_length = normal_snap
	if not jumping and (grounded or _step_settle_time > 0.0 or (_coyote_time > 0.0 and velocity.y >= 0.0)) and not is_on_floor():
		# 下同等小台沿时延续真实地面，避免8px+接触容差变成六帧微坠落。
		var remaining_drop := max_step_height + step_probe_margin * 2.0 - maxf(0.0, global_position.y - _last_floor_y)
		floor_snap_length = maxf(0.0, remaining_drop)
		apply_floor_snap()
		floor_snap_length = normal_snap
	if _step_settle_time > 0.0:
		_step_settle_time = 0.0 if is_on_floor() else maxf(0.0, _step_settle_time - delta)
	if is_on_wall():
		_dash_time = 0.0
		dash_active = false
		_air_speed_limit = move_speed
	_update_gait()
	if _step_settle_time > 0.0 and not dash_active:
		gait = Gait.RUN if is_running else Gait.WALK


func _try_step(horizontal_motion: Vector2) -> bool:
	if max_step_height <= 0.0 or absf(horizontal_motion.x) < 0.01:
		return false
	var obstacle := KinematicCollision2D.new()
	if not test_move(global_transform, horizontal_motion, obstacle, step_probe_margin):
		return false
	# 可行走坡面由原生 move_and_slide 处理；这里仅处理朝向玩家的低竖边。
	if obstacle.get_normal().dot(Vector2.UP) >= cos(floor_max_angle):
		return false
	if obstacle.get_normal().x * horizontal_motion.x >= -0.01:
		return false
	var lift: float = max_step_height + step_probe_margin * 2.0
	var ceiling := KinematicCollision2D.new()
	if test_move(global_transform, Vector2(0.0, -lift), ceiling, step_probe_margin):
		lift = maxf(0.0, -ceiling.get_travel().y - step_probe_margin)
	if lift < 0.25:
		return false
	var raised := global_transform
	raised.origin.y -= lift
	if test_move(raised, horizontal_motion, null, step_probe_margin):
		return false
	var landing := KinematicCollision2D.new()
	var ahead := raised
	ahead.origin += horizontal_motion
	var can_land := test_move(ahead, Vector2(0.0, lift + step_probe_margin * 2.0), landing, step_probe_margin)
	var crossing_edge := not can_land or landing.get_normal().dot(Vector2.UP) < cos(floor_max_angle)
	if crossing_edge:
		# 最多提前查看8px（短于半只碰撞脚宽），只为确认矮石顶部，绝不额外前移。
		# 高根侧壁在12px上限内仍无真实平缓踏面，因此同样拒绝。
		var foot_reach := Vector2(signf(horizontal_motion.x) * maxf(absf(horizontal_motion.x), 8.0), 0.0)
		if test_move(raised, foot_reach, null, step_probe_margin):
			return false
		ahead = raised
		ahead.origin += foot_reach
		can_land = test_move(ahead, Vector2(0.0, lift + step_probe_margin * 2.0), landing, step_probe_margin)
	if not can_land or landing.get_normal().dot(Vector2.UP) < cos(floor_max_angle):
		return false
	var rise: float = lift - landing.get_travel().y
	if rise < 0.25 or rise > max_step_height + step_probe_margin * 2.0:
		return false
	# 只预抬真实身体，横向仍由下面唯一一次 move_and_slide 消耗，避免双倍前进。
	global_position.y -= rise
	velocity.y = 0.0
	step_up_height = rise
	step_count += 1
	if crossing_edge:
		_step_settle_time = 0.10
		_step_direction = signf(horizontal_motion.x)
	return true


func reset_motion() -> void:
	super.reset_motion()
	step_up_height = 0.0
	_step_settle_time = 0.0
	_step_direction = 0.0
	_last_floor_y = global_position.y
