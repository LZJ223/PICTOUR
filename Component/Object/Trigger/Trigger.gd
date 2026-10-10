## 挂在图层物体上的触发器。不自己换层，也不要放进 VisualRoot。
## 玩家走进范围，并且就在这个物体所在的那一层，才执行下面选中的一种动作。
## 已经站在范围里再换到这一层，也会执行。

@tool
class_name Trigger
extends Area2D

enum Action { TELEPORT, DIALOGUE, CHECKPOINT, DEATH, MECHANISM }

@export var action: Action = Action.TELEPORT:
	set(value):
		action = value
		notify_property_list_changed()
		if is_node_ready():
			_apply_zone_color()
## 传送的落点。落点要在这块范围外面。
@export_node_path("Node2D") var teleport_target: NodePath
## 走进来时显示的一句话。
@export var dialogue_text: String = ""
## 被叫到的物体。它自己决定做什么。
@export_node_path("Node") var mechanism_target: NodePath
## 在画面上画出这块范围，方便摆放。
@export var show_zone: bool = true:
	set(value):
		show_zone = value
		if is_node_ready():
			_apply_zone_color()

var _player_inside: bool = false
var _consumed: bool = false

@onready var _shape: CollisionShape2D = $CollisionShape2D
@onready var _zone: Polygon2D = $Zone


func _ready() -> void:
	_sync_zone()
	_apply_zone_color()
	if Engine.is_editor_hint():
		return
	input_pickable = false
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	for bit in range(1, Global.layer_count + 1):
		set_collision_mask_value(bit, true)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_sync_zone()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not _player_inside:
		return
	if _layer_matches():
		if not _consumed:
			_run_action()
			_consumed = true
	else:
		_consumed = false


func _validate_property(property: Dictionary) -> void:
	var hide := false
	if property.name == "teleport_target" and action != Action.TELEPORT:
		hide = true
	elif property.name == "dialogue_text" and action != Action.DIALOGUE:
		hide = true
	elif property.name == "mechanism_target" and action != Action.MECHANISM:
		hide = true
	if hide:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _on_body_entered(body: Node2D) -> void:
	if body == Global.player:
		_player_inside = true


func _on_body_exited(body: Node2D) -> void:
	if body == Global.player:
		_player_inside = false
		_consumed = false


func _layer_matches() -> bool:
	var layer := _host_layer()
	if layer == null or Global.player == null:
		return false
	return layer.layer_id == Global.player.collision_group - 1


func _node_at(path: NodePath) -> Node:
	if path.is_empty():
		return null
	return get_node_or_null(path)


func _host_layer() -> DepthLayer:
	var current := get_parent()
	while current != null:
		if current is DepthLayer:
			return current as DepthLayer
		current = current.get_parent()
	return null


func _run_action() -> void:
	match action:
		Action.TELEPORT:
			var destination := _node_at(teleport_target) as Node2D
			if destination != null and Global.player != null:
				Global.player.global_position = destination.global_position
				Global.player.velocity = Vector2.ZERO
		Action.DIALOGUE:
			Global.show_line(dialogue_text)
		Action.CHECKPOINT:
			Global.remember_player_state()
		Action.DEATH:
			Global.restore_player_state()
		Action.MECHANISM:
			var target := _node_at(mechanism_target)
			if target != null and target.has_method("activate"):
				target.activate()


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


func _apply_zone_color() -> void:
	if _zone == null:
		return
	_zone.visible = show_zone
	match action:
		Action.TELEPORT:
			_zone.color = Color(0.35, 0.7, 1, 0.28)
		Action.DIALOGUE:
			_zone.color = Color(0.95, 0.85, 0.3, 0.28)
		Action.CHECKPOINT:
			_zone.color = Color(0.4, 0.85, 0.45, 0.28)
		Action.DEATH:
			_zone.color = Color(0.9, 0.3, 0.3, 0.28)
		Action.MECHANISM:
			_zone.color = Color(0.75, 0.45, 0.9, 0.28)
