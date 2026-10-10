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
func apply_slot_state(anchor_position: Vector2) -> void:
	var relative_depth: int = slot - Global.current_layer_index
	if relative_depth != _last_relative_depth:
		_apply_depth_filter(relative_depth)
		_last_relative_depth = relative_depth

	for child in get_children():
		if child is LayerObject:
			child.apply_visual_transfer(anchor_position)

## 根据图层与关卡层的距离，统一更新整层的后处理效果。
func _apply_depth_filter(relative_depth: int) -> void:
	if Global.level == null or _filter_material == null:
		return
	var front_distance: int = maxi(-relative_depth, 0)
	var back_distance: int = maxi(relative_depth, 0)
	var level: Level = Global.level
	var blur: float = minf(
		front_distance * level.foreground_blur_step,
		level.maximum_blur_lod
	)
	var darkness: float = clampf(
		front_distance * level.foreground_dark_step,
		0.0,
		0.6
	)
	var fog: float = clampf(
		back_distance * level.background_fog_step,
		0.0,
		1.0
	)
	## CanvasGroup 作为整个图层的绘制单元，根节点负责层间排序。
	z_index = (Global.layer_count - slot) * 100
	## 只有前景模糊需要生成 mipmap，避免后景和关卡层承担无效开销。
	use_mipmaps = front_distance > 0
	_filter_material.set_shader_parameter("blur_lod", blur)
	_filter_material.set_shader_parameter("darkness", darkness)
	_filter_material.set_shader_parameter("fog_strength", fog)
	_filter_material.set_shader_parameter("fog_color", level.background_fog_color)
	_filter_material.set_shader_parameter("outline_color", level.layer_outline_color)
	## 描边和图层使用同一缩放倍率，保持与物体轮廓一致的远近变化。
	_filter_material.set_shader_parameter(
		"outline_width_px",
		level.layer_outline_width * Global.layer_scales[slot]
	)
