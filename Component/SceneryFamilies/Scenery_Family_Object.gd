@tool
class_name SceneryFamilyObject
extends PaperStageObject

@export var piece: SceneryFamilyPiece:
	set(value):
		piece = value
		if piece != null:
			dimensions = piece.display_size
		_rebuild()
@export var mirror_x: bool = false:
	set(value):
		mirror_x = value
		_rebuild()

var _configuring_piece := false

func _rebuild() -> void:
	if not is_node_ready() or _configuring_piece or piece == null:
		return
	_configuring_piece = true
	## 使用统一名义矩形接入旧组件，尺寸仍由继承的 dimensions 控制。
	profile = PaperStageForm.Profile.SLANT_ROCK
	kind = NaturalForm.Kind.ROCK
	display_name = piece.display_name
	texture_override = piece.atlas_texture()
	var nominal := PaperStageForm.size_for(profile)
	texture_rect = Rect2(Vector2(-nominal.x*0.5,-nominal.y),nominal)
	solid_overrides = piece.local_polygons(nominal,mirror_x)
	pick_overrides = piece.local_pick_polygons(nominal,mirror_x)
	_configuring_piece = false
	super._rebuild()
	$VisualRoot/Sprite2D.flip_h = mirror_x

func _texture_pick_polygons(nominal: Vector2) -> Array[PackedVector2Array]:
	var result := super._texture_pick_polygons(nominal)
	if mirror_x:
		for i in range(result.size()):
			var reflected := PackedVector2Array()
			for point in result[i]:
				reflected.append(Vector2(-point.x,point.y))
			reflected.reverse()
			result[i] = reflected
	return result

func get_footholds() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if piece == null:
		return result
	for edge in piece.footholds:
		var local_edge := PackedVector2Array()
		for point in edge:
			local_edge.append(piece.local_point(point,dimensions,mirror_x))
		result.append(local_edge)
	return result
