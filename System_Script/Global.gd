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
