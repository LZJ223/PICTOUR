@tool
class_name StoryBank
extends PaperIsland

## edge左到右，underside右到左。下沿独立设计，避免地貌变成等厚细条。
@export var underside: PackedVector2Array = PackedVector2Array():
	set(value):
		underside = value
		if is_node_ready():
			_build()
@export var show_strata := false

func _build() -> void:
	if underside.is_empty():
		super._build()
		return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if edge.size() < 2 or underside.size() < 2:
		return
	var polygon := edge.duplicate()
	polygon.append_array(StoryLandformArt.eroded_edge(underside, seed_value))
	if Geometry2D.triangulate_polygon(polygon).is_empty():
		push_error("STORY_BANK: 地形上下轮廓不能自交：" + str(name))
		return
	var solid := CollisionPolygon2D.new()
	solid.name = "WorldBase"
	solid.polygon = polygon
	add_child(solid)
	StoryLandformArt.add_surface(self, polygon, ink_color, seed_value, 0.0)
	if show_strata:
		StoryLandformArt.add_strata(self, edge, polygon, Color(0.79, 0.65, 0.64, 0.18), seed_value)
