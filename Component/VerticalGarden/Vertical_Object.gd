@tool
class_name VerticalGardenObject
extends NaturalObject
## 折页井的连续自然实体。外形、实体和点选共享同一组轮廓。
@export var solid_polygons: Array[PackedVector2Array] = []
@export var painting: Texture2D
@export var painting_rect := Rect2(-200, -280, 400, 280)
@export var ink_color := Color("665162")
var _extra_solids: Array[CollisionPolygon2D] = []
var _native_material: ShaderMaterial

func _rebuild() -> void:
	if not is_node_ready():
		return
	for holder in [$VisualRoot/Area2D, $VisualRoot/Art]:
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()
	for line in _outline_lines:
		if is_instance_valid(line): line.queue_free()
	_outline_lines.clear()
	_collision_parts.clear()
	for collision in _extra_solids:
		if is_instance_valid(collision):
			remove_child(collision)
			collision.queue_free()
	_extra_solids.clear()
	_native_material = ShaderMaterial.new()
	_native_material.shader = preload("res://Art/PaperStage/Paper_Ink.gdshader")
	_native_material.set_shader_parameter("grain", preload("res://Art/Materials/Dry_Ink_AI.png"))
	_native_material.set_shader_parameter("grain_offset", Vector2(0.13,0.37))
	var primary := $CollisionBox as CollisionPolygon2D
	primary.polygon = PackedVector2Array()
	for index in solid_polygons.size():
		var points := solid_polygons[index]
		assert(not Geometry2D.triangulate_polygon(points).is_empty(), "折页井实体必须为简单轮廓")
		if index == 0:
			primary.polygon = points
		else:
			var collision := CollisionPolygon2D.new()
			collision.polygon = points
			collision.transform = primary.transform
			add_child(collision)
			_extra_solids.append(collision)
		for convex in Geometry2D.decompose_polygon_in_convex(points):
			var shape := ConvexPolygonShape2D.new()
			shape.points = convex
			_collision_parts.append(shape)
		var pick := CollisionPolygon2D.new()
		pick.polygon = points
		$VisualRoot/Area2D.add_child(pick)
		var outline := Line2D.new()
		outline.points = points
		outline.closed = true
		outline.antialiased = true
		$VisualRoot.add_child(outline)
		_outline_lines.append(outline)
		var fill := Polygon2D.new()
		fill.polygon = points
		fill.color = ink_color
		fill.material = _native_material
		$VisualRoot/Art.add_child(fill)
	var sprite := $VisualRoot/Sprite2D as Sprite2D
	sprite.texture = painting
	sprite.visible = painting != null
	$VisualRoot/Art.visible = painting == null
	if painting != null:
		sprite.position = painting_rect.get_center()
		sprite.scale = painting_rect.size / painting.get_size()
	_ink_material = ShaderMaterial.new()
	_ink_material.shader = preload("res://Art/Nature/Depth_Ink.gdshader")
	_ink_material.set_shader_parameter("texture_strength", 0.0)
	sprite.material = _ink_material
	_depth_offset = -100
	if Engine.is_editor_hint(): _apply_depth_style(0)
	else: _refresh_depth_style()
	_refresh_outline()

func apply_visual_transfer(anchor_position: Vector2) -> void:
	super.apply_visual_transfer(anchor_position)
	for collision in _extra_solids:
		if is_instance_valid(collision):
			collision.transform = collision_box.transform

func _apply_depth_style(offset: int) -> void:
	_depth_offset = offset
	var fog := 0.77 if offset > 0 else 0.0
	if _ink_material != null: _ink_material.set_shader_parameter("depth_fog", fog)
	if _native_material != null: _native_material.set_shader_parameter("depth_fog", fog)
	_refresh_outline()

func allows_non_solid_transfer() -> bool:
	return solid_polygons.is_empty()
