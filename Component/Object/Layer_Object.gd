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
@onready var collision_box: CollisionPolygon2D = $CollisionBox
@onready var visual_root: Node2D = $VisualRoot
var owner_layer: DepthLayer
## 影子信息
var shadow_box: Array[Polygon2D] = []
var shadow_visual: Array[Polygon2D] = []
var shadow_active: Array[bool] = []
const _EAGLE_SHADER := preload("res://Shader/Eagle_Eye_Grayscale.gdshader")
static var _eagle_gray_material: ShaderMaterial

## 初始化
func _ready() -> void:
	add_to_group("layer_objects")
	owner_layer = find_owner_layer()
	assert(owner_layer != null, "%s 必须位于 DepthLayer/Objects 下！" % name)
	update_layer_slot()

## 图层切换
func transfer_to(target_layer: DepthLayer, target_transform: Transform2D, target_collision_transform: Transform2D) -> void:
	## 可行性检测
	if not can_transfer:
		return
	## 改变属性
	reparent(target_layer, false)
	global_transform = target_transform
	collision_box.transform = target_collision_transform
	owner_layer = target_layer
	update_layer_slot()

## 更新屏幕位置
func apply_visual_transfer(anchor_position: Vector2) -> void:
	var scaling: float = Global.layer_scales[owner_layer.slot]
	visual_root.scale = collision_box.scale * scaling
	visual_root.position = (anchor_position - position) * (1 - scaling)

## 更新物体所属图层状态
func update_layer_slot() -> void:
	collision_layer = 0
	collision_mask = 0
	self.set_collision_layer_value(owner_layer.layer_id + 1, true)
	self.set_collision_mask_value(owner_layer.layer_id + 1, true)
	refresh_eagle_eye()

## 鹰眼打开时，不在玩家当前碰撞层的画面变成灰。原来的颜色会保留。
func refresh_eagle_eye() -> void:
	if visual_root == null:
		return
	var gray := Global.eagle_eye and not _is_player_layer()
	_set_eagle_gray(visual_root, gray)
	for node in shadow_box:
		_set_eagle_gray(node, gray)
	for node in shadow_visual:
		_set_eagle_gray(node, gray)
	var shadow_template := get_node_or_null("Shadow") as CanvasItem
	if shadow_template != null:
		_set_eagle_gray(shadow_template, gray)

func _is_player_layer() -> bool:
	if Global.player == null or owner_layer == null:
		return true
	return owner_layer.layer_id == Global.player.collision_group - 1

func _set_eagle_gray(node: Node, gray: bool) -> void:
	if node is Polygon2D or node is Line2D:
		_apply_gray_material(node as CanvasItem, gray)
	for child in node.get_children():
		_set_eagle_gray(child, gray)

func _apply_gray_material(item: CanvasItem, gray: bool) -> void:
	var gray_material := _shared_eagle_material()
	if gray:
		if item.material == gray_material:
			return
		item.set_meta(&"eagle_eye_previous_material", item.material)
		item.material = gray_material
		return
	if item.material != gray_material:
		return
	var previous: Material = item.get_meta(&"eagle_eye_previous_material")
	item.material = previous
	item.remove_meta(&"eagle_eye_previous_material")

static func _shared_eagle_material() -> ShaderMaterial:
	if _eagle_gray_material == null:
		_eagle_gray_material = ShaderMaterial.new()
		_eagle_gray_material.shader = _EAGLE_SHADER
	return _eagle_gray_material

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
