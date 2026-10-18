## 设置界面原型与导航回归：不修改实际配置、InputMap 或存档。
extends Node

const OUTPUT := "res://.godot/options_menu_qa/"
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("OPTIONS_MENU_TEST: " + message)

func _frames(count: int = 3) -> void:
	for frame in count:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _key(code: Key, pressed: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)

func _escape() -> void:
	_key(KEY_ESCAPE)
	_key(KEY_ESCAPE, false)

func _click(control: Control) -> void:
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	get_viewport().push_input(event, true)

func _select(options: Control, index: int) -> void:
	var tabs: Array[String] = ["Game", "Audio", "Control"]
	var button: Button = options.get_node("SideBar/" + tabs[index])
	button.button_pressed = true
	for tab_index in tabs.size():
		var tab: Button = options.get_node("SideBar/" + tabs[tab_index])
		_check(tab.button_pressed == (tab_index == index), "侧栏恰好只有一个按钮被按下")
		_check(options.get_node("Content/" + tabs[tab_index]).visible == (tab_index == index), "恰好只有对应的子菜单可见")
		var expected := "Button_Pressed.png" if tab_index == index else "Button_released.png"
		_check(tab.get_node("Icon").texture.resource_path.ends_with(expected), "侧栏纹理跟随选中状态")

func _snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_viewport().get_texture().get_image().save_png(OUTPUT + name + ".png")

func _run() -> void:
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	var window_mode := DisplayServer.window_get_mode()
	var original_volume := AudioServer.get_bus_volume_db(0)
	var original_key: InputEventKey = InputMap.action_get_events(&"move_up")[0].duplicate()
	var main := load("res://Interface/Main.tscn").instantiate() as Node2D
	get_tree().root.add_child(main)
	get_tree().current_scene = main
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	await _wait(0.35)
	(main.get_node("MainMenu/GameOption") as Button).pressed.emit()
	await _wait(0.5)
	var options: Control = main.get_node("GameOption")
	_check(options.is_visible_in_tree(), "主菜单设置按钮打开 Options 场景")
	_select(options, 0)
	_click(options.get_node("SideBar/Game"))
	await _frames()
	_check(options.get_node("SideBar/Game").button_pressed, "再次点击已选中的侧栏不会取消唯一选中状态")
	_check(not options.get_node("Content/Game/Fullscreen/Toggle").button_pressed, "全屏默认关闭")
	_check(options.get_node("Content/Game/Dialogue/Toggle").button_pressed, "教程／剧情对话默认开启")
	_check(not options.get_node("Content/Game/Progress/Toggle").button_pressed, "解除进度限制默认关闭")
	for entry: String in ["Fullscreen", "Dialogue", "Progress"]:
		var checkbox: CheckBox = options.get_node("Content/Game/" + entry + "/Toggle")
		var previous := checkbox.button_pressed
		_click(checkbox)
		await _frames()
		_check(checkbox.button_pressed != previous, "复选框可通过真实鼠标事件切换")
	_check(DisplayServer.window_get_mode() == window_mode, "全屏复选框不改变实际窗口模式")
	_check(options.get_node("Content/Game/Fullscreen/Label").get_theme_font("font").resource_path == "res://Font/WenYuanRoundedSC-Regular.ttf", "子菜单使用指定中文字体")
	await _snapshot("game")
	var clear: Button = options.get_node("Content/Game/Clear/Action")
	clear.button_down.emit()
	await _wait(0.12)
	_check(options._clear_timer.wait_time == 5.0 and options._clear_progress.value > 0.0, "清除按钮使用 5 秒计时并显示实时进度")
	clear.button_up.emit()
	_check(options._clear_timer.is_stopped() and not options._clear_progress.visible, "提前松开取消长按并清空进度")
	clear.button_down.emit()
	await _wait(5.1)
	_check(clear.text.contains("预览") and is_equal_approx(options._clear_progress.value, 1.0), "长按完成显示反馈而不清除存档")
	clear.button_up.emit()
	clear.button_down.emit()
	await _wait(0.04)
	get_window().focus_exited.emit()
	_check(options._clear_timer.is_stopped(), "失焦取消长按")
	_select(options, 1)
	await _frames()
	var master: HSlider = options.get_node("Content/Audio/Master/Slider")
	_click(master)
	await _frames()
	_check(master.value > 40.0 and master.value < 60.0, "滑条可通过真实鼠标点击调整")
	var audio_index: int = 0
	for row in options.get_node("Content/Audio").get_children():
		if row is HBoxContainer:
			audio_index += 1
			var slider: HSlider = row.get_node("Slider")
			slider.value = audio_index * 17
			_check(row.get_node("Value").text == "%d%%" % (audio_index * 17), "滑条即时显示百分数")
	_check(audio_index == 4, "音频子菜单包含四个滑条")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(0), original_volume), "滑条不改变实际音频总线")
	await _snapshot("audio")
	var sidebar: Button = options.get_node("SideBar/Audio")
	var text: Label = sidebar.get_node("Text")
	var original_scale := text.scale
	sidebar.mouse_entered.emit()
	await _wait(0.1)
	_check(text.scale.is_equal_approx(original_scale * 1.06) and is_zero_approx(text.rotation), "已选中侧栏文字悬停只放大、不旋转")
	sidebar.mouse_exited.emit()
	await _wait(0.1)
	_check(text.scale.is_equal_approx(original_scale), "移出后恢复原始文字缩放")
	sidebar = options.get_node("SideBar/Game")
	text = sidebar.get_node("Text")
	sidebar.mouse_entered.emit()
	await _wait(0.1)
	_check(text.scale.is_equal_approx(Vector2.ONE * 1.06) and is_zero_approx(text.rotation), "未选中侧栏文字也可悬停放大")
	sidebar.mouse_exited.emit()
	_select(options, 2)
	await _frames()
	var columns := options.get_node("Content/Control/Columns")
	_check(columns.get_child_count() == 2 and columns.get_child(0).get_child_count() == 5 and columns.get_child(1).get_child_count() == 5, "控件按两列每列五项排列")
	var key_button: Button = columns.get_node("Left/Up/Key")
	_check(key_button.text == "W", "初始键位从 InputMap 读取")
	_click(key_button)
	await _frames()
	_check(options._listening_button == key_button and key_button.text == "按键…", "真实点击进入键盘监听")
	_key(KEY_K, true, true)
	await _frames()
	_check(options._listening_button == key_button, "按键重复不结束监听")
	_key(KEY_K)
	_key(KEY_K, false)
	await _frames()
	_check(options._listening_button == null and key_button.text == "K", "下一个键盘按键更新界面键位")
	_check((InputMap.action_get_events(&"move_up")[0] as InputEventKey).physical_keycode == original_key.physical_keycode, "界面绑定不修改实际 InputMap")
	_click(key_button)
	await _frames()
	(options.get_node("SideBar/Game") as Button).button_pressed = true
	_check(options._listening_button == null and key_button.text == "K", "切换子菜单取消监听并恢复原文字")
	_select(options, 2)
	await _frames()
	await _snapshot("control")
	_click(key_button)
	await _frames()
	_escape()
	await _frames()
	_check(main._page == main.Page.MAIN and not options.visible and options._listening_button == null, "主菜单监听期间 Esc 仍能返回主菜单")
	_check(main._exit_timer.is_stopped(), "返回不会误启动长按退出")
	await _wait(0.5)
	main._show_page(main.Page.GAME_OPTION)
	await _wait(0.5)
	_check(options.get_node("Content/Game").visible and key_button.text == "K", "重开设置默认显示游戏页，保留本实例的预览状态")
	main.back_button.pressed.emit()
	await _wait(0.5)
	_check(main._page == main.Page.MAIN, "主菜单 Back 按钮可关闭设置")
	main.queue_free()
	await _frames()
	var game := load("res://Interface/Game.tscn").instantiate() as Node2D
	game.play_dialogue = false
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	await _frames()
	var pause: Control = game.get_node("Camera/MenuUI/Screen/Pause")
	var back: Button = game.get_node("Camera/MenuUI/Screen/Back")
	_escape()
	await _frames()
	_check(pause.visible and get_tree().paused, "Esc 打开暂停菜单")
	_check(not pause.get_node("Options").disabled, "暂停菜单设置按钮已开放")
	_click(pause.get_node("Options"))
	await _frames()
	options = pause.get_node("OptionsMenu")
	_check(options.is_visible_in_tree() and not pause.get_node("Continue").visible and get_tree().paused, "暂停设置替换四个按钮且保持游戏冻结")
	var player_position: Vector2 = Global.player.position
	var time_left: float = SignalSystem.timer.time_left
	_select(options, 2)
	await _frames()
	key_button = options.get_node("Content/Control/Columns/Left/Up/Key")
	_click(key_button)
	await _frames()
	_key(KEY_J)
	_key(KEY_J, false)
	await _frames()
	_check(key_button.text == "J", "暂停期间仍可监听并显示新按键")
	_check(Global.player.position == player_position and is_equal_approx(SignalSystem.timer.time_left, time_left), "交互期间玩家和游戏计时器保持冻结")
	await _snapshot("paused_control")
	_click(key_button)
	await _frames()
	_escape()
	await _frames()
	_check(not options.visible and pause.visible and pause.get_node("Continue").visible and get_tree().paused, "监听期间 Esc 只退回暂停菜单，不恢复游戏")
	_check(options._listening_button == null and key_button.text == "J", "关闭时正确清理监听")
	_click(pause.get_node("Options"))
	await _frames()
	_check(options.visible, "暂停菜单可以重复打开设置")
	_click(back)
	await _frames()
	_check(not options.visible and pause.visible and get_tree().paused, "Back 在设置层上方可真实点击，返回暂停菜单且不恢复游戏")
	_escape()
	await _frames()
	_check(not pause.visible and not get_tree().paused, "再次 Esc 正常恢复游戏")
	_check((InputMap.action_get_events(&"move_up")[0] as InputEventKey).physical_keycode == original_key.physical_keycode, "整个流程没有修改实际键位")
	game.queue_free()
	await _frames()
	print("OPTIONS_MENU_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
