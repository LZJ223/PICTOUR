extends Node

## 在实际白模关卡中执行真实物理路线。测试入口使用同名 .tscn，保留 Global 自动加载。
const GAME_SCENE: PackedScene = preload("res://Prologue_Test_Game.tscn")
var game: Node2D
var level: PrologueTestLevel
var player: PlayerController
var _failed: bool = false
var _finished: bool = false

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	get_tree().create_timer(75.0).timeout.connect(_on_timeout)
	game = GAME_SCENE.instantiate() as Node2D
	add_child(game)
	level = game.get_node("Level") as PrologueTestLevel
	player = game.get_node("Player") as PlayerController
	await _ticks(6)
	if not _require(player.is_on_floor(), "玩家在真实白模地面上出生"):
		return
	print("PLAYTHROUGH: 树、垫脚箱与高台机关")
	level.spawn_for_section(1)
	await _ticks(5)
	if not await _walk_to_x(1580.0, 100):
		return
	Input.action_press("move_right")
	await _ticks(28)
	Input.action_release("move_right")
	await _ticks(5)
	if not _require(player.position.x <= 1600.5, "未搬运时，高树确实阻挡玩家"):
		return
	var tree := level.get_node("PlayerLayer/BlockingTree") as LayerObject
	if not await _click_object(tree):
		return
	await _tap_key(KEY_S)
	if not _require(tree.owner_layer.layer_id == 1, "S 将挡路树送到背景"):
		return
	if not await _walk_to_x(1940.0, 160):
		return
	if not _require(level.milestones.tree_moved, "玩家真实走过移走后的树，关卡记录搬运结果"):
		return
	await _place_player(Vector2(1980, 600))
	var box := level.get_node("BackgroundLayer/StepBox") as LayerObject
	if not await _click_object(box):
		return
	await _tap_key(KEY_W)
	if not _require(box.owner_layer.layer_id == 0 and absf(box.position.x - 2188.0) < 2.0, "W 按站位搬入垫脚箱"):
		return
	if not await _walk_to_x(2100.0, 80):
		return
	if not await _jump_right_to_surface(510.0, 2130.0, false, 100):
		return
	if not _require(player.is_on_floor() and absf(player.position.y - 510.0) < 3.0, "第一跳实际落在搬入箱子顶部"):
		return
	if not await _jump_right_to_surface(420.0, 2250.0, false, 100):
		return
	if not await _walk_to_x(2445.0, 100):
		return
	await _ticks(4)
	if not _require(level.milestones.plate_opened, "第二跳登上高台，站在压力机关上开门"):
		return
	var door_shape := level.get_node("PlayerLayer/MechanismDoor/CollisionBox") as CollisionShape2D
	if not _require(door_shape.disabled, "机关门的实体碰撞已关闭"):
		return
	if not await _walk_to_x(2810.0, 160):
		return
	if not _require(player.position.x > 2720.0, "玩家真实穿过打开后的门"):
		return

	print("PLAYTHROUGH: 视差桥段与两次跑跳")
	level.spawn_for_section(2)
	await _ticks(5)
	await _place_player(Vector2(2900, 600))
	var bridge := level.get_node("BackgroundLayer/BridgePiece") as LayerObject
	if not await _click_object(bridge):
		return
	await _tap_key(KEY_W)
	if not _require(bridge.owner_layer.layer_id == 0 and absf(bridge.position.x - 3350.0) < 2.0, "W 搬入桥段，形成缺口中间的真实落脚点"):
		return
	var prior_resets: int = level.reset_count
	if not await _run_to_x(2960.0, 80):
		return
	if not await _jump_right_to_surface(580.0, 3190.0, true, 110):
		return
	if not _require(player.position.x < 3510.0 and player.is_on_floor(), "第一段跑跳落在桥段上"):
		return
	if not await _run_to_x(3470.0, 100):
		return
	if not await _jump_right_to_surface(600.0, 3700.0, true, 110):
		return
	if not _require(level.reset_count == prior_resets, "两次真实跑跳跨越 700 像素缺口，没有跌落重置"):
		return
	if not await _walk_to_x(3870.0, 90):
		return
	await _ticks(3)
	if not _require(level.milestones.ink_collected and not level.get_node("WorldNotes/Ink").visible, "玩家接近墨水，真实触发收集"):
		return
	if not await _walk_to_x(4190.0, 130):
		return
	await _ticks(3)
	if not _require(level.milestones.canvas_painted and level.get_node("WorldNotes/Canvas/FirstStroke").visible, "将墨水带进画室，画卷显现第一笔"):
		return
	if not _require(level.checkpoint_position == Vector2(4120, 600), "抵达画室建立本地恢复点"):
		return

	print("PLAYTHROUGH: R 与跌落恢复保留进度")
	var ink_state: bool = level.milestones.ink_collected
	var door_state: bool = level.milestones.plate_opened
	var painted_state: bool = level.milestones.canvas_painted
	await _tap_key(KEY_R)
	if not _require(player.position.distance_to(level.checkpoint_position) < 3.0, "真实 R 输入回到画室恢复点"):
		return
	if not _require(bridge.owner_layer.layer_id == 1, "R 将本段桥物件恢复到原始背景层"):
		return
	if not _require(level.milestones.ink_collected == ink_state and level.milestones.plate_opened == door_state and level.milestones.canvas_painted == painted_state and door_shape.disabled, "R 保留墨水、画卷与机关门"):
		return
	prior_resets = level.reset_count
	player.reset_motion()
	player.position = Vector2(4210, 850)
	await _ticks(6)
	if not _require(level.reset_count == prior_resets + 1 and player.position.distance_to(level.checkpoint_position) < 3.0, "跌落真实触发恢复，不停留在坑底"):
		return
	if not _require(level.milestones.ink_collected and level.milestones.canvas_painted and level.milestones.plate_opened and door_shape.disabled, "跌落恢复仍保留墨水、画卷和已开启机关"):
		return
	_release_controls()
	_finished = true
	print("PASS: 实际序章树、箱子两级跳、机关门、桥段两次跑跳、墨水、画室、R 与跌落恢复全部通过")
	get_tree().quit(0)

func _place_player(point: Vector2) -> void:
	_release_controls()
	Global.clear_selection()
	player.reset_motion()
	player.position = point
	await _ticks(5)

func _click_object(object: LayerObject) -> bool:
	Global.clear_selection()
	await _ticks(2)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = get_viewport().get_canvas_transform() * object.visual_root.global_position
	click.global_position = click.position
	# headless 的实际窗口尺寸与逻辑视口不同，直接使用已换算的视口坐标。
	get_viewport().push_input(click, true)
	await _ticks(3)
	click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = false
	get_viewport().push_input(click, true)
	await _ticks(2)
	return _require(Global.object_selected == object, "左键通过投影视觉的点选代理选中 " + str(object.name))

func _tap_key(key: Key) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = key
	press.keycode = key
	press.pressed = true
	Input.parse_input_event(press)
	await _ticks(3)
	var release := InputEventKey.new()
	release.physical_keycode = key
	release.keycode = key
	release.pressed = false
	Input.parse_input_event(release)
	await _ticks(3)

func _walk_to_x(target: float, frame_limit: int) -> bool:
	Input.action_release("sprint")
	Input.action_press("move_right")
	for frame in range(frame_limit):
		await _ticks(1)
		if player.position.x >= target:
			Input.action_release("move_right")
			await _ticks(10)
			return true
	_release_controls()
	return _require(false, "行走到 x=%s 超时；实际位置 %s" % [target, player.position])

## 保留右方向和 Shift，供接下来的跑跳使用。
func _run_to_x(target: float, frame_limit: int) -> bool:
	Input.action_press("move_right")
	Input.action_press("sprint")
	for frame in range(frame_limit):
		await _ticks(1)
		if player.position.x >= target and player.is_running:
			return _require(player.is_on_floor(), "跑跳起点仍在平台上")
	_release_controls()
	return _require(false, "奔跑到 x=%s 超时；实际位置 %s" % [target, player.position])

func _jump_right_to_surface(surface_y: float, minimum_x: float, running: bool, frame_limit: int) -> bool:
	if not _require(player.is_on_floor(), "跳跃从真实地面或平台起跳"):
		return false
	Input.action_press("move_right")
	if not running:
		Input.action_release("sprint")
	Input.action_press("jump")
	await _ticks(2)
	Input.action_release("jump")
	var has_left_floor: bool = not player.is_on_floor()
	for frame in range(frame_limit):
		await _ticks(1)
		has_left_floor = has_left_floor or not player.is_on_floor()
		if has_left_floor and player.is_on_floor() and absf(player.position.y - surface_y) < 3.0 and player.position.x >= minimum_x:
			_release_controls()
			await _ticks(10)
			return _require(player.is_on_floor() and absf(player.position.y - surface_y) < 3.0, "落地后停止，仍稳定站在 y=%s 的平台" % surface_y)
	_release_controls()
	return _require(false, "跳到 y=%s / x>=%s 超时；实际位置 %s" % [surface_y, minimum_x, player.position])

func _ticks(count: int) -> void:
	for frame in range(count):
		await get_tree().physics_frame

func _release_controls() -> void:
	for action in ["move_left", "move_right", "sprint", "jump"]:
		Input.action_release(action)

func _require(condition: bool, description: String) -> bool:
	if condition:
		print("PASS: " + description)
		return true
	_failed = true
	_finished = true
	_release_controls()
	push_error("FAIL: " + description)
	get_tree().quit(1)
	return false

func _on_timeout() -> void:
	if not _finished:
		_require(false, "序章路线集成测试超过 75 秒总时限")
