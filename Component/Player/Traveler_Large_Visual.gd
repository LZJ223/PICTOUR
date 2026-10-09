extends AnimatedSprite2D
## 帧相位由真实位移推进；切换姿态不限制人物输入。

@onready var player: PlayerController = get_parent().get_parent() as PlayerController

var _clock: float = 0.0
var _stride_phase: float = 0.0
var _transition: StringName = &""
var _transition_left: float = 0.0
var _transition_duration: float = 0.0
var _previous_grounded: bool = false
var _previous_speed: float = 0.0
var _previous_facing: int = 1
var _last_position := Vector2.ZERO
var collar_offset := Vector2(-4, -63)


func _ready() -> void:
	process_physics_priority = 1
	_last_position = player.global_position
	stop()
	animation = &"idle"
	frame = 0


func _begin_transition(action: StringName, duration: float) -> void:
	_transition = action
	_transition_duration = duration
	_transition_left = duration


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player.UAV_activated:
		return
	_clock += delta
	var grounded: bool = player.is_on_floor()
	var speed: float = absf(player.velocity.x)
	if player.global_position.distance_to(_last_position) > 120.0:
		_transition_left = 0.0
		_previous_grounded = grounded
		_previous_speed = speed
	if not _previous_grounded and grounded:
		_begin_transition(&"land", 0.12)
	elif _previous_grounded and not grounded and player.velocity.y < -80:
		_begin_transition(&"takeoff", 0.07)
	elif grounded and player.facing_direction != _previous_facing and speed > 35:
		_begin_transition(&"turn", 0.09)
	elif grounded and _previous_speed > 80 and speed < _previous_speed - 25 and Input.get_axis("move_left", "move_right") == 0:
		if _transition != &"brake" or _transition_left <= 0:
			_begin_transition(&"brake", 0.13)
	_transition_left = maxf(0.0, _transition_left - delta)
	flip_h = player.facing_direction < 0
	var action: StringName = &"idle"
	var phase: float = 0.0
	if player.dash_active:
		action = &"dash"
		phase = fmod(_clock * 24.0, 4.0) / 4.0
	elif _transition_left > 0:
		action = _transition
		phase = 1.0 - _transition_left / _transition_duration
	elif not grounded:
		action = &"rise" if player.velocity.y < -20 else &"fall"
		phase = clampf(1.0 - absf(player.velocity.y) / player.jump_speed, 0.0, 0.999) if action == &"rise" else clampf(player.velocity.y / 620.0, 0.0, 0.999)
	elif speed > 8:
		action = &"run" if player.is_running or speed > 290 else &"walk"
		var stride_length: float = 118.0 if action == &"run" else 96.0
		_stride_phase = fmod(_stride_phase + speed * delta / stride_length, 1.0)
		phase = _stride_phase
	else:
		phase = fmod(_clock * 0.75, 1.0)
	if animation != action:
		animation = action
	var frame_count: int = sprite_frames.get_frame_count(action)
	var precise_frame: float = phase * frame_count
	set_frame_and_progress(mini(int(precise_frame), frame_count - 1), fmod(precise_frame, 1.0))
	_update_collar(action, frame, frame_count)
	_previous_grounded = grounded
	_previous_speed = speed
	_previous_facing = player.facing_direction
	_last_position = player.global_position


func _update_collar(action: StringName, index: int, count: int) -> void:
	var phase: float = float(index) / float(count) * TAU
	var lean: float = 0.0
	var bounce: float = 0.0
	match action:
		&"idle": bounce = sin(phase) * 1.3
		&"walk":
			lean = 3.0
			bounce = -absf(cos(phase)) * 2.3
		&"run":
			lean = 11.0
			bounce = -absf(cos(phase)) * 5.0
		&"rise", &"takeoff":
			lean = 7.0
			bounce = -3.0 - index * 0.45
		&"fall": bounce = 1.0 + index * 0.5
		&"dash":
			lean = 24.0
			bounce = 9.0 + sin(phase) * 1.3
		&"land": bounce = (1.0 - float(index) / 3.0) * 11.0
		&"brake":
			lean = -12.0 + index * 2.0
			bounce = 3.0 - index * 0.7
		&"turn":
			lean = -8.0 + index * 3.0
			bounce = absf(sin(phase)) * 3.0
	collar_offset = Vector2((-7.0 + lean * 0.5) * player.facing_direction, -63.0 + bounce * 0.5)
