## 在隔离的用户目录中运行；使用真实主菜单、鼠标事件和转场验证选关。
extends Node

const OUTPUT := "res://.godot/levels_menu_qa/"
var _checks: int = 0
var _failures: Array[String] = []
var _requests: Array[int] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("LEVELS_MENU_TEST: " + message)

func _frames(count: int = 3) -> void:
	for frame in count:
		await get_tree().process_frame

func _wait(seconds: float = 0.15) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)

func _center(button: Control) -> Vector2:
	return button.get_global_transform_with_canvas() * (button.size * 0.5)

func _click(button: Control) -> void:
	var point := _center(button)
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

func _fixture(completed: Array[int]) -> void:
	var values: Array[bool] = []
	for level_id in range(1, 13):
		values.append(completed.has(level_id))
	var file := FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(values))
	file.close()
	_check(SaveSystem.load_progress() == OK, "测试进度可以从磁盘读取")

func _snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_viewport().get_texture().get_image().save_png(OUTPUT + name + ".png")

func _run() -> void:
	_fixture([])
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	var menu := load("res://Interface/Main.tscn").instantiate() as Node2D
	get_tree().root.add_child(menu)
	get_tree().current_scene = menu
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	await _wait(0.35)
	var levels: Control = menu.get_node("LevelSelection")
	_check(levels.scene_file_path == "res://Interface/UI/Levels.tscn", "Main 实例化用户搭建的选关场景")
	var buttons := levels.get_node("OptionsInterface/Level").get_children()
	_check(buttons.size() == 12, "场景包含十二个关卡按钮")
	levels.level_selected.connect(func(level_id: int) -> void: _requests.append(level_id))
	_click(menu.get_node("MainMenu/LevelSelection"))
	await _wait(0.55)
	_check(levels.is_visible_in_tree(), "主菜单按钮打开新选关界面")
	for index in 12:
		var button: Button = buttons[index]
		_check(button.get_meta(&"level_id") == index + 1, "按钮对应关卡 %d" % (index + 1))
		var expected := "Leve_Unlock.png" if index == 0 else "Level_Lock.png"
		_check(button.get_node("LevelIconBackground").texture.resource_path.ends_with(expected), "初始背景对应解锁状态")
		_check(button.disabled == (index != 0), "初始仅第一关可点击")
		_check(button.get_node("LevelIcon").texture.resource_path.ends_with("Level_Icon_%02d.png" % (index + 1)), "保留用户的关卡图标")
	_move(Vector2(3, 3))
	await _wait()
	_snapshot("01_initial")
	var first: Button = buttons[0]
	var background: Sprite2D = first.get_node("LevelIconBackground")
	var icon: Sprite2D = first.get_node("LevelIcon")
	var button_transform := first.get_transform()
	var background_transform := background.transform
	var icon_transform := icon.transform
	_move(_center(first))
	await _wait()
	_check(background.scale.is_equal_approx(background_transform.get_scale() * 1.06), "真实悬停放大背景")
	_check(icon.scale.is_equal_approx(icon_transform.get_scale() * 1.06), "图标与背景同步放大")
	_check(is_equal_approx(background.rotation, icon.rotation) and not is_zero_approx(icon.rotation), "两张贴图使用同一个随机倾斜角")
	_check(absf(icon.rotation) <= deg_to_rad(4.0) + 0.0001, "随机倾斜幅度不超过四度")
	_check(first.get_transform().is_equal_approx(button_transform), "悬停保持按钮位置、缩放和命中范围")
	_snapshot("02_hover")
	_move(Vector2(3, 3))
	await _wait()
	_check(background.transform.is_equal_approx(background_transform) and icon.transform.is_equal_approx(icon_transform), "移出后恢复原始外观")
	for index in 4:
		_move(_center(first))
		await _frames(1)
		_move(Vector2(3, 3))
		await _frames(1)
	await _wait()
	_check(background.transform.is_equal_approx(background_transform) and icon.transform.is_equal_approx(icon_transform), "快速反复悬停不会累计变换")
	var locked: Button = buttons[1]
	var locked_icon: Sprite2D = locked.get_node("LevelIcon")
	var locked_background: Sprite2D = locked.get_node("LevelIconBackground")
	var locked_transform := locked_icon.transform
	var locked_background_transform := locked_background.transform
	_move(_center(locked))
	await _wait()
	_click(locked)
	await _frames()
	_check(locked_icon.transform == locked_transform and locked_background.transform == locked_background_transform, "锁定按钮悬停没有缩放或倾斜")
	_check(locked.modulate == Color.WHITE and locked.self_modulate == Color.WHITE, "锁定不额外调色或变暗")
	_check(_requests.is_empty() and not SceneTransition.busy and get_tree().current_scene == menu, "真实点击锁定按钮不发出关卡请求")
	_fixture([2, 6, 12])
	menu._show_page(menu.Page.MAIN)
	await _wait(0.5)
	_click(menu.get_node("MainMenu/LevelSelection"))
	await _wait(0.5)
	var expected_available := [1, 2, 3, 6, 7, 12]
	for index in 12:
		var button: Button = buttons[index]
		var expected := "Level_Completed.png" if [2, 6, 12].has(index + 1) else (
			"Leve_Unlock.png" if [1, 3, 7].has(index + 1) else "Level_Lock.png"
		)
		_check(button.get_node("LevelIconBackground").texture.resource_path.ends_with(expected), "再次打开按存档刷新关卡 %d 的背景" % (index + 1))
		_check(button.disabled == (not expected_available.has(index + 1)), "已完成关卡可重玩，仅解锁紧邻的下一关")
	_move(Vector2(3, 3))
	await _wait()
	_snapshot("03_progress")
	_move(_center(first))
	await _wait()
	get_window().focus_exited.emit()
	_check(background.transform.is_equal_approx(background_transform) and icon.transform.is_equal_approx(icon_transform), "窗口失焦清理悬停动效")
	_move(Vector2(3, 3))
	await _frames()
	_move(_center(first))
	await _frames(1)
	menu._show_page(menu.Page.MAIN)
	_check(background.transform.is_equal_approx(background_transform) and icon.transform.is_equal_approx(icon_transform), "关闭菜单即时清理未完成的悬停动效")
	await _wait(0.5)
	_click(menu.get_node("MainMenu/LevelSelection"))
	await _wait(0.5)
	get_tree().root.size = Vector2i(1100, 900)
	await _frames()
	_snapshot("04_tall_window")
	get_tree().root.size = Vector2i(1280, 720)
	await _frames()
	_click(buttons[11])
	_check(_requests == [12] and SceneTransition.busy, "已完成的第十二关通过真实点击发出正确关卡请求")
	await SceneTransition.transition_finished
	_check(is_instance_valid(Global.level) and Global.level.level_id == 12, "主菜单实际加载对应关卡")
	_check(await SceneTransition.enter_main_menu() == OK, "关卡返回主菜单正常")
	var reopened := get_tree().current_scene.get_node("LevelSelection/OptionsInterface/Level")
	_check(reopened.get_node("Level12/LevelIconBackground").texture.resource_path.ends_with("Level_Completed.png"), "重新创建主菜单仍读取保存的通关状态")
	print("LEVELS_MENU_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
