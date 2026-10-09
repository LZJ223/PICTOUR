@tool
class_name NaturalObject
extends LayerObject

@export_enum("Rock", "ShortTree", "Arch", "Branch", "Plant") var kind: int = 0:
	set(value):
		kind = value
		_rebuild()
@export var dimensions: Vector2 = Vector2(140, 90):
	set(value):
		dimensions = Vector2(maxf(value.x, 1), maxf(value.y, 1))
		_rebuild()
@export_range(0, 1, 1) var variation: int = 0:
	set(value):
		variation = value
		_rebuild()
@export var display_name: String = "墨石"

var _selected: bool = false
var _hovered: bool = false
var _valid_transfer: bool = true
var _depth_offset: int = -100
var _ink_material: ShaderMaterial
var _collision_parts: Array[Shape2D] = []
var _outline_lines: Array[Line2D] = []

func _ready() -> void:
	_rebuild()
	if Engine.is_editor_hint():
		return
	super._ready()
	$VisualRoot/Area2D.input_pickable = can_transfer
	$VisualRoot/Area2D.mouse_entered.connect(_on_mouse_entered)
	$VisualRoot/Area2D.mouse_exited.connect(_on_mouse_exited)
	_refresh_depth_style()

func _rebuild() -> void:
	if not is_node_ready():
		return
	var nominal := NaturalForm.nominal_size(kind)
	var geometry_scale := dimensions / nominal
	var polygon := _scaled(NaturalForm.solid_polygon(kind, variation), geometry_scale)
	$CollisionBox.polygon = polygon
	$CollisionBox.disabled = kind == NaturalForm.Kind.PLANT
	_collision_parts.clear()
	if not polygon.is_empty():
		for convex in Geometry2D.decompose_polygon_in_convex(polygon):
			var shape := ConvexPolygonShape2D.new()
			shape.points = convex
			_collision_parts.append(shape)
	var pick_area := $VisualRoot/Area2D as Area2D
	for child in pick_area.get_children():
		pick_area.remove_child(child)
		child.queue_free()
	for line in _outline_lines:
		if is_instance_valid(line):
			line.queue_free()
	_outline_lines.clear()
	for points in NaturalForm.pick_polygons(kind, variation):
		var scaled_points := _scaled(points, geometry_scale)
		var pick_shape := CollisionPolygon2D.new()
		pick_shape.polygon = scaled_points
		pick_area.add_child(pick_shape)
		var outline := Line2D.new()
		outline.points = scaled_points
		outline.closed = true
		outline.width = 2.5
		outline.antialiased = true
		outline.joint_mode = Line2D.LINE_JOINT_ROUND
		$VisualRoot.add_child(outline)
		_outline_lines.append(outline)
	var path := "res://Art/Nature/PNG/" + NaturalForm.asset_name(kind, variation) + ".png"
	var sprite := $VisualRoot/Sprite2D as Sprite2D
	if ResourceLoader.exists(path):
		sprite.texture = load(path) as Texture2D
	sprite.position = Vector2(0, -dimensions.y * 0.5)
	sprite.scale = geometry_scale * 0.5
	_ink_material = ShaderMaterial.new()
	_ink_material.shader = preload("res://Art/Nature/Depth_Ink.gdshader")
	if ResourceLoader.exists("res://Art/Materials/Dry_Ink_AI.png"):
		_ink_material.set_shader_parameter("dry_ink", load("res://Art/Materials/Dry_Ink_AI.png"))
	else:
		_ink_material.set_shader_parameter("texture_strength", 0.0)
	sprite.material = _ink_material
	_depth_offset = -100
	if Engine.is_editor_hint():
		_apply_depth_style(0)
	else:
		_refresh_depth_style()
	_refresh_outline()

func apply_visual_transfer(anchor_position: Vector2) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(owner_layer):
		return
	super.apply_visual_transfer(anchor_position)
	_refresh_depth_style()

## 每项对应同一凹轮廓的一个凸部分；空心拱门洞口不会被实体查询填满。
func get_transfer_collision_parts(target_layer: DepthLayer, anchor_position: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if allows_non_solid_transfer():
		return result
	var transform := get_transfer_collision_transform(target_layer, anchor_position)
	for shape in _collision_parts:
		result.append({"shape": shape, "transform": transform})
	return result

func allows_non_solid_transfer() -> bool:
	return kind == NaturalForm.Kind.PLANT

func set_pick_condition(condition: bool = false) -> void:
	_selected = condition and can_transfer
	_refresh_outline()

func set_transfer_preview(valid: bool) -> void:
	_valid_transfer = valid
	_refresh_outline()

func _refresh_depth_style() -> void:
	if not is_instance_valid(owner_layer):
		return
	var offset := owner_layer.slot - Global.current_layer_index
	if offset != _depth_offset:
		_apply_depth_style(offset)

func _apply_depth_style(offset: int) -> void:
	_depth_offset = offset
	if _ink_material != null:
		_ink_material.set_shader_parameter("depth_fog", clampf(0.72 + (offset - 1) * 0.08, 0.0, 0.9) if offset > 0 else 0.0)
	_refresh_outline()

func _refresh_outline() -> void:
	for line in _outline_lines:
		if not is_instance_valid(line):
			continue
		line.visible = can_transfer and (_selected or _hovered)
		line.width = 2.2 if _selected else 1.3
		line.default_color = Color("7b634d") if _selected and not _valid_transfer else Color("62506c")
		line.modulate.a = 0.82 if _selected else 0.45

func _on_mouse_entered() -> void:
	_hovered = true
	_refresh_outline()

func _on_mouse_exited() -> void:
	_hovered = false
	_refresh_outline()

func _scaled(points: PackedVector2Array, scaling: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(point * scaling)
	return result
