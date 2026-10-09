class_name StudySystemController
extends SystemController
## 纵向庭院：镜头可以上下取景，解谜的投影基准始终是玩家X / 固定Y。

@export var projection_anchor_y: float = 720.0
@export var view_follow_y: bool = true
@export var view_use_deadzone: bool = true
@export_range(0.0, 200.0, 1.0) var view_deadzone_y: float = 65.0
@export var view_offset_y: float = -150.0
@export var view_min_y: float = 390.0
@export var view_max_y: float = 930.0
@export var view_min_x: float = 640.0
@export var view_max_x: float = 1600.0
var history: StudyTransferHistory
var _pending_history_action: StringName = &""
var _preview: TransferPreview
var _preview_state: Dictionary = {}
var _view_center_y: float = 0.0
var _view_initialized := false


class TransferPreview extends Node2D:
	var outlines: Array[PackedVector2Array] = []
	var contacts := PackedVector2Array()
	var valid := true
	func _draw() -> void:
		var color := Color(0.31, 0.57, 0.46, 0.85) if valid else Color(0.74, 0.25, 0.26, 0.9)
		for outline in outlines:
			if outline.size() > 2:
				var closed := outline.duplicate()
				closed.append(closed[0])
				draw_polyline(closed, color, 1.5, true)
		for point in contacts:
			draw_circle(point, 5.5, Color(0.92, 0.51, 0.25, 0.9), false, 1.6, true)
			draw_line(point - Vector2(3, 3), point + Vector2(3, 3), color, 1.3, true)
			draw_line(point - Vector2(3, -3), point + Vector2(3, -3), color, 1.3, true)


func _ready() -> void:
	super._ready()
	assert(level.layer_count == 2 and level.current_layer_index == 0 and not level.allow_layer_cycle and not level.allow_uav, "Study历史只适用于玩家槽位0的固定两层单物件搬运。")
	history = StudyTransferHistory.new()
	history.name = "TransferHistory"
	add_child(history)
	history.configure(self)
	_preview = TransferPreview.new()
	_preview.name = "TargetOutline"
	_preview.z_index = 900
	add_child(_preview)


func get_projection_anchor() -> Vector2:
	return Vector2(player.global_position.x, projection_anchor_y)


func _refresh_camera_and_layers() -> void:
	if camera_fixed:
		var target_y := player.global_position.y + view_offset_y if view_follow_y else level.camera_height
		if not _view_initialized or not view_follow_y or not view_use_deadzone:
			_view_center_y = target_y
		else:
			# 小跳与碎坡保持取景；持续越过死区后只推到相应边界。
			_view_center_y = clampf(_view_center_y, target_y - view_deadzone_y, target_y + view_deadzone_y)
		if view_follow_y:
			_view_center_y = clampf(_view_center_y, view_min_y, view_max_y)
		_view_initialized = true
		camera.global_position = Vector2(clampf(player.global_position.x, view_min_x, view_max_x), _view_center_y)
	for layer in layers:
		layer.apply_slot_state(get_projection_anchor())


func reset_view_interpolation() -> void:
	# 普通传送/调试重置将新站位作为视野中心，不沿用上一区域的死区。
	_view_initialized = false
	super.reset_view_interpolation()


func reset_restored_view_interpolation() -> void:
	# Z/R已恢复当时的相机；由它重建死区，保留操作前的准确构图。
	_view_center_y = camera.global_position.y
	_view_initialized = true
	super.reset_view_interpolation()


func transfer(direction: int, object: LayerObject) -> bool:
	if history == null:
		return super.transfer(direction, object)
	var previous := history.capture_state()
	if previous.is_empty():
		Global.transfer_result.emit(object if is_instance_valid(object) else null, false, "庭院物件不完整，无法记录这次换层。")
		return false
	var success := super.transfer(direction, object)
	if success:
		history.record_success(previous)
	return success


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_Z:
		_pending_history_action = &"undo"
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_R:
		_pending_history_action = &"reset"
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _pending_history_action == &"undo":
		undo_transfer()
	elif _pending_history_action == &"reset":
		reset_study()
	_pending_history_action = &""
	super._physics_process(delta)
	_update_study_preview()


func undo_transfer() -> bool:
	return history.undo() if history != null else false


func reset_study() -> bool:
	return history.reset_initial() if history != null else false


func get_preview_state() -> Dictionary:
	return _preview_state.duplicate(true)


func _update_study_preview() -> void:
	_preview.outlines.clear()
	_preview.contacts.clear()
	_preview_state.clear()
	var object := Global.object_selected
	if not is_instance_valid(object) or not is_instance_valid(object.owner_layer) or not layers.has(object.owner_layer):
		_preview.queue_redraw()
		return
	var direction := 1 if object.owner_layer.slot > Global.current_layer_index else -1
	var target := get_layer_at_slot(object.owner_layer.slot - direction)
	if target == null:
		_preview.queue_redraw()
		return
	var anchor := get_projection_anchor()
	var reason := _transfer_rejection(direction, object)
	_preview.valid = reason.is_empty()
	var ratio: float = Global.layer_scales[object.owner_layer.slot] / Global.layer_scales[target.slot]
	var projected_scale: float = Global.layer_scales[target.slot]
	var next_position := object.get_transfer_position(target, anchor)
	for child in object.get_children():
		if not (child is CollisionPolygon2D or child is CollisionShape2D) or child.disabled:
			continue
		var points := PackedVector2Array()
		if child is CollisionPolygon2D:
			points = child.polygon
		elif child.shape is ConvexPolygonShape2D:
			points = child.shape.points
		elif child.shape != null:
			var rect: Rect2 = child.shape.get_rect()
			points = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0), rect.end, rect.position + Vector2(0, rect.size.y)])
		var projected := PackedVector2Array()
		for point in points:
			var physical: Vector2 = next_position + (child.global_transform * point - object.global_position) * ratio
			projected.append(anchor + (physical - anchor) * projected_scale)
		_preview.outlines.append(projected)
	if not reason.is_empty():
		var parts: Array[Dictionary] = object.get_transfer_collision_parts(target, anchor) if object.has_method("get_transfer_collision_parts") else _legacy_collision_parts(object, target)
		for part in parts:
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = part.shape
			query.transform = _contact_tolerant_transform(part.shape, part.transform)
			query.collision_mask = 1 << target.layer_id
			query.exclude = _transfer_query_exclusions(object, target)
			var contacts := player.get_world_2d().direct_space_state.collide_shape(query, 4)
			for index in range(0, contacts.size() - 1, 2):
				var contact: Vector2 = (contacts[index] + contacts[index + 1]) * 0.5
				var visible_contact := anchor + (contact - anchor) * projected_scale
				var duplicate := false
				for existing in _preview.contacts:
					duplicate = duplicate or existing.distance_to(visible_contact) < 10.0
				if not duplicate:
					_preview.contacts.append(visible_contact)
				if _preview.contacts.size() >= 6:
					break
			if _preview.contacts.size() >= 6:
				break
	_preview_state = {"valid": _preview.valid, "reason": reason, "target_slot": target.slot, "anchor": anchor, "outlines": _preview.outlines.duplicate(), "contacts": _preview.contacts.duplicate()}
	_preview.queue_redraw()
