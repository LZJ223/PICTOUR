@tool
class_name CloudGroundProfile
extends Resource

@export_group("Colors")
@export var base_color: Color = Color("b8b8b8")
@export var dot_color: Color = Color("f2f2f2")
@export var outline_color: Color = Color("252525")

@export_group("Corners")
@export_range(0.0, 4096.0, 0.5) var outer_radius: float = 26.0
@export_range(0.0, 4096.0, 0.5) var inner_radius: float = 7.0
@export_range(0.01, 4.0, 0.01) var max_chord_error: float = 0.5
@export_range(16, 4096, 16) var max_vertices: int = 1024

@export_group("Outline (output pixels)")
@export_range(0.0, 16.0, 0.25) var outline_width_px: float = 2.0
@export_range(0.0, 4.0, 0.1) var outline_wobble_px: float = 0.7
@export_range(4.0, 128.0, 1.0) var outline_wavelength_px: float = 18.0

@export_group("Cloud dots (local units)")
@export_range(0.0, 1000.0, 1.0) var cloud_depth: float = 85.0
@export_range(2.0, 64.0, 0.5) var dot_spacing: float = 8.0
@export_range(0.0, 0.49, 0.01) var dot_radius_ratio: float = 0.46
@export_range(0.1, 4.0, 0.1) var depth_falloff: float = 1.0
@export_range(0.1, 1.0, 0.05) var upward_threshold: float = 0.65
@export var seed: int = 1429

@export_group("Output")
@export_range(0.25, 4.0, 0.25) var pixels_per_unit: float = 1.0
@export_range(1, 3, 1) var supersampling: int = 2
@export_range(256, 2048, 256) var tile_size_px: int = 1024


func validation_error() -> String:
	for value in [outer_radius, inner_radius, max_chord_error, outline_width_px, outline_wobble_px, outline_wavelength_px, cloud_depth, dot_spacing, dot_radius_ratio, depth_falloff, upward_threshold, pixels_per_unit]:
		if not is_finite(value):
			return "参数必须是有限数值。"
	for color in [base_color, dot_color, outline_color]:
		for value in [color.r, color.g, color.b, color.a]:
			if not is_finite(value) or value < 0.0 or value > 1.0:
				return "颜色通道必须在 0～1 之间。"
	if outer_radius < 0.0 or inner_radius < 0.0 or inner_radius > outer_radius:
		return "圆角半径需非负，内角半径不能大于外角半径。"
	if max_chord_error < 0.01 or max_vertices < 16 or max_vertices > 4096:
		return "弦误差至少为 0.01，最大顶点数应在 16～4096 之间。"
	if outline_width_px < 0.0 or outline_wobble_px < 0.0 or outline_wavelength_px < 4.0:
		return "描边宽度与抖动需非负，抖动波长至少为 4px。"
	if cloud_depth < 0.0 or dot_spacing < 2.0 or dot_radius_ratio < 0.0 or dot_radius_ratio > 0.49 or depth_falloff <= 0.0:
		return "波点深度需非负、间距至少为 2，半径比例为 0～0.49，衰减强度需大于零。"
	if upward_threshold < 0.1 or upward_threshold > 1.0:
		return "上表面法线阈值应在 0.1～1 之间。"
	if pixels_per_unit < 0.25 or pixels_per_unit > 4.0 or supersampling < 1 or supersampling > 3 or tile_size_px < 256 or tile_size_px > 2048:
		return "像素密度应为 0.25～4，超采样为 1～3，分块边长为 256～2048px。"
	return ""
