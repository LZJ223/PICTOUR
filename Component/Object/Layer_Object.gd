## 此脚本为物件抽象类，所有物件都继承于此，其中实现了物件的图层转换系统、画面更新，其余有关交互的视觉更新在子类中实现
## 其中，所有物件都是PhysicsBody2D，根目录下必须是CollisionBox节点和VisualRoot节点，负责物体实际大小的管理
## CollisionBox节点负责物体实际大小的管理，VisualRoot节点中包含贴图和点击判定的Area，负责视觉上的变换，碰撞箱位置不改变
## 注意以上两个节点的位移和旋转的初始状态必须保持为0，在关卡中的移动依靠根节点，缩放依靠CollisionBox，旋转暂不支持

@abstract
class_name LayerObject
extends PhysicsBody2D
## 物体信息
@export var can_transfer: bool = true
@export var can_leave_shadow: bool = false
@export var can_be_shadowed: bool = false
## 子节点信息
@onready var collision_box: Node2D = $CollisionBox
@onready var visual_root: Node2D = $VisualRoot
var owner_layer: DepthLayer
## 影子信息
var shadow_box: Array[Polygon2D] = []
var shadow_visual: Array[Polygon2D] = []
var shadow_active: Array[bool] = []

## 初始化
func _ready() -> void:
	add_to_group("layer_objects")
	owner_layer = find_owner_layer()
	assert(owner_layer != null, "%s 必须位于 DepthLayer/Objects 下！" % name)
	update_layer_slot()

## 图层切换
func transfer_to(target_layer: DepthLayer, anchor_position: Vector2) -> void:
	## 可行性检测
	if not can_transfer:
		return
	## 改变属性
	reparent(target_layer, false)
	var ratio : float = Global.layer_scales[owner_layer.slot] / Global.layer_scales[target_layer.slot]
	position = anchor_position + (position - anchor_position) * ratio
	collision_box.scale *= ratio
	owner_layer = target_layer
	update_layer_slot()

## 更新屏幕位置
func apply_visual_transfer(anchor_position: Vector2) -> void:
	var scaling: float = Global.layer_scales[owner_layer.slot]
	visual_root.scale = collision_box.scale * scaling
	visual_root.position = (anchor_position - position) * (1 - scaling)

## 更新图层深度
func update_layer_slot() -> void:
	visual_root.z_index = (Global.layer_count - owner_layer.slot) * 100
	collision_layer = 0
	collision_mask = 0
	self.set_collision_layer_value(owner_layer.layer_id + 1, true)
	self.set_collision_mask_value(owner_layer.layer_id + 1, true)

## 寻找母图层
func find_owner_layer() -> DepthLayer:
	var current := get_parent()
	while current != null:
		if current is DepthLayer:
			return current as DepthLayer
		current = current.get_parent()
	return null

## 更新选取状态
@abstract func set_pick_condition(condition: bool = false) -> void
