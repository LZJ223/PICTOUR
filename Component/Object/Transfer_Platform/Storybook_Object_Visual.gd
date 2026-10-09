@tool
extends Node2D

## PNG 九宫平铺只作用于外观：单位纹理不随巨大平台一起拉伸。
## 纹理为 2 倍密度，控件在局部缩小一半，使刻线在实际游戏尺度保持一致。
const BODY_TEXTURES := {
	1: preload("res://Art/Environment/PNG/Terrain.png"),
	2: preload("res://Art/Environment/PNG/Fold_Step.png"),
	3: preload("res://Art/Environment/PNG/Paper_Tree.png"),
	4: preload("res://Art/Environment/PNG/Paint_Box.png"),
	5: preload("res://Art/Environment/PNG/Page_Bridge.png"),
	6: preload("res://Art/Environment/PNG/Tall_Door.png"),
	7: preload("res://Art/Environment/PNG/Terrain.png"),
}
const TAG_TEXTURE := preload("res://Art/Environment/PNG/Transfer_Tag.png")
const INK_SHADER := preload("res://Art/Environment/Layer_Ink.gdshader")

var _body: NinePatchRect
var _tag: Sprite2D
var _ink_material: ShaderMaterial
var _configured_kind: int = -1
var _is_boundary: bool = false

func configure(dimensions: Vector2, art_kind: int, can_transfer: bool) -> void:
	_ensure_nodes()
	_is_boundary = art_kind == 7
	_body.position = -dimensions * 0.5
	_body.size = dimensions * 2.0
	_body.scale = Vector2(0.5, 0.5)
	if _configured_kind != art_kind:
		_configured_kind = art_kind
		_body.texture = BODY_TEXTURES.get(art_kind, BODY_TEXTURES[1])
		var margins: Vector4 = Vector4(16, 16, 16, 16)
		if art_kind == 2:
			margins = Vector4(28, 28, 28, 26)
		elif art_kind == 3:
			margins = Vector4(24, 320, 24, 140)
		elif art_kind == 4:
			margins = Vector4(26, 38, 26, 28)
		elif art_kind == 5:
			margins = Vector4(22, 12, 22, 12)
		elif art_kind == 6:
			margins = Vector4(20, 160, 20, 190)
		_body.patch_margin_left = int(margins.x)
		_body.patch_margin_top = int(margins.y)
		_body.patch_margin_right = int(margins.z)
		_body.patch_margin_bottom = int(margins.w)
		_body.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
		_body.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	_tag.visible = can_transfer
	var physical_size: Vector2 = TAG_TEXTURE.get_size() * 0.5
	var tag_scale: float = clampf(minf((dimensions.x - 8.0) / physical_size.x, (dimensions.y - 8.0) / physical_size.y), 0.02, 1.0)
	_tag.scale = Vector2.ONE * (0.5 * tag_scale)
	var tag_y: float = maxf(-dimensions.y * 0.5 + physical_size.y * tag_scale * 0.5 + 4.0, -160.0)
	tag_y = minf(tag_y, dimensions.y * 0.5 - physical_size.y * tag_scale * 0.5 - 4.0)
	_tag.position = Vector2(dimensions.x * 0.5 - physical_size.x * tag_scale * 0.5 - 4.0, tag_y)

func set_depth_style(depth_offset: int) -> void:
	_ensure_nodes()
	var fog_strength: float = minf(0.88, 0.77 + 0.05 * (depth_offset - 1)) if depth_offset > 0 else 0.0
	_ink_material.set_shader_parameter("fog_strength", fog_strength)
	# 边界柱退入画面边缘，但保留完整实体矩形，不添加隐形扩大碰撞。
	_body.self_modulate = Color(0.83, 0.83, 0.83, 1.0) if _is_boundary else Color.WHITE
	_tag.self_modulate = Color(1.0, 0.91, 0.83, 1.0) if depth_offset > 0 else Color.WHITE

func _ensure_nodes() -> void:
	if is_instance_valid(_body):
		return
	_ink_material = ShaderMaterial.new()
	_ink_material.shader = INK_SHADER
	_body = NinePatchRect.new()
	_body.name = "BodySprite"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_body.material = _ink_material
	add_child(_body)
	_tag = Sprite2D.new()
	_tag.name = "TransferTag"
	_tag.texture = TAG_TEXTURE
	_tag.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_tag)
