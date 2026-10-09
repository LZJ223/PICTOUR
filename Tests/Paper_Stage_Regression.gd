extends Node
## 新画页实际输入验证。仅使用独立测试存档，GPU 运行时记录真实视口。

const GAME_PATH := "res://Paper_Stage_Game.tscn"
const SAVE_PATH := "user://Tests/Paper_Stage_Regression.json"
var game: Node2D
var level: Level
var player: PlayerController
var system: SystemController
var checks: int = 0
var finished: bool = false


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	get_tree().create_timer(55.0).timeout.connect(func():
		if not finished:
			_require(false, "画页输入验证超过55秒")
	)
	_clean_save()
	var scene := load(GAME_PATH) as PackedScene
	if not _require(scene != null, "新画页资源存在"):
		return
	game = scene.instantiate()
	level = game.get_node("Level") as Level
	level.set("save_path", SAVE_PATH)
	add_child(game)
	player = game.get_node("Player") as PlayerController
	system = game.get_node("System") as SystemController
	await _ticks(20)
	if not _require(player.is_on_floor(), "初始脚位位于真实纸岸"):
		return
	_require(Global.layer_count == 2 and Global.current_layer_index == 0, "画页使用两层与玩家槽位0")
	_require(not Global.allow_layer_cycle and not Global.allow_uav, "序章不提前开放轮换与无人机")
	_require(level.allow_scenery_overlap_outside_player_layer, "非玩家景别保留叠景与送回规则")
	await _capture("01_initial")
	var arch := level.get_node("Back/BrokenArch") as LayerObject
	var tree := level.get_node("Mid/HeroTree") as LayerObject
	if not _require(arch != null and tree != null, "主树和残拱均为统一换层实体"):
		return
	if not _require(_registered_shape_count(arch) > 0 and _registered_shape_count(tree) > 0, "主树与残拱在物理世界实际注册实体形状"):
		return
	if not await _click_object(arch):
		return
	var arch_origin := arch.global_position
	var arch_scale := arch.collision_box.global_scale
	var appearance := arch.visual_root.global_transform
	await _tap_key(KEY_W)
	if not _require(arch.owner_layer.slot == 0, "真实左键选取后W将残拱搬入玩家景别"):
		return
	_require(_same_transform(appearance, arch.visual_root.global_transform), "搬入瞬间保持残拱可见位置和尺寸")
	Global.clear_selection()
	await _capture("02_arch_in_mid")
	if not await _click_object(arch):
		return
	await _tap_key(KEY_S)
	if not _require(arch.owner_layer.slot == 1, "S可将残拱送回背景"):
		return
	_require(arch.global_position.distance_to(arch_origin) < 0.1 and arch.collision_box.global_scale.distance_to(arch_scale) < 0.001, "同站位来回搬运无位置或尺度累积")
	if not await _click_object(tree):
		return
	var tree_origin := tree.global_position
	var tree_scale := tree.collision_box.global_scale
	appearance = tree.visual_root.global_transform
	await _tap_key(KEY_S)
	if not _require(tree.owner_layer.slot == 1, "主树与残拱一致，可以移至背景"):
		return
	_require(_same_transform(appearance, tree.visual_root.global_transform), "主树换层保持视觉连续")
	Global.clear_selection()
	await _capture("03_hero_tree_in_back")
	if not await _click_object(tree):
		return
	await _tap_key(KEY_W)
	if not _require(tree.owner_layer.slot == 0, "主树可以回到原景别"):
		return
	_require(tree.global_position.distance_to(tree_origin) < 0.1 and tree.collision_box.global_scale.distance_to(tree_scale) < 0.001, "主树来回搬运无漂移")
	Global.clear_selection()
	# 测量原控制器真实完整跳跃，而非直接指定人物高度或播放空中动画。
	var start_y: float = player.global_position.y
	var highest: float = start_y
	var took_off: bool = false
	Input.action_press("jump")
	for frame in 52:
		await _ticks(1)
		highest = minf(highest, player.global_position.y)
		took_off = took_off or not player.is_on_floor()
	Input.action_release("jump")
	if not _require(took_off and player.is_on_floor() and absf(player.global_position.y-start_y) < 1.0, "原控制器完成起跳、腾空与同纸岸落地"):
		return
	_require(start_y-highest > 105 and start_y-highest < 112, "满跳仍约108.6px，维持人物1.2倍身高")
	# 步行、Shift首帧加速与刹停在游戏实例中实测；观察场的演示驱动不用于此结论。
	Input.action_press("move_left")
	await _ticks(8)
	if not _require(player.velocity.x < -player.move_speed + 1, "A步行达到设置速度"):
		return
	Input.action_press("sprint")
	await _ticks(1)
	_require(player.is_running and absf(player.velocity.x) > player.move_speed, "Shift首个物理帧即加速")
	await _ticks(12)
	_require(absf(player.velocity.x) >= player.run_speed-1, "长按Shift达到奔跑速度")
	_release()
	await _ticks(12)
	_require(absf(player.velocity.x) < 0.1 and not player.dash_active, "释放长跑后自然刹停，不追加短冲")
	await _capture("04_after_actual_motion")
	# 恢复操作由关卡真实R处理；测试从不写默认用户存档。
	await _tap_key(KEY_R)
	await _ticks(5)
	_require(player.is_on_floor(), "R恢复后安全站立")
	if not await _click_object(arch):
		return
	await _tap_key(KEY_W)
	if not _require(arch.owner_layer.slot == 0, "恢复后再次搬入残拱建立跨岸路线"):
		return
	Global.clear_selection()
	if not await _move_to(730):
		return
	if not await _jump_to(Vector2(836,410.47), true):
		return
	if not await _jump_to(Vector2(888,367.03), false):
		return
	if not await _jump_to(Vector2(910,291.37), false):
		return
	if not await _jump_to(Vector2(1033,218.88), true):
		return
	await _capture("05_arch_summit")
	_require(level.get("bookmarks").has_ink("arch_ink"), "沿残拱真实攀登并取得拱顶墨水")
	if not await _jump_to(Vector2(1180,510), true):
		return
	if not await _jump_to(Vector2(1260,430), false):
		return
	if not await _move_to(1530,180):
		return
	await _tap_key(KEY_E)
	_require(level.get("bookmarks").last_bookmark == 1, "从左岸实际走跳到右岸第二书签并记录")
	await _capture("06_right_bookmark")
	if not await _move_to(1380,100):
		return
	if not await _jump_to(Vector2(1250,430), true):
		return
	if not await _jump_to(Vector2(1140,373.64), true):
		return
	if not await _jump_to(Vector2(1125,279.86), false):
		return
	if not await _jump_to(Vector2(1040,218.88), false):
		return
	if not await _jump_to(Vector2(730,510), true):
		return
	_require(player.global_position.x < 790 and player.is_on_floor(), "由右岸反向沿残拱真实跳回纸岸")
	await _capture("07_returned_left")
	finished = true
	_release()
	_clean_save()
	print("PAPER_STAGE_REGRESSION: %d checks, 0 failures；真实点选、换层送回、移动、残拱跨岸与书签通过。" % checks)
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
	DirAccess.make_dir_recursive_absolute("res://Exports/Paper_Stage")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://Exports/Paper_Stage/%s.png" % label)


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
	push_error("PAPER_STAGE_REGRESSION_FAIL: "+message)
	_clean_save()
	get_tree().quit(1)
	return false
