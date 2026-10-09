@tool
class_name PaperIsland
extends StaticBody2D

## 顶面是玩法地平线，底面真实终止在纸面留白中。
@export var edge: PackedVector2Array = PackedVector2Array([Vector2(-450,510),Vector2(790,510)]):
	set(value):
		edge = value
		if is_inside_tree(): _build()
@export var thickness: float = 125.0:
	set(value):
		thickness = value
		if is_inside_tree(): _build()
@export var seed_value: int = 11:
	set(value):
		seed_value = value
		if is_inside_tree(): _build()
@export var ink_color: Color = Color("574451")

func _ready() -> void:
	_build()

func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if edge.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var polygon := edge.duplicate()
	var left := edge[0]
	var right := edge[edge.size()-1]
	var span := right.x-left.x
	var count := maxi(12,int(span/28.0))
	for i in range(count+1):
		var t := float(i)/count
		var envelope := sin(t*PI)*0.65+0.24
		var large_fold := 0.60+0.22*sin(t*TAU*2.2+seed_value)+0.20*sin(t*TAU*4.1)
		var depth := thickness*envelope*large_fold+rng.randf_range(-7,7)
		var x := lerpf(right.x,left.x,t)
		polygon.append(Vector2(x,_edge_height(x)+maxf(15,depth)))
	var solid := CollisionPolygon2D.new()
	solid.name = "WorldBase"
	solid.polygon = polygon
	add_child(solid)
	var material := ShaderMaterial.new()
	material.shader = preload("res://Art/PaperStage/Paper_Ink.gdshader")
	material.set_shader_parameter("grain",preload("res://Art/Materials/Dry_Ink_AI.png"))
	material.set_shader_parameter("wear",0.76)
	material.set_shader_parameter("grain_offset",Vector2(seed_value*0.023,0.17))
	var fill := Polygon2D.new()
	fill.name = "BrokenInkShore"
	fill.polygon = polygon
	fill.color = ink_color
	fill.material = material
	add_child(fill)
	var lip := Line2D.new()
	lip.points = edge
	lip.width = 1.0
	lip.default_color = Color(0.66,0.54,0.56,0.35)
	lip.antialiased = true
	add_child(lip)
	## 大块断墨缺口同底缘相接，避免覆盖真实踏面或增加隐形碰撞。
	for i in range(3):
		var root_t := 0.2+float(i)*0.25
		var x := lerpf(left.x,right.x,root_t)
		var y := lerpf(left.y,right.y,root_t)+thickness*0.28
		var seam := Line2D.new()
		seam.points = PackedVector2Array([Vector2(x,y),Vector2(x+9,y+14),Vector2(x-5,y+36)])
		seam.width = 1.6
		seam.default_color = Color(0.83,0.72,0.65,0.45)
		seam.antialiased = true
		add_child(seam)

func _edge_height(x: float) -> float:
	for i in range(edge.size()-1):
		if x >= edge[i].x and x <= edge[i+1].x:
			return lerpf(edge[i].y,edge[i+1].y,inverse_lerp(edge[i].x,edge[i+1].x,x))
	return edge[0].y
