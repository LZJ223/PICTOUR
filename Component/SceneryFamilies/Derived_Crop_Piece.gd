@tool
class_name DerivedCropPiece
extends SceneryFamilyPiece

## 在父图裁框内沿枝颈、岩理、砖缝取自然断片；原 PNG 不被改写。
@export var visual_masks: Array[PackedVector2Array] = []
@export var non_solid := false
@export_multiline var derivation_note: String
## 归一化的生长依托点；垂生植物的根颈可位于裁框上侧而非下侧。
@export var attachment_point := Vector2(0.5,1.0)
