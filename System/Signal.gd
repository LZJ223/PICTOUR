## 此脚本为自动挂载，负责全局输入判定、信号发射与影子布尔计时

extends Node
## 信号定义
signal layer_cycle(direction: int, check_collision: bool)
signal layer_change(direction: int, object: LayerObject)
signal UAV_activate()
signal shadow_boolean()
signal destination_view_changed(active: bool)
signal dialogue_advance
signal back_pressed
signal back_released
var dialogue_active: bool = false
var looking_at_destination: bool = false
var _gameplay_active: bool = false
## 影子布尔计时器
var timer: Timer = null

func _ready() -> void:
	## 返回键在菜单和暂停期间也有效；玩法与计时器仍遵守游戏暂停状态。
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	process_physics_priority = -100
	timer = Timer.new()
	timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(timer)
	timer.wait_time = 5.0
	timer.one_shot = true
	timer.timeout.connect(_timer_trigger)
	set_gameplay_active(false)

func set_gameplay_active(active: bool) -> void:
	_gameplay_active = active
	set_process_unhandled_input(active)
	set_process(active)
	set_physics_process(active)
	if active:
		timer_reset()
		_update_destination_view()
	else:
		## 离场时只清空状态，不通知已退出场景树的节点。
		looking_at_destination = false
		dialogue_active = false
		timer.stop()
		PhysicsServer2D.set_active(true)

## 全局界面输入不受玩法开关、对话或观察目标的输入锁影响。
func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	## 松键也通知界面；即使已进入转场，也要结束此前的蓄力。
	if event.is_action_released("back"):
		get_viewport().set_input_as_handled()
		back_released.emit()
	elif not SceneTransition.busy and event.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		back_pressed.emit()

## 玩法输入判定与信号触发
func _unhandled_input(event: InputEvent) -> void:
	_update_destination_view()
	if get_tree().paused or SceneTransition.busy:
		return
	if dialogue_active:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			get_viewport().set_input_as_handled()
			dialogue_advance.emit()
		return
	if looking_at_destination or Global.goal.completed:
		return
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
		var previous: LayerObject = Global.object_selected
		if previous:
			previous.set_pick_condition(false)
		Global.object_selected = best
		if Global.object_selected:
			Global.object_selected.set_pick_condition(true)
			if Global.object_selected != previous:
				SoundPlayer.play(&"select")

func _process(_delta: float) -> void:
	if get_tree().paused:
		return
	_update_destination_view()
	## 对话和观察目标只锁定玩家操作，期间仍保持世界物理与 Bot 巡逻运行。
	if dialogue_active or looking_at_destination or Global.object_selected:
		timer_reset()

func _physics_process(_delta: float) -> void:
	## 恢复暂停后的首个物理帧，先同步 Shift，再更新玩家。
	_update_destination_view()

func _update_destination_view() -> void:
	if not _gameplay_active or get_tree().paused:
		return
	var active: bool = (
		not dialogue_active
		and Input.is_action_pressed("look_at_destination")
		and _is_destination_key_pressed()
		and not Global.goal.completed
	)
	if active == looking_at_destination:
		return
	looking_at_destination = active
	## 观察切换也属于玩家操作，长按进入休息后松开时重新唤醒游戏。
	timer_reset()
	if active:
		SoundPlayer.play_for(&"destination", &"destination_in")
	else:
		SoundPlayer.stop(&"destination")
	destination_view_changed.emit(active)

func _is_destination_key_pressed() -> bool:
	## 左右键位置不匹配的松键事件可能留下动作状态，需同时核对实际按键。
	for event in InputMap.action_get_events("look_at_destination"):
		if event is InputEventKey:
			if event.physical_keycode != 0:
				if Input.is_physical_key_pressed(event.physical_keycode):
					return true
			elif Input.is_key_pressed(event.keycode):
				return true
	return false

func _timer_trigger() -> void:
	if dialogue_active or looking_at_destination:
		timer_reset()
		return
	if not is_physics_resting():
		return
	PhysicsServer2D.set_active(false)
	shadow_boolean.emit()

## Player 始终跟随计时器休息，只有夜间影子关卡需要同时冻结物理世界。
func is_physics_resting() -> bool:
	return is_instance_valid(Global.level) and Global.level.is_night and timer != null and timer.is_stopped()

func timer_reset() -> void:
	if timer.is_stopped():
		PhysicsServer2D.set_active(true)
	timer.start()

func set_dialogue_active(active: bool) -> void:
	dialogue_active = active
	if _gameplay_active:
		timer_reset()
		_update_destination_view()
