@tool
class_name VerticalGardenTerrain
extends LayerDecoration
## 世界地平线的实体永远留在物理坐标；只有墨面接受景别投影。
@export var contour := PackedVector2Array()
@export var ink_color := Color("695663")
@export var seed_value := 21
@export var top_vertices := 2
var _visual: Node2D
var _body: StaticBody2D

func _ready() -> void:
	_layer = get_parent() as DepthLayer
	assert(_layer != null)
	## 侵蚀只改变下缘；实际碰撞与墨面一起使用它，不侵蚀玩家踏面。
	if top_vertices > 0 and top_vertices < contour.size():
		var upper := contour.slice(0,top_vertices)
		var lower := contour.slice(top_vertices-1)
		lower.append(contour[0])
		var worn := StoryLandformArt.eroded_edge(lower,seed_value)
		upper.append_array(worn.slice(1,worn.size()-1))
		contour = upper
	assert(not Geometry2D.triangulate_polygon(contour).is_empty(), "世界地貌必须为简单轮廓："+str(name))
	_body = StaticBody2D.new()
	_body.name = "WorldOccupancy"
	_body.collision_layer = 1 << _layer.layer_id
	_body.collision_mask = _body.collision_layer
	add_child(_body)
	var collision := CollisionPolygon2D.new()
	collision.polygon = contour
	_body.add_child(collision)
	_visual = Node2D.new()
	_visual.name = "ProjectedInk"
	add_child(_visual)
	StoryLandformArt.add_surface(_visual, contour, ink_color, seed_value, 0.52 if _layer.slot > 0 else 0.0)
	## 研究场的大片世界底面减弱颗粒，避免与主物件抢夺纹理注意力。
	var fill := _visual.get_node("LandInk") as Polygon2D
	var material := fill.material as ShaderMaterial
	material.shader = preload("res://Component/VerticalGarden/Vertical_Ink.gdshader")

func apply_visual_transfer(anchor_position: Vector2) -> void:
	if not is_instance_valid(_visual): return
	var multiplier: float = Global.layer_scales[_layer.slot]
	_visual.global_position = anchor_position + (global_position-anchor_position)*multiplier
	_visual.global_scale = Vector2.ONE*multiplier
	_visual.z_index = (Global.layer_count-_layer.slot)*100-8
