## 场景内的黑夜表现协调器。GPU 图集只绘制投影，不复制场景或回读像素。
class_name NightRenderSystem
extends Node

const MASK_SHADER := preload("res://Shader/Shadow_Mask_Write.gdshader")
const RAY_SHADER := preload("res://Shader/Night_Light_Rays.gdshader")
const ATLAS_COLUMNS: int = 2

@export_range(0.25, 1.0, 0.25) var mask_resolution_scale: float = 1.0

static var _empty_mask: ImageTexture
var _mask_viewport: SubViewport
var _rays: Polygon2D
var _light_origin: Marker2D
var _level: Level
var _casters: Dictionary = {}
var _occluders: Dictionary = {}
var _tile_size := Vector2i.ONE
var _time: float = 0.0

func _ready() -> void:
	set_process(false)
	## Game._ready 先发现玩家、图层和相机，然后才初始化此表现系统。
	get_parent().ready.connect(_initialize, CONNECT_ONE_SHOT)

static func empty_mask() -> Texture2D:
	if _empty_mask == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.BLACK)
		_empty_mask = ImageTexture.create_from_image(image)
	return _empty_mask

func _initialize() -> void:
	_level = Global.level
	if _level == null or not _level.is_night:
		return
	assert(_level.layer_count <= 4, "黑夜遮罩图集最多支持四个物理图层")
	_light_origin = Global.player.get_node("LightOrigin") as Marker2D
	assert(_light_origin != null, "黑夜关卡需要 Player/LightOrigin")
	var ids: Dictionary = {}
	for layer in Global.layers:
		assert(layer.layer_id >= 0 and layer.layer_id < 4 and not ids.has(layer.layer_id), "物理图层编号必须唯一且在 0～3 之间")
		ids[layer.layer_id] = true
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "ShadowMaskAtlas"
	_mask_viewport.world_2d = World2D.new()
	_mask_viewport.disable_3d = true
	_mask_viewport.transparent_bg = true
	_mask_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_viewport.gui_disable_input = true
	add_child(_mask_viewport)
	_resize_mask()
	RenderingServer.global_shader_parameter_set(&"render_shadow_mask", _mask_viewport.get_texture())
	RenderingServer.global_shader_parameter_set(&"render_night_enabled", true)
	RenderingServer.global_shader_parameter_set(&"render_night_ambient", _level.night_ambient)
	RenderingServer.global_shader_parameter_set(&"render_night_light_color", _level.night_light_color)
	RenderingServer.global_shader_parameter_set(&"render_night_ray_energy", _level.night_ray_energy)
	RenderingServer.global_shader_parameter_set(&"render_night_surface_energy", _level.night_surface_energy)
	_rays = Polygon2D.new()
	_rays.name = "NightLightRays"
	_rays.top_level = true
	## 空气光束在实体之后合成，由实体覆盖，不能重新照亮纯黑影子。
	_rays.z_as_relative = false
	_rays.z_index = -1000
	var ray_material := ShaderMaterial.new()
	ray_material.shader = RAY_SHADER
	_rays.material = ray_material
	add_child(_rays)
	get_viewport().size_changed.connect(_resize_mask)
	RenderingServer.frame_pre_draw.connect(_sync_frame)
	set_process(true)
	_sync_frame()

func _process(delta: float) -> void:
	_time += delta
	RenderingServer.global_shader_parameter_set(&"render_night_time", _time)

func _resize_mask() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	_tile_size = Vector2i(maxi(2, ceili(viewport_size.x * mask_resolution_scale)), maxi(2, ceili(viewport_size.y * mask_resolution_scale)))
	_mask_viewport.size = _tile_size * ATLAS_COLUMNS
	RenderingServer.global_shader_parameter_set(&"render_shadow_tile_size", Vector2(_tile_size))

## 在 Tween、物理、相机完成后同步。同帧绘制子视口，主视口只读取其结果。
func _sync_frame() -> void:
	if not is_instance_valid(_level) or not is_instance_valid(_light_origin):
		return
	var view_size := get_viewport().get_visible_rect().size
	var canvas := get_viewport().get_canvas_transform()
	var light_position: Vector2 = _light_origin.global_position
	var scales := Vector4.ONE
	var focus: float = 0.0
	for layer in Global.layers:
		scales[layer.layer_id] = layer.visual_scale
		var distance: float = absf(log(layer.visual_scale) / log(_level.layer_scale))
		focus = maxf(focus, 1.0 - smoothstep(0.0, 0.5, distance))
	RenderingServer.global_shader_parameter_set(&"render_shadow_anchor", Global.camera.global_position)
	RenderingServer.global_shader_parameter_set(&"render_shadow_layer_scales", scales)
	RenderingServer.global_shader_parameter_set(&"render_shadow_screen_x", Vector3(canvas.x.x, canvas.y.x, canvas.origin.x))
	RenderingServer.global_shader_parameter_set(&"render_shadow_screen_y", Vector3(canvas.x.y, canvas.y.y, canvas.origin.y))
	RenderingServer.global_shader_parameter_set(&"render_shadow_view_size", view_size)
	## 统一使用屏幕 UV，避免窗口拉伸时逻辑尺寸与实际帧缓冲尺寸混用。
	RenderingServer.global_shader_parameter_set(&"render_night_light_uv", (canvas * light_position) / view_size)
	RenderingServer.global_shader_parameter_set(&"render_night_light_radius", _level.night_light_radius * Global.camera.zoom.x / view_size.y)
	RenderingServer.global_shader_parameter_set(&"render_night_surface_width", _level.night_surface_width * Global.camera.zoom.x / view_size.y)
	RenderingServer.global_shader_parameter_set(&"render_night_focus", focus)
	_sync_objects(light_position)
	var to_world := canvas.affine_inverse()
	_rays.polygon = PackedVector2Array([to_world * Vector2.ZERO, to_world * Vector2(view_size.x, 0.0), to_world * view_size, to_world * Vector2(0.0, view_size.y)])

func _sync_objects(light_position: Vector2) -> void:
	var live_casters: Dictionary = {}
	var live_objects: Dictionary = {}
	for layer in Global.layers:
		for child in layer.get_children():
			if not child is LayerObject or child.is_queued_for_deletion():
				continue
			var object := child as LayerObject
			if not object.is_visible_in_tree():
				continue
			var id: int = object.get_instance_id()
			live_objects[id] = true
			_sync_occluder(object, id)
			if object is ShadowedGeometry and object.can_leave_shadow:
				live_casters[id] = true
				_sync_caster(object as ShadowedGeometry, id, light_position)
	for id in _casters.keys():
		if not live_casters.has(id):
			for proxy: Polygon2D in _casters[id].proxies.values():
				proxy.free()
			_casters.erase(id)
	for id in _occluders.keys():
		if not live_objects.has(id):
			if is_instance_valid(_occluders[id].node):
				(_occluders[id].node as LightOccluder2D).queue_free()
			_occluders.erase(id)

func _sync_caster(caster: ShadowedGeometry, id: int, light_position: Vector2) -> void:
	if not _casters.has(id):
		_casters[id] = {"geometry": caster.shadow.polygon, "proxies": {}}
	var entry: Dictionary = _casters[id]
	var geometry: PackedVector2Array = caster.shadow.polygon
	if entry.geometry != geometry:
		entry.geometry = geometry
		for proxy: Polygon2D in entry.proxies.values():
			proxy.polygon = geometry
	for receiver in Global.layers:
		var receiver_id: int = receiver.layer_id
		var active: bool = caster.can_project_on(receiver)
		if not entry.proxies.has(receiver_id):
			if not active:
				continue
			var proxy := Polygon2D.new()
			proxy.name = "Shadow_%d_%d" % [id, receiver_id]
			proxy.polygon = geometry
			var mask_material := ShaderMaterial.new()
			mask_material.shader = MASK_SHADER
			mask_material.set_shader_parameter("receiver_id", receiver_id)
			proxy.material = mask_material
			_mask_viewport.add_child(proxy)
			## 顶点着色器把世界坐标投向图集；CPU 原始包围盒不参与裁剪。
			RenderingServer.canvas_item_set_custom_rect(proxy.get_canvas_item(), true, Rect2(-1000000, -1000000, 2000000, 2000000))
			entry.proxies[receiver_id] = proxy
		var proxy: Polygon2D = entry.proxies[receiver_id]
		proxy.visible = active
		if active:
			proxy.transform = caster.get_projection_transform(receiver, light_position)
			(proxy.material as ShaderMaterial).set_shader_parameter("receiver_offset", receiver.blocked_shake_offset)

func _sync_occluder(object: LayerObject, id: int) -> void:
	if not _occluders.has(id):
		var occluder := LightOccluder2D.new()
		occluder.name = "NightOccluder"
		occluder.occluder = OccluderPolygon2D.new()
		object.visual_root.add_child(occluder)
		_occluders[id] = {"node": occluder, "geometry": PackedVector2Array()}
	var entry: Dictionary = _occluders[id]
	var shape: PackedVector2Array = object.collision_box.polygon
	if entry.geometry != shape:
		entry.geometry = shape
		(entry.node as LightOccluder2D).occluder.polygon = shape
	var distance: float = absf(log(object.owner_layer.visual_scale) / log(_level.layer_scale))
	(entry.node as LightOccluder2D).visible = distance < 0.5 and object.is_visible_in_tree()

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_frame):
		RenderingServer.frame_pre_draw.disconnect(_sync_frame)
	if _mask_viewport == null:
		return
	RenderingServer.global_shader_parameter_set(&"render_night_enabled", false)
	RenderingServer.global_shader_parameter_set(&"render_shadow_mask", empty_mask())
	for entry: Dictionary in _occluders.values():
		if is_instance_valid(entry.node):
			(entry.node as LightOccluder2D).queue_free()
	_casters.clear()
	_occluders.clear()
