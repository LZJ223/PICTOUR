@tool
class_name DerivedCropObject
extends SceneryFamilyObject

var _building_crop := false

func _rebuild() -> void:
	if not is_node_ready() or _building_crop or not piece is DerivedCropPiece:
		return
	_building_crop = true
	super._rebuild()
	var crop := piece as DerivedCropPiece
	## 继承类为旧十二种实体保留了石块回退；薄冠必须显式去掉该回退。
	if crop.non_solid:
		_collision_parts.clear()
		$CollisionBox.polygon = PackedVector2Array()
		$CollisionBox.disabled = true
	$VisualRoot/Sprite2D.visible = false
	var art := $VisualRoot/Art as Node2D
	for child in art.get_children():
		art.remove_child(child)
		child.queue_free()
	if crop.visual_masks.is_empty():
		## 完整透明植物直接使用 AtlasTexture；无需额外掩片或栅格改写。
		$VisualRoot/Sprite2D.visible = true
		art.visible = false
		_building_crop = false
		return
	art.visible = true
	for mask in crop.visual_masks:
		var points := PackedVector2Array()
		var uv := PackedVector2Array()
		for point in mask:
			points.append(crop.local_point(point,dimensions,mirror_x))
			## Polygon2D 使用父图像素 UV；AtlasTexture 仍记录并用于裁框/选取来源。
			uv.append(crop.region.position+point*crop.region.size)
		if mirror_x:
			points.reverse()
			uv.reverse()
		var polygon := Polygon2D.new()
		polygon.polygon = points
		polygon.uv = uv
		polygon.texture = crop.parent_texture
		polygon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		polygon.material = _ink_material
		art.add_child(polygon)
	_building_crop = false

func allows_non_solid_transfer() -> bool:
	return piece is DerivedCropPiece and (piece as DerivedCropPiece).non_solid

func get_attachment_offset() -> Vector2:
	if not piece is DerivedCropPiece:
		return Vector2.ZERO
	return piece.local_point((piece as DerivedCropPiece).attachment_point,dimensions,mirror_x)
