## 只管理贴图、可见性与局部动效，不改变角色或物体的物理变换。
class_name PlayerAnimation
extends Node2D

enum DisplayMode { FULL, HEAD_ONLY, BODY_ONLY }

const FACE_SPEED_THRESHOLD: float = 8.0
const WHEEL_RADIUS: float = 7.083333
const WHEEL_SPEED_FACTOR: float = 0.35
const IDLE_BOB_AMPLITUDE: float = 0.7
const IDLE_BOB_FREQUENCY: float = 3.0
const WALK_BOB_AMPLITUDE: float = 0.45
const WALK_BOB_FREQUENCY: float = 14.0
const UAV_MAX_TILT: float = 0.24
const UAV_FULL_TILT_SPEED: float = 300.0
const SMALL_FLAME: Texture2D = preload("res://Texture/Player/Player_Flame_01.png")
const LARGE_FLAME: Texture2D = preload("res://Texture/Player/Player_Flame_02.png")
const EXPRESSIONS: Array[Texture2D] = [
	preload("res://Texture/Player/Player_Expression_01.png"),
	preload("res://Texture/Player/Player_Expression_02.png"),
	preload("res://Texture/Player/Player_Expression_03.png"),
]

@export var display_mode: DisplayMode = DisplayMode.FULL
@export_range(0.02, 0.3, 0.01) var turn_duration: float = 0.09
@export_range(0.0, 1.0, 0.01) var expression_middle_time: float = 0.35

@onready var _poses: Array[Node2D] = [$Left, $Middle, $Right]
@onready var _heads: Array[Node2D] = [$Left/HeadRig, $Middle/HeadRig, $Right/HeadRig]
@onready var _bodies: Array[Node2D] = [$Left/BodyRig, $Middle/BodyRig, $Right/BodyRig]
@onready var _feet: Array[Node2D] = [$Left/FootRig, $Middle/FootRig, $Right/FootRig]
@onready var _lights: Array[Sprite2D] = [
	$Left/HeadRig/PlayerPropellerLight,
	$Middle/HeadRig/PlayerPropellerLight,
	$Right/HeadRig/PlayerPropellerLight,
]
@onready var _expressions: Array[Sprite2D] = [
	$Left/HeadRig/PlayerExpression,
	$Right/HeadRig/PlayerExpression,
]
@onready var _flames: Array[Sprite2D] = [
	$Left/BodyRig/PlayerFlame,
	$Right/BodyRig/PlayerFlame,
]
@onready var _wheels: Array[Sprite2D] = [
	$Left/FootRig/PlayerWheel01,
	$Left/FootRig/PlayerWheel02,
	$Left/FootRig/PlayerWheel03,
	$Right/FootRig/PlayerWheel01,
	$Right/FootRig/PlayerWheel02,
	$Right/FootRig/PlayerWheel03,
]

var _facing: int = 1
var _speed_x: float = 0.0
var _grounded: bool = true
var _phase: float = 0.0
var _bob_amplitude: float = 0.0
var _bob_frequency: float = IDLE_BOB_FREQUENCY
var _head_tilt: float = 0.0
var _wheel_angle: float = 0.0
var _head_base_y: Array[float] = []
var _wheel_base_angles: Array[float] = []
var _expression_index: int = -1
var _turn_tween: Tween
var _flame_tween: Tween

func _ready() -> void:
	for head in _heads:
		_head_base_y.append(head.position.y)
	for wheel in _wheels:
		_wheel_base_angles.append(wheel.rotation)
	_show_pose(_facing)
	set_display_mode(display_mode)
	_set_flame_visible(false)
	_update_expression()

func _process(delta: float) -> void:
	var resting: bool = SignalSystem.timer != null and SignalSystem.timer.is_stopped()
	var can_bob: bool = not resting and (
		display_mode == DisplayMode.HEAD_ONLY
		or (display_mode == DisplayMode.FULL and _grounded)
	)
	var moving: bool = can_bob and absf(_speed_x) > FACE_SPEED_THRESHOLD
	if can_bob:
		var target_amplitude: float = WALK_BOB_AMPLITUDE if moving else IDLE_BOB_AMPLITUDE
		_bob_amplitude = move_toward(_bob_amplitude, target_amplitude, delta * 5.0)
	else:
		_bob_amplitude = 0.0
	_bob_frequency = lerpf(
		_bob_frequency,
		WALK_BOB_FREQUENCY if moving else IDLE_BOB_FREQUENCY,
		minf(delta * 12.0, 1.0)
	)
	_phase += TAU * _bob_frequency * delta
	var target_tilt: float = (
		clampf(_speed_x / UAV_FULL_TILT_SPEED, -1.0, 1.0) * UAV_MAX_TILT
		if display_mode == DisplayMode.HEAD_ONLY else 0.0
	)
	_head_tilt = lerp_angle(_head_tilt, target_tilt, minf(delta * 9.0, 1.0))
	for index in _poses.size():
		_heads[index].position.y = _head_base_y[index] + sin(_phase + 0.55) * _bob_amplitude
		_heads[index].rotation = _head_tilt
		_bodies[index].position.y = sin(_phase) * _bob_amplitude * 0.7
	if moving and display_mode == DisplayMode.FULL:
		_wheel_angle += _speed_x * delta / WHEEL_RADIUS * WHEEL_SPEED_FACTOR
	for index in _wheels.size():
		_wheels[index].rotation = _wheel_base_angles[index] + _wheel_angle
	_update_expression()

func set_motion(speed_x: float, grounded: bool) -> void:
	_speed_x = speed_x
	_grounded = grounded
	if absf(speed_x) > FACE_SPEED_THRESHOLD:
		set_facing(-1 if speed_x < 0.0 else 1)

func get_facing() -> int:
	return _facing

func set_facing(direction: int, instant: bool = false) -> void:
	var next_facing: int = -1 if direction < 0 else 1
	if next_facing == _facing and not instant:
		return
	_facing = next_facing
	if _turn_tween != null and _turn_tween.is_valid():
		_turn_tween.kill()
	_turn_tween = null
	if instant:
		_show_pose(_facing)
		return
	_show_pose(0)
	_turn_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_turn_tween.tween_interval(turn_duration)
	_turn_tween.tween_callback(_show_pose.bind(_facing))

func set_display_mode(mode: DisplayMode) -> void:
	display_mode = mode
	if mode == DisplayMode.BODY_ONLY:
		_bob_amplitude = 0.0
	for index in _poses.size():
		_heads[index].visible = mode != DisplayMode.BODY_ONLY
		_bodies[index].visible = mode != DisplayMode.HEAD_ONLY
		_feet[index].visible = mode != DisplayMode.HEAD_ONLY
		_lights[index].visible = mode == DisplayMode.HEAD_ONLY
	if mode == DisplayMode.HEAD_ONLY:
		_stop_flame()

func play_jump_flame() -> void:
	if display_mode != DisplayMode.FULL:
		return
	_stop_flame()
	_set_flame(SMALL_FLAME)
	_flame_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_flame_tween.tween_interval(0.055)
	_flame_tween.tween_callback(_set_flame.bind(LARGE_FLAME))
	_flame_tween.tween_interval(0.09)
	_flame_tween.tween_callback(_set_flame.bind(SMALL_FLAME))
	_flame_tween.tween_interval(0.065)
	_flame_tween.tween_callback(_finish_flame)

func _show_pose(direction: int) -> void:
	for index in _poses.size():
		_poses[index].visible = index == direction + 1

func _set_flame(texture: Texture2D) -> void:
	for flame in _flames:
		flame.texture = texture
		flame.visible = true

func _set_flame_visible(visible_now: bool) -> void:
	for flame in _flames:
		flame.visible = visible_now

func _stop_flame() -> void:
	if _flame_tween != null and _flame_tween.is_valid():
		_flame_tween.kill()
	_flame_tween = null
	_set_flame_visible(false)

func _finish_flame() -> void:
	_flame_tween = null
	_set_flame_visible(false)

func _update_expression() -> void:
	if SignalSystem.timer == null:
		return
	var next_index: int = 2 if SignalSystem.timer.is_stopped() else (
		1 if SignalSystem.timer.time_left <= expression_middle_time else 0
	)
	if next_index == _expression_index:
		return
	_expression_index = next_index
	for expression in _expressions:
		expression.texture = EXPRESSIONS[next_index]
