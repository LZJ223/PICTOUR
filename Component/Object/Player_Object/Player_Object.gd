class_name Player_Object
extends LayerObject
## 节点信息
@onready var selected_box = $VisualRoot/Line2D

## 更新选取状态
func set_pick_condition(condition: bool = false) -> void:
	selected_box.visible = condition
