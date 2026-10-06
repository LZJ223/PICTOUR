class_name SystemController
extends Node
## 节点信息
@export var player: PlayerController
@export var camera: Camera2D
@export var layers: Array[DepthLayer] = []
const player_body_type = preload("res://Component/Object/Player_Object/Player_Object.tscn")
var player_body: Player_Object = null

## 异常检测与初始化
func _ready() -> void:
	assert(player != null)
	assert(camera != null)
	assert(layers.size() == Global.layer_count)
	assert(slots_are_unique())
	camera.position_smoothing_enabled = false
	camera.enabled = true
	Global.layer_cycle.connect(cycle)
	Global.layer_change.connect(transfer)
	Global.UAV_activate.connect(UAV_activate)

## 相机与位置更新
func _process(_delta: float) -> void:
	camera.global_position = player.global_position
	for layer in layers:
		layer.apply_slot_state(player.global_position)


## 图层槽位检测
func slots_are_unique() -> bool:
	var used := {}
	for layer in layers:
		if used.has(layer.slot):
			return false
		used[layer.slot] = true
	return used.size() == Global.layer_count
	
## 查询特定图层
func get_layer_at_slot(target_slot: int) -> DepthLayer:
	for layer in layers:
		if layer.slot == target_slot:
			return layer
	return null


## 图层轮换
func cycle(direction: int) -> void:
	for layer in layers:
		layer.set_slot(posmod(layer.slot + direction, Global.layer_count))
	assert(slots_are_unique())

## 改变物体图层
func transfer(direction: int, object: LayerObject) -> void:
	var old_slot: int = object.find_owner_layer().slot
	var new_slot: int = old_slot - direction
	if new_slot < 0 or new_slot >= Global.layer_count:
		return
	var target_layer: DepthLayer = get_layer_at_slot(new_slot)
	object.transfer_to(target_layer, player.global_position, direction)

## 无人机激活/关闭
func UAV_activate(condition: bool) -> void:
	player.UAV_activate(condition)
	if condition:
		var current_layer = get_layer_at_slot(1)
		player_body = player_body_type.instantiate()
		current_layer.add_child(player_body)
		player_body.position = player.position
	else:
		var player_body_layer: DepthLayer = player_body.find_owner_layer()
		while player_body_layer.slot != 1:
			cycle(1)
			player.collision_group_change(1)
		player.position = player_body.position
		player.scale = player_body.collision_box.scale
		player_body.queue_free()
		player_body = null
