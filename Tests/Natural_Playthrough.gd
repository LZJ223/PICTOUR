extends Node
## 在真实关卡中分别走枝桥与拱顶路线；只设置各路线最初的 x800 出发点。

const GAME := preload("res://Natural_Garden_Game.tscn")
const SAVE_PATH := "user://Tests/Natural_Playthrough_Save.json"
var game: Node2D
var level: NaturalGardenLevel
var player: PlayerController
var system: SystemController
var checks: int = 0
var finished: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(75.0).timeout.connect(func():
		if not finished:
			_require(false, "两路线超过75秒总时限")
	)
	await _fresh_game()
	print("NATURAL_PLAYTHROUGH: 枝桥下路")
	var bridge := level.get_node("BackgroundLayer/RootBridge") as NaturalObject
	if not await _click_form(bridge, Vector2(-20,-70)):
		return
	await _tap_key(KEY_W)
	if not _require(bridge.owner_layer.layer_id == 0 and bridge.global_position.distance_to(Vector2(1040,600)) < 2, "W按当前视差把枝桥搬到1040,600"):
		return
	if not await _jump_to(Vector2(910,573.08), false):
		return
	if not await _jump_to(Vector2(1030,536.92), false):
		return
	if not await _jump_to(Vector2(1170,500), false):
		return
	if not await _jump_to(Vector2(1300,600), true):
		return
	_require(player.global_position.x > 1240 and player.is_on_floor(), "枝桥三阶实际跳过360px缺口")
	await _capture("branch_right_bank")
	if not await _jump_to(Vector2(1170,500),true):
		return
	if not await _jump_to(Vector2(1030,536.92),false):
		return
	if not await _jump_to(Vector2(910,573.08),false):
		return
	if not await _jump_to(Vector2(800,600),false):
		return
	_require(player.global_position.x<880 and player.is_on_floor(),"枝桥从右岸真实反向走跳返回纸岸，形成物理回路")
	await _capture("branch_return")
	await _fresh_game()
	print("NATURAL_PLAYTHROUGH: 拱顶上路与墨水")
	var arch := level.get_node("BackgroundLayer/PassageArch") as NaturalObject
	if not await _click_form(arch, Vector2(0,-230)):
		return
	await _tap_key(KEY_W)
	if not _require(arch.owner_layer.layer_id == 0 and arch.global_position.distance_to(Vector2(1088,600)) < 2, "W按当前视差把空心拱门搬到1088,600"):
		return
	if not await _jump_to(Vector2(889,523.85), false):
		return
	if not await _jump_to(Vector2(945,456.67), false):
		return
	if not await _jump_to(Vector2(1030,385), false):
		return
	if not await _move_to(1080,100,false):
		return
	if not _require(level.bookmarks.has_ink("arch_ink"), "登上拱顶真实收集墨水"):
		return
	await _capture("arch_ink")
	if not await _jump_to(Vector2(1360,600),true):
		return
	if not await _jump_to(Vector2(1280,523.85),false):
		return
	if not await _jump_to(Vector2(1220,456.67),false):
		return
	if not await _jump_to(Vector2(1130,385),false):
		return
	if not await _jump_to(Vector2(800,600),true):
		return
	_require(player.global_position.x<880 and player.is_on_floor(),"拱门从右岸沿右阶真实返回纸岸，形成物理回路")
	await _capture("arch_return")
	await _tap_key(KEY_R)
	if not _require(player.global_position.distance_to(Vector2(180,600)) < 3 and arch.owner_layer.layer_id == 1, "真实R回到纸岸并恢复搬前布局"):
		return
	if not _require(level.bookmarks.has_ink("arch_ink"), "R布局恢复保留墨水"):
		return
	# 从已复原的纸岸继续真实走跳；没有传送至踏面或书签。
	if not await _move_to(330,100,false):
		return
	if not await _jump_to(Vector2(410,520),false):
		return
	if not await _jump_to(Vector2(750,600),true):
		return
	if not await _move_to(800,80,false):
		return
	if not await _click_form(arch,Vector2(0,-230)):
		return
	await _tap_key(KEY_W)
	if not await _jump_to(Vector2(889,523.85),false):
		return
	if not await _jump_to(Vector2(945,456.67),false):
		return
	if not await _jump_to(Vector2(1040,385),false):
		return
	if not await _jump_to(Vector2(1360,600),true):
		return
	if not await _move_to(1480,120,false):
		return
	if not await _jump_to(Vector2(1580,520),false):
		return
	if not await _jump_to(Vector2(1800,481.68),true):
		return
	if not await _jump_to(Vector2(1965,402.12),true):
		return
	if not await _jump_to(Vector2(2050,345),false):
		return
	if not await _jump_to(Vector2(2220,600),true):
		return
	if not await _move_to(2260,80,false):
		return
	await _tap_key(KEY_E)
	if not _require(level.bookmarks.unlocked_bookmarks.has(1) and level.bookmarks.last_bookmark == 1, "真实走跳至第二书签并按E记录"):
		return
	await _tap_key(KEY_M)
	if not _require(level.bookmarks.map_open and not player.activated,"M展开地图并暂停玩家输入"):
		return
	await _capture("bookmark_map")
	if not await _click_map_button(0):
		return
	if not _require(player.global_position.distance_to(Vector2(180,600)) < 3 and level.bookmarks.last_bookmark == 0,"地图真实点击回纸岸"):
		return
	await _tap_key(KEY_M)
	if not await _click_map_button(1):
		return
	if not _require(player.global_position.distance_to(Vector2(2260,600)) < 3 and player.is_on_floor() and level.bookmarks.has_ink("arch_ink"),"地图真实点击第二书签安全恢复且墨水保留"):
		return
	await _capture("second_bookmark")
	_release()
	finished = true
	print("NATURAL_PLAYTHROUGH: %d checks, 0 failures; 枝桥、拱顶、墨水、R和第二书签地图恢复全部通过" % checks)
	_clean_save()
	get_tree().quit(0)


func _fresh_game() -> void:
	_release()
	Global.clear_selection()
	if is_instance_valid(game):
		game.queue_free()
		await _ticks(3)
	_clean_save()
	game = GAME.instantiate()
	game.get_node("Level").save_path = SAVE_PATH
	add_child(game)
	level = game.get_node("Level")
	player = game.get_node("Player")
	system = game.get_node("System")
	await _ticks(6)
	player.global_position = Vector2(800,600)
	player.reset_motion()
	system.reset_view_interpolation()
	await _ticks(4)
	_require(player.is_on_floor(), "路线从x800真实地面出发")


func _jump_to(target: Vector2, running: bool, frame_limit: int = 100) -> bool:
	if not _require(player.is_on_floor(), "从实体踏面起跳 %s -> %s" % [player.global_position,target]):
		return false
	Input.action_press("sprint") if running else Input.action_release("sprint")
	_steer(target.x,running)
	Input.action_press("jump")
	await _ticks(2)
	var left_floor: bool = not player.is_on_floor()
	var min_y: float = player.global_position.y
	for frame in frame_limit:
		_steer(target.x,running)
		await _ticks(1)
		min_y = minf(min_y,player.global_position.y)
		left_floor = left_floor or not player.is_on_floor()
		if left_floor and player.is_on_floor() and absf(player.global_position.y-target.y)<3 and absf(player.global_position.x-target.x)<25:
			_release()
			await _ticks(8)
			return _require(player.is_on_floor() and absf(player.global_position.y-target.y)<3,"真实跳跃稳落 %s；最高脚位 %.1f" % [target,min_y])
	_release()
	return _require(false,"跳至%s失败，实际%s / grounded=%s，最高y=%.1f" % [target,player.global_position,player.is_on_floor(),min_y])


func _move_to(target: float, frame_limit: int, running: bool) -> bool:
	Input.action_press("sprint") if running else Input.action_release("sprint")
	for frame in frame_limit:
		_steer(target,running)
		await _ticks(1)
		if absf(player.global_position.x-target)<8 and absf(player.velocity.x)<65 and player.is_on_floor():
			_release()
			await _ticks(4)
			return true
	_release()
	return _require(false,"走到x=%s失败，实际%s" % [target,player.global_position])


func _steer(target: float, running: bool) -> void:
	# 连续Input强度模拟轻按方向，仍由原控制器加速度、碰撞和真实物理推进。
	var speed: float = player.run_speed if running else player.move_speed
	var direction: float = clampf((target-player.global_position.x)*7.0/speed,-1,1)
	if direction>0:
		Input.action_release("move_left")
		Input.action_press("move_right",direction)
	else:
		Input.action_release("move_right")
		Input.action_press("move_left",-direction)


func _click_form(object: NaturalObject, nominal: Vector2) -> bool:
	Global.clear_selection()
	await _ticks(2)
	var local: Vector2 = nominal * object.dimensions / NaturalForm.nominal_size(object.kind)
	var point: Vector2 = object.visual_root.global_transform * local
	await _click(get_viewport().get_canvas_transform()*point)
	return _require(Global.object_selected==object,"真实左键点选"+str(object.name))


func _click_map_button(index: int) -> bool:
	await _ticks(3)
	var entries: VBoxContainer = level.bookmarks.get("_map_entries")
	var button := entries.get_child(index) as Button
	if not _require(button!=null and not button.disabled,"地图中目标书签可选"):
		return false
	await _click(button.get_global_rect().get_center())
	await _ticks(3)
	return _require(not level.bookmarks.map_open,"地图鼠标点击触发实际恢复并关闭")


func _click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	event.global_position = point
	get_viewport().push_input(event,true)
	await _ticks(3)
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	event.position = point
	event.global_position = point
	get_viewport().push_input(event,true)
	await _ticks(2)


func _tap_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(2)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await _ticks(2)


func _ticks(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().create_timer(0).timeout


func _capture(name: String) -> void:
	if DisplayServer.get_name()=="headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://Exports/Natural_Playthrough_%s.png" % name)


func _release() -> void:
	for action in ["move_left","move_right","jump","sprint"]:
		Input.action_release(action)


func _clean_save() -> void:
	# 固定测试专属路径，绝不接触实际用户存档。
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	if FileAccess.file_exists(SAVE_PATH+".tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH+".tmp"))


func _require(condition: bool, message: String) -> bool:
	checks += 1
	if condition:
		print("PASS: "+message)
		return true
	finished = true
	_release()
	push_error("NATURAL_PLAYTHROUGH_FAIL: "+message)
	_clean_save()
	get_tree().quit(1)
	return false
