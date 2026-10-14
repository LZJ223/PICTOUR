## 此脚本为物件抽象类，所有物件都继承于此，其中实现了物件的图层转换系统、画面更新，其余有关交互的视觉更新在子类中实现
## 其中，所有物件都是PhysicsBody2D，根目录下必须是CollisionBox节点和VisualRoot节点，负责物体实际大小的管理
## CollisionBox节点负责物体实际大小的管理，VisualRoot节点中包含贴图和点击判定的Area，负责视觉上的变换，碰撞箱位置不改变
## 注意以上两个节点的位移和旋转的初始状态必须保持为0，在关卡中的移动依靠根节点，缩放依靠CollisionBox，旋转暂不支持

@abstract
class_name LayerObject
extends PhysicsBody2D

enum TransferMotion { OUTWARD, INWARD }

## 物体信息
@export var can_transfer: bool = true
@export var can_leave_shadow: bool = false
@export var can_be_shadowed: bool = false

@export_group("图层切换动效")
## 向外切换时，物体短暂放大的倍率。
@export_range(1.0, 2.0, 0.01) var outward_peak_scale: float = 1.15
## 向内切换时，物体短暂缩小的倍率。
@export_range(0.1, 1.0, 0.01) var inward_min_scale: float = 0.86
## 向内/向外拉拽的第一阶段时长。
@export_range(0.01, 0.5, 0.01) var transfer_impulse_duration: float = 0.07
## 物体恢复到正常画面大小的时长。
@export_range(0.01, 0.5, 0.01) var transfer_settle_duration: float = 0.10
## 换层失败时的最大水平抖动幅度，单位接近屏幕像素。
@export_range(0.0, 32.0, 0.5) var blocked_shake_amplitude: float = 7.0
## 换层失败时的总抖动时长。
@export_range(0.01, 0.5, 0.01) var blocked_shake_duration: float = 0.20

## 子节点信息
@onready var collision_box: CollisionPolygon2D = $CollisionBox
@onready var visual_root: Node2D = $VisualRoot
var owner_layer: DepthLayer
## 影子信息
var shadow_box: Array[Polygon2D] = []
var shadow_visual: Array[Polygon2D] = []
var shadow_active: Array[bool] = []
const _EAGLE_SHADER := preload("res://Shader/Eagle_Eye_Grayscale.gdshader")
const _SELECTION_OUTLINE_SHADER := preload("res://Shader/Selection_Outline.gdshader")
static var _eagle_gray_material: ShaderMaterial
var _selected: bool = false
var _selection_outlines: Array[Dictionary] = []
## 图层切换动效只修饰画面，不修改物体根节点或碰撞箱。
var _transfer_visual_scale: float = 1.0
var _transfer_visual_offset: Vector2 = Vector2.ZERO
var _transfer_visual_tween: Tween

## 初始化
func _ready() -> void:
	add_to_group("layer_objects")
	owner_layer = find_owner_layer()
	assert(owner_layer != null, "%s 必须位于 DepthLayer/Objects 下！" % name)
	_setup_selection_outlines()
	update_layer_slot()

## 图层切换
func transfer_to(target_layer: DepthLayer, target_transform: Transform2D, target_collision_transform: Transform2D) -> void:
	## 可行性检测
	if not can_transfer:
		return
	## 改变属性
	reparent(target_layer, false)
	global_transform = target_transform
	collision_box.transform = target_collision_transform
	owner_layer = target_layer
	update_layer_slot()

## 更新屏幕位置
func apply_visual_transfer(anchor_position: Vector2) -> void:
	var scaling: float = Global.layer_scales[owner_layer.slot]
	var camera_zoom := Vector2.ONE
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		camera_zoom = camera.zoom.abs()
	var visual_offset := Vector2(
		_transfer_visual_offset.x / maxf(camera_zoom.x, 0.0001),
		_transfer_visual_offset.y / maxf(camera_zoom.y, 0.0001)
	)
	visual_root.scale = collision_box.scale * scaling * _transfer_visual_scale
	visual_root.position = (anchor_position - position) * (1 - scaling) + visual_offset
	if _selected:
		_sync_selection_outlines()

## 播放一次成功换层反馈。真实换层已完成，本动画只在新的基础画面上叠加缩放。
func play_transfer_success(motion: int) -> void:
	_prepare_transfer_visual_tween()
	var impulse_scale: float = (
		outward_peak_scale
		if motion == TransferMotion.OUTWARD
		else inward_min_scale
	)
	_transfer_visual_tween.tween_property(
		self, "_transfer_visual_scale", impulse_scale, transfer_impulse_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT if motion == TransferMotion.OUTWARD else Tween.EASE_IN
	)
	_transfer_visual_tween.tween_property(
		self, "_transfer_visual_scale", 1.0, transfer_settle_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_transfer_visual_tween.finished.connect(_on_transfer_visual_finished)

## 播放一次换层受阻反馈。偏移按屏幕像素解释，不会改变物理位置。
func play_transfer_blocked() -> void:
	_prepare_transfer_visual_tween()
	if blocked_shake_amplitude <= 0.0:
		_on_transfer_visual_finished()
		return
	var step_duration: float = blocked_shake_duration / 5.0
	var offsets: Array[float] = [
		blocked_shake_amplitude,
		-blocked_shake_amplitude * 0.8,
		blocked_shake_amplitude * 0.55,
		-blocked_shake_amplitude * 0.3,
		0.0,
	]
	for offset in offsets:
		_transfer_visual_tween.tween_property(
			self,
			"_transfer_visual_offset",
			Vector2(offset, 0.0),
			step_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_transfer_visual_tween.finished.connect(_on_transfer_visual_finished)

## 新反馈会安全中断旧反馈，避免快速连续操作导致倍率与偏移累积。
func _prepare_transfer_visual_tween() -> void:
	if _transfer_visual_tween != null and _transfer_visual_tween.is_valid():
		_transfer_visual_tween.kill()
	_reset_transfer_visual_state()
	_transfer_visual_tween = create_tween()
	_transfer_visual_tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)

func _on_transfer_visual_finished() -> void:
	_reset_transfer_visual_state()
	_transfer_visual_tween = null

func _reset_transfer_visual_state() -> void:
	_transfer_visual_scale = 1.0
	_transfer_visual_offset = Vector2.ZERO

## 更新物体所属图层状态
func update_layer_slot() -> void:
	collision_layer = 0
	collision_mask = 0
	self.set_collision_layer_value(owner_layer.layer_id + 1, true)
	self.set_collision_mask_value(owner_layer.layer_id + 1, true)
	refresh_eagle_eye()
	if _selected:
		_sync_selection_outlines()

## 鹰眼打开时，不在玩家当前碰撞层的画面变成灰。原来的颜色会保留。
func refresh_eagle_eye() -> void:
	if visual_root == null:
		return
	var gray := Global.eagle_eye and not _is_player_layer()
	_set_eagle_gray(visual_root, gray)
	for node in shadow_box:
		_set_eagle_gray(node, gray)
	for node in shadow_visual:
		_set_eagle_gray(node, gray)
	var shadow_template := get_node_or_null("Shadow") as CanvasItem
	if shadow_template != null:
		_set_eagle_gray(shadow_template, gray)

func _is_player_layer() -> bool:
	if Global.player == null or owner_layer == null:
		return true
	return owner_layer.layer_id == Global.player.collision_group - 1

func _set_eagle_gray(node: Node, gray: bool) -> void:
	## 选择描边拥有独立材质，不能被鹰眼材质覆盖。
	if node.has_meta(&"selection_outline_visual"):
		return
	if node is Polygon2D or node is Sprite2D:
		_apply_gray_material(node as CanvasItem, gray)
	for child in node.get_children():
		_set_eagle_gray(child, gray)

func _apply_gray_material(item: CanvasItem, gray: bool) -> void:
	var gray_material := _shared_eagle_material()
	if gray:
		if item.material == gray_material:
			return
		item.set_meta(&"eagle_eye_previous_material", item.material)
		item.material = gray_material
		return
	if item.material != gray_material:
		return
	var previous: Material = item.get_meta(&"eagle_eye_previous_material")
	item.material = previous
	item.remove_meta(&"eagle_eye_previous_material")

static func _shared_eagle_material() -> ShaderMaterial:
	if _eagle_gray_material == null:
		_eagle_gray_material = ShaderMaterial.new()
		_eagle_gray_material.shader = _EAGLE_SHADER
	return _eagle_gray_material

## 寻找母图层
func find_owner_layer() -> DepthLayer:
	var current := get_parent()
	while current != null:
		if current is DepthLayer:
			return current as DepthLayer
		current = current.get_parent()
	return null

## 更新选取状态。所有物体统一由独立描边副本响应，不再要求子类实现。
func set_pick_condition(condition: bool = false) -> void:
	_selected = condition
	_sync_selection_outlines(condition)


## 为 VisualRoot 下的 Polygon2D 与 Sprite2D 建立独立描边副本。
## 副本使用绝对 Z 值绘制在所属 CanvasGroup 前一层，因此不会被整层滤镜模糊或染色。
func _setup_selection_outlines() -> void:
	if visual_root == null:
		return
	var sources: Array[Node2D] = []
	_collect_outline_sources(visual_root, sources)
	for source in sources:
		var outline := _create_outline_visual(source)
		if outline == null:
			continue
		var outline_material := ShaderMaterial.new()
		outline_material.shader = _SELECTION_OUTLINE_SHADER
		outline.material = outline_material
		outline.set_meta(&"selection_outline_visual", true)
		source.get_parent().add_child(outline)
		_selection_outlines.append({
			"source": source,
			"outline": outline,
			"material": outline_material,
		})
	_sync_selection_outlines(true)


func _collect_outline_sources(node: Node, sources: Array[Node2D]) -> void:
	for child in node.get_children():
		if child is Polygon2D or child is Sprite2D:
			sources.append(child as Node2D)
		_collect_outline_sources(child, sources)


func _create_outline_visual(source: Node2D) -> Node2D:
	var outline: Node2D
	if source is Polygon2D:
		var source_polygon := source as Polygon2D
		var polygon := Polygon2D.new()
		polygon.polygon = source_polygon.polygon
		polygon.uv = source_polygon.uv
		polygon.texture = source_polygon.texture
		polygon.texture_offset = source_polygon.texture_offset
		polygon.texture_rotation = source_polygon.texture_rotation
		polygon.texture_scale = source_polygon.texture_scale
		polygon.invert_enabled = source_polygon.invert_enabled
		polygon.invert_border = source_polygon.invert_border
		outline = polygon
	elif source is Sprite2D:
		var source_sprite := source as Sprite2D
		var sprite := Sprite2D.new()
		sprite.texture = source_sprite.texture
		sprite.centered = source_sprite.centered
		sprite.offset = source_sprite.offset
		sprite.flip_h = source_sprite.flip_h
		sprite.flip_v = source_sprite.flip_v
		sprite.hframes = source_sprite.hframes
		sprite.vframes = source_sprite.vframes
		sprite.frame = source_sprite.frame
		sprite.region_enabled = source_sprite.region_enabled
		sprite.region_rect = source_sprite.region_rect
		sprite.region_filter_clip_enabled = source_sprite.region_filter_clip_enabled
		outline = sprite
	else:
		return null
	outline.name = "%s_SelectionOutline" % source.name
	outline.show_behind_parent = true
	outline.z_as_relative = false
	outline.visible = false
	return outline


## 同步源节点的形状、变换与图层。缩放补偿会把描边宽度固定为屏幕像素。
func _sync_selection_outlines(sync_geometry: bool = false) -> void:
	if owner_layer == null:
		return
	var camera_zoom := Vector2.ONE
	var camera := get_viewport().get_camera_2d()
	if camera != null:
		camera_zoom = camera.zoom.abs()
	for entry in _selection_outlines:
		var source := entry.source as Node2D
		var outline := entry.outline as Node2D
		var outline_material := entry.material as ShaderMaterial
		if not is_instance_valid(source) or not is_instance_valid(outline):
			continue
		outline.transform = source.transform
		outline.z_index = (Global.layer_count - owner_layer.slot) * 100 - 1
		outline.visible = _selected and source.visible
		outline_material.set_shader_parameter("selected", _selected)
		## Sprite2D 可能正在逐帧动画；仅选中的精灵需要持续同步帧与 UV。
		if sync_geometry or source is Sprite2D:
			_sync_outline_geometry(source, outline, outline_material)
		var screen_scale := source.global_transform.get_scale().abs() * camera_zoom
		outline_material.set_shader_parameter(
			"outline_scale_compensation",
			Vector2(
				1.0 / maxf(screen_scale.x, 0.0001),
				1.0 / maxf(screen_scale.y, 0.0001)
			)
		)


func _sync_outline_geometry(
	source: Node2D,
	outline: Node2D,
	outline_material: ShaderMaterial
) -> void:
	if source is Polygon2D and outline is Polygon2D:
		var source_polygon := source as Polygon2D
		var outline_polygon := outline as Polygon2D
		outline_polygon.polygon = source_polygon.polygon
		outline_polygon.uv = source_polygon.uv
		outline_polygon.texture = source_polygon.texture
		outline_material.set_shader_parameter("use_texture_alpha", false)
		outline_material.set_shader_parameter("rectangular_geometry", false)
		outline_material.set_shader_parameter(
			"visual_center", _polygon_bounds(source_polygon.polygon).get_center()
		)
	elif source is Sprite2D and outline is Sprite2D:
		var source_sprite := source as Sprite2D
		var outline_sprite := outline as Sprite2D
		outline_sprite.texture = source_sprite.texture
		outline_sprite.frame = source_sprite.frame
		outline_sprite.region_rect = source_sprite.region_rect
		outline_material.set_shader_parameter("source_texture", source_sprite.texture)
		var texture_size := Vector2(source_sprite.texture.get_size()) if source_sprite.texture else Vector2.ONE
		outline_material.set_shader_parameter(
			"source_texture_pixel_size",
			Vector2(1.0 / texture_size.x, 1.0 / texture_size.y)
		)
		outline_material.set_shader_parameter(
			"use_texture_alpha", source_sprite.texture != null
		)
		outline_material.set_shader_parameter("rectangular_geometry", true)
		outline_material.set_shader_parameter(
			"visual_center", source_sprite.get_rect().get_center()
		)
		outline_material.set_shader_parameter(
			"source_uv_rect", _sprite_uv_rect(source_sprite)
		)


func _sprite_uv_rect(sprite: Sprite2D) -> Vector4:
	if sprite.texture == null:
		return Vector4(0.0, 0.0, 1.0, 1.0)
	var texture_size := Vector2(sprite.texture.get_size())
	if sprite.region_enabled:
		return Vector4(
			sprite.region_rect.position.x / texture_size.x,
			sprite.region_rect.position.y / texture_size.y,
			sprite.region_rect.size.x / texture_size.x,
			sprite.region_rect.size.y / texture_size.y
		)
	var frame_size := Vector2(1.0 / sprite.hframes, 1.0 / sprite.vframes)
	var frame_x := sprite.frame % sprite.hframes
	var frame_y := sprite.frame / sprite.hframes
	return Vector4(
		frame_x * frame_size.x,
		frame_y * frame_size.y,
		frame_size.x,
		frame_size.y
	)


func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds

## 触发器的机关动作会调用这里。各物体自己决定被叫到之后做什么。
func activate() -> void:
	pass
