## 此脚本挂载在level节点上，包含关卡全局信息

class_name Level
extends Node2D

const DialogueLine = preload("res://Interface/Dialogue/Dialogue_Line.gd")
## 关卡全局信息
@export var layer_count: int = 4
@export var layer_scale: float = 0.8
@export var current_layer_index: int = 1
@export var level_id: int = 0
@export var is_night: bool = false

@export_group("开场对话")
@export var dialogue: Array[DialogueLine] = []

@export_group("关卡层夜间照明")
@export_range(200.0, 3000.0, 50.0) var night_light_radius: float = 1600.0
@export_range(0.0, 1.0, 0.01) var night_light_energy: float = 0.28
@export var night_light_color: Color = Color(1.0, 0.95, 0.84, 1.0)
@export_range(0.0, 1.0, 0.01) var night_ambient: float = 0.86
@export_range(2.0, 100.0, 1.0) var night_surface_width: float = 32.0

@export_group("图层偏移色")
@export var foreground_tint_color: Color = Color(0.212, 0.22, 0.125, 1.0)
@export var background_tint_color: Color = Color(0.339, 0.852, 0.87, 1.0)

## 向Global写入关卡参数
func write_to_global() -> void:
	Global.layer_count = layer_count
	Global.current_layer_index = current_layer_index
	var layer_scales: Array[float] = []
	for index in range(layer_count):
		layer_scales.append(pow(layer_scale, index - current_layer_index))
	Global.layer_scales = layer_scales
	Renderer.foreground_tint_color = foreground_tint_color
	Renderer.background_tint_color = background_tint_color
