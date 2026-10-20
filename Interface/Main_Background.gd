## 菜单背景不注册游戏关卡或玩家控制器，只保留 Bot 巡逻所需的碰撞。
extends Node2D

@export_range(0.0, 1000.0, 1.0) var scroll_speed: float = 260.0
@export_range(1.0, 32000.0, 1.0, "or_greater") var loop_length: float = 8000.0
@export var initial_scroll: float = 0.0

@onready var _level: Level = $Level
@onready var _player: Node2D = $Player
@onready var _animation: PlayerAnimation = $Player/PlayerSprite
var _layers: Array[DepthLayer] = []
var _origins: Array[Vector2] = []
var _centers: Array[float] = []
var _copy_indices: Array[int] = []
var _scroll: float = 0.0
var _tiles: Array[Level] = []

func _ready() -> void:
	## 背景及展示角色不随转场暂停，淡入、淡出期间也持续运动。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_scroll = initial_scroll
	_register_tile(_level)
	_level.write_to_renderer()
	Renderer.apply_settings()
	_animation.set_facing(1, true)
	_player.z_index = 1
	## 等主菜单相机完成定位，再在黑幕下同步首帧。
	get_viewport().size_changed.connect(refresh_view)
	refresh_view.call_deferred()

func _register_tile(tile: Level) -> void:
	var copy_index: int = _tiles.size()
	_tiles.append(tile)
	_disable_interactions(tile)
	for child in tile.get_children():
		if child is DepthLayer:
			var layer := child as DepthLayer
			_layers.append(layer)
			_origins.append(layer.position)
			_centers.append(_get_layer_center(layer))
			_copy_indices.append(copy_index)
			layer.cancel_cycle()
			if copy_index > 0:
				layer.haze_plane.hide()

func refresh_view() -> void:
	var camera := get_viewport().get_camera_2d()
	var camera_zoom := camera.zoom.abs() if camera != null else Vector2.ONE
	var minimum_scale: float = 1.0
	for layer in _level.get_children():
		if layer is DepthLayer:
			minimum_scale = minf(minimum_scale, layer.visual_scale)
	var tile_width: float = loop_length * minimum_scale * absf(global_scale.x) * camera_zoom.x
	var count: int = maxi(2, ceili(get_viewport_rect().size.x / maxf(tile_width, 0.0001)) + 1)
	while _tiles.size() < count:
		var copy := (load(_level.scene_file_path) as PackedScene).instantiate() as Level
		copy.name = "LevelCopy%d" % _tiles.size()
		copy.transform = _level.transform
		add_child(copy)
		_register_tile(copy)
	while _tiles.size() > count:
		var tile: Level = _tiles.pop_back()
		while not _layers.is_empty() and _layers.back().get_parent() == tile:
			_layers.pop_back()
			_origins.pop_back()
			_centers.pop_back()
			_copy_indices.pop_back()
		tile.hide()
		remove_child(tile)
		tile.queue_free()
	_update_background()

func _process(delta: float) -> void:
	_scroll += scroll_speed * delta
	_update_background()

func _update_background() -> void:
	var camera := get_viewport().get_camera_2d()
	var camera_zoom := camera.zoom.abs() if camera != null else Vector2.ONE
	var world_to_background := global_transform.affine_inverse()
	var period: float = loop_length * _tiles.size()
	_animation.set_motion(scroll_speed, true)
	for index in _layers.size():
		var layer := _layers[index]
		var center: float = _centers[index] - _player.position.x
		## 按地面中心回收，保留原始布置；视差层各自离屏后才从右侧接续。
		layer.position.x = _origins[index].x + fposmod(
			_copy_indices[index] * loop_length - _scroll + center + period * 0.5, period
		) - center - period * 0.5
		layer.apply_slot_state(_player.global_position, camera_zoom)
		if _copy_indices[index] == 0:
			var haze := layer.haze_plane.material as ShaderMaterial
			haze.set_shader_parameter("world_to_space", world_to_background)
			## 雾使用自身纹理的周期，不随景物的 8000px 回收而重置。
			var haze_period: float = Renderer.HAZE_TEXTURE.get_width() * Renderer.haze_world_scale
			haze.set_shader_parameter("scroll_offset", fposmod(_scroll, maxf(haze_period, 0.0001)))

func _get_layer_center(layer: DepthLayer) -> float:
	var bounds := Rect2()
	var initialized := false
	for child in layer.get_children():
		if child is LayerObject and child.collision_box != null:
			for point in child.collision_box.polygon:
				var local_point := to_local(child.collision_box.to_global(point))
				if not initialized:
					bounds = Rect2(local_point, Vector2.ZERO)
					initialized = true
				else:
					bounds = bounds.expand(local_point)
	return bounds.get_center().x if initialized else _player.position.x

func _disable_interactions(node: Node) -> void:
	if node is RigidBody2D:
		node.freeze = true
	if node is Bot:
		node.enable_background_motion()
	if node is CollisionObject2D:
		node.input_pickable = false
	if node is Area2D:
		node.collision_layer = 0
		node.collision_mask = 0
		node.monitoring = false
		node.monitorable = false
	for child in node.get_children():
		_disable_interactions(child)
