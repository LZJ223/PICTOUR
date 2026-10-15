## 此脚本挂载在Player上，负责玩家的移动逻辑、碰撞箱管理与无人机状态切换

class_name PlayerController
extends CharacterBody2D

## 玩家状态机
enum PlayerState { NORMAL, UAV, RECALLING }

const UAV_RECALL_DURATION: float = 0.25

## 人物运动参数
@export var move_speed: float = 260.0
@export var jump_speed: float = 620.0
@export var UAV_move_speed: float = 350
@export var max_falling_speed: float = 600
@export var acceleration: float = 80
@export var gravity_acceleration: float =30.0
@export var friction_deceleration: float = 40
@export var UAV_friction_deceleration: float = 20
@export var UAV_distance: float = 400
## 节点信息
@onready var body_collision_box: CollisionPolygon2D = $CollisionBox_Body
@onready var UAV_collision_box: CollisionPolygon2D = $CollisionBox_UAV
@onready var body_visual: Polygon2D = $Visual_Body
@onready var UAV_visual: Polygon2D = $Visual_UAV
## 状态信息
var current_state: PlayerState = PlayerState.NORMAL
var player_body: LayerObject = null
## 无人机系统使用的玩家（物体）节点资源预加载
const player_body_type: PackedScene = preload("res://Component/Object/Player_Object.tscn")

## 准备阶段绑定信号
func _ready() -> void:
	SignalSystem.UAV_activate.connect(UAV_activate)

## 人物移动逻辑
func _physics_process(delta: float) -> void:
	if current_state == PlayerState.RECALLING:
		return
	match current_state:
		PlayerState.NORMAL:
			_update_normal(delta)
		PlayerState.UAV:
			_update_uav(delta)
	if velocity.length() > 0.0001:
		SignalSystem.timer_reset()
	move_and_slide()

## 普通地面/空中移动
func _update_normal(_delta: float) -> void:
	var input_axis: float = Input.get_axis("move_left", "move_right")
	velocity.x += input_axis * acceleration
	if abs(velocity.x) < friction_deceleration:
		velocity.x = 0
	else:
		velocity.x -= sign(velocity.x) * friction_deceleration
	velocity.x = clamp(velocity.x, -move_speed, move_speed)
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = -jump_speed
	if not is_on_floor():
		velocity.y += gravity_acceleration
		velocity.y = clamp(velocity.y, jump_speed * -1, max_falling_speed)

## 无人机移动
func _update_uav(_delta: float) -> void:
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
	if current_state == PlayerState.RECALLING:
		return
	if current_state == PlayerState.NORMAL and not is_on_floor():
		return
	if current_state == PlayerState.UAV:
		_recall_uav()
	else:
		## 从普通切入无人机
		current_state = PlayerState.UAV
		body_collision_box.disabled = true
		body_visual.visible = false
		UAV_collision_box.disabled = false
		UAV_visual.visible = true
		velocity = Vector2.ZERO
		var current_layer: DepthLayer = Global.get_layer_at_slot(Global.current_layer_index)
		player_body = player_body_type.instantiate() as LayerObject
		current_layer.add_child(player_body)
		player_body.position = position
		player_body.collision_box.scale = scale
		player_body.update_layer_slot()

## 位置回收与图层轮换并行；两者都结束后才恢复普通状态。
func _recall_uav() -> void:
	current_state = PlayerState.RECALLING
	velocity = Vector2.ZERO
	UAV_collision_box.disabled = true
	var layer_controller := get_tree().get_first_node_in_group("layer_controllers") as LayerControllerSystem
	while layer_controller.is_cycling():
		await layer_controller.cycle_finished
	var player_body_layer: DepthLayer = player_body.find_owner_layer()
	var position_tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	position_tween.tween_property(
		self, "global_position", player_body.global_position, UAV_RECALL_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	while player_body_layer.slot != Global.current_layer_index:
		layer_controller.cycle(1, false)
		await layer_controller.cycle_finished
	if position_tween.is_running():
		await position_tween.finished
	global_position = player_body.global_position
	scale = player_body.collision_box.scale
	body_collision_box.disabled = false
	body_visual.visible = true
	UAV_visual.visible = false
	current_state = PlayerState.NORMAL
	player_body.queue_free()
	player_body = null

## 改变碰撞图层
func set_collision_group(group: int) -> void:
	collision_mask = 0
	collision_layer = 0
	set_collision_layer_value(group, true)
	set_collision_mask_value(group, true)
