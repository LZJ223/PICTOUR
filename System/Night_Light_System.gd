## 黑夜关卡层的柔和表面照明，不叠加全屏空气效果，不管理跨层 Shadow 节点。
class_name NightLightSystem
extends Node

@export var enabled: bool = true

var _level: Level
var _origin: Marker2D
var _light: PointLight2D
var _occluders: Dictionary = {}

func _ready() -> void:
	get_parent().ready.connect(_initialize, CONNECT_ONE_SHOT)

func _initialize() -> void:
	_level = Global.level
	if _level == null or not _level.is_night:
		return
	_origin = Global.player.get_node("LightOrigin") as Marker2D
	_light = PointLight2D.new()
	_light.name = "HeadLight"
	_light.range_item_cull_mask = DepthLayer.NIGHT_LIGHT_MASK
	_light.shadow_item_cull_mask = DepthLayer.NIGHT_LIGHT_MASK
	# 仅照明主画布中 Z=0 的关卡层合成，排除其他景深层、背景和界面。
	_light.range_z_min = 0
	_light.range_z_max = 0
	_light.range_layer_min = 0
	_light.range_layer_max = 0
	_light.shadow_enabled = true
	_light.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	_light.shadow_filter_smooth = 0.5
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color.TRANSPARENT])
	var texture := GradientTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.gradient = gradient
	_light.texture = texture
	add_child(_light)
	RenderingServer.frame_pre_draw.connect(_sync_frame)
	_sync_frame()

func _sync_frame() -> void:
	if not is_instance_valid(_level) or _light == null:
		return
	var view_size := get_viewport().get_visible_rect().size
	var canvas := get_viewport().get_canvas_transform()
	var focus: float = 0.0
	for layer in Global.layers:
		var distance: float = absf(log(layer.visual_scale) / log(_level.layer_scale))
		focus = maxf(focus, 1.0 - smoothstep(0.0, 0.5, distance))
	_light.global_position = _origin.global_position
	_light.color = _level.night_light_color
	_light.energy = _level.night_light_energy * focus
	_light.texture_scale = _level.night_light_radius / 128.0
	_light.enabled = enabled and focus > 0.001
	RenderingServer.global_shader_parameter_set(&"render_night_light_enabled", enabled)
	RenderingServer.global_shader_parameter_set(&"render_night_light_uv", (canvas * _origin.global_position) / view_size)
	# 将屏幕 UV 的差值还原为世界距离，前景衰减范围不随缩放、旋转或窗口比例改变。
	var inverse_canvas := canvas.affine_inverse()
	var uv_x := inverse_canvas.x * view_size.x
	var uv_y := inverse_canvas.y * view_size.y
	RenderingServer.global_shader_parameter_set(&"render_night_world_per_uv", Vector4(uv_x.x, uv_x.y, uv_y.x, uv_y.y))
	RenderingServer.global_shader_parameter_set(&"render_night_light_radius", _level.night_light_radius * Global.camera.zoom.x / view_size.y)
	RenderingServer.global_shader_parameter_set(&"render_night_surface_width", _level.night_surface_width * Global.camera.zoom.x / view_size.y)
	RenderingServer.global_shader_parameter_set(&"render_night_ambient", _level.night_ambient)
	_sync_occluders()

func _sync_occluders() -> void:
	var live: Dictionary = {}
	for layer in Global.layers:
		var distance: float = absf(log(layer.visual_scale) / log(_level.layer_scale))
		for child in layer.get_children():
			if not child is LayerObject or child.is_queued_for_deletion():
				continue
			var object := child as LayerObject
			var id: int = object.get_instance_id()
			live[id] = true
			if not _occluders.has(id):
				var occluder := LightOccluder2D.new()
				occluder.name = "NightOccluder"
				occluder.occluder_light_mask = DepthLayer.NIGHT_LIGHT_MASK
				occluder.occluder = OccluderPolygon2D.new()
				object.visual_root.add_child(occluder)
				_occluders[id] = {"node": occluder, "geometry": PackedVector2Array()}
			var entry: Dictionary = _occluders[id]
			if entry.geometry != object.collision_box.polygon:
				entry.geometry = object.collision_box.polygon
				(entry.node as LightOccluder2D).occluder.polygon = entry.geometry
			(entry.node as LightOccluder2D).visible = enabled and distance < 0.5 and object.is_visible_in_tree()
	for id in _occluders.keys():
		if not live.has(id):
			if is_instance_valid(_occluders[id].node):
				(_occluders[id].node as LightOccluder2D).queue_free()
			_occluders.erase(id)

func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_sync_frame):
		RenderingServer.frame_pre_draw.disconnect(_sync_frame)
	if _light == null:
		return
	RenderingServer.global_shader_parameter_set(&"render_night_light_enabled", false)
	for entry: Dictionary in _occluders.values():
		if is_instance_valid(entry.node):
			(entry.node as LightOccluder2D).queue_free()
	_occluders.clear()
