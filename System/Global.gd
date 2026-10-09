## 自动挂载：图层配置、选中状态和在物理更新中执行的交互请求。
extends Node

var layer_count: int = 4
var layer_scale: float = 0.8
var layer_scales: Array = [1.25, 1.0, 0.8, 0.64]
var current_layer_index: int = 1
var allow_object_transfer: bool = true
var allow_layer_cycle: bool = true
var allow_uav: bool = true
var uav_active: bool = false
var object_selected: LayerObject = null
var _pending_inputs: Array[Dictionary] = []

signal layer_cycle(direction: int)
signal layer_change(direction: int, object: LayerObject)
signal UAV_activate()
signal transfer_result(object: LayerObject, success: bool, reason: String)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("pickup"):
		var point: Vector2 = event.position if event is InputEventMouseButton else get_viewport().get_mouse_position()
		_pending_inputs.append({"kind": "pick", "point": get_viewport().get_canvas_transform().affine_inverse() * point})
	elif event.is_action_pressed("transfer_forward") and allow_object_transfer and not uav_active:
		_pending_inputs.append({"kind": "transfer", "direction": 1})
	elif event.is_action_pressed("transfer_backward") and allow_object_transfer and not uav_active:
		_pending_inputs.append({"kind": "transfer", "direction": -1})
	elif allow_layer_cycle and event.is_action_pressed("forward"):
		_pending_inputs.append({"kind": "legacy", "direction": 1})
	elif allow_layer_cycle and event.is_action_pressed("backward"):
		_pending_inputs.append({"kind": "legacy", "direction": -1})
	elif allow_uav and event.is_action_pressed("UAV"):
		_pending_inputs.append({"kind": "uav"})


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(object_selected):
		object_selected = null
	var commands := _pending_inputs.duplicate()
	_pending_inputs.clear()
	for command in commands:
		match command.kind:
			"pick":
				_pick_at(command.point)
			"transfer":
				if allow_object_transfer and not uav_active and is_instance_valid(object_selected):
					layer_change.emit(command.direction, object_selected)
			"legacy":
				if allow_layer_cycle:
					if is_instance_valid(object_selected) and allow_object_transfer:
						layer_change.emit(command.direction, object_selected)
					else:
						layer_cycle.emit(command.direction)
			"uav":
				if allow_uav:
					UAV_activate.emit()


func select_object(object: LayerObject) -> void:
	if is_instance_valid(object_selected):
		object_selected.set_pick_condition(false)
	object_selected = object if is_instance_valid(object) and object.can_transfer else null
	if is_instance_valid(object_selected):
		object_selected.set_pick_condition(true)


func clear_selection() -> void:
	select_object(null)
	_pending_inputs.clear()


func _pick_at(point: Vector2) -> void:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = point
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var results := get_viewport().world_2d.direct_space_state.intersect_point(params, 64)
	var best: LayerObject = null
	var best_z: int = -2147483648
	for result in results:
		var area := result.collider as Area2D
		if area == null or not area.input_pickable:
			continue
		var ancestor: Node = area
		while ancestor != null and not ancestor is LayerObject:
			ancestor = ancestor.get_parent()
		var object := ancestor as LayerObject
		if object == null or not object.can_transfer:
			continue
		var effective_z := _effective_z(area)
		if best == null or effective_z > best_z or (effective_z == best_z and object.get_instance_id() > best.get_instance_id()):
			best = object
			best_z = effective_z
	select_object(null if best == object_selected else best)


func _effective_z(item: CanvasItem) -> int:
	var result := item.z_index
	if item.z_as_relative:
		var ancestor := item.get_parent() as CanvasItem
		if ancestor != null:
			result += _effective_z(ancestor)
	return result
