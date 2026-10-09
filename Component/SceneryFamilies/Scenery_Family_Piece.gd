@tool
class_name SceneryFamilyPiece
extends Resource

## 父图保持完整；子素材只保存裁切区域和玩法轮廓，不另存重复图片。
@export var piece_id: StringName
@export var display_name: String
@export var family: StringName
@export_multiline var silhouette_note: String
@export_multiline var affordance_note: String
@export var parent_texture: Texture2D
@export var region: Rect2
@export var display_size: Vector2 = Vector2(240, 240)
## 归一化到裁切矩形的实体。树冠、纤细枝叶及纸纹缺墨不直接转成实体。
@export var solids: Array[PackedVector2Array] = []
## 含封闭窗洞的素材使用分片点选轮廓，避免 alpha 外轮廓把空洞填满。
@export var picks: Array[PackedVector2Array] = []
## 调试用的真实可踩轮廓段，每项两个端点；不是额外碰撞或贴上去的台阶。
@export var footholds: Array[PackedVector2Array] = []
## 拱洞等必须可穿过的空白点，供组件验证使用。
@export var empty_points: PackedVector2Array = PackedVector2Array()

func atlas_texture() -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = parent_texture
	atlas.region = region
	atlas.filter_clip = true
	return atlas

func local_point(point: Vector2, size: Vector2, mirrored: bool = false) -> Vector2:
	return Vector2((1.0-point.x if mirrored else point.x)-0.5, point.y-1.0)*size

func local_polygons(size: Vector2, mirrored: bool = false) -> Array[PackedVector2Array]:
	return _convert_polygons(solids,size,mirrored)

func local_pick_polygons(size: Vector2, mirrored: bool = false) -> Array[PackedVector2Array]:
	return _convert_polygons(picks,size,mirrored)

func _convert_polygons(polygons: Array[PackedVector2Array], size: Vector2, mirrored: bool) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for polygon in polygons:
		var converted := PackedVector2Array()
		for point in polygon:
			converted.append(local_point(point,size,mirrored))
		if mirrored:
			converted.reverse()
		result.append(converted)
	return result
