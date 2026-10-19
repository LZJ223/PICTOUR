## 此脚本挂载在Player上，负责玩家的移动逻辑、碰撞箱管理与无人机状态切换

class_name PlayerController
extends CharacterBody2D

## 玩家状态机
enum PlayerState { NORMAL, UAV, RECALLING }

const UAV_RECALL_DURATION: float = 0.25

## 人物运动参数
@export var move_speed: float = 260.0
@export var jump_speed: float = 700
@export var UAV_move_speed: float = 350
@export var max_falling_speed: float = 600
@export var acceleration: float = 80
@export var gravity_acceleration: float =30.0
@export var friction_deceleration: float = 40
@export var UAV_friction_deceleration: float = 20
@export var UAV_distance: float = 750
## 节点信息
@onready var body_collision_box: CollisionPolygon2D = $CollisionBox_Body
@onready var UAV_collision_box: CollisionPolygon2D = $CollisionBox_UAV
@onready var player_animation: PlayerAnimation = $PlayerSprite
## 状态信息
var current_state: PlayerState = PlayerState.NORMAL
var player_body: LayerObject = null
var _recall_tween: Tween
var _was_on_floor: bool = true
var _step_wait: float = 0.0
const STEP_INTERVAL := 0.34
## 无人机系统使用的玩家（物体）节点资源预加载
const player_body_type: PackedScene = preload("res://Component/Object/Others/Player_Object.tscn")

## 准备阶段绑定信号
func _ready() -> void:
	SignalSystem.UAV_activate.connect(UAV_activate)

## 人物移动逻辑
func _physics_process(delta: float) -> void:
	if SignalSystem.dialogue_active:
		velocity = Vector2.ZERO
		SoundPlayer.stop(&"jump")
		player_animation.set_motion(0.0, true)
		return
	if Global.goal.completed:
		## 结算时只注入向右行走，不读取按键，保留碰撞、重力和行走动效。
		_update_normal(1.0, false)
	elif current_state == PlayerState.RECALLING:
		return
	else:
		## 观察目标只屏蔽输入，重力、惯性、碰撞和动画仍正常更新。
		var can_control: bool = not SignalSystem.looking_at_destination
		match current_state:
			PlayerState.NORMAL:
				_update_normal(Input.get_axis("move_left", "move_right") if can_control else 0.0, can_control)
			PlayerState.UAV:
				_update_uav(delta, can_control)
	if velocity.length() > 0.0001:
		SignalSystem.timer_reset()
	move_and_slide()
	_play_motion_sounds(delta)
	player_animation.set_motion(velocity.x, current_state == PlayerState.NORMAL and is_on_floor())

## 普通地面/空中移动
func _update_normal(input_axis: float, can_jump: bool = true) -> void:
	velocity.x += input_axis * acceleration
	if abs(velocity.x) < friction_deceleration:
		velocity.x = 0
	else:
		velocity.x -= sign(velocity.x) * friction_deceleration
	velocity.x = clamp(velocity.x, -move_speed, move_speed)
	if can_jump and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = -jump_speed
		player_animation.play_jump_flame()
		SoundPlayer.play_for(&"jump", &"player_jump")
		_step_wait = STEP_INTERVAL
	if not is_on_floor():
		velocity.y += gravity_acceleration
		velocity.y = clamp(velocity.y, jump_speed * -1, max_falling_speed)

## 无人机移动
func _update_uav(_delta: float, can_control: bool = true) -> void:
	if can_control:
		velocity.x += Input.get_axis("move_left", "move_right") * acceleration
		velocity.y += Input.get_axis("move_up", "move_down") * acceleration
	var dist: Vector2 = position - player_body.position
	if dist.length() > UAV_distance:
		velocity -= dist.normalized() * (dist.length() - UAV_distance)
	if velocity.length() > UAV_friction_deceleration:
		velocity -= velocity.normalized() * UAV_friction_deceleration
	else:
		velocity = Vector2.ZERO
	velocity = velocity.normalized() * clamp(velocity.length(), 0, UAV_move_speed)
	velocity.y = clamp(velocity.y, -1 * move_speed, move_speed)

## 无人机状态切换
func UAV_activate() -> void:
	if SignalSystem.dialogue_active or SignalSystem.looking_at_destination or Global.goal.completed or current_state == PlayerState.RECALLING:
		return
	if current_state == PlayerState.NORMAL and not is_on_floor():
		SoundPlayer.play(&"uav_fail")
		return
	if current_state == PlayerState.UAV:
		SoundPlayer.stop(&"uav_move")
		SoundPlayer.play(&"uav_off")
		_recall_uav()
	else:
		SoundPlayer.play(&"uav_on")
		SoundPlayer.play_for(&"uav_move", &"uav_move", true)
		_was_on_floor = true
		## 从普通切入无人机
		current_state = PlayerState.UAV
		body_collision_box.disabled = true
		UAV_collision_box.disabled = false
		player_animation.set_display_mode(PlayerAnimation.DisplayMode.HEAD_ONLY)
		velocity = Vector2.ZERO
		var current_layer: DepthLayer = Global.get_layer_at_slot(Global.current_layer_index)
		player_body = player_body_type.instantiate() as LayerObject
		current_layer.add_child(player_body)
		player_body.position = position
		player_body.collision_box.scale = scale
		player_body.update_layer_slot()
		var body_animation := player_body.visual_root.get_node("PlayerSprite") as PlayerAnimation
		body_animation.set_facing(player_animation.get_facing(), true)
		body_animation.set_motion(0.0, true)

## 位置回收与图层轮换并行；两者都结束后才恢复普通状态。
func _recall_uav() -> void:
	current_state = PlayerState.RECALLING
	velocity = Vector2.ZERO
	UAV_collision_box.disabled = true
	var body_animation := player_body.visual_root.get_node("PlayerSprite") as PlayerAnimation
	player_animation.set_facing(body_animation.get_facing())
	player_animation.set_motion(0.0, false)
	var layer_controller := get_tree().get_first_node_in_group("layer_controllers") as LayerControllerSystem
	while layer_controller.is_cycling():
		await layer_controller.cycle_finished
	var player_body_layer: DepthLayer = player_body.find_owner_layer()
	_recall_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_recall_tween.set_parallel(true)
	_recall_tween.tween_property(
		self, "global_position", player_body.global_position, UAV_RECALL_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_recall_tween.tween_property(
		self, "scale", player_body.collision_box.scale, UAV_RECALL_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	while player_body_layer.slot != Global.current_layer_index:
		layer_controller.cycle(1, false)
		await layer_controller.cycle_finished
	if _recall_tween.is_valid():
		await _recall_tween.finished
	_recall_tween = null
	global_position = player_body.global_position
	scale = player_body.collision_box.scale
	body_collision_box.disabled = false
	player_animation.set_facing(body_animation.get_facing(), true)
	player_animation.set_display_mode(PlayerAnimation.DisplayMode.FULL)
	current_state = PlayerState.NORMAL
	player_body.queue_free()
	player_body = null

## 脚步按间隔重播。跳跃声在落地时停，避免落地后还拖着。
func _play_motion_sounds(delta: float) -> void:
	if current_state != PlayerState.NORMAL:
		return
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		SoundPlayer.stop(&"jump")
		SoundPlayer.play(&"player_land")
		_step_wait = STEP_INTERVAL
	elif on_floor and absf(velocity.x) > 30.0:
		_step_wait -= delta
		if _step_wait <= 0.0:
			SoundPlayer.play(&"player_step")
			_step_wait = STEP_INTERVAL
	_was_on_floor = on_floor

## 改变碰撞图层
func set_collision_group(group: int) -> void:
	collision_mask = 0
	collision_layer = 0
	set_collision_layer_value(group, true)
	set_collision_mask_value(group, true)
