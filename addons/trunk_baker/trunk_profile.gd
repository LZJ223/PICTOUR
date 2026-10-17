@tool
extends Resource
class_name TrunkBakeProfile

@export_group("颜色")
@export_color_no_alpha var base_color: Color = Color("b7a181")
@export_color_no_alpha var dot_color: Color = Color("786449")
@export_color_no_alpha var outline_color: Color = Color("201c17")

@export_group("描边（最终贴图像素）")
@export_range(0.0, 16.0, 0.25) var outline_width: float = 2.0
@export_range(0.0, 4.0, 0.1) var outline_wobble: float = 0.6
@export_range(4.0, 80.0, 1.0) var outline_wavelength: float = 18.0

@export_group("波点（物体本地单位）")
@export_range(2.0, 48.0, 0.5) var dot_spacing: float = 4.0
@export_range(0.4, 1.5, 0.01) var dot_row_spacing_ratio: float = 0.8660254
@export_range(0.0, 0.49, 0.01) var dot_radius_ratio: float = 0.32

@export_group("宽度三等分阴影")
## Fixed divisions at 1/3 and 2/3 of the rectangle's local width.
## Both the base color and the dots are shaded; the right third is unshaded.
@export_range(0.0, 1.0, 0.01) var deep_shadow_opacity: float = 0.30
@export_range(0.0, 1.0, 0.01) var light_shadow_opacity: float = 0.15

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
	if pixels_per_unit < 0.25 or pixels_per_unit > 2.0 or supersampling < 1 or supersampling > 3:
		return "像素密度应为 0.25～2，超采样应为 1～3。"
	if tile_size_px < 256 or tile_size_px > 2048:
		return "分块尺寸应为 256～2048 像素。"
	if dot_spacing < 2.0 or dot_spacing > 48.0 or dot_row_spacing_ratio < 0.4 or dot_row_spacing_ratio > 1.5 or dot_radius_ratio < 0.0 or dot_radius_ratio > 0.49:
		return "波点间距、行距或半径比例无效。"
	if outline_width < 0.0 or outline_width > 16.0 or outline_wobble < 0.0 or outline_wobble > 4.0 or outline_wavelength < 4.0 or outline_wavelength > 80.0:
		return "描边宽度应为 0～16px，抖动为 0～4px，波长为 4～80px。"
	if light_shadow_opacity < 0.0 or deep_shadow_opacity > 1.0 or deep_shadow_opacity < light_shadow_opacity:
		return "阴影应满足 0 ≤ 浅阴影 ≤ 深阴影 ≤ 1。"
	return ""
