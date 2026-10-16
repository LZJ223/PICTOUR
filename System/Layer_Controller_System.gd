## 此脚本挂载在 LayerControllerSystem 节点上，负责视角更新、图层轮换和物件图层转换

class_name LayerControllerSystem
extends Node

signal cycle_finished

const COLLISION_TOLERANCE := 0.5
@export_range(0.1, 1.0, 0.01) var cycle_duration: float = 0.18
@export_range(0.05, 1.0, 0.01, "or_greater") var destination_camera_duration: float = 0.35

var _cycle_layers_remaining: int = 0
var _destination_blend: float = 0.0
var _camera_tween: Tween

func _ready() -> void:
	add_to_group("layer_controllers")

func initialize() -> void:
	Global.discover_scene_nodes(get_parent())
	Renderer.apply_settings()
	for layer in Global.layers:
		layer.cancel_cycle()
		layer.cycle_finished.connect(_on_layer_cycle_finished)
	SignalSystem.layer_cycle.connect(cycle)
	SignalSystem.layer_change.connect(transfer)
	SignalSystem.destination_view_changed.connect(_on_destination_view_changed)
	_update_view()

func _on_destination_view_changed(active: bool) -> void:
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_camera_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_camera_tween.tween_property(
		self, "_destination_blend", 1.0 if active else 0.0, destination_camera_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

## 相机与位置更新
func _process(_delta: float) -> void:
	_update_view()

func _update_view() -> void:
	if Global.camera_fixed:
		## 对两个实时位置做插值，回程期间玩家移动也不会导致终点跳变。
		Global.camera.global_position = Global.player.global_position.lerp(
			Global.goal.global_position, _destination_blend
		)
	Global.camera.force_update_scroll()
	for layer in Global.layers:
		layer.apply_slot_state(Global.camera.global_position, Global.camera.zoom.abs())

## 图层轮换
func cycle(direction: int, check_collision: bool = true) -> bool:
	if SignalSystem.looking_at_destination or Global.goal.completed:
		return false
	if abs(direction) != 1:
		return false
	if _cycle_layers_remaining > 0:
		return false
	if check_collision and Global.player.current_state == PlayerController.PlayerState.RECALLING:
		return false
	var target_slot: int = posmod(Global.current_layer_index - direction, Global.layer_count)
	var target_layer: DepthLayer = Global.get_layer_at_slot(target_slot)
	if check_collision:
		var player_collision: CollisionPolygon2D = (
			Global.player.UAV_collision_box
			if Global.player.current_state == PlayerController.PlayerState.UAV
			else Global.player.body_collision_box
		)
		if _has_collision(Global.player, player_collision, target_layer, player_collision.global_transform):
			target_layer.play_cycle_blocked()
			return false
	Global.player.set_collision_group(target_layer.layer_id + 1)
	for layer in Global.layers:
		layer.slot = posmod(layer.slot + direction, Global.layer_count)
		for object in layer.get_children():
			if object is LayerObject:
				object.update_layer_slot()
	_cycle_layers_remaining = Global.layers.size()
	for layer in Global.layers:
		layer.play_cycle(direction, cycle_duration)
	return true

func _on_layer_cycle_finished() -> void:
	_cycle_layers_remaining -= 1
	if _cycle_layers_remaining == 0:
		cycle_finished.emit()

func is_cycling() -> bool:
	return _cycle_layers_remaining > 0

## 改变物体图层
func transfer(direction: int, object: LayerObject) -> bool:
	if SignalSystem.looking_at_destination or Global.goal.completed:
		return false
	if _cycle_layers_remaining > 0 or Global.player.current_state == PlayerController.PlayerState.RECALLING:
		return false
	if not object.can_transfer:
		object.play_transfer_blocked()
		return false
	var source_layer: DepthLayer = object.find_owner_layer()
	var source_slot: int = source_layer.slot
	var target_slot: int = source_slot - direction
	if target_slot < 0 or target_slot >= Global.layer_count or target_slot == source_slot:
		object.play_transfer_blocked()
		return false
	var target_layer: DepthLayer = Global.get_layer_at_slot(target_slot)
	var ratio: float = Global.layer_scales[source_slot] / Global.layer_scales[target_slot]
	var object_transform: Transform2D = object.global_transform
	object_transform.origin = Global.camera.global_position + (object.global_position - Global.camera.global_position) * ratio
	var collision_transform: Transform2D = object.collision_box.transform
	collision_transform.x *= ratio
	collision_transform.y *= ratio
	if _has_collision(object, object.collision_box, target_layer, object_transform * collision_transform):
		object.play_transfer_blocked()
		return false
	object.transfer_to(target_layer, object_transform, collision_transform)
	## 先按目标层重算基础画面，再叠加短促的拉拽动画。
	object.apply_visual_transfer(Global.camera.global_position, Global.camera.zoom.abs())
	var motion: int = (
		LayerObject.TransferMotion.OUTWARD
		if target_slot < source_slot
		else LayerObject.TransferMotion.INWARD
	)
	object.play_transfer_success(motion)
	return true

## 检测候选碰撞箱是否与目标图层中的物理体重叠
func _has_collision(body: PhysicsBody2D, collision_box: CollisionPolygon2D, target_layer: DepthLayer, candidate_transform: Transform2D) -> bool:
	if collision_box.disabled or collision_box.polygon.size() < 3:
		return false
	## 碰撞检测
	var query := PhysicsShapeQueryParameters2D.new()
	var excluded: Array[RID] = [body.get_rid()]
	query.transform = candidate_transform
	query.collision_mask = 1 << target_layer.layer_id
	query.exclude = excluded
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.margin = 0.0
	var space := body.get_world_2d().direct_space_state
	for polygon in Geometry2D.decompose_polygon_in_convex(collision_box.polygon):
		var shape := ConvexPolygonShape2D.new()
		shape.points = polygon
		query.shape = shape
		var contacts: Array[Vector2] = space.collide_shape(query, 32)
		for index in range(0, contacts.size() - 1, 2):
			if contacts[index].distance_to(contacts[index + 1]) > COLLISION_TOLERANCE:
				return true
	return false
