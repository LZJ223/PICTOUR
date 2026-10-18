## 用真实 Esc 检查主菜单返回、蓄力与进度环；最后允许实际退出流程结束测试。
extends Node

var _menu: Node2D
var _button_events: int = 0
var _releases: int = 0
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("MAIN_BACK_TEST: " + message)

func _frames(count: int = 3) -> void:
	for index in count:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _key(pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _create_menu() -> void:
	_menu = load("res://Interface/Main.tscn").instantiate() as Node2D
	get_tree().root.add_child(_menu)
	get_tree().current_scene = _menu

func _run() -> void:
	SceneTransition.fade_in_duration = 0.04
	SceneTransition.fade_out_duration = 0.12
	SignalSystem.back_released.connect(func() -> void: _releases += 1)
	_create_menu()
	_key(true)
	await _frames(1)
	_check(_menu._exit_timer.is_stopped(), "初始黑幕不接受 Esc 蓄力")
	_key(false)
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	await _frames()
	for button_signal: Signal in [_menu.back_button.button_down, _menu.back_button.button_up, _menu.back_button.pressed]:
		button_signal.connect(func() -> void: _button_events += 1)
	for page: int in [_menu.Page.LEVEL_SELECTION, _menu.Page.GAME_OPTION]:
		_menu._show_page(page)
		await _wait(_menu.CAMERA_MOVE_DURATION + 0.02)
		_key(true)
		await _frames()
		_check(_menu._page == _menu.Page.MAIN and _menu.main_menu.visible, "次级菜单按 Esc 直接返回主菜单")
		await _wait(_menu.EXIT_HOLD_DURATION + 0.05)
		_check(_menu._exit_timer.is_stopped() and not _menu._back_key_held and not SceneTransition.busy, "返回时继续按住同一次 Esc 不会误蓄力退出")
		_key(false)
		await _frames()
	var button := _menu.back_button as Button
	_key(true)
	await _wait(0.25)
	await _frames()
	_check(_menu._back_key_held and not _menu._exit_timer.is_stopped(), "主菜单按住 Esc 启动原有一秒退出蓄力")
	_check(button._hold_timer == _menu._exit_timer and button._hold_progress > 0.15, "Esc 蓄力使用真实退出计时器显示进度环")
	_check(button._icon.position != button._base_position, "Esc 蓄力也播放图标抖动")
	_check(_button_events == 0 and not button.button_pressed, "Esc 直接走全局信号，没有模拟任何按钮事件")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var icon_size: Vector2 = button._icon_size * button._base_scale.abs() * button.hover_scale
		var radius: float = maxf(maxf(icon_size.x, icon_size.y), maxf(button.size.x, button.size.y)) * 0.5 + button.ring_padding
		var point: Vector2 = button.get_global_transform_with_canvas() * (button._base_position + Vector2.from_angle(-PI * 0.25) * radius)
		var color := image.get_pixel(roundi(point.x), roundi(point.y))
		_check(color.g > color.r + 0.15 and color.g > color.b + 0.1, "真实 GPU 画面中出现绿色蓄力圆弧")
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/main_back_qa"))
		image.save_png("res://.godot/main_back_qa/esc_hold.png")
	var remaining: float = _menu._exit_timer.time_left
	_key(true, true)
	await _frames()
	_check(_menu._exit_timer.time_left < remaining, "长按重复键不会重启蓄力计时")
	remaining = _menu._exit_timer.time_left
	button.mouse_exited.emit()
	await _frames()
	_check(not _menu._exit_timer.is_stopped() and _menu._exit_timer.time_left < remaining, "鼠标移出按钮不会取消键盘蓄力")
	_key(false)
	await _frames()
	_check(_menu._exit_timer.is_stopped() and button._hold_timer == null and is_zero_approx(button._hold_progress), "提前松开 Esc 取消退出并清空进度环")
	_check(not SceneTransition.busy, "未蓄满不会启动退出转场")
	_key(true)
	await _wait(0.08)
	get_window().focus_exited.emit()
	await _frames()
	_check(_menu._exit_timer.is_stopped() and not _menu._back_key_held and button._hold_timer == null, "窗口失焦取消键盘蓄力及视觉效果")
	_key(false)
	await _frames()
	_key(true)
	await _wait(0.08)
	SceneTransition.busy = true
	var releases_before := _releases
	_key(false)
	await _frames()
	_check(_releases == releases_before + 1 and _menu._exit_timer.is_stopped(), "转场期间仍收到松键信号，正确清理此前蓄力")
	_key(true)
	await _frames()
	_check(_menu._exit_timer.is_stopped(), "转场期间不能开始新的退出蓄力")
	_key(false)
	SceneTransition.busy = false
	await _frames()
	_key(true)
	await _wait(0.08)
	button.button_down.emit()
	await _frames()
	_key(false)
	await _frames()
	_check(not _menu._exit_timer.is_stopped() and _menu._back_held, "键盘松开但鼠标仍按住时继续蓄力")
	button.button_up.emit()
	await _frames()
	_check(_menu._exit_timer.is_stopped(), "两个输入源均释放后取消蓄力")
	button.button_down.emit()
	await _wait(0.08)
	_key(true)
	button.mouse_exited.emit()
	await _frames()
	_check(not _menu._exit_timer.is_stopped() and _menu._back_key_held, "鼠标先按住再离开时，仍按住的键盘能接续蓄力")
	_key(false)
	await _frames()
	_key(true)
	await _wait(0.08)
	_menu._show_page(_menu.Page.LEVEL_SELECTION)
	await _frames()
	_check(_menu._exit_timer.is_stopped() and not _menu._back_key_held, "切换菜单页面会清空蓄力状态")
	_key(false)
	_menu.queue_free()
	await _frames()
	_check(SignalSystem.back_pressed.get_connections().is_empty() and SignalSystem.back_released.get_connections().size() == 1, "主菜单离场后解除按下和松开订阅")
	var game := load("res://Interface/Game.tscn").instantiate() as Node2D
	game.play_dialogue = false
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	await _frames()
	_key(true)
	_key(false)
	await _frames()
	_check(get_tree().paused and game.get_node("Camera/MenuUI/Screen/Pause").visible, "离开菜单进入游戏后 Esc 仅控制暂停")
	_key(true)
	_key(false)
	await _frames()
	game.queue_free()
	await _frames()
	_create_menu()
	await _frames()
	_check(SignalSystem.back_pressed.get_connections().size() == 1, "再次进入主菜单没有残留暂停订阅")
	# 最后一次真的长按到完成，允许 SceneTransition 的黑屏退出结束进程。
	_menu._exit_timer.timeout.connect(_finish, CONNECT_ONE_SHOT)
	_key(true)
	await _wait(_menu.EXIT_HOLD_DURATION * 0.65)
	_check(not SceneTransition.busy and _menu.back_button._hold_progress > 0.5, "最后一次蓄力未满时仍留在菜单并显示过半进度")
	await _wait(_menu.EXIT_HOLD_DURATION + 0.5)
	_check(false, "蓄力完成后应已通过真实退出流程结束进程")
	_print_result()
	get_tree().quit(1)

func _finish() -> void:
	_check(SceneTransition.busy and get_tree().paused, "长按 Esc 蓄满后启动真实黑屏退出流程")
	_check(_menu._exit_timer.is_stopped() and _menu.back_button._hold_timer == null, "完成后清空蓄力，不重复退出")
	_print_result()
	if not _failures.is_empty():
		get_tree().quit(1)

func _print_result() -> void:
	print("MAIN_BACK_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
