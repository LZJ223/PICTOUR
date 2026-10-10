## 此脚本挂载在Player上，负责玩家的移动逻辑、碰撞箱管理与无人机状态切换

class_name PlayerController
extends CharacterBody2D
## 人物运动参数
@export var move_speed: float = 260.0
@export var jump_speed: float = 620.0
## 离开地面后还能再跳几次。1 是二段跳，0 是只能在地面跳。
@export var air_jump_count: int = 1:
	set(value):
		air_jump_count = maxi(value, 0)
@export var acceleration: float = 80
@export var UAV_move_speed: float = 350
@export var gravity_acceleration: float = 1800.0
@export var friction_deceleration: float = 40
@export var UAV_friction_deceleration: float = 20
@export var UAV_distance: float = 400
## 节点信息
@onready var body_collision_box: CollisionPolygon2D = $CollisionBox_Body
@onready var UAV_collision_box: CollisionPolygon2D = $CollisionBox_UAV
@onready var body_visual: Polygon2D = $Visual_Body
@onready var UAV_visual: Polygon2D = $Visual_UAV
## 状态信息
var collision_group: int = 1
var activated: bool = false
var UAV_activated: bool = false
var _air_jumps_left: int = 0
var player_body: Player_Object = null
## 无人机系统使用的玩家（物体）节点资源预加载
const player_body_type = preload("res://Component/Object/Player_Object/Player_Object.tscn")

## 准备阶段绑定信号
func _ready() -> void:
	activated = true
	_air_jumps_left = air_jump_count
	SignalSystem.UAV_activate.connect(UAV_activate)

## 人物移动逻辑
func _physics_process(delta: float) -> void:
	if activated:
		## 无人机未激活
		if not UAV_activated:
			velocity.x += Input.get_axis("move_left", "move_right") * acceleration
			if abs(velocity.x) < friction_deceleration:
				velocity.x = 0
			else:
				velocity.x -= sign(velocity.x) * friction_deceleration
			velocity.x = clamp(velocity.x, -1 * move_speed, move_speed)
			var grounded := is_on_floor()
			if grounded:
				_air_jumps_left = air_jump_count
			else:
				velocity.y += gravity_acceleration * delta
			if Input.is_action_just_pressed("jump") and (grounded or _air_jumps_left > 0):
				if not grounded:
					_air_jumps_left -= 1
				velocity.y = -jump_speed
		## 无人机激活
		else:
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
		if velocity.length() > 0.0001:
			SignalSystem.timer_reset()
		move_and_slide()

## 无人机状态切换
func UAV_activate() -> void:
	if not UAV_activated and not is_on_floor():
		return
	UAV_activated = not UAV_activated
	body_collision_box.disabled = UAV_activated
	body_visual.visible = not UAV_activated
	UAV_collision_box.disabled = not UAV_activated
	UAV_visual.visible = UAV_activated
	velocity = Vector2.ZERO
	if UAV_activated:
		var current_layer: DepthLayer = Global.get_layer_at_slot(Global.current_layer_index)
		player_body = player_body_type.instantiate()
		current_layer.add_child(player_body)
		player_body.position = position
		player_body.collision_box.scale = scale
		player_body.update_layer_slot()
	else:
		var player_body_layer: DepthLayer = player_body.find_owner_layer()
		while player_body_layer.slot != Global.current_layer_index:
			SignalSystem.layer_cycle.emit(1, false)
		position = player_body.position
		scale = player_body.collision_box.scale
		player_body.queue_free()
		player_body = null

## 轮换图层时碰撞箱改变
func collision_group_change(direction: int) -> void:
	var new_collision_group: int = posmod(collision_group - direction - 1, Global.layer_count) + 1
	set_collision_layer_value(collision_group, false)
	set_collision_layer_value(new_collision_group, true)
	set_collision_mask_value(collision_group, false)
	set_collision_mask_value(new_collision_group, true)
	collision_group = new_collision_group
