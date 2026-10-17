## 自主巡逻物体。检测与运动使用物理坐标，局部动画不占用 VisualRoot。
class_name Bot
extends LayerObject

enum Facing { LEFT = -1, RIGHT = 1 }
enum PatrolState { WALKING, TURNING, WAITING, AIRBORNE }

const PROBE_SKIN: float = 0.5
const FLAT_NORMAL_Y: float = -0.9986 # 约 3°，只容忍地面的数值误差。

@export_group("巡逻")
@export_range(0.0, 1000.0, 1.0, "or_greater") var move_speed: float = 80.0
@export var initial_direction: Facing = Facing.RIGHT
## 前缘预留距离；还会自动加上下一物理帧的移动距离。
@export_range(1.0, 64.0, 0.5) var look_ahead: float = 6.0
@export_range(1.0, 32.0, 0.5) var ground_probe_distance: float = 6.0
## 允许的地面高度误差，不用于登阶。
@export_range(0.1, 4.0, 0.1) var flat_tolerance: float = 1.0

@export_group("巡逻动画")
@export_range(0.02, 0.3, 0.01) var turn_duration: float = 0.09
@export_range(0.0, 4.0, 0.05) var bob_amplitude: float = 0.5
@export_range(1.0, 30.0, 0.5) var bob_frequency: float = 6.0

@onready var _body: RigidBody2D = get_node(".") as RigidBody2D
@onready var _sprite: Node2D = $VisualRoot/BotSprite
@onready var _poses: Array[Sprite2D] = [
	$VisualRoot/BotSprite/BotLeft,
	$VisualRoot/BotSprite/BotMiddle,
	$VisualRoot/BotSprite/BotRight,
]
var _direction: int = 1
var _state: PatrolState = PatrolState.AIRBORNE
var _moving: bool = false
var _sprite_origin: Vector2
var _bob_phase: float = 0.0
var _bob_offset: float = 0.0
var _turn_tween: Tween
var _wall_shape := RectangleShape2D.new()
var _wall_query := PhysicsShapeQueryParameters2D.new()
var _ground_query := PhysicsRayQueryParameters2D.new()
var _background_motion: bool = false
var _background_velocity := Vector2.ZERO

func _ready() -> void:
	assert(_body != null, "Bot 的根节点必须为 RigidBody2D")
	_body.lock_rotation = true
	_body.can_sleep = false
	_direction = int(initial_direction)
	_sprite_origin = _sprite.position
	_show_pose(_direction)
	super._ready()
	_wall_query.shape = _wall_shape
	_wall_query.margin = 0.0
	_wall_query.exclude = [get_rid()]
	_wall_query.collide_with_areas = false
	_ground_query.exclude = [get_rid()]
	_ground_query.collide_with_areas = false

## 循环背景直接移动和回收父图层，使用受控运动避免刚体模拟覆盖局部位置。
func enable_background_motion() -> void:
	_background_motion = true
	_body.freeze = true
	## 先更新巡逻，再由背景统一滚动图层并同步视差，避免视觉位置落后一帧。
	process_priority = -1

func transfer_to(target_layer: DepthLayer, target_transform: Transform2D, target_collision_transform: Transform2D) -> void:
	super.transfer_to(target_layer, target_transform, target_collision_transform)
	## 切入悬空位置时不能沿用旧图层的水平速度，避免首帧仍向前滑动。
	_body.linear_velocity = Vector2(0.0, _body.linear_velocity.y)
	_moving = false

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	state.linear_velocity = _patrol_velocity(state.get_space_state(), state.transform, state.linear_velocity, state.step)

## 两种运行方式共用巡逻判断，检测始终位于真实物理坐标系。
func _patrol_velocity(space: PhysicsDirectSpaceState2D, body_transform: Transform2D, velocity: Vector2, delta: float) -> Vector2:
	_moving = false
	velocity.x = 0.0
	if (not _background_motion and SignalSystem.is_physics_resting()) or collision_box.disabled or collision_box.polygon.size() < 3:
		return velocity
	## 换层可改变碰撞箱大小与碰撞位，因此每帧读取当前物理状态。
	var bounds: Rect2 = body_transform * collision_box.transform * _polygon_bounds(collision_box.polygon)
	var unit_scale: float = absf(global_scale.x) if _background_motion else 1.0
	_ground_query.collision_mask = collision_mask
	_wall_query.collision_mask = collision_mask
	var ground := _sample_ground(space, bounds.get_center().x, bounds.end.y)
	if not _is_flat_ground(ground) or velocity.y < -1.0:
		if _state != PatrolState.TURNING:
			_state = PatrolState.AIRBORNE
	elif _state != PatrolState.TURNING:
		var distance: float = (look_ahead + move_speed * delta) * unit_scale
		if _can_advance(space, bounds, ground.position.y, _direction, distance):
			_state = PatrolState.WALKING
			velocity.x = _direction * move_speed * unit_scale
			_moving = move_speed > 0.0
		elif _can_advance(space, bounds, ground.position.y, -_direction, distance):
			_begin_turn()
		else:
			## 两侧都堵住时保留朝向，持续重试，避免每帧反复转身。
			_state = PatrolState.WAITING
	return velocity

func _sample_ground(space: PhysicsDirectSpaceState2D, x: float, foot_y: float) -> Dictionary:
	var unit_scale: float = absf(global_scale.y) if _background_motion else 1.0
	_ground_query.from = Vector2(x, foot_y - (flat_tolerance + PROBE_SKIN) * unit_scale)
	_ground_query.to = Vector2(x, foot_y + ground_probe_distance * unit_scale)
	return space.intersect_ray(_ground_query)

func _is_flat_ground(hit: Dictionary) -> bool:
	return not hit.is_empty() and hit.normal.y <= FLAT_NORMAL_Y

func _can_advance(
	space: PhysicsDirectSpaceState2D, bounds: Rect2, ground_y: float,
	direction: int, distance: float
) -> bool:
	var edge_x: float = bounds.end.x if direction > 0 else bounds.position.x
	var ahead := _sample_ground(space, edge_x + direction * distance, ground_y)
	var unit_scale: float = absf(global_scale.y) if _background_motion else 1.0
	if not _is_flat_ground(ahead) or absf(ahead.position.y - ground_y) > flat_tolerance * unit_scale:
		return false
	## 用覆盖整个前缘高度的扫掠区域检测墙和低矮障碍；底部略收缩以排除脚下地面。
	_wall_shape.size = Vector2(distance + PROBE_SKIN, maxf(bounds.size.y - PROBE_SKIN * 2.0, PROBE_SKIN))
	_wall_query.transform = Transform2D(0.0, Vector2(
		edge_x + direction * (distance - PROBE_SKIN) * 0.5, bounds.get_center().y
	))
	return space.intersect_shape(_wall_query, 1).is_empty()

func _begin_turn() -> void:
	_state = PatrolState.TURNING
	_direction = -_direction
	_show_pose(0)
	_turn_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_turn_tween.tween_interval(turn_duration)
	_turn_tween.tween_callback(_finish_turn)

func _finish_turn() -> void:
	_show_pose(_direction)
	_state = PatrolState.WAITING
	_turn_tween = null

func _show_pose(direction: int) -> void:
	for index in _poses.size():
		_poses[index].visible = index == direction + 1
	if _selected:
		_sync_selection_outlines()

func _process(delta: float) -> void:
	if _background_motion:
		_move_background(delta)
	var resting: bool = not _background_motion and (SignalSystem.is_physics_resting() or _body.freeze)
	if _turn_tween != null and _turn_tween.is_valid():
		if resting:
			_turn_tween.pause()
		elif not _turn_tween.is_running():
			_turn_tween.play()
	if resting:
		return
	if _moving:
		_bob_phase = fposmod(_bob_phase + TAU * bob_frequency * delta, TAU)
		_bob_offset = sin(_bob_phase) * bob_amplitude
	else:
		_bob_offset = move_toward(_bob_offset, 0.0, delta * maxf(bob_amplitude, 0.1) * 20.0)
	_sprite.position = _sprite_origin + Vector2(0.0, _bob_offset)

func _move_background(delta: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)
	_background_velocity.y += gravity * _body.gravity_scale * absf(global_scale.y) * delta
	_background_velocity = _patrol_velocity(get_world_2d().direct_space_state, global_transform, _background_velocity, delta)
	var motion := _background_velocity * delta
	## 先碰到地面时保留水平余量，避免对角运动每帧被地面截停。
	for step in 2:
		var hit := move_and_collide(motion)
		if hit == null:
			break
		_background_velocity = _background_velocity.slide(hit.get_normal())
		motion = hit.get_remainder().slide(hit.get_normal())
