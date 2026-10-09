class_name BookmarkMarker
extends Node2D

## 固定的凝墨书签：圆形墨印与红丝带组成自己的存档符号。
var title: String = "书签"
var unlocked: bool = false
var current: bool = false
var _visual: Node2D
var _owner_layer: DepthLayer

func _ready() -> void:
	_owner_layer = get_parent() as DepthLayer
	_visual = Node2D.new()
	_visual.name = "InkBookmark"
	add_child(_visual)
	_visual.draw.connect(_draw_marker)
	queue_visual_update()

func queue_visual_update() -> void:
	if is_instance_valid(_visual):
		_visual.queue_redraw()

func apply_projection(anchor: Vector2) -> void:
	if not is_instance_valid(_owner_layer) or not is_instance_valid(_visual):
		return
	var multiplier: float = Global.layer_scales[_owner_layer.slot]
	_visual.global_position = anchor + (global_position - anchor) * multiplier
	_visual.global_scale = Vector2.ONE * multiplier
	_visual.z_index = (Global.layer_count - _owner_layer.slot) * 100

func _draw_marker() -> void:
	var plum := Color("44384e")
	var paper := Color("f4e9d3")
	var red := Color("c96755")
	var muted := Color("a4989c")
	var ink := plum if unlocked else muted
	_visual.draw_circle(Vector2(0, -9), 14, ink)
	_visual.draw_circle(Vector2(-2, -12), 8, paper)
	_visual.draw_arc(Vector2(0, -9), 19, 0.12, 5.7, 28, Color(ink, 0.35), 1.5, true)
	_visual.draw_colored_polygon(PackedVector2Array([Vector2(-3, -24), Vector2(2, -25), Vector2(6, -39), Vector2(1, -44), Vector2(-5, -34)]), red)
	_visual.draw_polyline(PackedVector2Array([Vector2(1, -36), Vector2(8, -51), Vector2(18, -58), Vector2(17, -66)]), red, 3, true)
	_visual.draw_colored_polygon(PackedVector2Array([Vector2(16, -67), Vector2(30, -62), Vector2(25, -57), Vector2(28, -53), Vector2(16, -58)]), red)
	_visual.draw_line(Vector2(-20, 0), Vector2(23, 0), Color(ink, 0.55), 2, true)
	if current:
		_visual.draw_arc(Vector2(0, -9), 23, 2.95, 6.45, 24, Color(red, 0.5), 1.5, true)
