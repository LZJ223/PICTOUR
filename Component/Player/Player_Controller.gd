## 此脚本挂载在Player上，负责玩家移动、冲刺奔跑、碰撞箱和无人机状态。

class_name PlayerController
extends CharacterBody2D

enum Gait { WALK, RUN, DASH, AIR, UAV }

## 人物运动参数，速度为像素/秒，加速度为像素/秒平方。
@export var move_speed: float = 260.0
@export var run_speed: float = 420.0
@export var dash_speed: float = 600.0
@export var jump_speed: float = 620.0
@export var acceleration: float = 2400.0
@export var gravity_acceleration: float = 1800.0
@export var friction_deceleration: float = 2200.0
@export var air_acceleration: float = 900.0
@export var air_friction_deceleration: float = 80.0
@export var sprint_hold_threshold: float = 0.18
@export var dash_duration: float = 0.16
@export var dash_cooldown: float = 0.4
@export var jump_buffer_duration: float = 0.1
@export var coyote_duration: float = 0.1
## 新样板启用：松开 Space 提早结束上升；旧白模默认保持固定跳高。
@export var variable_jump_height: bool = false
@export_range(0.1, 1.0, 0.05) var jump_release_speed_factor: float = 0.55
## 无人机参数。
@export var UAV_move_speed: float = 350.0
@export var UAV_friction_deceleration: float = 1200.0
@export var UAV_distance: float = 400.0

## 节点信息。
@onready var body_collision_box: CollisionShape2D = $CollisionBox_Body
@onready var UAV_collision_box: CollisionShape2D = $CollisionBox_UAV
@onready var body_visual: Polygon2D = $Visual_Body
@onready var UAV_visual: Polygon2D = $Visual_UAV

## 可供关卡反馈与回归验证读取的状态。
var collision_group: int = 1
var activated: bool = false
var UAV_activated: bool = false
var player_body: Player_Object = null
var gait: Gait = Gait.WALK
var dash_active: bool = false
var is_running: bool = false
var facing_direction: int = 1

var _sprint_held_time: float = 0.0
var _sprint_pressed: bool = false
var _dash_time: float = 0.0
var _dash_cooldown_time: float = 0.0
var _dash_direction: int = 1
var _jump_buffer_time: float = 0.0
var _coyote_time: float = 0.0
var _air_speed_limit: float = 0.0
var _was_on_floor: bool = false


func _ready() -> void:
	activated = true
	UAV_collision_box.disabled = true


func _physics_process(delta: float) -> void:
	if not activated:
		return
	if UAV_activated:
		_process_uav(delta)
	else:
		_process_body(delta)


func _process_body(delta: float) -> void:
	var grounded: bool = is_on_floor()
	var direction: float = Input.get_axis("move_left", "move_right")
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
	if _jump_buffer_time > 0.0 and _coyote_time > 0.0:
		velocity.y = -jump_speed
		_air_speed_limit = maxf(move_speed, absf(velocity.x))
		_jump_buffer_time = 0.0
		_coyote_time = 0.0
	if variable_jump_height and Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= jump_release_speed_factor

	_was_on_floor = grounded
	move_and_slide()
	if is_on_wall():
		_dash_time = 0.0
		dash_active = false
		_air_speed_limit = move_speed
	_update_gait()


## Shift按下立即开始奔跑加速；时长阈值只决定释放时是否追加短冲刺。
func _update_sprint(delta: float, grounded: bool) -> void:
	if Input.is_action_just_pressed("sprint") or (Input.is_action_pressed("sprint") and not _sprint_pressed):
		_sprint_pressed = true
		_sprint_held_time = 0.0
	if _sprint_pressed and Input.is_action_pressed("sprint"):
		_sprint_held_time += delta
	is_running = _sprint_pressed and Input.is_action_pressed("sprint")
	if Input.is_action_just_released("sprint"):
		if _sprint_pressed and _sprint_held_time < sprint_hold_threshold and grounded and _dash_cooldown_time <= 0.0:
			_dash_direction = facing_direction
			_dash_time = dash_duration
			_dash_cooldown_time = dash_cooldown
		_sprint_pressed = false
		_sprint_held_time = 0.0
		is_running = false


func _update_gait() -> void:
	if dash_active:
		gait = Gait.DASH
	elif not is_on_floor():
		gait = Gait.AIR
	elif is_running:
		gait = Gait.RUN
	else:
		gait = Gait.WALK


func _process_uav(delta: float) -> void:
	gait = Gait.UAV
	if not is_instance_valid(player_body):
		velocity = Vector2.ZERO
		return
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var change_rate: float = acceleration if not direction.is_zero_approx() else UAV_friction_deceleration
	velocity = velocity.move_toward(direction * UAV_move_speed, change_rate * delta)
	var dist: Vector2 = global_position - player_body.global_position
	if dist.length() > UAV_distance:
		velocity -= dist.normalized() * (dist.length() - UAV_distance) * 60.0 * delta
	velocity = velocity.limit_length(UAV_move_speed)
	move_and_slide()


## 恢复检查点时清除冲刺、跳跃缓存和惯性，不改变位置与图层。
func reset_motion() -> void:
	velocity = Vector2.ZERO
	_sprint_held_time = 0.0
	_sprint_pressed = false
	_dash_time = 0.0
	_dash_cooldown_time = 0.0
	_jump_buffer_time = 0.0
	_coyote_time = 0.0
	_air_speed_limit = move_speed
	_was_on_floor = false
	dash_active = false
	is_running = false
	gait = Gait.UAV if UAV_activated else Gait.WALK


## 无人机状态切换，仍仅允许在地面启动。
func UAV_activate(condition: bool) -> bool:
	if condition and not is_on_floor():
		return false
	body_collision_box.disabled = condition
	body_visual.visible = not condition
	UAV_collision_box.disabled = not condition
	UAV_visual.visible = condition
	UAV_activated = condition
	reset_motion()
	return true


## 设置固定内容层的碰撞位；初始化由System显式同步。
func set_collision_group(group: int) -> void:
	assert(group >= 1 and group <= 32, "玩家碰撞组须在1到32之间！")
	collision_layer = 1 << (group - 1)
	collision_mask = collision_layer
	collision_group = group


## 保留原四层轮换入口。
func collision_group_change(direction: int) -> void:
	var new_collision_group: int = posmod(collision_group - direction - 1, Global.layer_count) + 1
	set_collision_group(new_collision_group)
