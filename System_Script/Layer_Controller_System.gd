## 此脚本挂载在 LayerControllerSystem 节点上，负责视角更新、图层轮换和物件图层转换

class_name LayerControllerSystem
extends Node

func _ready() -> void:
	Global.discover_scene_nodes(get_parent())
	SignalSystem.layer_cycle.connect(cycle)
	SignalSystem.layer_change.connect(transfer)

## 相机与位置更新
func _process(_delta: float) -> void:
	if Global.camera_fixed:
		Global.camera.global_position = Global.player.global_position
	for layer in Global.layers:
		layer.apply_slot_state(Global.camera.global_position)

## 图层轮换
func cycle(direction: int) -> void:
	for layer in Global.layers:
		layer.slot = posmod(layer.slot + direction, Global.layer_count)
		for object in layer.get_children():
			if object is LayerObject:
				object.update_layer_slot()

## 改变物体图层
func transfer(direction: int, object: LayerObject) -> void:
	var slot: int = object.find_owner_layer().slot - direction
	if slot < 0 or slot >= Global.layer_count:
		return
	var target_layer: DepthLayer = Global.get_layer_at_slot(slot)
	object.transfer_to(target_layer, Global.camera.global_position)
