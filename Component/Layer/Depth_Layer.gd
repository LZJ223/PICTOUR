## 此脚本挂载在Layer节点上，负责管理图层槽位，调用子物件进行视觉更新

class_name DepthLayer
extends Node2D
## 图层信息
@export var layer_id: int = 0
@export_enum("FRONT", "CURRENT", "MIDDLE", "BACK") var slot: int = 1

## 初始化
func _ready() -> void:
	add_to_group("depth_layers")
	apply_slot_state(Vector2.ZERO)

## 更新图层槽位
func set_slot(new_slot: int) -> void:
	assert(new_slot >= 0 and new_slot < 4, "图层超出范围！")
	slot = new_slot

## 更新位置
func apply_slot_state(anchor_position: Vector2) -> void:
	for child in get_children():
		if child is Object:
			child.apply_visual_transfer(anchor_position, slot)
