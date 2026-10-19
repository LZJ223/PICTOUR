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
	_check(data is Array and data.size() == 12, "磁盘数据恰好是十二个元素的数组")
	return data if data is Array else []

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
		_finish()
		return
	_check(FileAccess.file_exists(SaveSystem.SAVE_PATH), "首次启动自动创建存档")
	_check_progress([])
	_check(SaveSystem.complete_level(1) == OK, "第一关可以写入")
	_check_progress([1])
	_check(SaveSystem.complete_level(6) == OK, "完成第六关保留此前进度")
	_check(SaveSystem.complete_level(6) == OK, "重复通关可以安全保存")
	_check(SaveSystem.complete_level(0) == ERR_INVALID_PARAMETER, "拒绝编号 0")
	_check(SaveSystem.complete_level(13) == ERR_INVALID_PARAMETER, "拒绝编号 13")
	_check(not SaveSystem.is_level_completed(0) and not SaveSystem.is_level_completed(13), "越界查询不会越界访问数组")
	_check(SaveSystem.load_progress() == OK, "已有存档可以重新读取")
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
	_finish()

func _finish() -> void:
	print("SAVE_SYSTEM_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
