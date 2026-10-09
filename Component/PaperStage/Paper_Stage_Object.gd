@tool
class_name PaperStageObject
extends NaturalObject

@export_enum("HeroTree", "BrokenArch", "SlantRock", "SeedPlant", "FallenBough") var profile: int = 0:
	set(value):
		profile = value
		_rebuild()
@export var texture_override: Texture2D:
	set(value):
		texture_override = value
		_rebuild()
## 名义坐标中的完整贴图矩形；有透明出血时可独立于碰撞轮廓调整。
@export var texture_rect: Rect2 = Rect2():
	set(value):
		texture_rect = value
		_rebuild()
## 可为生成美术提供准确追踪轮廓；不改变原有默认形状。
@export var solid_overrides: Array[PackedVector2Array] = []:
	set(value):
		solid_overrides = value
		_rebuild()
@export var pick_overrides: Array[PackedVector2Array] = []:
	set(value):
		pick_overrides = value
		_rebuild()

var _native_material: ShaderMaterial
var _extra_solids: Array[CollisionPolygon2D] = []

func _rebuild() -> void:
	if not is_node_ready():
		return
	var nominal := PaperStageForm.size_for(profile)
	var geometry_scale := dimensions / nominal
	var solids := PaperStageForm.solids(profile, variation) if solid_overrides.is_empty() else solid_overrides
	var foliage := PaperStageForm.foliage(profile, variation)
	var picks: Array[PackedVector2Array] = []
	picks.append_array(solids)
	picks.append_array(foliage)
	if profile == PaperStageForm.Profile.SEED_PLANT:
		picks.append(PackedVector2Array([Vector2(-26,0),Vector2(-23,-86),Vector2(-13,-89),Vector2(-10,-45),Vector2(21,-71),Vector2(22,-119),Vector2(31,-122),Vector2(30,-65),Vector2(-9,-30),Vector2(-10,0)]))
	if not pick_overrides.is_empty():
		picks = pick_overrides
	elif texture_override != null:
		picks = _texture_pick_polygons(nominal)
	for holder in [$VisualRoot/Area2D, $VisualRoot/Art]:
		for child in holder.get_children():
			holder.remove_child(child)
			child.queue_free()
	for line in _outline_lines:
		if is_instance_valid(line):
			line.queue_free()
	_outline_lines.clear()
	_collision_parts.clear()
	for extra in _extra_solids:
		if is_instance_valid(extra):
			remove_child(extra)
			extra.queue_free()
	_extra_solids.clear()
	var primary := $CollisionBox as CollisionPolygon2D
	primary.polygon = PackedVector2Array()
	primary.disabled = solids.is_empty()
	for index in range(solids.size()):
		var polygon := solids[index]
		var points := _scaled(polygon, geometry_scale)
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
	for polygon in picks:
		var points := _scaled(polygon,geometry_scale)
		var pick_shape := CollisionPolygon2D.new()
		pick_shape.polygon = points
		$VisualRoot/Area2D.add_child(pick_shape)
		var outline := Line2D.new()
		outline.points = points
		outline.closed = true
		outline.antialiased = true
		$VisualRoot.add_child(outline)
		_outline_lines.append(outline)
	_native_material = ShaderMaterial.new()
	_native_material.shader = preload("res://Art/PaperStage/Paper_Ink.gdshader")
	_native_material.set_shader_parameter("grain", preload("res://Art/Materials/Dry_Ink_AI.png"))
	_native_material.set_shader_parameter("grain_offset",Vector2(profile*0.173,variation*0.283))
	var art := $VisualRoot/Art as Node2D
	art.visible = texture_override == null
	for polygon in solids:
		_add_ink(polygon, Color("564351"), geometry_scale)
	var colors: Array[Color] = [Color("67505a"),Color("94707a"),Color("594553"),Color("ae8790")]
	for i in range(foliage.size()):
		_add_ink(foliage[i], colors[i%colors.size()], geometry_scale)
		var points := foliage[i]
		for j in range(2,points.size()-1,2):
			_add_stroke(PackedVector2Array([points[0].lerp(points[j],0.12),points[0].lerp(points[j],0.96)]),Color(0.90,0.84,0.71,0.28),0.7,geometry_scale)
	if profile == PaperStageForm.Profile.HERO_TREE:
		_add_stroke(PackedVector2Array([Vector2(31,-5),Vector2(27,-87),Vector2(-8,-179),Vector2(-61,-237)]), Color("92717a"),2.0,geometry_scale)
		_add_stroke(PackedVector2Array([Vector2(39,-20),Vector2(46,-83),Vector2(18,-161)]),Color(0.90,0.84,0.71,0.22),1.3,geometry_scale)
		_add_ink(PackedVector2Array([Vector2(-15,-103),Vector2(64,-145),Vector2(72,-135),Vector2(-12,-91)]), Color("aa8289"),geometry_scale)
	elif profile == PaperStageForm.Profile.BROKEN_ARCH:
		_add_stroke(PackedVector2Array([Vector2(-110,-292),Vector2(-66,-281),Vector2(-25,-278)]),Color("aa8289"),2.5,geometry_scale)
		_add_stroke(PackedVector2Array([Vector2(-131,-212),Vector2(-92,-204),Vector2(-75,-223)]),Color("ab9292"),1.4,geometry_scale)
		_add_stroke(PackedVector2Array([Vector2(-165,-108),Vector2(-150,-38),Vector2(-155,-12)]),Color("ad9493"),1.6,geometry_scale)
		_add_stroke(PackedVector2Array([Vector2(160,-131),Vector2(164,-62),Vector2(177,-24)]),Color("ab9292"),1.2,geometry_scale)
	elif profile == PaperStageForm.Profile.SEED_PLANT:
		_add_stroke(PackedVector2Array([Vector2(-18,0),Vector2(-19,-49),Vector2(-18,-86)]),Color("695364"),3.0,geometry_scale)
		_add_stroke(PackedVector2Array([Vector2(-18,-32),Vector2(26,-68),Vector2(27,-117)]),Color("695364"),2.0,geometry_scale)
	elif profile == PaperStageForm.Profile.SLANT_ROCK:
		_add_ink(PackedVector2Array([Vector2(-40,-95),Vector2(28,-95),Vector2(66,-76),Vector2(27,-74),Vector2(-15,-86)]),Color("927c82"),geometry_scale)
		_add_stroke(PackedVector2Array([Vector2(-27,-78),Vector2(-16,-39),Vector2(-29,-14)]),Color("b3a093"),1.1,geometry_scale)
	var sprite := $VisualRoot/Sprite2D as Sprite2D
	sprite.visible = texture_override != null
	sprite.texture = texture_override
	if texture_override != null:
		var rect := texture_rect if texture_rect.has_area() else Rect2(Vector2(-nominal.x*0.5,-nominal.y),nominal)
		sprite.position = (rect.position+rect.size*0.5)*geometry_scale
		sprite.scale = rect.size / texture_override.get_size() * geometry_scale
	_ink_material = ShaderMaterial.new()
	_ink_material.shader = preload("res://Art/Nature/Depth_Ink.gdshader")
	_ink_material.set_shader_parameter("texture_strength",0.0)
	sprite.material = _ink_material
	_depth_offset = -100
	if Engine.is_editor_hint():
		_apply_depth_style(0)
	else:
		_refresh_depth_style()
	_refresh_outline()

func apply_visual_transfer(anchor_position: Vector2) -> void:
	super.apply_visual_transfer(anchor_position)
	## Godot要求碰撞多边形直接挂在PhysicsBody下；额外轮廓同步实体尺度。
	for collision in _extra_solids:
		if is_instance_valid(collision) and collision.transform != collision_box.transform:
			collision.transform = collision_box.transform

func allows_non_solid_transfer() -> bool:
	return profile == PaperStageForm.Profile.SEED_PLANT and solid_overrides.is_empty()

func _texture_pick_polygons(nominal: Vector2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var image := texture_override.get_image()
	if image == null:
		return result
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image,0.15)
	var rect := texture_rect if texture_rect.has_area() else Rect2(Vector2(-nominal.x*0.5,-nominal.y),nominal)
	for points in bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO,image.get_size()),4.0):
		if points.size() < 3:
			continue
		var polygon := PackedVector2Array()
		for point in points:
			polygon.append(rect.position+point/Vector2(image.get_size())*rect.size)
		result.append(polygon)
	return result

func _apply_depth_style(offset: int) -> void:
	_depth_offset = offset
	var fog := clampf(0.86 + (offset-1)*0.06,0.0,0.96) if offset > 0 else 0.0
	if _ink_material != null:
		_ink_material.set_shader_parameter("depth_fog",fog)
	if _native_material != null:
		_native_material.set_shader_parameter("depth_fog",fog)
	_refresh_outline()

func _add_ink(points: PackedVector2Array, color: Color, scaling: Vector2) -> void:
	var polygon := Polygon2D.new()
	polygon.polygon = _scaled(points,scaling)
	polygon.color = color
	polygon.material = _native_material
	$VisualRoot/Art.add_child(polygon)

func _add_stroke(points: PackedVector2Array, color: Color, width: float, scaling: Vector2) -> void:
	var line := Line2D.new()
	line.points = _scaled(points,scaling)
	line.width = width * minf(scaling.x,scaling.y)
	line.default_color = color
	line.antialiased = true
	line.material = _native_material
	$VisualRoot/Art.add_child(line)
