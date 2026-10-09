@tool
class_name IllustratedGardenPiece
extends Resource
## 母素材的像素、原图区域和手追实体一起保存。实例只摆根位置。
@export var display_name := "页石"
@export var family := "page"
@export var painting: Texture2D
@export var source_region := Rect2()
@export var source_pivot := Vector2.ZERO
@export var unit_scale := 0.25
@export var source_contours: Array[PackedVector2Array] = []
@export var source_pick_contours: Array[PackedVector2Array] = []
@export var source_walkable: Array[PackedVector2Array] = []
@export var visual_masks: Array[PackedVector2Array] = []

func local_polygons(multiplier: float = 1.0, mirrored: bool = false, picks: bool = false) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var source := source_pick_contours if picks and not source_pick_contours.is_empty() else source_contours
	for polygon in source:
		var points := PackedVector2Array()
		for point in polygon:
			var local := (point-source_pivot)*unit_scale*multiplier
			if mirrored: local.x = -local.x
			points.append(local)
		if mirrored: points.reverse()
		result.append(points)
	return result
