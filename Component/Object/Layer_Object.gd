@abstract
class_name LayerObject
extends PhysicsBody2D
## 物体信息
@export var object_id: int = 0
@export var can_transfer: bool = true
@export var size_step: int = 0
var owner_layer: DepthLayer

## 初始化
func _ready() -> void:
	add_to_group("layer_objects")
	owner_layer = find_owner_layer()
	assert(owner_layer != null, "%s 必须位于 DepthLayer/Objects 下" % name)
	scale = Vector2.ONE * pow(Global.layer_scale, size_step * -1)
	set_collision_group(1, owner_layer.slot + 1)

## 图层切换
func transfer_to(target_layer: DepthLayer, anchor_position: Vector2, direction: int) -> void:
	## 可行性检测
	if not can_transfer:
		return
	## 改变属性
	reparent(target_layer, false)
	var ratio : float = Global.layer_scales[owner_layer.slot] / Global.layer_scales[target_layer.slot]
	size_step += direction
	position = anchor_position + (position - anchor_position) * ratio
	set_scaling(pow(Global.layer_scale, size_step))
	set_collision_group(owner_layer.layer_id + 1, target_layer.layer_id + 1)
	owner_layer = target_layer
	return

## 寻找母图层
func find_owner_layer() -> DepthLayer:
	var current := get_parent()
	while current != null:
		if current is DepthLayer:
			return current as DepthLayer
		current = current.get_parent()
	return null

## 更新屏幕位置
@abstract func apply_visual_transfer(anchor_position: Vector2, slot: int) -> void
## 更新碰撞组
@abstract func set_collision_group(old_group: int, new_group: int) -> void
## 更新大小
@abstract func set_scaling(scaling: float) -> void
## 更新选取状态
@abstract func set_pick_condition(condition: bool = false) -> void
