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

@export_group("图层模糊")
@export_range(0.0, 4.0, 0.1) var foreground_blur_step: float = 1.2
@export_range(0.0, 4.0, 0.1) var background_blur_step: float = 0.8
@export_range(0.0, 4.0, 0.1) var maximum_blur_lod: float = 4.0

@export_group("前景图层")
@export_range(0.0, 1.0, 0.01) var foreground_darkness_step: float = 0.2
@export_range(0.0, 1.0, 0.01) var foreground_tint_step: float = 0.05

@export_group("远离关卡层")
@export_range(0.0, 1.0, 0.01) var contrast_falloff: float = 0.15

@export_group("后景图层")
@export_range(0.0, 1.0, 0.01) var background_tint_step: float = 0.1

@export_group("后景雾效")
@export_range(0.0, 4.0, 0.1) var haze_blur_step: float = 2.0
@export_range(0.0, 4.0, 0.1) var haze_maximum_blur_lod: float = 6.0
@export_range(0.0, 1.0, 0.01) var haze_opacity: float = 0.75
@export_range(0.01, 1.0, 0.01) var haze_world_scale: float = 0.4
@export_range(-2000.0, 2000.0, 1.0) var haze_bottom_y: float = 500.0
@export_range(-200.0, 200.0, 1.0) var haze_speed: float = 30.0
@export_range(0.0, 6000.0, 1.0) var haze_layer_offset: float = 450.0

@export_group("图层偏移色")
@export var foreground_tint_color: Color = Color(0.212, 0.22, 0.125, 1.0)
@export var background_tint_color: Color = Color(0.339, 0.852, 0.87, 1.0)

@export_group("选择描边")
@export var selection_outline_color: Color = Color.WHITE
@export_range(0.0, 16.0, 0.5) var selection_outline_width: float = 6.0

## 向Global写入关卡参数
func write_to_global() -> void:
	Global.layer_count = layer_count
	Global.current_layer_index = current_layer_index
	var layer_scales: Array[float] = []
	for index in range(layer_count):
		layer_scales.append(pow(layer_scale, index - current_layer_index))
	Global.layer_scales = layer_scales
	write_to_renderer()

## 写入当前关卡的渲染配置；菜单背景也可使用，不注册游戏关卡或玩家状态。
func write_to_renderer() -> void:
	Renderer.foreground_blur_step = foreground_blur_step
	Renderer.background_blur_step = background_blur_step
	Renderer.maximum_blur_lod = maximum_blur_lod
	Renderer.foreground_darkness_step = foreground_darkness_step
	Renderer.foreground_tint_step = foreground_tint_step
	Renderer.contrast_falloff = contrast_falloff
	Renderer.background_tint_step = background_tint_step
	Renderer.haze_blur_step = haze_blur_step
	Renderer.haze_maximum_blur_lod = haze_maximum_blur_lod
	Renderer.haze_opacity = haze_opacity
	Renderer.haze_world_scale = haze_world_scale
	Renderer.haze_bottom_y = haze_bottom_y
	Renderer.haze_speed = haze_speed
	Renderer.haze_layer_offset = haze_layer_offset
	Renderer.foreground_tint_color = foreground_tint_color
	Renderer.background_tint_color = background_tint_color
	Renderer.selection_outline_color = selection_outline_color
	Renderer.selection_outline_width = selection_outline_width
