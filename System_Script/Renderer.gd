## 自动挂载的全局渲染参数。所有强度参数设为 0 时，对应效果会直接关闭。
extends Node

@export_group("前景图层")
@export_range(0.0, 4.0, 0.1) var foreground_blur_step: float = 1.0
@export_range(0.0, 4.0, 0.1) var maximum_blur_lod: float = 3.0
@export_range(0.0, 1.0, 0.01) var foreground_darkness_step: float = 0.28
@export var foreground_tint_color: Color = Color(0.04, 0.05, 0.07, 1.0)
@export_range(0.0, 1.0, 0.01) var foreground_tint_step: float = 0.10

@export_group("远离关卡层")
@export_range(0.0, 1.0, 0.01) var contrast_falloff: float = 0.15

@export_group("后景图层")
@export var background_tint_color: Color = Color(0.18, 0.24, 0.28, 1.0)
@export_range(0.0, 1.0, 0.01) var background_tint_step: float = 0.14

@export_group("选择描边")
@export var selection_outline_color: Color = Color.WHITE
@export_range(0.0, 16.0, 0.5) var selection_outline_width: float = 3.0

## 运行时修改参数后可再次调用，立即把当前配置同步给所有着色器。
func apply_settings() -> void:
	RenderingServer.global_shader_parameter_set(
		&"render_foreground_blur_step", foreground_blur_step
	)
	RenderingServer.global_shader_parameter_set(
		&"render_maximum_blur_lod", maximum_blur_lod
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
	RenderingServer.global_shader_parameter_set(
		&"render_selection_outline_color", selection_outline_color
	)
	RenderingServer.global_shader_parameter_set(
		&"render_selection_outline_width", selection_outline_width
	)
