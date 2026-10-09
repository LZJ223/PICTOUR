extends Node
## 新庭园实际输入验证。仅使用独立测试存档，GPU 运行时记录真实视口。

const GAME_PATH := "res://Garden_Study_Game.tscn"
const SAVE_PATH := "user://Tests/Garden_Study_Regression.json"
var game: Node2D
var level: Level
var player: PlayerController
var system: SystemController
var checks: int = 0
var finished: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(100.0).timeout.connect(func():
		if not finished:
			_require(false,"双路线验证超时")
	)
	_clean_save()
	game = (load(GAME_PATH) as PackedScene).instantiate()
	level = game.get_node("Level") as Level
	level.set("save_path",SAVE_PATH)
	add_child(game)
	player = game.get_node("Player") as PlayerController
	system = game.get_node("System") as SystemController
	await _ticks(20)
	if not _require(player.is_on_floor(),"初始书签落在真实纸岸"):
		return
	var used_families: Dictionary = {}
	for layer in system.layers:
		for object in layer.get_children():
			if object is SceneryFamilyObject:
				used_families[object.piece.family] = true
				if not _require(object.can_transfer and _registered_shape_count(object)>0,"衍生景物可搬且具有真实实体："+str(object.name)):
					return
	_require(used_families.size()>=3,"庭园同时使用三种来源的差异化景物")
	await _capture("01_initial")
	var arch := level.get_node("Back/BrokenArch") as LayerObject
	if not await _click_object(arch):
		return
	await _tap_key(KEY_W)
	if not _require(arch.owner_layer.slot == 1,"初始站位残拱左脚与岸相交，拒绝搬入"):
		return
	Global.clear_selection()
	if not await _move_to(730):
		return
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _ticks(2)
	Input.action_release("sprint")
	Input.action_press("jump")
	var fell_into_gap := false
	var landed_right := false
	for frame in 95:
		await _ticks(1)
		fell_into_gap = fell_into_gap or player.global_position.y > 650
		landed_right = landed_right or (player.is_on_floor() and player.global_position.x > 1250)
		if fell_into_gap and player.global_position.x < 600:
			break
	_release()
	if not _require(fell_into_gap and not landed_right,"未组合景物时，完整冲跳仍不能越过缺口"):
		return
	await _tap_key(KEY_R)
	await _ticks(10)
	_require(player.is_on_floor() and player.global_position.x < 600,"坠落与R安全回到本研究场景独立书签")
	if not await _move_to(640):
		return
	if not await _click_object(arch):
		return
	await _tap_key(KEY_W)
	if not _require(arch.owner_layer.slot == 0,"换站位后拱脚落入岸间空白，允许搬入"):
		return
	Global.clear_selection()
	print("ARCH_ROOT ",arch.global_position)
	await _capture("02_arch_route")
	if not await _move_to(730):
		return
	if not await _jump_to(Vector2(859,408.49),true):
		return
	if not await _jump_to(Vector2(923,368.07),false):
		return
	if not await _jump_to(Vector2(950,298.99),false):
		return
	if not await _jump_to(Vector2(1020,264.88),true):
		return
	if not await _jump_to(Vector2(1103,232.12),true):
		return
	await _capture("03_arch_summit")
	if not await _jump_to(Vector2(1290,520),true):
		return
	if not await _jump_to(Vector2(1360,440),true):
		return
	if not await _move_to(1600,220):
		return
	await _tap_key(KEY_E)
	_require(level.get("bookmarks").last_bookmark == 1,"高路抵达右岸书签并实际记录")
	await _capture("04_right_bank")
	if not await _move_to(1470):
		return
	if not await _jump_to(Vector2(1360,440),true):
		return
	if not await _jump_to(Vector2(1235,374.99),true):
		return
	if not await _jump_to(Vector2(1235,313.02),false):
		return
	if not await _jump_to(Vector2(1111,232.12),true):
		return
	if not await _jump_to(Vector2(950,298.99),true):
		return
	if not await _jump_to(Vector2(859,408.49),false):
		return
	if not await _jump_to(Vector2(730,480),true):
		return
	_require(player.is_on_floor() and player.global_position.x < 740,"高路真实反向回到左岸")
	await _capture("05_arch_return")
	await _tap_key(KEY_M)
	var manager: BookmarkManager = level.get("bookmarks")
	var first_button := manager._map_entries.get_child(0) as Button
	await _click(first_button.get_global_rect().get_center())
	await _ticks(12)
	if not _require(manager.last_bookmark == 0 and arch.owner_layer.slot == 1,"实际书签地图恢复起始摆位，残拱留在背景"):
		return
	if not await _move_to(640):
		return
	var stone := level.get_node("Back/LowStone") as LayerObject
	var root := level.get_node("Back/RootBridge") as LayerObject
	if not await _click_object(stone):
		return
	await _tap_key(KEY_W)
	if not _require(stone.owner_layer.slot == 0,"第二解先将页石搬近"):
		return
	Global.clear_selection()
	var before_offset := root.visual_root.global_position.x-stone.visual_root.global_position.x
	if not await _move_to(660):
		return
	if not _require(absf(root.visual_root.global_position.x-stone.visual_root.global_position.x-before_offset)>2,"先落下页石后，走动确实改变横根相对页石的位置"):
		return
	if not await _click_object(root):
		return
	await _tap_key(KEY_W)
	if not _require(root.owner_layer.slot == 0 and arch.owner_layer.slot == 1,"第二解组合真实根石轮廓，未借用残拱实体"):
		return
	Global.clear_selection()
	print("LOW_ROOTS ",stone.global_position," / ",root.global_position)
	await _capture("06_root_stone_route")
	if not await _move_to(730):
		return
	if not await _jump_to(Vector2(800,400),false):
		return
	if not await _jump_to(Vector2(930,356),true):
		return
	if not await _jump_to(Vector2(1050,383),true):
		return
	if not await _jump_to(Vector2(1175,428.6),true):
		return
	await _capture("07_root_crossing")
	if not await _jump_to(Vector2(1290,520),true):
		return
	if not await _jump_to(Vector2(1360,440),true):
		return
	if not await _move_to(1600,220):
		return
	await _tap_key(KEY_E)
	_require(manager.last_bookmark == 1 and arch.owner_layer.slot == 1,"不用残拱的第二解抵达同一个右岸书签")
	if not await _move_to(1470):
		return
	if not await _jump_to(Vector2(1360,440),true):
		return
	if not await _jump_to(Vector2(1290,520),false):
		return
	if not await _jump_to(Vector2(1175,428.6),true):
		return
	if not await _jump_to(Vector2(1050,383),true):
		return
	if not await _jump_to(Vector2(930,356),true):
		return
	if not await _jump_to(Vector2(800,400),true):
		return
	if not await _jump_to(Vector2(730,480),false):
		return
	_require(player.is_on_floor() and player.global_position.x < 740,"根石低路真实反向回到左岸")
	await _capture("08_root_return")
	if not await _click_object(root):
		return
	var root_appearance := root.visual_root.global_transform
	await _tap_key(KEY_S)
	if not _require(root.owner_layer.slot == 1,"横根送回有残拱遮叠的背景仍可成功"):
		return
	_require(_same_transform(root_appearance,root.visual_root.global_transform),"衍生物送回时外观连续")
	await _tap_key(KEY_W)
	if not _require(root.owner_layer.slot == 0,"同站位再次搬入，保留已形成的根石路径"):
		return
	finished = true
	_release()
	_clean_save()
	print("GARDEN_STUDY_REGRESSION: %d checks, 0 failures；残拱与根石两种实际解法均可往返。" % checks)
	get_tree().quit(0)

func _move_to(target: float, frame_limit: int = 120) -> bool:
	Input.action_release("sprint")
	for frame in frame_limit:
		_steer(target,false)
		await _ticks(1)
		if absf(player.global_position.x-target) < 8 and absf(player.velocity.x) < 65 and player.is_on_floor():
			_release()
			await _ticks(4)
			return _require(true,"沿实际地形走至x=%.1f" % target)
	_release()
	return _require(false,"走至x=%.1f失败，实际%s" % [target,player.global_position])


func _jump_to(target: Vector2, running: bool, frame_limit: int = 110) -> bool:
	if not _require(player.is_on_floor(),"从真实踏面起跳 %s -> %s" % [player.global_position,target]):
		return false
	Input.action_press("sprint") if running else Input.action_release("sprint")
	_steer(target.x,running)
	Input.action_press("jump")
	await _ticks(2)
	var left_floor: bool = not player.is_on_floor()
	var highest: float = player.global_position.y
	for frame in frame_limit:
		_steer(target.x,running)
		await _ticks(1)
		highest = minf(highest,player.global_position.y)
		left_floor = left_floor or not player.is_on_floor()
		if left_floor and player.is_on_floor() and absf(player.global_position.y-target.y)<3 and absf(player.global_position.x-target.x)<25:
			_release()
			await _ticks(8)
			return _require(player.is_on_floor() and absf(player.global_position.y-target.y)<3,"真实跳跃稳落%s；最高脚位%.1f" % [target,highest])
	_release()
	return _require(false,"跳至%s失败，实际%s / grounded=%s；最高脚位%.1f" % [target,player.global_position,player.is_on_floor(),highest])


func _steer(target: float, running: bool) -> void:
	var speed: float = player.run_speed if running else player.move_speed
	var direction: float = clampf((target-player.global_position.x)*7.0/speed,-1,1)
	if direction > 0:
		Input.action_release("move_left")
		Input.action_press("move_right",direction)
	else:
		Input.action_release("move_right")
		Input.action_press("move_left",-direction)


func _same_transform(first: Transform2D, second: Transform2D) -> bool:
	return first.origin.distance_to(second.origin) < 0.1 and first.x.distance_to(second.x) < 0.001 and first.y.distance_to(second.y) < 0.001


func _registered_shape_count(object: CollisionObject2D) -> int:
	var count := 0
	for owner_id in object.get_shape_owners():
		if not object.is_shape_owner_disabled(owner_id):
			count += object.shape_owner_get_shape_count(owner_id)
	return count


func _click_object(object: LayerObject) -> bool:
	Global.clear_selection()
	await _ticks(2)
	# 从实体已有可点轮廓找未被别的物件覆盖的内部点，然后发送真实鼠标事件。
	# 不依赖新美术图尺寸，也不直接调用select_object来绕过点选。
	var candidates: Array[Vector2] = []
	for node in object.visual_root.find_children("*", "CollisionPolygon2D", true, false):
		var shape := node as CollisionPolygon2D
		if not shape.get_parent() is Area2D or shape.disabled:
			continue
		var triangles := Geometry2D.triangulate_polygon(shape.polygon)
		for index in range(0,triangles.size(),3):
			var center := (shape.polygon[triangles[index]]+shape.polygon[triangles[index+1]]+shape.polygon[triangles[index+2]])/3.0
			candidates.append(shape.global_transform*center)
	var canvas := get_viewport().get_canvas_transform()
	for world_point in candidates:
		var screen_point: Vector2 = canvas * world_point
		if not Rect2(Vector2(4,4),Vector2(1272,712)).has_point(screen_point):
			continue
		var query := PhysicsPointQueryParameters2D.new()
		query.position = world_point
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var hits := player.get_world_2d().direct_space_state.intersect_point(query,64)
		var exclusive: bool = not hits.is_empty()
		for hit in hits:
			var ancestor: Node = hit.collider
			while ancestor != null and not ancestor is LayerObject:
				ancestor = ancestor.get_parent()
			if ancestor != object:
				exclusive = false
		if not exclusive:
			continue
		await _click(screen_point)
		return _require(Global.object_selected == object, "真实鼠标点选"+str(object.name))
	return _require(false,"可见范围内找不到未被覆盖的点选轮廓："+str(object.name))


func _click(point: Vector2) -> void:
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		get_viewport().push_input(event,true)
		await _ticks(3)


func _tap_key(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await _ticks(3)


func _ticks(count: int) -> void:
	for frame in count:
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().create_timer(0).timeout


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute("res://Exports/Garden_Study")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://Exports/Garden_Study/%s.png" % label)


func _release() -> void:
	for action in ["move_left","move_right","jump","sprint"]:
		Input.action_release(action)


func _clean_save() -> void:
	for suffix in ["", ".tmp"]:
		if FileAccess.file_exists(SAVE_PATH+suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH+suffix))


func _require(condition: bool, message: String) -> bool:
	checks += 1
	if condition:
		print("PASS: "+message)
		return true
	finished = true
	_release()
	push_error("GARDEN_STUDY_REGRESSION_FAIL: "+message)
	_clean_save()
	get_tree().quit(1)
	return false
