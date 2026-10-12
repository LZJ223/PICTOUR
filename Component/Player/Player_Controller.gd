## 此脚本挂载在Player上，负责玩家的移动逻辑、碰撞箱管理与无人机状态切换

class_name PlayerController
extends CharacterBody2D
## 人物运动参数
@export var move_speed: float = 260.0
@export var jump_speed: float = 620.0
## 离开地面后还能再跳几次。0 是只能在地面跳，1 是二段跳。
@export var air_jump_count: int = 0:
	set(value):
		air_jump_count = maxi(value, 0)
@export var acceleration: float = 80
@export var UAV_move_speed: float = 350
@export var gravity_acceleration: float = 1800.0
@export var friction_deceleration: float = 40
@export var UAV_friction_deceleration: float = 20
@export var UAV_distance: float = 400
## 弹力平台判定阈值：碰撞法线 y 分量小于此值才算"从上方踩下"。
## -1.0 是纯水平面，0.0 是垂直墙，-0.5 约为 60° 以下的坡面。
@export var bounce_normal_threshold: float = -0.5
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
	## 关掉地板吸附，否则弹起瞬间会被吸附回平台表面。
	floor_snap_length = 0.0
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
		if not UAV_activated:
			_handle_bounce()

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
	_set_collision_group(new_collision_group)

## 死亡触发器按记录恢复位置、所在层和大小。已经换层的物体不动。
func apply_recorded_state(recorded_position: Vector2, recorded_group: int, recorded_scale: Vector2) -> void:
	_leave_uav_without_returning()
	global_position = recorded_position
	scale = recorded_scale
	_set_collision_group(recorded_group)
	velocity = Vector2.ZERO
	_air_jumps_left = air_jump_count

func _set_collision_group(group: int) -> void:
	if group != collision_group:
		set_collision_layer_value(collision_group, false)
		set_collision_mask_value(collision_group, false)
		collision_group = group
	set_collision_layer_value(collision_group, true)
	set_collision_mask_value(collision_group, true)

func _leave_uav_without_returning() -> void:
	if not UAV_activated:
		return
	UAV_activated = false
	body_collision_box.disabled = false
	body_visual.visible = true
	UAV_collision_box.disabled = true
	UAV_visual.visible = false
	velocity = Vector2.ZERO
	if player_body != null:
		player_body.queue_free()
		player_body = null

## 玩家从上方踩到带 bounce_force 的平台时，沿法线弹起。
## 方案 D：保留切向速度，法向速度替换为平台弹力。
## 弹起后立即再 move_and_slide() 一次，确保离开平台表面，
## 否则下一帧会因仍在 floor 上而被重力/吸附拉回。
func _handle_bounce() -> void:
	var count := get_slide_collision_count()
	if count == 0:
		return
	for i in count:
		var collision: KinematicCollision2D = get_slide_collision(i)
		var normal: Vector2 = collision.get_normal()
		## 只处理从上方踩下的碰撞（法线朝上，y 分量小于阈值）。
		if normal.y >= bounce_normal_threshold:
			continue
		var platform: Platform = _find_platform(collision.get_collider())
		if platform == null or platform.bounce_force <= 0.0:
			continue
		## 分解速度：切向保留，法向替换为弹力方向（沿法线向上）。
		var normal_dot: float = velocity.dot(normal)
		var tangent_vel: Vector2 = velocity - normal * normal_dot
		velocity = tangent_vel + normal * platform.bounce_force
		## 立即用新速度移动一次，离开平台表面，避免被吸附回地面。
		move_and_slide()
		return

## 从碰撞体向上查找 Platform 节点。
func _find_platform(collider: Node) -> Platform:
	var current: Node = collider
	while current != null:
		if current is Platform:
			return current as Platform
		current = current.get_parent()
	return null
