@tool
extends Resource
class_name SoilBakeProfile

## All distances are in the Ground's local units. At one pixel per unit,
## the outline width is also the width in the saved PNG.
@export_group("Colors")
@export var soil_color: Color = Color("92513f")
@export var grass_color: Color = Color("52d719")
@export var outline_color: Color = Color("201c17")

@export_group("Corners")
@export_range(0.0, 128.0, 0.5) var outer_corner_radius: float = 26.0
@export_range(0.0, 64.0, 0.5) var inner_corner_radius: float = 7.0

@export_group("Outline")
@export_range(0.0, 16.0, 0.25) var outline_width: float = 2.0
@export_range(0.0, 4.0, 0.1) var outline_wobble: float = 0.7
@export_range(4.0, 64.0, 1.0) var wobble_wavelength: float = 18.0

@export_group("Grass dots")
@export_range(0.0, 300.0, 1.0) var grass_depth: float = 85.0
@export_range(4.0, 48.0, 0.5) var dot_spacing: float = 14.0
@export_range(0.0, 0.49, 0.01) var dot_radius_ratio: float = 0.46
## A surface normal must point upward by at least this amount.
@export_range(0.0, 1.0, 0.05) var upward_threshold: float = 0.65
@export var seed: int = 1429

@export_group("Output")
@export_range(0.25, 2.0, 0.25) var pixels_per_unit: float = 1.0
@export_range(1, 3, 1) var supersampling: int = 2
