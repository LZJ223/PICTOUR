extends Node2D
## Story替换V6后的近距离R/M复位检查，专用存档在进入树前覆盖。

const SAVE_PATH := "user://Tests/Study_Transfer_V6_Bookmark.json"
var game: Node2D
var player: PlayerController
var manager: BookmarkManager
var visual: Node2D
var scarf: Node2D
var checks := 0
var failures := 0
var origin := Vector2.ZERO
var _restore_label := ""
var _restore_callbacks := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("V6_BOOKMARK: " + message)


func _wait(count := 2) -> void:
	for tick in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _run() -> void:
	_clean()
	game = (load("res://Story_Garden_Game.tscn") as PackedScene).instantiate()
	game.get_node("Level").set("save_path", SAVE_PATH)
	add_child(game)
	await _wait(20)
	player = game.get_node("Player") as PlayerController
	manager = game.get_node("Level").get("bookmarks")
	visual = player.get_node("Visual_Body/Traveler")
	scarf = player.get_node("Visual_Body/Scarf")
	manager.restored.connect(_on_restored)
	_check(visual.get_script().resource_path == "res://Component/Player/V6/Traveler_V6_Visual.gd", "实际Story使用V6分件视觉")
	_check(manager.save_path == SAVE_PATH and FileAccess.file_exists(SAVE_PATH), "实际书签使用隔离存档")
	origin = manager._bookmarks[0].position
	await _depart_near()
	_restore_label = "R"
	_key(KEY_R, true)
	await _wait(2)
	_key(KEY_R, false)
	_check(_restore_callbacks == 1, "实际R触发书签恢复回调")
	await _wait(4)
	_check(player.is_on_floor(), "近距R后真实站稳")
	await _depart_near()
	_key(KEY_M, true)
	await _wait(2)
	_key(KEY_M, false)
	_check(manager.map_open and not player.activated, "实际M展开地图并冻结输入")
	await _wait(2)
	var button := manager._map_entries.get_child(0) as Button
	_check(not button.disabled, "起点地图按钮已解锁")
	_restore_label = "地图返回"
	button.pressed.emit()
	_check(_restore_callbacks == 2, "地图按钮触发第二次恢复回调")
	_check(not manager.map_open and player.activated, "地图返回后恢复控制")
	await _wait(4)
	_check(player.is_on_floor(), "近距地图返回后真实站稳")
	game.queue_free()
	await _wait(3)
	_clean()
	_check(not FileAccess.file_exists(SAVE_PATH) and not FileAccess.file_exists(SAVE_PATH + ".tmp"), "已清理本测试专用存档")
	print("V6_BOOKMARK: %d checks, %d failures." % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _depart_near() -> void:
	Input.action_press("move_right")
	await _wait(13)
	Input.action_release("move_right")
	await _wait(8)
	var distance := player.position.distance_to(origin)
	_check(distance > 15 and distance < 100, "测试位移确实小于角色自动传送清理阈值")
	# 输入方向已经变左、身体仍在向右的瞬间，控制器朝向可能先于视觉改变。
	player.facing_direction = -1
	visual.set("visual_facing", 1)


func _check_restored(label: String) -> void:
	_check(player.position.distance_to(origin) < 0.25 and player.velocity == Vector2.ZERO, label + "当帧回到书签并清除惯性")
	var gait: RefCounted = visual.get("_gait")
	var feet: PackedVector2Array = gait.get("world_feet")
	_check(feet[0].distance_to(player.position) < 22 and feet[1].distance_to(player.position) < 22, label + "立即重建世界脚锚")
	_check(visual.get("pose") == visual.get("previous_pose"), label + "立即重建新旧姿态，不跨旧位置插值")
	_check(int(visual.get("visual_facing")) == player.facing_direction, label + "立即对齐控制器朝向")
	_check(Vector2(scarf.get("_last_origin")).is_equal_approx(player.global_position), label + "围巾使用新位置重新展开")


func _on_restored(_bookmark_id: int) -> void:
	_restore_callbacks += 1
	# 书签恢复信号在_teleport之后同一调用触发，检查真正的恢复当帧。
	_check_restored(_restore_label)


func _clean() -> void:
	for suffix in ["", ".tmp"]:
		var path: String = SAVE_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
