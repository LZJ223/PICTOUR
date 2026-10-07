## 此脚本挂载在Player上，负责玩家的移动逻辑（以及碰撞箱管理），外观状态切换

class_name PlayerController
extends CharacterBody2D
## 人物运动参数
@export var move_speed: float = 260.0
@export var jump_speed: float = 620.0
@export var acceleration: float = 80
@export var UAV_move_speed: float = 350
@export var gravity_acceleration: float = 1800.0
@export var friction_deceleration: float = 40
@export var UAV_friction_deceleration: float = 20
@export var UAV_distance: float = 400
## 节点信息
@onready var body_collision_box: CollisionShape2D = $CollisionBox_Body
@onready var UAV_collision_box: CollisionShape2D = $CollisionBox_UAV
@onready var body_visual: Polygon2D = $Visual_Body
@onready var UAV_visual: Polygon2D = $Visual_UAV
## 状态信息
var collision_group: int = 1
var activated: bool = false
var UAV_activated: bool = false
var player_body: Player_Object = null

## 准备阶段绑定信号
func _ready() -> void:
	activated = true
	Global.layer_cycle.connect(collision_group_change)

## 人物移动逻辑
func _physics_process(delta: float) -> void:
	if activated:
		## 无人机未激活
		if not UAV_activated:
			velocity.x += Input.get_axis("move_left", "move_right") * acceleration
			velocity.x -= sign(velocity.x) * friction_deceleration
			velocity.x = clamp(velocity.x, -1 * move_speed, move_speed)
			if not is_on_floor():
				velocity.y += gravity_acceleration * delta
			if Input.is_action_just_pressed("jump") and is_on_floor():
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
		move_and_slide()

## 无人机状态切换
func UAV_activate(condition: bool) -> bool:
	if condition and not is_on_floor():
		return false
	body_collision_box.disabled = condition
	body_visual.visible = not condition
	UAV_collision_box.disabled = not condition
	UAV_visual.visible = condition
	UAV_activated = condition
	velocity = Vector2.ZERO
	return true

## 轮换图层时碰撞箱改变
func collision_group_change(direction: int) -> void:
	var new_collision_group: int = posmod(collision_group - direction - 1, Global.layer_count) + 1
	set_collision_layer_value(collision_group, false)
	set_collision_layer_value(new_collision_group, true)
	set_collision_mask_value(collision_group, false)
	set_collision_mask_value(new_collision_group, true)
	collision_group = new_collision_group
