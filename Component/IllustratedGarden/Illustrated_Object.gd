@tool
class_name IllustratedGardenObject
extends VerticalGardenObject
## 同一母素材可用不同裁框、轮廓和镜像派生；实体与点选始终一致。
@export var piece: IllustratedGardenPiece:
	set(value):
		if piece != null and piece.changed.is_connected(_piece_changed): piece.changed.disconnect(_piece_changed)
		piece = value
		if piece != null: piece.changed.connect(_piece_changed)
		_rebuild()
@export var mirror_x := false:
	set(value):
		mirror_x = value
		_rebuild()
@export_range(0.1, 4.0, 0.01) var size_multiplier := 1.0:
	set(value):
		size_multiplier = value
		_rebuild()
@export var variant_tint := Color.WHITE:
	set(value):
		variant_tint = value
		_rebuild()

func _piece_changed() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_node_ready() or piece == null: return
	display_name = piece.display_name
	solid_polygons = piece.local_polygons(size_multiplier,mirror_x)
	painting = piece.painting
	var region := piece.source_region
	if region.size == Vector2.ZERO and painting != null:
		region = Rect2(Vector2.ZERO,painting.get_size())
	if painting != null and region.size != painting.get_size():
		var atlas := AtlasTexture.new()
		atlas.atlas = painting
		atlas.region = region
		painting = atlas
	painting_rect = Rect2((region.position-piece.source_pivot)*piece.unit_scale*size_multiplier,region.size*piece.unit_scale*size_multiplier)
	if mirror_x: painting_rect.position.x = -painting_rect.end.x
	super._rebuild()
	$VisualRoot/Sprite2D.flip_h = mirror_x
	$VisualRoot/Sprite2D.modulate = variant_tint
	if not piece.visual_masks.is_empty():
		$VisualRoot/Sprite2D.visible = false
		$VisualRoot/Art.visible = true
		for child in $VisualRoot/Art.get_children():
			$VisualRoot/Art.remove_child(child)
			child.queue_free()
		for mask in piece.visual_masks:
			var points := PackedVector2Array()
			var uv := PackedVector2Array()
			for source_point in mask:
				var point := (source_point-piece.source_pivot)*piece.unit_scale*size_multiplier
				if mirror_x: point.x = -point.x
				points.append(point)
				uv.append(source_point)
			if mirror_x:
				points.reverse()
				uv.reverse()
			var patch := Polygon2D.new()
			patch.polygon = points
			patch.uv = uv
			patch.texture = piece.painting
			patch.material = _ink_material
			patch.modulate = variant_tint
			patch.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			$VisualRoot/Art.add_child(patch)
	if solid_polygons.is_empty():
		for points in piece.local_polygons(size_multiplier,mirror_x,true):
			var pick := CollisionPolygon2D.new()
			pick.polygon = points
			$VisualRoot/Area2D.add_child(pick)
			var line := Line2D.new()
			line.points = points
			line.closed = true
			line.antialiased = true
			$VisualRoot.add_child(line)
			_outline_lines.append(line)
		_refresh_outline()

func get_editor_geometry() -> Dictionary:
	var walkable: Array[PackedVector2Array] = []
	if piece != null:
		for line in piece.source_walkable:
			var points := PackedVector2Array()
			for point in line:
				var local := (point-piece.source_pivot)*piece.unit_scale*size_multiplier
				if mirror_x: local.x = -local.x
				points.append(local)
			walkable.append(points)
	return {"solids":piece.local_polygons(size_multiplier,mirror_x) if piece != null else [],"walkable":walkable}
