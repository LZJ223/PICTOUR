extends Node
## 新地图真实V7近距离恢复。只用本场景的内存历史，不写玩家存档。
var game: Node2D
var checks := 0
var failures := 0

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ILLUSTRATED_RESTORE: " + message)

func _ticks(count: int) -> void:
	for tick in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _walk_near(player: PlayerController) -> void:
	var before := player.position
	Input.action_press("move_right")
	await _ticks(9)
	Input.action_release("move_right")
	await _ticks(6)
	_check(player.position.distance_to(before) > 10 and player.position.distance_to(before) < 100, "实际输入移动小于自动传送阈值")

func _restored_visual(player: PlayerController, label: String) -> void:
	var visual := player.get_node("Visual_Body/Traveler")
	var scarf := player.get_node("Visual_Body/Scarf")
	_check(visual.get_script().resource_path.ends_with("/V7/Traveler_V7_Visual.gd"), label + "使用正式V7而非旧私有足锚实现")
	_check(visual.pose == visual.previous_pose, label + "立即同步前后绘图姿态，避免插值拉回")
	_check(Vector2(visual.get("_last_position")).is_equal_approx(player.global_position), label + "位移缓存立即重置为恢复站位")
	_check(scarf.get("_points") == scarf.get("_previous_points"), label + "围巾前后绘图历史立即一致")
	_check(scarf.get_ribbon_points().size() == 25, label + "围巾保持完整曲面")

func _run() -> void:
	game = (load("res://Illustrated_Garden_Game.tscn") as PackedScene).instantiate()
	add_child(game)
	await _ticks(20)
	var player := game.get_node("Player") as PlayerController
	var system := game.get_node("System") as StudySystemController
	var plant := game.get_node("Level/Mid/StartBell") as LayerObject
	_check(player.is_on_floor(), "默认地图出生点真实落地")
	var origin := player.position
	_check(system.transfer(-1, plant), "真实可搬花草退到背景并记录完整历史")
	await _walk_near(player)
	_check(system.undo_transfer(), "实际整套换层历史可撤回")
	_check(player.position.distance_to(origin) < 0.1 and plant.owner_layer.slot == 0, "撤回同时恢复人物与物件")
	_restored_visual(player, "Z接口")
	await _ticks(5)
	_check(player.is_on_floor(), "近距离撤回后实体站稳")
	await _walk_near(player)
	_check(system.reset_study(), "实际R基线原子恢复")
	_restored_visual(player, "R接口")
	await _ticks(5)
	_check(player.is_on_floor() and player.position.distance_to(origin) < 1, "R后真实落在初始岸体")
	_check(system.history.get_history_count() == 0, "R清空换层历史")
	game.queue_free()
	await _ticks(2)
	print("ILLUSTRATED_RESTORE: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures else 0)

func _exit_tree() -> void:
	Input.action_release("move_right")
