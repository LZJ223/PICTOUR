## 此脚本挂载在 LayerControllerSystem 节点上，负责视角更新、图层轮换和物件图层转换

class_name LayerControllerSystem
extends Node

const COLLISION_TOLERANCE := 0.5

func _ready() -> void:
	Global.discover_scene_nodes(get_parent())
	Renderer.apply_settings()
	SignalSystem.layer_cycle.connect(cycle)
	SignalSystem.layer_change.connect(transfer)

## 相机与位置更新
func _process(_delta: float) -> void:
	if Global.camera_fixed:
		Global.camera.global_position = Global.player.global_position
	for layer in Global.layers:
		layer.apply_slot_state(Global.camera.global_position, Global.camera.zoom.abs())

## 图层轮换
func cycle(direction: int, check_collision: bool = true) -> void:
	var target_slot: int = posmod(Global.current_layer_index - direction, Global.layer_count)
	var target_layer: DepthLayer = Global.get_layer_at_slot(target_slot)
	if check_collision:
		var player_collision: CollisionPolygon2D = (
			Global.player.UAV_collision_box
			if Global.player.current_state == PlayerController.PlayerState.UAV
			else Global.player.body_collision_box
		)
		if _has_collision(Global.player, player_collision, target_layer, player_collision.global_transform):
			return
	Global.player.set_collision_group(target_layer.layer_id + 1)
	for layer in Global.layers:
		layer.slot = posmod(layer.slot + direction, Global.layer_count)
		for object in layer.get_children():
			if object is LayerObject:
				object.update_layer_slot()

## 改变物体图层
func transfer(direction: int, object: LayerObject) -> bool:
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
