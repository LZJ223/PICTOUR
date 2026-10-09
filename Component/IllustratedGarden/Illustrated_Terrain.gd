@tool
class_name IllustratedGardenTerrain
extends LayerDecoration
## 固定大岸体。上沿是踏面，下沿形成有根的洞壁与薄断口。
@export var upper := PackedVector2Array():
	set(value):
		upper = value
		_rebuild()
@export var lower := PackedVector2Array():
	set(value):
		lower = value
		_rebuild()
@export var ink_color := Color("725363"):
	set(value):
		ink_color = value
		_rebuild()
@export var seed_value := 21:
	set(value):
		seed_value = value
		_rebuild()
@export var edge_rounding := 24.0:
	set(value):
		edge_rounding = value
		_rebuild()
var _visual: Node2D
var _body: StaticBody2D
var contour := PackedVector2Array()
var walkable := PackedVector2Array()

func _ready() -> void:
	_layer = get_parent() as DepthLayer
	_rebuild()

func _rebuild() -> void:
	if not is_node_ready() or upper.size()<2 or lower.size()<2: return
	for node in [_visual,_body]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	walkable = rounded(upper,edge_rounding)
	contour = walkable.duplicate()
	contour.append_array(StoryLandformArt.eroded_edge(rounded(lower,edge_rounding),seed_value))
	if Geometry2D.triangulate_polygon(contour).is_empty():
		push_error("ILLUSTRATED_TERRAIN: 地貌不能自交："+str(name))
		return
	_body = StaticBody2D.new()
	_body.name = "WorldOccupancy"
	_body.collision_layer = 1 << _layer.layer_id if _layer != null else 1
	_body.collision_mask = _body.collision_layer
	add_child(_body)
	var collision := CollisionPolygon2D.new()
	collision.polygon = contour
	_body.add_child(collision)
	_visual = Node2D.new()
	_visual.name = "ProjectedInk"
	add_child(_visual)
	var fog := 0.50 if _layer != null and _layer.slot>0 else 0.0
	StoryLandformArt.add_surface(_visual,contour,ink_color,seed_value,fog)
	var fill := _visual.get_node("LandInk") as Polygon2D
	(fill.material as ShaderMaterial).shader = preload("res://Component/IllustratedGarden/Illustrated_Ink.gdshader")
	(fill.material as ShaderMaterial).set_shader_parameter("page_surface",preload("res://Art/IllustratedGarden/Generated/Page_Strata_Surface.png"))
	(fill.material as ShaderMaterial).set_shader_parameter("background_surface",_layer != null and _layer.slot>0)
	if Engine.is_editor_hint(): _visual.z_index = 192 if _layer != null and _layer.slot==0 else 92

static func rounded(raw: PackedVector2Array, radius: float) -> PackedVector2Array:
	if raw.size()<3 or radius<=0.0: return raw.duplicate()
	var result := PackedVector2Array([raw[0]])
	for index in range(1,raw.size()-1):
		var a := raw[index-1]
		var b := raw[index]
		var c := raw[index+1]
		var p := b.move_toward(a,minf(radius,a.distance_to(b)*0.32))
		var q := b.move_toward(c,minf(radius,c.distance_to(b)*0.32))
		for step in range(7):
			var t := float(step)/6.0
			result.append(p.lerp(b,t).lerp(b.lerp(q,t),t))
	result.append(raw[-1])
	return result

func apply_visual_transfer(anchor_position: Vector2) -> void:
	if not is_instance_valid(_visual) or not is_instance_valid(_layer): return
	var multiplier: float = Global.layer_scales[_layer.slot]
	_visual.global_position = anchor_position + (global_position-anchor_position)*multiplier
	_visual.global_scale = Vector2.ONE*multiplier
	_visual.z_index = (Global.layer_count-_layer.slot)*100-8

func get_editor_geometry() -> Dictionary:
	var polygon := rounded(upper,edge_rounding)
	polygon.append_array(StoryLandformArt.eroded_edge(rounded(lower,edge_rounding),seed_value))
	return {"solids":[polygon],"walkable":[rounded(upper,edge_rounding)]}
