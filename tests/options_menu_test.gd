## 使用隔离存档验证游戏设置、长按重置、界面反馈和导航。
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

func _move(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)

func _click(control: Control) -> void:
	var point := control.get_global_transform_with_canvas() * (control.size * 0.5)
	_move(point)
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

func _bus_matches(bus_name: String, percent: float) -> bool:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return false
	return is_equal_approx(AudioServer.get_bus_volume_db(index), linear_to_db(percent / 100.0))

func _snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_viewport().get_texture().get_image().save_png(OUTPUT + name + ".png")

func _key_text(button: Button) -> String:
	return (button.get_node("Text") as Label).text

func _sample_clear_motion(options: Control) -> float:
	var visual: Control = options.get_node("Content/Game/Clear/Action/VisualRoot")
	var origin: Vector2 = options._clear_visual_position
	var amplitude: float = 0.0
	for frame in 12:
		await get_tree().process_frame
		amplitude = maxf(amplitude, visual.position.distance_to(origin))
	return amplitude

func _run() -> void:
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
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
	_check(options.find_children("*", "Container", true, false).is_empty(), "设置界面全部使用可手调位置的 Control")
	_check(not options.has_node("Hint"), "移除底部测试说明")
	for page_name in ["Game", "Audio", "Control"]:
		_check(not options.get_node("Content/" + page_name).has_node("Title"), "子菜单不再显示标题")
	_select(options, 0)
	_click(options.get_node("SideBar/Game"))
	await _frames()
	_check(options.get_node("SideBar/Game").button_pressed, "再次点击已选中的侧栏不会取消唯一选中状态")
	_check(not options.get_node("Content/Game/Fullscreen/Toggle").button_pressed, "全屏默认关闭")
	_check(not options.get_node("Content/Game/Dialogue/Toggle").button_pressed, "跳过对话默认关闭")
	_check(options.get_node("Content/Game/Progress/Toggle").button_pressed, "进度限制默认开启")
	_check(options.get_node("Content/Game/Dialogue/Label").text == "跳过对话" and options.get_node("Content/Game/Progress/Label").text == "进度限制", "显示新的选项名称")
	for entry: String in ["Fullscreen", "Dialogue", "Progress"]:
		var checkbox: CheckBox = options.get_node("Content/Game/" + entry + "/Toggle")
		var previous := checkbox.button_pressed
		_click(checkbox)
		await _frames()
		_check(checkbox.button_pressed != previous, "复选框可通过真实鼠标事件切换")
		if entry == "Fullscreen":
			_check(SaveSystem.fullscreen, "全屏选项立即保存")
			if DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor():
				_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "全屏复选框立即切换实际窗口模式")
			_click(checkbox)
			await _frames()
			_check(not SaveSystem.fullscreen, "取消全屏同样保存")
			if DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor():
				_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "取消全屏恢复窗口模式")
	_check(SaveSystem.skip_dialogue and not SaveSystem.progress_limit_enabled, "两项偏好连接到存档系统")
	_check(SaveSystem.load_progress() == OK and SaveSystem.skip_dialogue and not SaveSystem.progress_limit_enabled, "重新读取保留偏好")
	var mirror := load("res://Interface/UI/Options.tscn").instantiate() as Control
	mirror.hide()
	add_child(mirror)
	_check(mirror.get_node("Content/Game/Dialogue/Toggle").button_pressed and not mirror.get_node("Content/Game/Progress/Toggle").button_pressed, "新建设置界面从存档同步选中状态")
	SaveSystem.set_preference("skip_dialogue", false)
	_check(not options.get_node("Content/Game/Dialogue/Toggle").button_pressed and not mirror.get_node("Content/Game/Dialogue/Toggle").button_pressed, "多个设置实例同步更新且不递归写盘")
	SaveSystem.set_preference("skip_dialogue", true)
	mirror.queue_free()
	_check(options.get_node("Content/Game/Fullscreen/Label").get_theme_font("font").resource_path == "res://Font/WenYuanRoundedSC-Regular.ttf", "子菜单使用指定中文字体")
	await _snapshot("game")
	var clear: Button = options.get_node("Content/Game/Clear/Action")
	var clear_transform := clear.get_transform()
	_check(clear.text.is_empty() and clear.get_node("VisualRoot/Text").text.is_empty(), "重置按钮不显示文字")
	SaveSystem.complete_level(6)
	clear.button_down.emit()
	await _wait(0.12)
	var early_motion := await _sample_clear_motion(options)
	_check(options._clear_timer.wait_time == 5.0 and options._clear_progress.value > 0.0, "清除按钮保留蓄力时长并显示实时进度")
	_check(early_motion > 0.0 and clear.get_transform().is_equal_approx(clear_transform), "仅按钮可见部分抖动，点击区域保持不动")
	_check(options._clear_progress.get_parent() == options._clear_visual and options._clear_progress.get_rect().end.is_equal_approx(options._clear_visual.size - Vector2(2, 2)), "绿色填充位于按钮内部并跟随按钮视觉部分")
	clear.button_up.emit()
	_check(options._clear_timer.is_stopped() and not options._clear_progress.visible, "提前松开取消长按并清空进度")
	_check(SaveSystem.is_level_completed(6), "提前松开不会重置存档")
	_check(options._clear_visual.position == options._clear_visual_position and is_zero_approx(options._clear_visual.rotation), "松开按钮恢复原始位置与旋转")
	clear.button_down.emit()
	await _wait(4.0)
	var late_motion := await _sample_clear_motion(options)
	_check(late_motion > early_motion * 2.0, "蓄力后期抖动强度明显增加")
	await _snapshot("clear_hold")
	await _wait(1.0)
	_check(is_equal_approx(options._clear_progress.value, 1.0) and not options.is_processing(), "蓄满后停止抖动并保持满条")
	_check(clear.text.is_empty() and clear.get_node("VisualRoot/Text").text.is_empty(), "蓄满后按钮仍不显示文字")
	for level_id in range(1, 13):
		_check(not SaveSystem.is_level_completed(level_id), "蓄满后清空关卡 %d 的通关记录" % level_id)
	_check(SaveSystem.load_progress() == OK and not SaveSystem.is_level_completed(6), "重置实际写盘")
	_check(SaveSystem.skip_dialogue and not SaveSystem.progress_limit_enabled, "重置保留用户偏好")
	clear.button_up.emit()
	clear.button_down.emit()
	await _wait(0.04)
	get_window().focus_exited.emit()
	_check(options._clear_timer.is_stopped() and not options._clear_progress.visible, "失焦取消蓄力")
	_select(options, 1)
	await _frames()
	var master: HSlider = options.get_node("Content/Audio/Master/Slider")
	_click(master)
	await _frames()
	_check(master.value > 40.0 and master.value < 60.0, "滑条可通过真实鼠标点击调整")
	var audio_index: int = 0
	for row in options.get_node("Content/Audio").get_children():
		if row.has_node("Slider"):
			audio_index += 1
			var slider: HSlider = row.get_node("Slider")
			slider.value = audio_index * 17
			_check(row.get_node("Value").text == "%d%%" % (audio_index * 17), "滑条即时显示百分数")
	_check(audio_index == 4, "音频子菜单包含四个滑条")
	_check(_bus_matches("Master", 17.0), "主音量滑条改变主总线")
	_check(_bus_matches("Music", 34.0), "音乐滑条改变音乐总线")
	_check(_bus_matches("SFX", 51.0), "音效滑条改变音效总线")
	_check(_bus_matches("Ambient", 68.0), "环境音滑条改变环境音总线")
	await _snapshot("audio")
	var sidebar: Button = options.get_node("SideBar/Audio")
	var text: Label = sidebar.get_node("Text")
	_move(Vector2(4, 4))
	await _wait(0.15)
	var original_scale := text.scale
	_move(sidebar.get_global_transform_with_canvas() * (sidebar.size * 0.5))
	await _wait(0.15)
	await _frames(2)
	_check(text.scale.is_equal_approx(original_scale * 1.06) and is_zero_approx(text.rotation), "已选中侧栏文字悬停只放大、不旋转")
	_move(Vector2(4, 4))
	await _wait(0.15)
	await _frames(2)
	_check(text.scale.is_equal_approx(original_scale), "移出后恢复原始文字缩放")
	sidebar = options.get_node("SideBar/Game")
	text = sidebar.get_node("Text")
	_move(sidebar.get_global_transform_with_canvas() * (sidebar.size * 0.5))
	await _wait(0.15)
	await _frames(2)
	_check(text.scale.is_equal_approx(Vector2.ONE * 1.06) and is_zero_approx(text.rotation), "未选中侧栏文字也可悬停放大")
	_move(Vector2(4, 4))
	_select(options, 2)
	await _frames()
	var key_rows := options.get_node("Content/Control").get_children().filter(func(child: Node) -> bool: return child.has_node("Key"))
	_check(key_rows.size() == 9, "控件菜单保留九项自定义按键")
	var column_positions: Dictionary = {}
	var row_positions: Dictionary = {}
	var cells: Dictionary = {}
	for row: Control in key_rows:
		column_positions[row.position.x] = true
		row_positions[row.position.y] = true
		cells[row.position] = true
		var button: Button = row.get_node("Key")
		_check(button.get_meta(&"action") != &"back", "Esc 不作为可自定义按键")
		_check(button.text.is_empty() and button.has_node("Text"), "按键文字使用按钮下独立的 Label")
	_check(column_positions.size() == 2 and row_positions.size() == 5 and cells.size() == 9, "九项控件排列为两列五行")
	var key_button: Button = options.get_node("Content/Control/Up/Key")
	_check(_key_text(key_button) == "W", "初始键位从 InputMap 读取")
	_click(key_button)
	await _frames()
	_check(options._listening_button == key_button and _key_text(key_button).is_empty() and key_button.text.is_empty() and options._binding_hint.visible and options._binding_hint.text == "请输入按键...", "真实点击进入键盘监听")
	_key(KEY_K, true, true)
	await _frames()
	_check(options._listening_button == key_button and _key_text(key_button).is_empty(), "按键重复不结束监听")
	await _snapshot("control_listening")
	_key(KEY_K)
	_key(KEY_K, false)
	await _frames()
	_check(options._listening_button == null and _key_text(key_button) == "K" and not options._binding_hint.visible, "下一个键盘按键更新 Label 并收起输入提示")
	_check((InputMap.action_get_events(&"move_up")[0] as InputEventKey).physical_keycode == KEY_K, "界面改键立即更新实际 InputMap")
	_check(SaveSystem.load_progress() == OK and SaveSystem.get_key_binding(&"move_up").physical_keycode == KEY_K, "界面改键实际保存到存档")
	var key_mirror := load("res://Interface/UI/Options.tscn").instantiate() as Control
	key_mirror.hide()
	add_child(key_mirror)
	_check(_key_text(key_mirror.get_node("Content/Control/Up/Key")) == "K", "新建设置界面显示自定义键位")
	_click(options.get_node("Content/Control/Down/Key"))
	_key(KEY_K)
	_key(KEY_K, false)
	await _frames()
	_check(_key_text(key_button) == "S" and _key_text(options.get_node("Content/Control/Down/Key")) == "K", "真实改键冲突时交换两项键位")
	_check(_key_text(key_mirror.get_node("Content/Control/Up/Key")) == "S", "其他设置实例同步显示交换后的键位")
	_click(options.get_node("Content/Control/Down/Key"))
	_key(KEY_S)
	_key(KEY_S, false)
	await _frames()
	key_mirror.queue_free()
	_click(key_button)
	await _frames()
	(options.get_node("SideBar/Game") as Button).button_pressed = true
	_check(options._listening_button == null and _key_text(key_button) == "K", "切换子菜单取消监听并恢复原文字")
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
	_check(options.get_node("Content/Game").visible and _key_text(key_button) == "K", "重开设置默认显示游戏页并保留保存的键位")
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
	_check(options.get_node("Content/Game/Dialogue/Toggle").button_pressed and not options.get_node("Content/Game/Progress/Toggle").button_pressed, "暂停菜单读取主菜单保存的偏好")
	var player_position: Vector2 = Global.player.position
	var time_left: float = SignalSystem.timer.time_left
	SaveSystem.complete_level(3)
	options.clear_hold_duration = 0.1
	clear = options.get_node("Content/Game/Clear/Action")
	clear.button_down.emit()
	await _wait(0.2)
	_check(not SaveSystem.is_level_completed(3) and get_tree().paused and is_instance_valid(Global.level), "暂停中蓄满可重置进度，保持当前关卡和暂停状态")
	_check(Global.player.position == player_position and is_equal_approx(SignalSystem.timer.time_left, time_left), "重置过程中玩家和计时器保持冻结")
	clear.button_up.emit()
	_select(options, 2)
	await _frames()
	key_button = options.get_node("Content/Control/Up/Key")
	_check(_key_text(key_button) == "K", "暂停菜单读取主菜单保存的键位")
	_click(key_button)
	await _frames()
	_key(KEY_J)
	_key(KEY_J, false)
	await _frames()
	_check(_key_text(key_button) == "J", "暂停期间仍可监听并显示新按键")
	_check(Global.player.position == player_position and is_equal_approx(SignalSystem.timer.time_left, time_left), "交互期间玩家和游戏计时器保持冻结")
	await _snapshot("paused_control")
	_click(key_button)
	await _frames()
	_escape()
	await _frames()
	_check(not options.visible and pause.visible and pause.get_node("Continue").visible and get_tree().paused, "监听期间 Esc 只退回暂停菜单，不恢复游戏")
	_check(options._listening_button == null and _key_text(key_button) == "J", "关闭时正确清理监听")
	_click(pause.get_node("Options"))
	await _frames()
	_check(options.visible, "暂停菜单可以重复打开设置")
	_click(back)
	await _frames()
	_check(not options.visible and pause.visible and get_tree().paused, "Back 在设置层上方可真实点击，返回暂停菜单且不恢复游戏")
	_escape()
	await _frames()
	_check(not pause.visible and not get_tree().paused, "再次 Esc 正常恢复游戏")
	_check((InputMap.action_get_events(&"move_up")[0] as InputEventKey).physical_keycode == KEY_J, "暂停中改键同样应用到实际操作")
	game.queue_free()
	await _frames()
	print("OPTIONS_MENU_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
