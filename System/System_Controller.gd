## 此脚本挂载在节点System下，负责记录关卡内的全局信息，并统筹视角更新、图层轮换、物件图层转换、释放无人机四个全局系统

class_name SystemController
extends Node
## 节点信息
@export var player: PlayerController
@export var camera: Camera2D
@export var level: Level
var layers: Array[DepthLayer] = []
## 玩家与相机信息
var UAV_activated: bool = false
var camera_fixed: bool = true
## 无人机系统使用的玩家（物体）节点资源预加载
const player_body_type = preload("res://Component/Object/Player_Object/Player_Object.tscn")

## 初始化
func _ready() -> void:
	level.write_to_global()
	## 异常状态检测
	assert(player != null, "未在System中指定Player！")
	assert(camera != null, "未在System中指定Camera！")
	assert(level != null, "未在System中指定Level！")
	assert(Global.current_layer_index < Global.layer_count, "关卡层超出图层数！")
	layers = []
	var used := {}
	for child in level.get_children():
		if child is DepthLayer:
			layers.append(child)
			assert(not used.has(child.slot), "图层不唯一！")
			used[child.slot] = true
	assert(layers.size() == Global.layer_count, "图层数量错误！")
	## 相机与玩家初始化
	camera.position_smoothing_enabled = false
	camera.enabled = true
	while not player.collision_group == Global.current_layer_index + 1:
		player.collision_group_change(1)
	player.z_index = (Global.layer_count - Global.current_layer_index) * 100 + 1
	## 信号连接
	Global.layer_cycle.connect(cycle)
	Global.layer_change.connect(transfer)
	Global.UAV_activate.connect(UAV_activate)

## 相机与位置更新
func _process(_delta: float) -> void:
	if camera_fixed:
		camera.global_position = player.global_position
	for layer in layers:
		layer.apply_slot_state(camera.global_position)

## 图层轮换
func cycle(direction: int) -> void:
	for layer in layers:
		layer.set_slot(posmod(layer.slot + direction, Global.layer_count))

## 改变物体图层
func transfer(direction: int, object: LayerObject) -> void:
	var old_slot: int = object.find_owner_layer().slot
	var new_slot: int = old_slot - direction
	if new_slot < 0 or new_slot >= Global.layer_count:
		return
	var target_layer: DepthLayer = get_layer_at_slot(new_slot)
	object.transfer_to(target_layer, camera.global_position)

## 无人机激活/关闭
func UAV_activate() -> void:
	if not player.UAV_activate(not UAV_activated):
		return
	UAV_activated = not UAV_activated
	if UAV_activated:
		var current_layer = get_layer_at_slot(Global.current_layer_index)
		player.player_body = player_body_type.instantiate()
		current_layer.add_child(player.player_body)
		player.player_body.set_collision_group(2, current_layer.layer_id + 1)
		player.player_body.position = player.position
	else:
		var player_body_layer: DepthLayer = player.player_body.find_owner_layer()
		while player_body_layer.slot != Global.current_layer_index:
			cycle(1)
			player.collision_group_change(1)
		player.position = player.player_body.position
		player.scale = player.player_body.collision_box.scale
		player.player_body.queue_free()
		player.player_body = null

## 查询特定图层
func get_layer_at_slot(target_slot: int) -> DepthLayer:
	for layer in layers:
		if layer.slot == target_slot:
			return layer
	return null
