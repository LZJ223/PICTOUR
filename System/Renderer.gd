## 自动挂载的全局渲染参数。所有强度参数设为 0 时，对应效果会直接关闭。
extends Node

const HAZE_TEXTURE: Texture2D = preload("res://Texture/Others/Haze.png")

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

## 偏移色由当前 Level 在初始化时写入，允许每个关卡拥有独立配色。
var foreground_tint_color: Color = Color(0.27, 0.159, 0.122, 1.0)
var background_tint_color: Color = Color(0.339, 0.852, 0.87, 1.0)

@export_group("选择描边")
@export var selection_outline_color: Color = Color.WHITE
@export_range(0.0, 16.0, 0.5) var selection_outline_width: float = 6.0

## 运行时修改参数后可再次调用，立即把当前配置同步给所有着色器。
func apply_settings() -> void:
	RenderingServer.global_shader_parameter_set(
		&"render_foreground_blur_step", foreground_blur_step
	)
	RenderingServer.global_shader_parameter_set(
		&"render_maximum_blur_lod", maximum_blur_lod
	)
	RenderingServer.global_shader_parameter_set(
		&"render_background_blur_step", background_blur_step
	)
	RenderingServer.global_shader_parameter_set(
		&"render_foreground_darkness_step", foreground_darkness_step
	)
	RenderingServer.global_shader_parameter_set(
		&"render_foreground_tint_color", foreground_tint_color
	)
	RenderingServer.global_shader_parameter_set(
		&"render_foreground_tint_step", foreground_tint_step
	)
	RenderingServer.global_shader_parameter_set(
		&"render_contrast_falloff", contrast_falloff
	)
	RenderingServer.global_shader_parameter_set(
		&"render_background_tint_color", background_tint_color
	)
	RenderingServer.global_shader_parameter_set(
		&"render_background_tint_step", background_tint_step
	)
	RenderingServer.global_shader_parameter_set(&"render_haze_texture", HAZE_TEXTURE)
	RenderingServer.global_shader_parameter_set(&"render_haze_blur_step", haze_blur_step)
	RenderingServer.global_shader_parameter_set(
		&"render_haze_maximum_blur_lod", haze_maximum_blur_lod
	)
	RenderingServer.global_shader_parameter_set(&"render_haze_opacity", haze_opacity)
	RenderingServer.global_shader_parameter_set(
		&"render_haze_world_scale", haze_world_scale
	)
	RenderingServer.global_shader_parameter_set(&"render_haze_bottom_y", haze_bottom_y)
	RenderingServer.global_shader_parameter_set(&"render_haze_speed", haze_speed)
	RenderingServer.global_shader_parameter_set(
		&"render_haze_layer_offset", haze_layer_offset
	)
	RenderingServer.global_shader_parameter_set(
		&"render_selection_outline_color", selection_outline_color
	)
	RenderingServer.global_shader_parameter_set(
		&"render_selection_outline_width", selection_outline_width
	)
