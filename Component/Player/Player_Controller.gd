## 此脚本挂载在Player上，负责玩家的移动逻辑、碰撞箱管理与无人机状态切换

class_name PlayerController
extends CharacterBody2D

## 玩家状态机
enum PlayerState { NORMAL, ON_ROPE, UAV }

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
var current_state: PlayerState = PlayerState.NORMAL
var _air_jumps_left: int = 0
var player_body: Player_Object = null
## 藤蔓交互
var _grabable_vines: Array[Vine] = []
var _current_vine: Vine = null
## 搬箱子
var _carried_box: Box = null
## 搬起时箱子相对于玩家的偏移（抱着，放在身体前方偏上）
@export var carry_offset: Vector2 = Vector2(16, -20)
## 可搬起箱子的最大距离（像素）
@export var pickup_range: float = 60.0
## 放下时箱子与玩家的水平距离，避免与玩家碰撞体重叠卡住
@export var drop_clearance: float = 32.0
## 玩家当前朝向（1=右，-1=左），用于抱着箱子时的位置
var _facing: float = 1.0
## 松手后的惯性保护时间（秒），期间不施加水平摩擦和速度上限，
## 确保摆荡惯性不会被 move_speed 钳位和摩擦立即抹消。
@export var release_inertia_time: float = 0.4
var _inertia_timer: float = 0.0
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
	if not activated:
		return
	match current_state:
		PlayerState.NORMAL:
			_update_normal(delta)
		PlayerState.ON_ROPE:
			_update_on_rope(delta)
		PlayerState.UAV:
			_update_uav(delta)
	if velocity.length() > 0.0001:
		SignalSystem.timer_reset()
	if current_state != PlayerState.ON_ROPE:
		move_and_slide()
		if current_state == PlayerState.NORMAL:
			_handle_bounce()
	## 搬起的箱子跟随玩家头顶
	if _carried_box != null:
		_sync_carried_box()


## 由风扇调用，根据当前状态处理风力。
## - NORMAL：直接加到 velocity，并限制风力方向的速度上限
## - ON_ROPE：转发给当前藤蔓，作为钟摆外力
## - UAV：无人机不受风
func apply_wind_force(direction: Vector2, force: float, max_speed: float, delta: float) -> void:
	match current_state:
		PlayerState.NORMAL:
			velocity += direction * force * delta
			var vel_along_wind: float = velocity.dot(direction)
			if vel_along_wind > max_speed:
				velocity -= direction * (vel_along_wind - max_speed)
		PlayerState.ON_ROPE:
			if _current_vine != null:
				_current_vine.apply_wind_force(direction, force, delta)
		PlayerState.UAV:
			pass

## 普通地面/空中移动
func _update_normal(delta: float) -> void:
	var input_axis: float = Input.get_axis("move_left", "move_right")
	velocity.x += input_axis * acceleration
	## 更新朝向（用于抱着箱子时的位置）
	if abs(input_axis) > 0.01:
		_facing = sign(input_axis)
	if _inertia_timer > 0.0:
		## 惯性保护期：施加较弱的摩擦让速度自然衰减，不硬钳位到 move_speed，
		## 但保留 2 倍 move_speed 的软上限，防止输入叠加导致速度失控。
		_inertia_timer -= delta
		var reduced_friction: float = friction_deceleration * 0.3
		if abs(velocity.x) < reduced_friction:
			velocity.x = 0
		else:
			velocity.x -= sign(velocity.x) * reduced_friction
		var soft_limit: float = move_speed * 2.0
		if abs(velocity.x) > soft_limit:
			velocity.x = sign(velocity.x) * soft_limit
	else:
		if abs(velocity.x) < friction_deceleration:
			velocity.x = 0
		else:
			velocity.x -= sign(velocity.x) * friction_deceleration
		velocity.x = clamp(velocity.x, -move_speed, move_speed)
	var grounded := is_on_floor()
	if grounded:
		_air_jumps_left = air_jump_count
		## 落地后结束惯性保护
		_inertia_timer = 0.0
	else:
		velocity.y += gravity_acceleration * delta
	if Input.is_action_just_pressed("jump") and (grounded or _air_jumps_left > 0):
		if not grounded:
			_air_jumps_left -= 1
		velocity.y = -jump_speed
	## F 键：先尝试搬起/放下箱子，没有箱子时再抓藤蔓
	if Input.is_action_just_pressed("grab"):
		if not _try_pickup_or_drop_box():
			_try_grab_vine()

## 藤蔓攀爬/摆荡：位置由藤蔓驱动，不调用 move_and_slide
func _update_on_rope(delta: float) -> void:
	if _current_vine == null:
		_force_release_vine()
		return
	## 空格松开藤蔓，获得切向惯性速度
	if Input.is_action_just_pressed("jump"):
		_release_vine()
		return
	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	global_position = _current_vine.update_swing(delta, input)

## 无人机移动
func _update_uav(delta: float) -> void:
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

## 尝试抓取最近的可抓取藤蔓。
## 主动扫描场景中所有 vines 组的藤蔓，不依赖 Area2D 信号注册，
## 确保高速飞行中也能抓到下一根绳子。
func _try_grab_vine() -> void:
	var candidates: Array[Vine] = []
	for node in get_tree().get_nodes_in_group("vines"):
		if node is Vine:
			candidates.append(node as Vine)
	if candidates.is_empty():
		return
	## 找最近的藤蔓（按到锚点的距离粗筛）
	var nearest: Vine = candidates[0]
	var min_dist: float = global_position.distance_to(nearest.global_position)
	for vine in candidates:
		var d: float = global_position.distance_to(vine.global_position)
		if d < min_dist:
			min_dist = d
			nearest = vine
	if nearest.try_grab(self):
		_current_vine = nearest
		current_state = PlayerState.ON_ROPE
		## 藤蔓上禁用实体碰撞，位置完全由藤蔓驱动
		body_collision_box.disabled = true
		velocity = Vector2.ZERO
		_inertia_timer = 0.0

## 主动松开藤蔓，获得切向惯性速度
func _release_vine() -> void:
	if _current_vine == null:
		return
	velocity = _current_vine.release()
	_current_vine = null
	current_state = PlayerState.NORMAL
	body_collision_box.disabled = false
	_air_jumps_left = air_jump_count
	## 启动惯性保护期，避免水平惯性被摩擦和速度上限立即抹消
	_inertia_timer = release_inertia_time

## 强制松开藤蔓（换层、死亡等），不保留惯性速度
func _force_release_vine() -> void:
	if _current_vine != null:
		_current_vine.force_release()
		_current_vine = null
	current_state = PlayerState.NORMAL
	body_collision_box.disabled = false
	velocity = Vector2.ZERO
	_inertia_timer = 0.0

## 由藤蔓 GrabArea 调用，注册可抓取藤蔓
func register_grabable_vine(vine: Vine) -> void:
	if vine not in _grabable_vines:
		_grabable_vines.append(vine)

## 由藤蔓 GrabArea 调用，注销可抓取藤蔓
func unregister_grabable_vine(vine: Vine) -> void:
	_grabable_vines.erase(vine)

## F 键：搬起或放下箱子。返回 true 表示本次按键由箱子逻辑消费。
func _try_pickup_or_drop_box() -> bool:
	if current_state != PlayerState.NORMAL:
		return false
	if _carried_box != null:
		_drop_box()
		return true
	var box := _find_nearest_box()
	if box != null:
		_pickup_box(box)
		return true
	return false

## 查找玩家附近同图层、可搬起的箱子
func _find_nearest_box() -> Box:
	var nearest: Box = null
	var min_dist: float = pickup_range
	var player_layer_id: int = collision_group - 1
	for node in get_tree().get_nodes_in_group("layer_objects"):
		if not (node is Box):
			continue
		var box := node as Box
		if box.is_carried():
			continue
		if not box.carriable:
			continue
		if box.owner_layer == null or box.owner_layer.layer_id != player_layer_id:
			continue
		var d: float = global_position.distance_to(box.global_position)
		if d < min_dist:
			min_dist = d
			nearest = box
	return nearest

func _pickup_box(box: Box) -> void:
	_carried_box = box
	box.set_carried(true)
	## 如果箱子正被选中，取消选中避免换层冲突
	if Global.object_selected == box:
		box.set_pick_condition(false)
		Global.object_selected = null
	_sync_carried_box()

func _drop_box() -> void:
	if _carried_box == null:
		return
	var box := _carried_box
	## 先放到玩家正前方安全距离，再恢复物理碰撞，避免在玩家碰撞体内生成
	box.global_position = global_position + Vector2(_facing * drop_clearance, carry_offset.y)
	box.set_carried(false)
	_carried_box = null

## 将搬起的箱子同步到玩家身前（抱着）
func _sync_carried_box() -> void:
	if _carried_box == null:
		return
	_carried_box.global_position = global_position + Vector2(_facing * abs(carry_offset.x), carry_offset.y)

## 强制放下箱子（换层、死亡、切无人机等状态切换时调用）
func _force_drop_box() -> void:
	if _carried_box != null:
		_carried_box.set_carried(false)
		_carried_box = null

## 无人机状态切换
func UAV_activate() -> void:
	## 藤蔓上不能切换无人机
	if current_state == PlayerState.ON_ROPE:
		return
	if current_state == PlayerState.NORMAL and not is_on_floor():
		return
	## 切换无人机前放下箱子
	_force_drop_box()
	if current_state == PlayerState.UAV:
		## 从无人机切回普通
		current_state = PlayerState.NORMAL
		body_collision_box.disabled = false
		body_visual.visible = true
		UAV_collision_box.disabled = true
		UAV_visual.visible = false
		velocity = Vector2.ZERO
		var player_body_layer: DepthLayer = player_body.find_owner_layer()
		while player_body_layer.slot != Global.current_layer_index:
			SignalSystem.layer_cycle.emit(1, false)
		position = player_body.position
		scale = player_body.collision_box.scale
		player_body.queue_free()
		player_body = null
	else:
		## 从普通切入无人机
		current_state = PlayerState.UAV
		body_collision_box.disabled = true
		body_visual.visible = false
		UAV_collision_box.disabled = false
		UAV_visual.visible = true
		velocity = Vector2.ZERO
		var current_layer: DepthLayer = Global.get_layer_at_slot(Global.current_layer_index)
		player_body = player_body_type.instantiate()
		current_layer.add_child(player_body)
		player_body.position = position
		player_body.collision_box.scale = scale
		player_body.update_layer_slot()

## 轮换图层时碰撞箱改变。藤蔓上换层强制松开。
func collision_group_change(direction: int) -> void:
	if current_state == PlayerState.ON_ROPE:
		_force_release_vine()
	_force_drop_box()
	var new_collision_group: int = posmod(collision_group - direction - 1, Global.layer_count) + 1
	_set_collision_group(new_collision_group)

## 死亡触发器按记录恢复位置、所在层和大小。已经换层的物体不动。
func apply_recorded_state(recorded_position: Vector2, recorded_group: int, recorded_scale: Vector2) -> void:
	_force_release_vine()
	_force_drop_box()
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
	if current_state != PlayerState.UAV:
		return
	current_state = PlayerState.NORMAL
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
