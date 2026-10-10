## 此脚本挂载在level节点上，包含关卡全局信息

class_name Level
extends Node2D
## 关卡全局信息
@export var layer_count: int = 4
@export var layer_scale: float = 0.8
@export var current_layer_index: int = 1

@export_group("图层滤镜")
## 每向关卡层前方移动一层增加的模糊等级
@export_range(0.0, 4.0, 0.1) var foreground_blur_step: float = 1.0
## 前景图层附带的轻微压暗强度
@export_range(0.0, 0.5, 0.01) var foreground_dark_step: float = 0.08
## 每向关卡层后方移动一层增加的雾浓度
@export_range(0.0, 1.0, 0.01) var background_fog_step: float = 0.18
## 雾颜色；Alpha 参与控制最终混合强度
@export var background_fog_color: Color = Color(0.75, 0.82, 0.78, 0.8)
## 限制最大模糊，防止前景完全丢失轮廓
@export_range(0.0, 4.0, 0.1) var maximum_blur_lod: float = 3.0
## 整层合成后的外描边颜色；Alpha 控制描边透明度
@export var layer_outline_color: Color = Color.WHITE
## 关卡层的描边基准宽度，其余图层会按照图层倍率同步缩放
@export_range(0.0, 8.0, 0.5) var layer_outline_width: float = 3.0

## 向Global写入关卡参数
func write_to_global() -> void:
	Global.layer_count = layer_count
	Global.layer_scale = layer_scale
	Global.current_layer_index = current_layer_index
	var layer_scales: Array[float] = []
	for index in range(layer_count):
		layer_scales.append(pow(layer_scale, index - current_layer_index))
	Global.layer_scales = layer_scales
