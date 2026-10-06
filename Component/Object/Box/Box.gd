class_name Box
extends LayerObject
## 节点信息
@onready var collision_box = $CollisionBox
@onready var visual_root = $VisualRoot
@onready var selected_box = $VisualRoot/Line2D

## 更新屏幕位置
func apply_visual_transfer(anchor_position: Vector2, slot: int) -> void:
	var scaling: float = Global.layer_scales[slot]
	visual_root.scale = collision_box.scale * scaling
	visual_root.position = (anchor_position - position) * (1 - scaling)
	visual_root.z_index = 400 - slot * 100

## 更新碰撞组
func set_collision_group(old_group: int, new_group: int) -> void:
	self.set_collision_layer_value(old_group, false)
	self.set_collision_layer_value(new_group, true)
	self.set_collision_mask_value(old_group, false)
	self.set_collision_mask_value(new_group, true)
	
## 更新大小
func set_scaling(scaling: float) -> void:
	collision_box.scale = Vector2.ONE * scaling

## 更新选取状态
func set_pick_condition(condition: bool = false) -> void:
	selected_box.visible = condition
