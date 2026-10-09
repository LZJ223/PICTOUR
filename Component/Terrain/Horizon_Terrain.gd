@tool
extends StaticBody2D
## 地平线是连续的世界底面。独立岩、树和建筑另用 NaturalObject。
@export var edge: PackedVector2Array = PackedVector2Array([Vector2(-600,600), Vector2(880,600)]):
	set(value):
		edge = value
		if is_inside_tree():
			_build()
const INK = preload("res://Art/Materials/Dry_Ink_AI.png")

func _ready() -> void:
	_build()

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if edge.size() < 2:
		return
	var polygon := edge.duplicate()
	var right := edge[edge.size()-1]
	var left := edge[0]
	## 墨面下沿不形成矩形平台；上沿保留真实、可读的接触面。
	polygon.append(right + Vector2(10,155))
	polygon.append(right + Vector2(-90,178))
	polygon.append(Vector2(lerpf(left.x,right.x,0.72),805))
	polygon.append(Vector2(lerpf(left.x,right.x,0.55),774))
	polygon.append(Vector2(lerpf(left.x,right.x,0.4),835))
	polygon.append(Vector2(lerpf(left.x,right.x,0.2),770))
	polygon.append(left + Vector2(-24,163))
	var solid := CollisionPolygon2D.new()
	solid.name = "WorldBase"
	solid.polygon = polygon
	add_child(solid)
	var art := Polygon2D.new()
	art.name = "DryInk"
	art.polygon = polygon
	art.texture = INK
	art.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	art.texture_scale = Vector2(2.8,2.8)
	art.color = Color("cab7c8")
	add_child(art)
	var lip := Line2D.new()
	lip.points = edge
	lip.width = 2.5
	lip.default_color = Color("6d5364")
	add_child(lip)
