class_name ShadowedGeometry
extends LayerObject
## 节点信息
@onready var selected_box = $VisualRoot/Line2D
@onready var shadow: Polygon2D = $Shadow

## 准备时生成影子
func _ready() -> void:
	add_to_group("layer_objects")
	owner_layer = find_owner_layer()
	assert(owner_layer != null, "%s 必须位于 DepthLayer/Objects 下！" % name)
	if can_leave_shadow:
		var shadow_temp: Polygon2D
		for shadow_layer in range(Global.current_layer_index + 2, Global.layer_count):
			shadow_active.append(false)
			shadow_temp = shadow.duplicate()
			add_child(shadow_temp)
			shadow_temp.z_index = (Global.layer_count - shadow_layer) * 100 + 50
			shadow_temp.visible = false
			shadow_box.append(shadow_temp)
			shadow_temp = shadow.duplicate()
			add_child(shadow_temp)
			shadow_temp.z_index = (Global.layer_count - shadow_layer) * 100 + 50
			shadow_temp.visible = false
			shadow_visual.append(shadow_temp)
	update_layer_slot()

## 每帧更新影子状态
func apply_visual_transfer(anchor_position: Vector2) -> void:
	super(anchor_position)
	if can_leave_shadow:
		for shadow_layer in range(Global.current_layer_index + 2, Global.layer_count):
			var index: int = shadow_layer - Global.current_layer_index - 2
			if shadow_active[index]:
				var owner_scale: float = Global.layer_scales[owner_layer.slot]
				var shadow_scale: float = Global.layer_scales[shadow_layer]
				var shadow_box_scale: float = (owner_scale * (1 - shadow_scale)) / (shadow_scale * (1 - owner_scale))
				shadow_box[index].position = (position - anchor_position) * (shadow_box_scale - 1)
				shadow_box[index].scale = collision_box.scale * shadow_box_scale
				shadow_visual[index].position = (anchor_position - position) * (1 - shadow_scale * shadow_box_scale)
				shadow_visual[index].scale = shadow_box[index].scale * shadow_scale

## 图层改变时更新影子激活状态
func update_layer_slot() -> void:
	super()
	if can_leave_shadow:
		for shadow_layer in range(Global.current_layer_index + 2, Global.layer_count):
			var index: int = shadow_layer - Global.current_layer_index - 2
			var active: bool = owner_layer.slot > Global.current_layer_index and owner_layer.slot < shadow_layer
			shadow_active[index] = active
			shadow_visual[index].visible = active
	

## 更新选取状态
func set_pick_condition(condition: bool = false) -> void:
	selected_box.visible = condition
