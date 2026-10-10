## 此脚本为自动挂载，负责全局参数、场景节点与图层信息的存储和维护

extends Node
## 图层配置信息
var layer_count: int = 4
var layer_scale: float = 0.8
var layer_scales: Array = [1.0 / layer_scale, 1.0, layer_scale, layer_scale * layer_scale]
var current_layer_index: int = 1
## 场景节点信息
var player: PlayerController = null
var camera: Camera2D = null
var level: Level = null
var layers: Array[DepthLayer] = []
## 全局状态信息
var object_selected: LayerObject = null
var camera_fixed: bool = true
var eagle_eye: bool = false
var checkpoint_position: Vector2 = Vector2.ZERO
var checkpoint_collision_group: int = 1
var checkpoint_scale: Vector2 = Vector2.ONE
var _dialogue_label: Label
var _dialogue_timer: Timer

## 开关鹰眼，并让全部图层物体按当前所在层刷新画面
func set_eagle_eye(enabled: bool) -> void:
	eagle_eye = enabled
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("layer_objects"):
		if node.has_method("refresh_eagle_eye"):
			node.refresh_eagle_eye()

## 自动查找主场景中的 Player、Camera、Level 和全部 DepthLayer
func discover_scene_nodes(scene_root: Node) -> void:
	## 查找节点
	player = null
	camera = null
	level = null
	layers = []
	_find_scene_nodes(scene_root)
	if player == null or camera == null or level == null:
		assert(not(player == null or camera == null or level == null), "缺少关卡/相机/玩家！")
	## 查找图层
	level.write_to_global()
	var used := {}
	for child in level.get_children():
		if child is DepthLayer:
			layers.append(child)
			assert(not used.has(child.slot), "图层不唯一！")
			used[child.slot] = true
	assert(current_layer_index < layer_count, "关卡层超出图层数！")
	assert(layers.size() == layer_count, "图层数量错误！")
	##初始化
	camera.position_smoothing_enabled = false
	camera.enabled = true
	while player.collision_group != current_layer_index + 1:
		player.collision_group_change(1)
	player.z_index = (layer_count - current_layer_index) * 100 + 1
	remember_player_state()

## 记下玩家现在的位置、所在层和大小。只在这一次游戏里有效。
func remember_player_state() -> void:
	if player == null:
		return
	checkpoint_position = player.global_position
	checkpoint_collision_group = player.collision_group
	checkpoint_scale = player.scale

## 把玩家放回最近记下的状态。
func restore_player_state() -> void:
	if player == null:
		return
	player.apply_recorded_state(checkpoint_position, checkpoint_collision_group, checkpoint_scale)

## 在画面上显示一句对话。后来的一句会换掉前面的。
func show_line(text: String) -> void:
	var tree := get_tree()
	if tree == null:
		return
	if _dialogue_label == null:
		var canvas := CanvasLayer.new()
		canvas.layer = 20
		var label := Label.new()
		label.position = Vector2(48, 620)
		label.size = Vector2(1180, 70)
		label.add_theme_font_size_override("font_size", 28)
		label.add_theme_color_override("font_color", Color(1, 1, 1))
		label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.05))
		label.add_theme_constant_override("outline_size", 6)
		canvas.add_child(label)
		tree.root.add_child(canvas)
		_dialogue_label = label
		_dialogue_timer = Timer.new()
		_dialogue_timer.one_shot = true
		_dialogue_timer.wait_time = 4.0
		_dialogue_timer.timeout.connect(func() -> void:
			if _dialogue_label != null:
				_dialogue_label.visible = false
		)
		add_child(_dialogue_timer)
	_dialogue_label.text = text
	_dialogue_label.visible = true
	_dialogue_timer.start()

func _find_scene_nodes(node: Node) -> void:
	if player == null and node is PlayerController:
		player = node as PlayerController
	elif camera == null and node is Camera2D:
		camera = node as Camera2D
	elif level == null and node is Level:
		level = node as Level
	for child in node.get_children():
		_find_scene_nodes(child)

## 查询特定图层
func get_layer_at_slot(target_slot: int) -> DepthLayer:
	for layer in layers:
		if layer.slot == target_slot:
			return layer
	return null
