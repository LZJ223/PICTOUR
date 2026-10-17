@tool
extends Resource
class_name LeafBakeProfile

@export_group("颜色")
@export_color_no_alpha var base_color: Color = Color("159825")
@export_color_no_alpha var dot_color: Color = Color("77cf30")
@export_color_no_alpha var outline_color: Color = Color("201c17")

@export_group("圆角")
## Each corner is sampled independently as a fraction of the shorter side.
@export_range(0.0, 0.45, 0.01) var corner_radius_min: float = 0.12
@export_range(0.0, 0.45, 0.01) var corner_radius_max: float = 0.20

@export_group("描边（最终贴图像素）")
@export_range(0.0, 16.0, 0.25) var outline_width: float = 2.0
@export_range(0.0, 4.0, 0.1) var outline_wobble: float = 0.6
@export_range(4.0, 80.0, 1.0) var outline_wavelength: float = 18.0

@export_group("波点（物体本地单位）")
@export_range(2.0, 48.0, 0.5) var dot_spacing: float = 4.0
@export_range(0.4, 1.5, 0.01) var dot_row_spacing_ratio: float = 0.8660254
@export_range(0.0, 0.49, 0.01) var dot_radius_ratio: float = 0.32

@export_group("弧形阴影")
@export_range(0.0, 1.0, 0.01) var deep_shadow_opacity: float = 0.30
@export_range(0.0, 1.0, 0.01) var light_shadow_opacity: float = 0.15
## Positions on the straight upper edge, as a fraction of the width.
@export_range(0.05, 0.90, 0.01) var deep_boundary_ratio: float = 0.28
@export_range(0.10, 0.95, 0.01) var light_boundary_ratio: float = 0.60
## Horizontal travel at the bottom, as a fraction of the shorter side.
## The circular arcs always enter the top edge perpendicularly.
@export_range(-0.6, 0.6, 0.01) var shadow_bend_ratio: float = 0.20
@export_range(0.0, 3.0, 0.1) var shadow_wobble: float = 0.45
@export_range(4.0, 80.0, 1.0) var shadow_wavelength: float = 18.0

@export_group("输出")
@export var seed: int = 1429
@export_range(0.25, 2.0, 0.25) var pixels_per_unit: float = 1.0
@export_range(1, 3, 1) var supersampling: int = 2
@export_range(256, 2048, 256) var tile_size_px: int = 1024


func validation_error() -> String:
	for property in get_property_list():
		if property.type == TYPE_FLOAT and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			if not is_finite(float(get(property.name))):
				return "参数 %s 必须是有限数值。" % property.name
	if corner_radius_min < 0.0 or corner_radius_max > 0.45 or corner_radius_min > corner_radius_max:
		return "圆角比例应满足 0 ≤ 最小值 ≤ 最大值 ≤ 0.45。"
	if pixels_per_unit < 0.25 or pixels_per_unit > 2.0 or supersampling < 1 or supersampling > 3:
		return "像素密度应为 0.25～2，超采样应为 1～3。"
	if tile_size_px < 256 or tile_size_px > 2048:
		return "分块尺寸应为 256～2048 像素。"
	if dot_spacing < 2.0 or dot_row_spacing_ratio < 0.4 or dot_radius_ratio < 0.0 or dot_radius_ratio > 0.49:
		return "波点间距、行距或半径比例无效。"
	if outline_width < 0.0 or outline_wobble < 0.0 or outline_wavelength < 4.0 or shadow_wobble < 0.0 or shadow_wavelength < 4.0:
		return "描边和抖动宽度必须非负，波长至少为 4。"
	if light_shadow_opacity < 0.0 or deep_shadow_opacity > 1.0 or deep_shadow_opacity < light_shadow_opacity:
		return "阴影应满足 0 ≤ 浅阴影 ≤ 深阴影 ≤ 1。"
	if deep_boundary_ratio < 0.0 or light_boundary_ratio > 1.0 or light_boundary_ratio - deep_boundary_ratio < 0.05:
		return "深、浅阴影分界需从左到右排列，间距至少为宽度的 5%。"
	if absf(shadow_bend_ratio) > 0.6:
		return "阴影弯曲比例应为 -0.6～0.6。"
	return ""
