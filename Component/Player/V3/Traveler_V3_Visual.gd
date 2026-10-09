extends AnimatedSprite2D
## 动画只消费碰撞完成后的真实位移，不以输入或预期速度假装走动。

const Pose = preload("res://Art/Player/V3/Traveler_Pose.gd")

@onready var player: PlayerController = get_parent().get_parent() as PlayerController
var visual_facing: int = 1
var collar_offset := Vector2(-4.5, -65.5)
var stride_phase: float = 0.0
var measured_distance: float = 0.0
var _clock: float = 0.0
var _previous_position := Vector2.ZERO
var _previous_speed: float = 0.0
var _previous_grounded: bool = false
var _transition: StringName = &""
var _transition_left: float = 0.0
var _transition_duration: float = 0.0


func _ready() -> void:
	process_physics_priority = 1
	_previous_position = player.global_position
	stop()
	animation = &"idle"
	_update_collar(&"idle", 0.0)


func _begin(action: StringName, duration: float) -> void:
	_transition = action
	_transition_left = duration
	_transition_duration = duration


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player.UAV_activated:
		return
	_clock += delta
	var displacement := player.global_position - _previous_position
	var teleported: bool = displacement.length() > 100.0
	var grounded: bool = player.is_on_floor()
	var speed: float = absf(player.velocity.x)
	measured_distance = 0.0 if teleported else absf(displacement.x)
	if teleported:
		_transition_left = 0.0
		_previous_grounded = grounded
		_previous_speed = speed
	# 转向先制动；实际速度过零后再换侧面，不在反向输入时立即镜像。
	var new_facing := visual_facing
	if speed > 15.0:
		new_facing = int(signf(player.velocity.x))
	elif speed < 4.0:
		new_facing = player.facing_direction
	if not _previous_grounded and grounded:
		_begin(&"land", 0.11)
	elif _previous_grounded and not grounded and player.velocity.y < -80.0:
		_begin(&"takeoff", 0.065)
	elif grounded and new_facing != visual_facing:
		_begin(&"turn", 0.07)
	elif grounded and _previous_speed > 100.0 and speed < _previous_speed - 20.0 and _transition_left <= 0.0:
		_begin(&"brake", 0.10)
	visual_facing = new_facing
	flip_h = visual_facing < 0
	_transition_left = maxf(0.0, _transition_left - delta)
	var action: StringName = &"idle"
	var phase: float = 0.0
	if player.dash_active:
		action = &"dash"
		phase = fposmod(_clock * 2.0, 1.0)
	elif _transition_left > 0.0:
		action = _transition
		phase = 1.0 - _transition_left / _transition_duration
	elif not grounded:
		action = &"rise" if player.velocity.y < -20.0 else &"fall"
		phase = clampf(1.0 - absf(player.velocity.y) / player.jump_speed, 0.0, 0.999) if action == &"rise" else clampf(player.velocity.y / 620.0, 0.0, 0.999)
	elif measured_distance > 0.02:
		action = &"run" if player.is_running or speed > 290.0 else &"walk"
		stride_phase = fposmod(stride_phase + measured_distance / Pose.stride(action), 1.0)
		phase = stride_phase
	else:
		phase = fposmod(_clock * 0.65, 1.0)
	if animation != action:
		animation = action
	var count := sprite_frames.get_frame_count(action)
	var value: float = phase * count
	set_frame_and_progress(mini(int(value), count - 1), fposmod(value, 1.0))
	_update_collar(action, float(frame) / count)
	_previous_grounded = grounded
	_previous_speed = speed
	_previous_position = player.global_position


func _update_collar(action: StringName, phase: float) -> void:
	var pose: Dictionary = Pose.pose(action, phase)
	var collar: Vector2 = (pose.collar - Vector2(128, 236)) * 0.5
	collar_offset = Vector2(collar.x * visual_facing, collar.y)
