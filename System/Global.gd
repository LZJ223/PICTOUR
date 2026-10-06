extends Node
## 图层配置信息
const layer_count : int = 4
const layer_scale : float = 0.75
var layer_scales : Array = [1.0 / layer_scale, 1.0, layer_scale, layer_scale * layer_scale]
## 操作状态信息
var object_selected : LayerObject = null
var UAV_activated : bool = false
## 信号定义
signal layer_cycle(direction: int)
signal layer_change(direction: int, object: LayerObject)
signal UAV_activate(UAV_status: bool)

## 输入判定与信号触发
func _unhandled_input(event: InputEvent) -> void:
	## 键盘交互
	if object_selected == null:
		if event.is_action_pressed("forward"):
			layer_cycle.emit(1)
		elif event.is_action_pressed("backward"):
			layer_cycle.emit(-1)
	else:
		if event.is_action_pressed("forward"):
			layer_change.emit(1, object_selected)
		elif event.is_action_pressed("backward"):
			layer_change.emit(-1, object_selected)
	if event.is_action_pressed("UAV"):
		UAV_activated = not UAV_activated
		UAV_activate.emit(UAV_activated)
	## 点击交互与物件选取
	if event.is_action_pressed("pickup"):
		## 查询鼠标位置
		var screen_position : Vector2 = get_viewport().get_mouse_position()
		var canvas_transform : Transform2D = get_viewport().get_canvas_transform()
		var mouse_position : Vector2 = canvas_transform.affine_inverse() * screen_position
		## 查询该位置下的碰撞体
		var space := get_viewport().world_2d.direct_space_state
		var params := PhysicsPointQueryParameters2D.new()
		params.position = mouse_position
		params.collide_with_areas = true
		params.collide_with_bodies = false
		var results := space.intersect_point(params, 32)
		## 检测z轴
		var best: Node = null
		var best_z : int = -999
		for result in results:
			var collider : Area2D = result.collider
			if collider.z_index > best_z:
				best_z = collider.z_index
				best = collider
		## 更新状态与输出信号
		while best != null and not best is LayerObject:
			best = best.get_parent()
		if object_selected:
			object_selected.set_pick_condition()
		object_selected = best as LayerObject
		if object_selected:
			object_selected.set_pick_condition(true)
