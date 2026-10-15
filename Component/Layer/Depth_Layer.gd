## 此脚本挂载在Layer节点上，负责管理图层槽位，调用子物件进行视觉更新

class_name DepthLayer
extends CanvasGroup
## 图层信息
@export var layer_id: int = 0
@export var slot: int = 1

var _filter_material: ShaderMaterial
var _last_relative_depth: int = 999

## 初始化
func _ready() -> void:
	add_to_group("depth_layers")
	_filter_material = material as ShaderMaterial
	assert(_filter_material != null, "DepthLayer 需要使用图层滤镜 ShaderMaterial")

## 更新位置
func apply_slot_state(anchor_position: Vector2, camera_zoom: Vector2) -> void:
	var relative_depth: int = slot - Global.current_layer_index
	if relative_depth != _last_relative_depth:
		_apply_depth_filter(relative_depth)
		_last_relative_depth = relative_depth
	for child in get_children():
		if child is LayerObject:
			child.apply_visual_transfer(anchor_position, camera_zoom)

## 根据图层与关卡层的距离，统一更新整层的后处理效果。
func _apply_depth_filter(relative_depth: int) -> void:
	if _filter_material == null:
		return
	## CanvasGroup 作为整个图层的绘制单元，根节点负责层间排序。
	z_index = (Global.layer_count - slot) * 100
	## 前景与后景都可能采样模糊 LOD；关卡层不需要生成 mipmap。
	use_mipmaps = relative_depth != 0
	_filter_material.set_shader_parameter("relative_depth", float(relative_depth))
