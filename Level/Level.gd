## 此脚本挂载在level节点上，包含关卡全局信息

class_name Level
extends Node2D
## 关卡全局信息
@export var layer_count: int = 4
@export var layer_scale: float = 0.8
@export var current_layer_index: int = 1
@export_group("关卡能力")
@export var allow_object_transfer: bool = true
@export var allow_layer_cycle: bool = true
@export var allow_uav: bool = true
## 非玩家景别允许自然景物叠放；地形、角色及其他实体仍不可穿入。
## 默认保持旧原型的占用规则，仅由需要绘本叠景的关卡显式开启。
@export var allow_scenery_overlap_outside_player_layer: bool = false
@export_group("相机")
@export var lock_camera_y: bool = false
@export var camera_height: float = 360.0

## 子物件 _ready 前配置参数，避免非默认层数使用上一关的状态。
func _enter_tree() -> void:
	write_to_global()

## 向Global写入关卡参数
func write_to_global() -> void:
	assert(layer_count >= 1 and layer_count <= 32, "图层数量须在 1～32 之间")
	assert(layer_scale > 0.0, "图层倍率必须大于零")
	assert(current_layer_index >= 0 and current_layer_index < layer_count, "当前槽位越界")
	Global.clear_selection()
	Global.uav_active = false
	Global.layer_count = layer_count
	Global.layer_scale = layer_scale
	Global.current_layer_index = current_layer_index
	var layer_scales: Array[float] = []
	for index in range(layer_count):
		layer_scales.append(pow(layer_scale, index - current_layer_index))
	Global.layer_scales = layer_scales
	Global.allow_object_transfer = allow_object_transfer
	Global.allow_layer_cycle = allow_layer_cycle
	Global.allow_uav = allow_uav
