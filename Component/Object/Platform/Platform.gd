## 可换层平台。能选中才能换层。碰撞、往返运动、出现和消失分开配置。
## 碰撞外形以 CollisionBox 的多边形为准，画面和点选在运行时跟它对齐。
## 只移动根节点。不要改 VisualRoot 的位置和缩放。

@tool
class_name Platform
extends LayerObject

@export_group("选中与碰撞")
## 可以选中时才能换层。关掉后鼠标点不中，也不能换层。
@export var selectable: bool = true:
	set(value):
		selectable = value
		can_transfer = value
		if is_node_ready():
			_apply_pick()
## 是否挡住玩家和其他物体。消失时碰撞会先关掉，出现后再按这个值恢复。
@export var has_collision: bool = true:
	set(value):
		has_collision = value
		if is_node_ready():
			_apply_collision()

@export_group("运动")
## 在摆放点和摆放点加上下面的偏移之间来回移动。
@export var moving: bool = false:
	set(value):
		if value and not moving and is_node_ready():
			_origin = position
			_distance_along = 0.0
			_forward = true
		moving = value
## 相对于摆放点的另一端，单位是像素。
@export var move_offset: Vector2 = Vector2(160, 0)
## 移动速度，像素每秒。
@export var move_speed: float = 80.0

@export_group("出现与消失")
## 关卡开始时是否看得到。
@export var shown_on_start: bool = true
## 按下面两段时间自己反复出现和消失。
@export var blink: bool = false
## 每次出现后停留的秒数。
@export var shown_duration: float = 2.0
## 每次消失后停留的秒数。
@export var hidden_duration: float = 2.0

var _shown: bool = true
var _origin: Vector2 = Vector2.ZERO
var _distance_along: float = 0.0
var _forward: bool = true
var _phase_time: float = 0.0

@onready var _visual_polygon: Polygon2D = $VisualRoot/Polygon2D
@onready var _outline: Line2D = $VisualRoot/Line2D
@onready var _pick_area: Area2D = $VisualRoot/Area2D
@onready var _pick_shape: CollisionPolygon2D = $VisualRoot/Area2D/CollisionShape2D


func _ready() -> void:
	_sync_shape()
	if Engine.is_editor_hint():
		return
	_shown = shown_on_start
	can_transfer = selectable
	super()
	_apply_presence()
	_apply_pick()
	_origin = position


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_shape()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_blink(delta)
	_update_motion(delta)


## 给以后的触发器调用。shown 为假时碰撞和点选一起关掉。
func set_shown(shown: bool) -> void:
	_shown = shown
	_phase_time = 0.0
	if is_node_ready():
		_apply_presence()
		_apply_pick()


func is_shown() -> bool:
	return _shown


func transfer_to(target_layer: DepthLayer, target_transform: Transform2D, target_collision_transform: Transform2D) -> void:
	can_transfer = selectable
	if not selectable:
		return
	super(target_layer, target_transform, target_collision_transform)
	_origin = position
	_distance_along = 0.0
	_forward = true


func update_layer_slot() -> void:
	super()
	_apply_collision()
	_apply_pick()


func set_pick_condition(condition: bool = false) -> void:
	if not is_node_ready():
		return
	_outline.visible = condition and selectable and _shown


func _validate_property(property: Dictionary) -> void:
	if property.name == "can_transfer":
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _sync_shape() -> void:
	if collision_box == null or _visual_polygon == null:
		return
	var points := collision_box.polygon
	_visual_polygon.polygon = points
	_outline.points = points
	_pick_shape.polygon = points


func _apply_presence() -> void:
	if _visual_polygon == null:
		return
	_visual_polygon.visible = _shown
	if not _shown:
		_outline.visible = false
	_apply_collision()


func _apply_collision() -> void:
	if collision_box == null:
		return
	var solid := has_collision and _shown
	collision_box.disabled = not solid
	collision_layer = 0
	collision_mask = 0
	if not solid or owner_layer == null:
		return
	set_collision_layer_value(owner_layer.layer_id + 1, true)
	set_collision_mask_value(owner_layer.layer_id + 1, true)


func _apply_pick() -> void:
	if _pick_area == null:
		return
	_pick_area.input_pickable = selectable and _shown
	_pick_area.monitoring = false
	_pick_area.monitorable = false


func _update_blink(delta: float) -> void:
	if not blink:
		return
	var duration := shown_duration if _shown else hidden_duration
	if duration <= 0.0:
		return
	_phase_time += delta
	if _phase_time >= duration:
		set_shown(not _shown)


func _update_motion(delta: float) -> void:
	if not moving or not _shown or move_speed <= 0.0:
		return
	var length := move_offset.length()
	if length <= 0.001:
		return
	_distance_along += move_speed * delta * (1.0 if _forward else -1.0)
	if _distance_along >= length:
		_distance_along = length
		_forward = false
	elif _distance_along <= 0.0:
		_distance_along = 0.0
		_forward = true
	position = _origin + move_offset * (_distance_along / length)
