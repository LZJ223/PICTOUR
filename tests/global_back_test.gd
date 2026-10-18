## 全局返回输入与真实暂停菜单回归；不修改关卡资源。
extends Node

var _backs: int = 0
var _gameplay_events: int = 0
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("GLOBAL_BACK_TEST: " + message)

func _frames(count: int = 3) -> void:
	for index in count:
		await get_tree().process_frame

func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	if code == KEY_SHIFT:
		event.location = KEY_LOCATION_LEFT
	Input.parse_input_event(event)

func _escape() -> void:
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)

func _action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate() as InputEventAction
	event.pressed = false
	Input.parse_input_event(event)

func _run() -> void:
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	SignalSystem.back_pressed.connect(func() -> void: _backs += 1)
	SignalSystem.layer_cycle.connect(func(_direction: int, _check_collision: bool) -> void: _gameplay_events += 1)
	SignalSystem.layer_change.connect(func(_direction: int, _object: LayerObject) -> void: _gameplay_events += 1)
	SignalSystem.UAV_activate.connect(func() -> void: _gameplay_events += 1)
	_check(InputMap.has_action(&"back"), "返回键在项目 InputMap 中显式注册")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	_check(InputMap.action_has_event(&"back", escape), "返回动作绑定物理 Esc 键")
	_escape()
	await _frames()
	_check(_backs == 0, "初始黑幕期间不发出返回信号")
	SceneTransition.scene_ready()
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	_escape()
	await _frames()
	_check(_backs == 1 and not get_tree().paused, "未激活玩法时也能接收全局返回，不自行改变场景状态")
	_key(KEY_ESCAPE, true, true)
	_key(KEY_ESCAPE, false)
	await _frames()
	_check(_backs == 1, "长按产生的重复按键不重复触发")
	get_tree().paused = true
	_escape()
	await _frames()
	_check(_backs == 2 and get_tree().paused, "全局信号在场景暂停期间仍能发出")
	get_tree().paused = false
	var timeout := SignalSystem.timer.wait_time
	var game := load("res://Interface/Game.tscn").instantiate() as Node2D
	game.play_dialogue = false
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	await _frames()
	Global.player.set_physics_process(false)
	var pause := game.get_node("Camera/MenuUI/Screen/Pause") as Control
	_check(SignalSystem.back_pressed.get_connections().size() == 2, "当前暂停菜单只订阅一次全局返回")
	var before := _backs
	_escape()
	await _frames()
	_check(_backs == before + 1 and get_tree().paused and pause.visible, "Esc 通过全局信号打开暂停菜单，且只切换一次")
	_check(get_viewport().gui_get_focus_owner() == pause.get_node("Continue"), "暂停菜单仍获得按钮焦点")
	_key(KEY_ESCAPE, true, true)
	_key(KEY_ESCAPE, false)
	await _frames()
	_check(get_tree().paused and _backs == before + 1, "暂停菜单有焦点时，按键重复不会误恢复")
	for action: StringName in [&"forward", &"backward", &"UAV", &"select_object"]:
		_action(action)
	await _frames()
	_check(_gameplay_events == 0 and Global.object_selected == null, "暂停期间仍屏蔽换层、无人机及选取输入")
	SignalSystem.set_dialogue_active(true)
	SignalSystem.timer.start(4.0)
	var remaining := SignalSystem.timer.time_left
	var player_position := Global.player.position
	await _frames(10)
	_check(is_equal_approx(SignalSystem.timer.time_left, remaining), "全局输入持续运行，但活动倒计时在暂停期间冻结，也不会被对话重置")
	_check(Global.player.position == player_position, "暂停期间角色物理保持冻结")
	_escape()
	await _frames()
	_check(not get_tree().paused and not pause.visible and SignalSystem.dialogue_active, "暂停后 Esc 正常恢复，并保留对话输入锁")
	_escape()
	await _frames()
	_check(get_tree().paused and pause.visible, "对话锁定期间仍能用全局 Esc 暂停")
	_escape()
	await _frames()
	SignalSystem.timer.wait_time = timeout
	SignalSystem.set_dialogue_active(false)
	_key(KEY_SHIFT, true)
	await _frames()
	_check(SignalSystem.looking_at_destination, "正常进入观察目标状态")
	_escape()
	await _frames()
	_key(KEY_SHIFT, false)
	await _frames()
	_check(get_tree().paused and SignalSystem.looking_at_destination, "观察时可暂停，暂停期间不推进观察状态")
	_escape()
	await _frames()
	_check(not get_tree().paused and not SignalSystem.looking_at_destination, "暂停期间松开 Shift，Esc 恢复后正确解除观察")
	SceneTransition.busy = true
	before = _backs
	_escape()
	await _frames()
	_check(_backs == before and not pause.visible, "转场锁定期间 Esc 不触发返回或暂停")
	SceneTransition.busy = false
	(game.get_node("Camera/MenuUI/Screen/Back") as Button).pressed.emit()
	await _frames()
	_check(pause.visible and get_tree().paused, "游戏内 Back 按钮仍可打开暂停菜单")
	(pause.get_node("Continue") as Button).pressed.emit()
	await _frames()
	_check(not pause.visible and not get_tree().paused, "Continue 按钮仍可恢复游戏")
	pause.open()
	pause._begin_hold(pause.HoldAction.RESTART)
	pause._on_hold_timeout()
	await SceneTransition.transition_finished
	await _frames()
	game = get_tree().current_scene as Node2D
	pause = game.get_node("Camera/MenuUI/Screen/Pause") as Control
	_check(SignalSystem.back_pressed.get_connections().size() == 2, "重开后旧暂停菜单自动解除订阅，不重复响应")
	before = _backs
	_escape()
	await _frames()
	_check(_backs == before + 1 and pause.visible and get_tree().paused, "重开后 Esc 仍只打开一次新暂停菜单")
	_escape()
	await _frames()
	game.queue_free()
	await _frames()
	_check(SignalSystem.back_pressed.get_connections().size() == 1 and Global.player == null, "离场后没有残留暂停订阅或玩家引用")
	before = _backs
	_escape()
	await _frames()
	_check(_backs == before + 1 and not get_tree().paused, "离开关卡后，全局返回输入仍然可用")
	print("GLOBAL_BACK_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
