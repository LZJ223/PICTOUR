## 此脚本为自动挂载，负责全局输入判定、信号发射与影子布尔计时

extends Node
## 信号定义
signal layer_cycle(direction: int, check_collision: bool)
signal layer_change(direction: int, object: LayerObject)
signal UAV_activate()
signal shadow_boolean()
## 影子布尔计时器
var timer: Timer = null

func _ready() -> void:
	timer = Timer.new()
	add_child(timer)
	timer.wait_time = 2.0
	timer.one_shot = true
	timer.timeout.connect(_timer_trigger)
	timer.start()

## 输入判定与信号触发
func _unhandled_input(event: InputEvent) -> void:
	## 键盘交互
	if Global.object_selected == null:
		if event.is_action_pressed("forward"):
			layer_cycle.emit(1, true)
			timer_reset()
		elif event.is_action_pressed("backward"):
			layer_cycle.emit(-1, true)
			timer_reset()
	else:
		if event.is_action_pressed("forward"):
			layer_change.emit(1, Global.object_selected)
		elif event.is_action_pressed("backward"):
			layer_change.emit(-1, Global.object_selected)
	if event.is_action_pressed("UAV"):
		UAV_activate.emit()
	## 点击交互与物件选取
	if event.is_action_pressed("select_object"):
		timer_reset()
		## 查询鼠标位置
		var screen_position: Vector2 = get_viewport().get_mouse_position()
		var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
		var mouse_position: Vector2 = canvas_transform.affine_inverse() * screen_position
		## 查询该位置下的碰撞体
		var space := get_viewport().world_2d.direct_space_state
		var params := PhysicsPointQueryParameters2D.new()
		params.position = mouse_position
		params.collide_with_areas = true
		params.collide_with_bodies = false
		var results := space.intersect_point(params, 32)
		## 检测 z 轴
		var best: LayerObject = null
		var best_z: int = -999
		for result in results:
			var collider: Area2D = result.collider
			if not collider.input_pickable:
				continue
			var candidate: Node = collider
			while candidate != null and not candidate is LayerObject:
				candidate = candidate.get_parent()
			if candidate is LayerObject:
				var object := candidate as LayerObject
				var layer_z := object.owner_layer.z_index
				if layer_z > best_z:
					best_z = layer_z
					best = object
		## 更新选取状态
		if Global.object_selected:
			Global.object_selected.set_pick_condition(false)
		Global.object_selected = best
		if Global.object_selected:
			Global.object_selected.set_pick_condition(true)

func _process(_delta: float) -> void:
	if Global.object_selected:
		timer_reset()

func _timer_trigger() -> void:
	PhysicsServer2D.set_active(false)
	shadow_boolean.emit()

func timer_reset() -> void:
	if timer.is_stopped():
		PhysicsServer2D.set_active(true)
	timer.start()
