## 自动挂载的渲染参数运行时副本，由当前 Level 初始化写入，再同步给全局 Shader。
## 可编辑配置位于 Level.gd；所有强度参数设为 0 时，对应效果会直接关闭。
extends Node

const HAZE_TEXTURE: Texture2D = preload("res://Texture/Others/Haze.png")

var foreground_blur_step: float = 1.2
var background_blur_step: float = 0.8
var maximum_blur_lod: float = 4.0

var foreground_darkness_step: float = 0.2
var foreground_tint_step: float = 0.05

var night_foreground_enabled: bool = true
var night_foreground_surface_width: float = 4.0
var night_foreground_fade_width: float = 2.0
var night_foreground_max_brightness: float = 0.75
var night_foreground_near_distance: float = 100.0
var night_foreground_far_distance: float = 700.0
var night_foreground_darkness: float = 0.8

var contrast_falloff: float = 0.15

var background_tint_step: float = 0.1

var haze_blur_step: float = 2.0
var haze_maximum_blur_lod: float = 6.0
var haze_opacity: float = 0.75
var haze_world_scale: float = 0.4
var haze_bottom_y: float = 500.0
var haze_speed: float = 30.0
var haze_layer_offset: float = 450.0

var foreground_tint_color: Color = Color(0.27, 0.159, 0.122, 1.0)
var background_tint_color: Color = Color(0.339, 0.852, 0.87, 1.0)

var selection_outline_color: Color = Color.WHITE
var selection_outline_width: float = 6.0

## 运行时修改参数后可再次调用，立即把当前配置同步给所有着色器。
func apply_settings() -> void:
	RenderingServer.global_shader_parameter_set(&"render_night_foreground_enabled", night_foreground_enabled)
	RenderingServer.global_shader_parameter_set(&"render_night_foreground_surface_width", night_foreground_surface_width)
	RenderingServer.global_shader_parameter_set(&"render_night_foreground_fade_width", night_foreground_fade_width)
	RenderingServer.global_shader_parameter_set(&"render_night_foreground_max_brightness", night_foreground_max_brightness)
	RenderingServer.global_shader_parameter_set(&"render_night_foreground_near_distance", night_foreground_near_distance)
	RenderingServer.global_shader_parameter_set(&"render_night_foreground_far_distance", night_foreground_far_distance)
	RenderingServer.global_shader_parameter_set(&"render_night_foreground_darkness", night_foreground_darkness)
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
