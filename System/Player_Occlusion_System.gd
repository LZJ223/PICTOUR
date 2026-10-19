## 仅在实际遮挡处补绘蓝色剪影，不改变角色、碰撞或原有图层材质。
extends Node

const OCCLUSION_SHADER := preload("res://Shader/Player_Occlusion.gdshader")
## 独立于承影覆盖的位 9～12；只标记实体视觉及其祖先。
const PLAYER_BIT: int = 1 << 12
const BODY_BIT: int = 1 << 13
const SAME_LAYER_BIT: int = 1 << 14
const MASK_BITS: int = PLAYER_BIT | BODY_BIT | SAME_LAYER_BIT

@export var enabled: bool = true
@export var xray_color := Color(0.48, 0.56, 0.64, 0.6)

var _player: PlayerController
var _captures: Dictionary[StringName, SubViewport] = {}
var _marked: Dictionary[int, CanvasItem] = {}
var _overlay: Node2D
var _quad: ColorRect
var _material: ShaderMaterial

func _ready() -> void:
	get_parent().ready.connect(_initialize, CONNECT_ONE_SHOT)

func _initialize() -> void:
	_player = Global.player
	assert(is_instance_valid(_player), "人物透视需要先初始化 Player")
	_mark_visual(_player.player_animation, PLAYER_BIT)
	_overlay = Node2D.new()
	_overlay.name = "PlayerOcclusionOverlay"
	_overlay.top_level = true
	_overlay.z_as_relative = false
	# 留在世界画布中，位于前景上方，但始终低于对话、暂停和转场的 CanvasLayer。
	_overlay.z_index = 4095
	add_child(_overlay)
	_material = ShaderMaterial.new()
	_material.shader = OCCLUSION_SHADER
	_quad = ColorRect.new()
	_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quad.material = _material
	_overlay.add_child(_quad)
	for pass_name: StringName in [&"player_mask", &"player_front", &"body_mask", &"body_front", &"body_same_layer"]:
		var capture := SubViewport.new()
		capture.name = String(pass_name).to_pascal_case()
		capture.world_2d = get_viewport().find_world_2d()
		capture.disable_3d = true
		capture.transparent_bg = true
		capture.gui_disable_input = true
		capture.canvas_cull_mask = 0
		capture.size = Vector2i.ONE
		capture.msaa_2d = get_viewport().msaa_2d
		capture.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		capture.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(capture)
		_captures[pass_name] = capture
		_material.set_shader_parameter(pass_name, capture.get_texture())
	RenderingServer.frame_pre_draw.connect(_sync_frame)
	_sync_frame()

## 所有视差、相机与 Tween 推进之后，离屏捕获和合成使用同一帧的状态。
func _sync_frame() -> void:
	_clear_marks(BODY_BIT | SAME_LAYER_BIT)
	if not enabled or not is_instance_valid(_player) or not is_instance_valid(Global.level):
		_disable_captures()
		return
	var canvas := get_viewport().get_canvas_transform()
	var size := Vector2i(get_viewport().get_visible_rect().size.ceil())
	var screen := Rect2(Vector2.ZERO, Vector2(size))
	var player_visible := _intersects_screen(_player.player_animation, canvas, screen)
	var player_front := _front_layers(_player) if player_visible else 0
	var body := _player.player_body
	var body_visible := is_instance_valid(body) and not body.is_queued_for_deletion()
	if body_visible:
		body_visible = is_instance_valid(body.owner_layer) and _intersects_screen(body.visual_root, canvas, screen)
	var body_front: int = 0
	var same_layer: int = 0
	var body_in_front: bool = false
	var body_opacity: float = 1.0
	if body_visible:
		_mark_visual(body.visual_root, BODY_BIT)
		body_front = _front_layers(body)
		body_in_front = _draws_after(body, _player)
		if player_visible and not body_in_front:
			body_front |= PLAYER_BIT
		body_opacity = body.owner_layer.cycle_opacity
		# CanvasGroup 内按实际兄弟顺序筛选；不把身体自身或整层当作同层遮挡物。
		for child in body.owner_layer.get_children():
			if child is LayerObject and child != body and not child.is_queued_for_deletion():
				if child.is_visible_in_tree() and _draws_after(child, body):
					_mark_visual(child.visual_root, SAME_LAYER_BIT)
					same_layer = SAME_LAYER_BIT
	var player_active := player_visible and player_front != 0
	var body_active := body_visible and body_opacity > 0.0001 and (body_front != 0 or same_layer != 0)
	_overlay.visible = player_active or body_active
	if not _overlay.visible:
		_disable_captures()
		return
	_overlay.global_transform = canvas.affine_inverse()
	_quad.size = Vector2(size)
	_material.set_shader_parameter("xray_color", xray_color)
	_material.set_shader_parameter("player_active", player_active)
	_material.set_shader_parameter("body_active", body_active)
	_material.set_shader_parameter("body_in_front", body_in_front)
	_material.set_shader_parameter("body_opacity", body_opacity)
	_material.set_shader_parameter("has_same_layer", same_layer != 0)
	# 即便某个目标没有遮挡，也保留其轮廓，避免后方剪影覆盖前方可见的角色。
	_update_capture(&"player_mask", PLAYER_BIT if player_visible else 0, size, canvas)
	_update_capture(&"player_front", player_front if player_active else 0, size, canvas)
	_update_capture(&"body_mask", BODY_BIT if body_visible else 0, size, canvas)
	_update_capture(&"body_front", body_front if body_active else 0, size, canvas)
	_update_capture(&"body_same_layer", same_layer if body_active else 0, size, canvas)
	_material.set_shader_parameter("has_player", player_visible)
	_material.set_shader_parameter("has_body", body_visible)
	_material.set_shader_parameter("has_body_front", body_active and body_front != 0)

func _front_layers(target: CanvasItem) -> int:
	var mask: int = 0
	for layer in Global.layers:
		if layer.is_visible_in_tree() and layer.cycle_opacity > 0.0001 and _draws_after(layer, target):
			mask |= LayerObject.receiver_mask_bit(layer.layer_id)
	return mask

## 同 Z 使用场景树顺序；身体自身的相对 Z 为零，必须累计所属图层的 Z。
func _draws_after(front: CanvasItem, back: CanvasItem) -> bool:
	var front_z := _effective_z(front)
	var back_z := _effective_z(back)
	return front_z > back_z or (front_z == back_z and front.is_greater_than(back))

func _effective_z(item: CanvasItem) -> int:
	var result: int = item.z_index
	while item.z_as_relative:
		item = item.get_parent() as CanvasItem
		if item == null:
			break
		result += item.z_index
	return clampi(result, -4096, 4096)

func _update_capture(pass_name: StringName, mask: int, size: Vector2i, canvas: Transform2D) -> void:
	var capture: SubViewport = _captures[pass_name]
	capture.canvas_cull_mask = mask
	if mask == 0:
		capture.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	capture.size = size
	capture.canvas_transform = canvas
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _disable_captures() -> void:
	_overlay.hide()
	for parameter: StringName in [&"player_active", &"body_active", &"has_player", &"has_body"]:
		_material.set_shader_parameter(parameter, false)
	for capture: SubViewport in _captures.values():
		capture.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _intersects_screen(node: Node, canvas: Transform2D, screen: Rect2) -> bool:
	if node.get_meta(&"selection_outline_visual", false):
		return false
	if node is CanvasItem and not node.is_visible_in_tree():
		return false
	if node is Sprite2D and node.texture != null:
		var bounds: Rect2 = (canvas * node.global_transform) * node.get_rect()
		return bounds.intersects(screen)
	for child in node.get_children():
		if _intersects_screen(child, canvas, screen):
			return true
	return false

func _mark_visual(root: CanvasItem, bit: int) -> void:
	_mark_tree(root, bit)
	var ancestor := root.get_parent()
	while ancestor != null and not ancestor is Viewport and not ancestor is CanvasLayer:
		if ancestor is CanvasItem:
			_mark(ancestor, bit)
		ancestor = ancestor.get_parent()

func _mark_tree(node: Node, bit: int) -> void:
	if node.get_meta(&"selection_outline_visual", false):
		return
	if node is CanvasItem:
		_mark(node, bit)
	for child in node.get_children():
		_mark_tree(child, bit)

func _mark(item: CanvasItem, bit: int) -> void:
	item.visibility_layer |= bit
	_marked[item.get_instance_id()] = item

func _clear_marks(bits: int) -> void:
	for id: int in _marked.keys():
		var item: CanvasItem = _marked[id]
		if not is_instance_valid(item):
			_marked.erase(id)
			continue
		item.visibility_layer &= ~bits
		if (item.visibility_layer & MASK_BITS) == 0:
			_marked.erase(id)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_frame):
		RenderingServer.frame_pre_draw.disconnect(_sync_frame)
	_clear_marks(MASK_BITS)
