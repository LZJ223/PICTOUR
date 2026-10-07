## 此脚本挂载在level节点上，包含关卡全局信息

class_name Level
extends Node2D
## 关卡全局信息
@export var layer_count: int = 4
@export var layer_scale: float = 0.8
@export var current_layer_index: int = 1

## 向Global写入关卡参数
func write_to_global() -> void:
	Global.layer_count = layer_count
	Global.layer_scale = layer_scale
	Global.current_layer_index = current_layer_index
	var layer_scales: Array[float] = []
	for index in range(layer_count):
		layer_scales.append(pow(layer_scale, index - current_layer_index))
	Global.layer_scales = layer_scales
