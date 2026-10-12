## 碰到就收走的图层物体。不挡住玩家，也不能被点选取层。
## 检测区在根节点上，不要放进 VisualRoot，否则范围会跟着画面视差挪走。
## 收藏记入收藏册；道具记入持有栏。门和成就来查全局账本，不写在这里。

@tool
class_name Pickup
extends LayerObject

enum Usage { COLLECTION, TOOL }

## 这一件东西的名字。同一个名字表示同一件。留空时用节点名。
@export var item_id: String = ""
## 收藏只进入收藏册。道具进入持有栏，需要时也可以同时记入收藏册。
@export var usage: Usage = Usage.COLLECTION:
	set(value):
		usage = value
		notify_property_list_changed()
		if is_node_ready():
			_apply_look()
## 道具是否同时算进收藏。收藏物忽略这一项。
@export var also_record: bool = false
## 这个名字已经收过时，后来的同类直接收起，不再记第二次。
@export var once: bool = true
## 在画面上画出检测范围，方便摆放。
@export var show_zone: bool = true:
	set(value):
		show_zone = value
		if is_node_ready():
			_apply_look()

var _player_inside: bool = false
var _picked: bool = false

@onready var _icon: Polygon2D = $VisualRoot/Polygon2D
@onready var _sensor: Area2D = $Sensor
@onready var _shape: CollisionShape2D = $Sensor/CollisionShape2D
@onready var _zone: Polygon2D = $Sensor/Zone


func _ready() -> void:
	_sync_zone()
	_apply_look()
	if Engine.is_editor_hint():
		return
	can_transfer = false
	super()
	_apply_no_collision()
	if once and Global.was_picked(_resolved_id()):
		_hide_picked()
	_arm_sensor()
	_sensor.body_entered.connect(_on_body_entered)
	_sensor.body_exited.connect(_on_body_exited)
	if not Global.item_picked.is_connected(_on_item_picked):
		Global.item_picked.connect(_on_item_picked)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_zone()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _picked:
		return
	_try_pick()


func update_layer_slot() -> void:
	super()
	_apply_no_collision()


func transfer_to(_target_layer: DepthLayer, _target_transform: Transform2D, _target_collision_transform: Transform2D) -> void:
	can_transfer = false


func _validate_property(property: Dictionary) -> void:
	var hide := false
	if property.name == "can_transfer":
		hide = true
	elif property.name == "also_record" and usage != Usage.TOOL:
		hide = true
	if hide:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _apply_no_collision() -> void:
	if collision_box == null:
		return
	collision_box.disabled = true
	collision_layer = 0
	collision_mask = 0


func _arm_sensor() -> void:
	if _sensor == null:
		return
	_sensor.collision_layer = 0
	_sensor.collision_mask = 0
	_sensor.monitorable = false
	_sensor.input_pickable = false
	_sensor.monitoring = not _picked
	for bit in range(1, Global.layer_count + 1):
		_sensor.set_collision_mask_value(bit, true)


func _on_body_entered(body: Node2D) -> void:
	if body == Global.player:
		_player_inside = true


func _on_body_exited(body: Node2D) -> void:
	if body == Global.player:
		_player_inside = false


func _on_item_picked(picked_id: String, _tool: bool) -> void:
	if _picked or not once or picked_id == "" or picked_id != _resolved_id():
		return
	_hide_picked()


func _layer_matches() -> bool:
	if owner_layer == null or Global.player == null:
		return false
	return owner_layer.layer_id == Global.player.collision_group - 1


func _resolved_id() -> String:
	if item_id != "":
		return item_id
	return str(name)


func _try_pick() -> void:
	if _picked or not _player_inside or not _layer_matches():
		return
	var id := _resolved_id()
	if once and Global.was_picked(id):
		_hide_picked()
		return
	Global.note_pickup(id, usage == Usage.TOOL, usage == Usage.TOOL and also_record)
	_hide_picked()


func _hide_picked() -> void:
	_picked = true
	if _icon != null:
		_icon.visible = false
	if _zone != null:
		_zone.visible = false
	if _sensor != null:
		_sensor.monitoring = false
	_apply_no_collision()


func _sync_zone() -> void:
	if _shape == null or _zone == null or not _shape.shape is RectangleShape2D:
		return
	var size := (_shape.shape as RectangleShape2D).size
	var half := size * 0.5
	_zone.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])


func _apply_look() -> void:
	var tint := Color(0.93, 0.76, 0.28, 1) if usage == Usage.COLLECTION else Color(0.45, 0.75, 0.95, 1)
	if _icon != null and not _picked:
		_icon.color = tint
	if _zone == null:
		return
	_zone.visible = show_zone and not _picked
	tint.a = 0.28
	_zone.color = tint
