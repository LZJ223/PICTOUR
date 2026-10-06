class_name Ground
extends LayerObject
## 节点信息
@onready var visual_root = $VisualRoot

## 更新屏幕位置
func apply_visual_transfer(anchor_position: Vector2, slot: int) -> void:
	var scaling: float = Global.layer_scales[slot]
	visual_root.scale = Vector2.ONE * scaling
	visual_root.position = (anchor_position - position) * (1 - scaling)
	visual_root.z_index = 400 - slot * 100

## 更新碰撞组
func set_collision_group(old_group: int, new_group: int) -> void:
	self.set_collision_layer_value(old_group, false)
	self.set_collision_layer_value(new_group, true)

## 更新大小
func set_scaling(scaling: float) -> void:
	return

## 更新选取状态
func set_pick_condition(condition: bool = false) -> void:
	return
