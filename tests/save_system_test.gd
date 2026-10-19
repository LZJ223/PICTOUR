## 使用隔离的用户目录运行；覆盖首次创建、累计保存、重新启动与真实 Goal 接入。
extends Node

var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("SAVE_SYSTEM_TEST: " + message)

func _read_saved() -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.SAVE_PATH))
	_check(data is Dictionary and data.get("completed_levels") is Array and data.completed_levels.size() == 12,
		"磁盘存档包含十二个通关布尔值")
	return data.completed_levels if data is Dictionary else []

func _check_preferences(fullscreen: bool, skip: bool, limit: bool) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.SAVE_PATH))
	_check(SaveSystem.fullscreen == fullscreen and data.preferences.fullscreen == fullscreen, "全屏偏好与磁盘一致")
	_check(SaveSystem.skip_dialogue == skip and data.preferences.skip_dialogue == skip, "跳过对话偏好与磁盘一致")
	_check(SaveSystem.progress_limit_enabled == limit and data.preferences.progress_limit_enabled == limit, "进度限制偏好与磁盘一致")

func _check_progress(expected: Array[int]) -> void:
	var saved := _read_saved()
	for index in 12:
		var completed := expected.has(index + 1)
		_check(SaveSystem.is_level_completed(index + 1) == completed, "关卡 %d 的内存状态正确" % (index + 1))
		_check(index < saved.size() and saved[index] is bool and saved[index] == completed,
			"关卡 %d 的磁盘状态为正确布尔值" % (index + 1))

func _run() -> void:
	if OS.get_cmdline_user_args().has("--verify-persisted"):
		_check_progress([1, 6, 12])
		_check_preferences(true, true, false)
		if DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor():
			_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "新进程启动时应用已保存的全屏偏好")
		_finish()
		return
	_check(FileAccess.file_exists(SaveSystem.SAVE_PATH), "首次启动自动创建存档")
	_check_progress([])
	_check_preferences(false, false, true)
	_check(SaveSystem.complete_level(1) == OK, "第一关可以写入")
	_check_progress([1])
	_check(SaveSystem.complete_level(6) == OK, "完成第六关保留此前进度")
	_check(SaveSystem.complete_level(6) == OK, "重复通关可以安全保存")
	_check(SaveSystem.complete_level(0) == ERR_INVALID_PARAMETER, "拒绝编号 0")
	_check(SaveSystem.complete_level(13) == ERR_INVALID_PARAMETER, "拒绝编号 13")
	_check(not SaveSystem.is_level_completed(0) and not SaveSystem.is_level_completed(13), "越界查询不会越界访问数组")
	_check(SaveSystem.load_progress() == OK, "已有存档可以重新读取")
	_check_progress([1, 6])
	var legacy: Array[bool] = []
	for level_id in range(1, 13):
		legacy.append(level_id == 1 or level_id == 6)
	var legacy_file := FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify(legacy))
	legacy_file.close()
	_check(SaveSystem.load_progress() == OK, "兼容并自动迁移旧十二布尔存档")
	_check_progress([1, 6])
	_check_preferences(false, false, true)
	_check(SaveSystem.set_preference("fullscreen", true) == OK, "保存全屏偏好")
	_check(SaveSystem.set_preference("skip_dialogue", true) == OK, "保存跳过对话偏好")
	_check(SaveSystem.set_preference("progress_limit_enabled", false) == OK, "保存进度限制偏好")
	_check(SaveSystem.set_preference("invalid", true) == ERR_INVALID_PARAMETER, "拒绝未知偏好名")
	_check_preferences(true, true, false)
	_check_progress([1, 6])
	var original := FileAccess.get_file_as_string(SaveSystem.SAVE_PATH)
	var file := FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
	file.store_string("[true]")
	file.close()
	_check(SaveSystem.load_progress() == ERR_FILE_CORRUPT, "拒绝长度错误的存档")
	_check(SaveSystem.is_level_completed(1) and SaveSystem.is_level_completed(6), "读取失败保留内存进度")
	file = FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
	file.store_string("[false,false,false,false,false,false,false,false,false,false,false,1]")
	file.close()
	_check(SaveSystem.load_progress() == ERR_FILE_CORRUPT, "拒绝非布尔值")
	var corrupt: Dictionary = JSON.parse_string(original)
	corrupt.preferences.skip_dialogue = 1
	file = FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(corrupt))
	file.close()
	_check(SaveSystem.load_progress() == ERR_FILE_CORRUPT, "拒绝非布尔偏好，保留内存状态")
	_check(SaveSystem.skip_dialogue and SaveSystem.is_level_completed(6), "损坏的偏好不会部分覆盖进度和偏好")
	_check(SaveSystem.reset_progress() == OK, "重置通关记录成功")
	_check_progress([])
	_check_preferences(true, true, false)
	file = FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
	file.store_string(original)
	file.close()
	_check(SaveSystem.load_progress() == OK, "恢复正常存档后可读取")
	_check_progress([1, 6])
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	SceneTransition.scene_ready()
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	Global.next_level_id = 12
	var game := load("res://Interface/Game.tscn").instantiate() as Node2D
	game.play_dialogue = false
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	Global.player.set_physics_process(false)
	var goal := Global.goal
	goal._on_body_entered(game)
	_check(not SaveSystem.is_level_completed(12), "普通物体触发 Goal 不记录通关")
	Global.player.current_state = PlayerController.PlayerState.UAV
	goal._on_body_entered(Global.player)
	_check(not SaveSystem.is_level_completed(12), "无人机触发 Goal 不记录通关")
	Global.player.current_state = PlayerController.PlayerState.NORMAL
	goal._on_body_entered(Global.player)
	_check(goal.completed, "正常玩家触发真实关卡 Goal")
	_check_progress([1, 6, 12])
	goal._on_body_entered(Global.player)
	await SceneTransition.transition_finished
	_check(get_tree().current_scene.scene_file_path == "res://Interface/Main.tscn", "第十二关通关后正常返回菜单")
	_check_progress([1, 6, 12])
	_check_preferences(true, true, false)
	_finish()

func _finish() -> void:
	print("SAVE_SYSTEM_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
