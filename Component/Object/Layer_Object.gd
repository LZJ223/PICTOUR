## 此脚本为物件抽象类，所有物件都继承于此，其中实现了物件的图层转换系统、画面更新，其余有关交互的视觉更新在子类中实现
## 其中，所有物件都是PhysicsBody2D，根目录下必须是CollisionBox节点和VisualRoot节点，负责物体实际大小的管理
## CollisionBox节点负责物体实际大小的管理，VisualRoot节点中包含贴图和点击判定的Area，负责视觉上的变换，碰撞箱位置不改变
## 注意以上两个节点的位移和旋转的初始状态必须保持为0，在关卡中的移动依靠根节点，缩放依靠CollisionBox，旋转暂不支持

@abstract
class_name LayerObject
extends PhysicsBody2D
## 物体信息
@export var can_transfer: bool = true
## 子节点信息
@onready var collision_box: Node2D = $CollisionBox
@onready var visual_root: Node2D = $VisualRoot
var owner_layer: DepthLayer

## 初始化
func _ready() -> void:
	add_to_group("layer_objects")
	owner_layer = find_owner_layer()
	assert(owner_layer != null, "%s 必须位于 DepthLayer/Objects 下！" % name)
	set_collision_group(1, owner_layer.layer_id + 1)

## 图层切换
func transfer_to(target_layer: DepthLayer, anchor_position: Vector2) -> bool:
	## 可行性检测
	if not can_transfer:
		return false
	## 改变属性
	var next_position := get_transfer_position(target_layer, anchor_position)
	var ratio : float = Global.layer_scales[owner_layer.slot] / Global.layer_scales[target_layer.slot]
	reparent(target_layer, true)
	global_position = next_position
	collision_box.scale *= ratio
	set_collision_group(owner_layer.layer_id + 1, target_layer.layer_id + 1)
	owner_layer = target_layer
	apply_visual_transfer(anchor_position)
	reset_physics_interpolation()
	return true

func get_transfer_position(target_layer: DepthLayer, anchor_position: Vector2) -> Vector2:
	var ratio: float = Global.layer_scales[owner_layer.slot] / Global.layer_scales[target_layer.slot]
	return anchor_position + (global_position - anchor_position) * ratio

func get_transfer_collision_transform(target_layer: DepthLayer, anchor_position: Vector2) -> Transform2D:
	var ratio: float = Global.layer_scales[owner_layer.slot] / Global.layer_scales[target_layer.slot]
	var result := collision_box.global_transform
	result.origin = get_transfer_position(target_layer, anchor_position) + (result.origin - global_position) * ratio
	result.x *= ratio
	result.y *= ratio
	return result

## 更新屏幕位置
func apply_visual_transfer(anchor_position: Vector2) -> void:
	var scaling: float = Global.layer_scales[owner_layer.slot]
	visual_root.global_position = anchor_position + (global_position - anchor_position) * scaling
	visual_root.global_rotation = global_rotation
	visual_root.global_scale = collision_box.global_scale * scaling
	visual_root.z_index = (Global.layer_count - owner_layer.slot) * 100

## 寻找母图层
func find_owner_layer() -> DepthLayer:
	var current := get_parent()
	while current != null:
		if current is DepthLayer:
			return current as DepthLayer
		current = current.get_parent()
	return null

## 更新碰撞组
func set_collision_group(_old_group: int, new_group: int) -> void:
	assert(new_group >= 1 and new_group <= 32)
	collision_layer = 1 << (new_group - 1)
	collision_mask = collision_layer

## 更新选取状态
@abstract func set_pick_condition(condition: bool = false) -> void
