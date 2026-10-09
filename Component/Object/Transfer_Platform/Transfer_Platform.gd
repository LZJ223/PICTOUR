@tool
class_name TransferPlatform
extends LayerObject

## 静态绘本片段：真实形状只由 CollisionBox 管理，PNG 外观跟随图层投影。
@export_enum("Auto", "Terrain", "Step", "Tree", "Box", "Bridge", "Door", "Boundary") var art_kind: int = 0:
	set(value):
		art_kind = value
		_update_geometry()
@export var show_caption: bool = false:
	set(value):
		show_caption = value
		_refresh_caption_visibility()
@export var show_layer_label: bool = true:
	set(value):
		show_layer_label = value
		_refresh_caption_visibility()
@export var dimensions: Vector2 = Vector2(160.0, 60.0):
	set(value):
		dimensions = Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		_update_geometry()
@export var color: Color = Color(0.62, 0.65, 0.69, 1.0):
	set(value):
		color = value
		_update_geometry()
@export var caption: String = "":
	set(value):
		caption = value
		_update_geometry()

var _styled_slot: int = -1
var _styled_player_slot: int = -1

const BACKGROUND_FOG := Color(0.3, 0.33, 0.37, 1.0)

func _ready() -> void:
	_update_geometry()
	if Engine.is_editor_hint():
		return
	super._ready()
	$VisualRoot/Area2D.input_pickable = can_transfer
	$VisualRoot/TransferMark.visible = false
	_refresh_depth_style()

## 图层外观只在槽位变化时更新；每帧投影不重新生成碰撞轮廓。
func apply_visual_transfer(anchor_position: Vector2) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(owner_layer):
		return
	super.apply_visual_transfer(anchor_position)
	_refresh_depth_style()

func _update_geometry() -> void:
	if not is_node_ready():
		return
	var half: Vector2 = dimensions * 0.5
	var points := PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	])
	var body_shape := RectangleShape2D.new()
	body_shape.size = dimensions
	$CollisionBox.shape = body_shape
	var pick_shape := RectangleShape2D.new()
	pick_shape.size = dimensions
	$VisualRoot/Area2D/CollisionShape2D.shape = pick_shape
	$VisualRoot/Polygon2D.polygon = points
	$VisualRoot/Polygon2D.color = color
	# 保留白模几何作为点选与投影的可检查基准，运行外观由 PNG 负责。
	$VisualRoot/Polygon2D.visible = false
	$VisualRoot/StorybookArt.configure(dimensions, _resolved_art_kind(), can_transfer)
	$VisualRoot/DepthOutline.points = points
	$VisualRoot/TopEdge.points = PackedVector2Array([
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
	])
	$VisualRoot/Selection.points = points
	$VisualRoot/TransferMark.points = PackedVector2Array([
		Vector2(-half.x + 3, -half.y + 3), Vector2(half.x - 3, -half.y + 3),
	])
	$VisualRoot/TransferMark.visible = false
	$VisualRoot/Caption.text = caption
	$VisualRoot/Caption.position = Vector2(-half.x, -half.y + 8)
	$VisualRoot/Caption.size = Vector2(dimensions.x, 26)
	$VisualRoot/Caption.visible = show_caption and not caption.is_empty()
	_styled_slot = -1
	_styled_player_slot = -1
	if Engine.is_editor_hint():
		_apply_depth_style(0, false)
	else:
		_refresh_depth_style()

func _refresh_depth_style() -> void:
	if not is_node_ready() or Engine.is_editor_hint() or not is_instance_valid(owner_layer):
		return
	if _styled_slot == owner_layer.slot and _styled_player_slot == Global.current_layer_index:
		return
	_styled_slot = owner_layer.slot
	_styled_player_slot = Global.current_layer_index
	_apply_depth_style(_styled_slot - _styled_player_slot, true)

func _apply_depth_style(depth_offset: int, show_layer: bool) -> void:
	var distant: bool = depth_offset > 0
	var fill: Color = color
	if distant:
		fill = color.lerp(BACKGROUND_FOG, minf(0.8, 0.6 + 0.1 * (depth_offset - 1)))
		fill.a = color.a
	$VisualRoot/Polygon2D.color = fill
	$VisualRoot/StorybookArt.set_depth_style(depth_offset)
	$VisualRoot/DepthOutline.width = 1.0 if distant else 2.0
	$VisualRoot/DepthOutline.default_color = Color("9fab99") if distant else Color("3d344a")
	$VisualRoot/TopEdge.width = 1.0 if distant else 2.5
	$VisualRoot/TopEdge.default_color = Color("becbb2") if distant else Color("b58b96")
	_update_caption(depth_offset, show_layer)

## 教学显示开关只刷新标签，不重建碰撞形状、点选代理或精灵。
func _refresh_caption_visibility() -> void:
	if not is_node_ready():
		return
	if Engine.is_editor_hint() or not is_instance_valid(owner_layer):
		_update_caption(0, false)
	else:
		_update_caption(owner_layer.slot - Global.current_layer_index, true)

func _update_caption(depth_offset: int, show_layer: bool) -> void:
	var label := $VisualRoot/Caption as Label
	label.text = caption
	label.visible = show_caption and not caption.is_empty()
	label.add_theme_font_size_override("font_size", 14 if can_transfer else 17)
	label.add_theme_color_override("font_color", Color("3d344a"))
	if can_transfer and show_layer:
		var layer_name: String = "背景" if depth_offset > 0 else ("前景" if depth_offset < 0 else "玩家层")
		label.text = caption + "\n" + layer_name if show_caption and not caption.is_empty() else layer_name
		label.visible = show_layer_label or (show_caption and not caption.is_empty())
		label.size = Vector2(dimensions.x, 44.0)
		var above_object: bool = dimensions.y < 48.0
		var label_y: float = -dimensions.y * 0.5 - 45.0 if above_object else clampf(-dimensions.y * 0.5 + 6.0, -90.0, -40.0)
		label.position = Vector2(-dimensions.x * 0.5, label_y)
		if depth_offset > 0:
			label.add_theme_color_override("font_color", Color("5f6d61"))

func _resolved_art_kind() -> int:
	if art_kind != 0:
		return art_kind
	var object_name := String(name).to_lower()
	if object_name.contains("tree"):
		return 3
	if object_name.contains("box"):
		return 4
	if object_name.contains("bridge"):
		return 5
	if object_name.contains("door"):
		return 6
	if object_name.contains("boundary"):
		return 7
	if object_name.contains("step") or object_name.contains("platform"):
		return 2
	return 1

func set_pick_condition(condition: bool = false) -> void:
	$VisualRoot/Selection.visible = condition and can_transfer

func set_transfer_preview(valid: bool) -> void:
	$VisualRoot/Selection.default_color = Color("d76a49") if valid else Color("ce3d46")
