## 风扇通用组件。产生风区，对进入风区的玩家和玩家本体施加持续风力。
## 风力方向、大小、风区范围均可配置。可被触发器开关。
## 与玩家同图层时才生效（由碰撞层保证）。
## UAV 状态下无人机不受风，但留在层上的玩家本体（Player_Object）受风。

@tool
class_name Fan
extends LayerObject

## 被触发器调用时的动作
enum ActivationKind { NONE, TURN_ON, TURN_OFF, TOGGLE }

@export_group("风力")
## 风力方向，会自动归一化。默认向上吹。
@export var wind_direction: Vector2 = Vector2(0, -1):
	set(value):
		wind_direction = value.normalized() if value.length() > 0.001 else Vector2(0, -1)
## 风力加速度（px/s²）。越大推得越快。
@export var wind_force: float = 1200.0
## 风力能达到的最大速度（px/s），仅限制风力方向上的速度分量。
@export var max_wind_speed: float = 600.0

@export_group("风区")
## 风区矩形大小。
@export var wind_area_size: Vector2 = Vector2(120, 300)
## 风区相对于风扇中心的偏移。
@export var wind_area_offset: Vector2 = Vector2(0, -150)

@export_group("开关")
## 关卡开始时是否开启。
@export var active_on_start: bool = true
## 被触发器调用时的动作。
@export var activation_kind: ActivationKind = ActivationKind.TOGGLE

@export_group("碰撞")
## 风扇本体是否作为实体碰撞。
@export var has_collision: bool = true

var _active: bool = true

@onready var _wind_area: Area2D = $WindArea
@onready var _wind_shape: CollisionShape2D = $WindArea/CollisionShape2D
@onready var _wind_zone: Polygon2D = $WindArea/Zone
@onready var _fan_polygon: Polygon2D = $VisualRoot/Polygon2D


func _ready() -> void:
	_active = active_on_start
	## 先于玩家执行风力，避免风力被玩家摩擦覆盖
	process_priority = -10
	super()
	_sync_wind_area()
	if Engine.is_editor_hint():
		return
	## 不使用 body_entered/body_exited 信号：藤蔓摆动时玩家位置通过直接赋值
	## global_position 移动（非 move_and_slide），进入/退出信号触发不可靠，
	## 会导致玩家摆回风区后风力不再生效。改为每帧主动查询重叠物体。


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_wind_area()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not _active:
		return
	## 每帧主动查询风区内的物体，确保藤蔓摆动等瞬移场景下风力持续生效
	for body in _wind_area.get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		_apply_wind(body, delta)


## 对单个受影响物体施加风力
func _apply_wind(body: Node2D, delta: float) -> void:
	if body is PlayerController:
		var player: PlayerController = body as PlayerController
		player.apply_wind_force(wind_direction, wind_force, max_wind_speed, delta)
	elif body is Player_Object:
		var obj: Player_Object = body as Player_Object
		obj.apply_wind_force(wind_direction, wind_force, max_wind_speed, delta)


func activate() -> void:
	match activation_kind:
		ActivationKind.TURN_ON:
			_active = true
		ActivationKind.TURN_OFF:
			_active = false
		ActivationKind.TOGGLE:
			_active = not _active
	if _wind_zone != null:
		_wind_zone.visible = _active


func update_layer_slot() -> void:
	super()
	## 同步风区碰撞层，确保只有同图层物体被检测
	if _wind_area != null and owner_layer != null:
		_wind_area.collision_layer = 0
		_wind_area.collision_mask = 0
		_wind_area.set_collision_layer_value(owner_layer.layer_id + 1, true)
		_wind_area.set_collision_mask_value(owner_layer.layer_id + 1, true)
	## 风扇本体碰撞
	if collision_box != null:
		collision_box.disabled = not has_collision


## 同步风区形状和视觉
func _sync_wind_area() -> void:
	if _wind_shape == null:
		return
	var shape = _wind_shape.shape
	if shape is RectangleShape2D:
		shape.size = wind_area_size
	_wind_shape.position = wind_area_offset
	## 同步视觉区域
	if _wind_zone != null:
		var half: Vector2 = wind_area_size * 0.5
		_wind_zone.polygon = PackedVector2Array([
			Vector2(-half.x, -half.y),
			Vector2(half.x, -half.y),
			Vector2(half.x, half.y),
			Vector2(-half.x, half.y),
		])
		_wind_zone.position = wind_area_offset
		_wind_zone.visible = _active
