## 提供承影覆盖与分层投影纹理；原系统继续管理影子节点、变换、激活和实体切割。
class_name ShadowMaskSystem
extends Node

const PACK_SHADER := preload("res://Shader/Receiver_Mask_Pack.gdshader")
const PREVIEW_SHADER := preload("res://Shader/Receiver_Mask_Preview.gdshader")

## 重绘已有视觉影子的轮廓，不复制节点、重挂节点或执行多边形布尔运算。
class ProjectionCanvas extends Node2D:
	var shadows: Array[Polygon2D] = []
	var receiver_opacity: float = 1.0

	func _draw() -> void:
		for shadow in shadows:
			if not is_instance_valid(shadow) or not shadow.is_visible_in_tree():
				continue
			var opacity: float = shadow.color.a * shadow.self_modulate.a
			var ancestor: CanvasItem = shadow
			while ancestor != null:
				opacity *= ancestor.modulate.a
				ancestor = ancestor.get_parent() as CanvasItem
			# 承影层自身的透明度由最终合成统一应用，不在投影里重复使用。
			opacity = clampf(opacity / maxf(receiver_opacity, 0.0001), 0.0, 1.0)
			draw_set_transform_matrix(shadow.global_transform * Transform2D(0.0, shadow.offset))
			draw_colored_polygon(shadow.polygon, Color(1, 1, 1, opacity))

@export_enum("正常裁切", "完整影子", "覆盖纹理") var debug_view: int = 0
@export_range(0, 3) var debug_layer_id: int = 3

static var _empty_texture: ImageTexture
var _level: Level
var _captures: Dictionary = {}
var _projections: Dictionary = {}
var _packed_viewport: SubViewport
var _pack_quad: ColorRect
var _pack_material: ShaderMaterial
var _preview: ColorRect

func _ready() -> void:
	get_parent().ready.connect(_initialize, CONNECT_ONE_SHOT)

static func empty_texture() -> Texture2D:
	if _empty_texture == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		_empty_texture = ImageTexture.create_from_image(image)
	return _empty_texture

func _initialize() -> void:
	_level = Global.level
	assert(_level != null and _level.layer_count <= 4, "RGBA 承影覆盖纹理最多支持四层")
	var ids: Dictionary = {}
	for layer in Global.layers:
		assert(layer.layer_id >= 0 and layer.layer_id < 4 and not ids.has(layer.layer_id), "承影覆盖需要唯一的 layer_id 0～3")
		ids[layer.layer_id] = true
	# Game、Level 等共同祖先需要允许各层的可见性位通过。
	var ancestor: Node = _level
	while ancestor != null and not ancestor is Viewport:
		if ancestor is CanvasItem:
			(ancestor as CanvasItem).visibility_layer |= LayerObject.RECEIVER_MASK_BITS
		ancestor = ancestor.get_parent()
	RenderingServer.frame_pre_draw.connect(_sync_frame)
	_sync_frame()

func _has_shadow_objects() -> bool:
	for layer in Global.layers:
		for child in layer.get_children():
			if child is LayerObject and not child.is_queued_for_deletion():
				if child.can_leave_shadow and not child.shadow_visual.is_empty() and child.is_visible_in_tree():
					return true
	return false

func _make_viewport(viewport_name: String, shared_world: bool) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.world_2d = get_viewport().find_world_2d() if shared_world else World2D.new()
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# 明确建立“覆盖视口 → 打包视口 → 主视口”的子视口依赖，避免读到上一帧。
	if shared_world:
		_packed_viewport.add_child(viewport)
	else:
		add_child(viewport)
	return viewport

func _create_pack() -> void:
	_packed_viewport = _make_viewport("ReceiverMaskRGBA", false)
	_pack_material = ShaderMaterial.new()
	_pack_material.shader = PACK_SHADER
	for id in 4:
		_pack_material.set_shader_parameter("receiver_%d" % id, empty_texture())
	_pack_quad = ColorRect.new()
	_pack_quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pack_quad.material = _pack_material
	_packed_viewport.add_child(_pack_quad)
	RenderingServer.global_shader_parameter_set(&"render_receiver_mask", _packed_viewport.get_texture())

## 每层投影先渲染，再由该层 Shader 染黑 RGB；实体 Alpha 始终只合成一次。
func _update_projection(layer: DepthLayer, capture: SubViewport, size: Vector2i, canvas: Transform2D) -> void:
	var id: int = layer.layer_id
	if not _projections.has(id):
		var viewport := SubViewport.new()
		viewport.name = "ShadowProjection_%d" % id
		viewport.world_2d = World2D.new()
		viewport.disable_3d = true
		viewport.transparent_bg = true
		viewport.gui_disable_input = true
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		# 层级依赖保证 投影 → 承影覆盖 → RGBA → 主画面 使用同一帧的数据。
		capture.add_child(viewport)
		var drawing := ProjectionCanvas.new()
		var material := CanvasItemMaterial.new()
		material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		drawing.material = material
		viewport.add_child(drawing)
		_projections[id] = {"viewport": viewport, "drawing": drawing}
		(layer.material as ShaderMaterial).set_shader_parameter("shadow_projection", viewport.get_texture())
	var entry: Dictionary = _projections[id]
	var viewport: SubViewport = entry.viewport
	viewport.size = size
	viewport.canvas_transform = canvas
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var drawing: ProjectionCanvas = entry.drawing
	drawing.shadows.clear()
	drawing.receiver_opacity = layer.cycle_opacity
	var shadow_index: int = layer.slot - Global.current_layer_index - 2
	for caster_slot in range(Global.current_layer_index + 1, layer.slot):
		for child in Global.get_layer_at_slot(caster_slot).get_children():
			if not child is LayerObject or child.is_queued_for_deletion():
				continue
			var object := child as LayerObject
			if object.can_leave_shadow and shadow_index < object.shadow_visual.size() and object.shadow_active[shadow_index]:
				var shadow: Polygon2D = object.shadow_visual[shadow_index]
				# 正常模式只绘制离屏投影，避免原节点再提交一遍无效的主画面绘制。
				shadow.visibility_layer = 1 if debug_view == 1 else 0
				drawing.shadows.append(shadow)
	drawing.queue_redraw()
	(layer.material as ShaderMaterial).set_shader_parameter("shadow_projection_enabled", debug_view != 1)

## 所有物理、物件视差、Tween 和主相机更新后，再同步离屏视角和通道对应关系。
func _sync_frame() -> void:
	if not is_instance_valid(_level):
		return
	# 倒计时开始时覆盖 80%，归零后覆盖 100%；直接读取计时器以同步重置与暂停。
	var remaining: float = 0.0
	if SignalSystem.timer != null:
		remaining = clampf(SignalSystem.timer.time_left / maxf(SignalSystem.timer.wait_time, 0.001), 0.0, 1.0)
	RenderingServer.global_shader_parameter_set(&"render_shadow_strength", lerpf(1.0, 0.8, remaining))
	RenderingServer.global_shader_parameter_set(&"render_receiver_mask_debug", debug_view)
	var enabled := _has_shadow_objects() and Global.current_layer_index + 2 < Global.layer_count
	RenderingServer.global_shader_parameter_set(&"render_receiver_mask_enabled", enabled)
	if _preview != null:
		_preview.visible = enabled and debug_view == 2
	for capture: SubViewport in _captures.values():
		capture.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for entry: Dictionary in _projections.values():
		(entry.viewport as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	for layer in Global.layers:
		(layer.material as ShaderMaterial).set_shader_parameter("shadow_projection_enabled", false)
	if not enabled:
		if _packed_viewport != null:
			_packed_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _packed_viewport == null:
		_create_pack()
	var size := Vector2i(get_viewport().get_visible_rect().size.ceil())
	var canvas := get_viewport().get_canvas_transform()
	var active := Vector4.ZERO
	var opacity := Vector4.ONE
	for slot in range(Global.current_layer_index + 2, Global.layer_count):
		var layer := Global.get_layer_at_slot(slot)
		var id: int = layer.layer_id
		if not _captures.has(id):
			var capture := _make_viewport("ReceiverLayer_%d" % id, true)
			capture.canvas_cull_mask = LayerObject.receiver_mask_bit(id)
			_captures[id] = capture
			_pack_material.set_shader_parameter("receiver_%d" % id, capture.get_texture())
		var capture: SubViewport = _captures[id]
		capture.size = size
		capture.canvas_transform = canvas
		capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_update_projection(layer, capture, size, canvas)
		active[id] = 1.0 if layer.cycle_opacity > 0.0001 else 0.0
		opacity[id] = layer.cycle_opacity
	_pack_material.set_shader_parameter("active_layers", active)
	_pack_material.set_shader_parameter("layer_opacity", opacity)
	_packed_viewport.size = size
	_pack_quad.size = Vector2(size)
	_packed_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if debug_view == 2:
		_update_preview(Vector2(size))

func _update_preview(size: Vector2) -> void:
	if _preview == null:
		var canvas := CanvasLayer.new()
		canvas.name = "ReceiverMaskPreview"
		canvas.layer = 90
		add_child(canvas)
		_preview = ColorRect.new()
		_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var preview_material := ShaderMaterial.new()
		preview_material.shader = PREVIEW_SHADER
		_preview.material = preview_material
		canvas.add_child(_preview)
	_preview.size = size
	_preview.visible = true
	(_preview.material as ShaderMaterial).set_shader_parameter("layer_id", debug_layer_id)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_frame):
		RenderingServer.frame_pre_draw.disconnect(_sync_frame)
	for layer in Global.layers:
		if is_instance_valid(layer):
			(layer.material as ShaderMaterial).set_shader_parameter("shadow_projection_enabled", false)
	RenderingServer.global_shader_parameter_set(&"render_receiver_mask_enabled", false)
	RenderingServer.global_shader_parameter_set(&"render_receiver_mask_debug", 0)
	RenderingServer.global_shader_parameter_set(&"render_receiver_mask", empty_texture())
	RenderingServer.global_shader_parameter_set(&"render_shadow_strength", 1.0)
