@tool
class_name BackgroundLandform
extends LayerDecoration

## 背景固定地平线。与同层景物共用投影，使根部的依托随视差保持一致。
## 纯背景世界底面，没有玩家实体；将来开放角色换层时须补对应实体。
@export var edge := PackedVector2Array([Vector2(0, 550), Vector2(900, 530)]):
	set(value):
		edge = value
		if is_node_ready():
			_build_land()
@export var underside := PackedVector2Array([Vector2(900, 670), Vector2(550, 720), Vector2(0, 650)]):
	set(value):
		underside = value
		if is_node_ready():
			_build_land()
@export var ink_color := Color(0.63, 0.68, 0.57, 0.76)
@export var seed_value := 21
@export_range(0.0, 1.0) var bottom_fade := 0.66
var _land_root: Node2D

func _ready() -> void:
	_layer = get_parent() as DepthLayer
	_build_land()

func _build_land() -> void:
	if is_instance_valid(_land_root):
		remove_child(_land_root)
		_land_root.queue_free()
	_land_root = Node2D.new()
	_land_root.name = "VisualLandform"
	add_child(_land_root)
	var polygon := edge.duplicate()
	if underside.size() >= 2:
		polygon.append_array(StoryLandformArt.eroded_edge(underside, seed_value))
	if polygon.size() < 3 or Geometry2D.triangulate_polygon(polygon).is_empty():
		push_error("BACKGROUND_LANDFORM: 背景地貌须为不自交多边形：" + str(name))
		return
	StoryLandformArt.add_surface(_land_root, polygon, ink_color, seed_value, bottom_fade)
	_land_root.z_index = 92

func apply_visual_transfer(anchor_position: Vector2) -> void:
	if not is_instance_valid(_land_root) or not is_instance_valid(_layer):
		return
	var multiplier: float = Global.layer_scales[_layer.slot]
	_land_root.global_position = anchor_position + (global_position - anchor_position) * multiplier
	_land_root.global_scale = Vector2.ONE * multiplier
	_land_root.z_index = (Global.layer_count - _layer.slot) * 100 - 8
