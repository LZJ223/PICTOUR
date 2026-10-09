extends Node
## 实际按键与碰撞验证；研究场不创建磁盘存档。
const GAME_PATH := "res://Vertical_Garden_Game.tscn"
var game: Node2D
var level: Level
var player: PlayerController
var system: SystemController
var checks := 0
var finished := false

func _ready() -> void:
	get_window().size = Vector2i(1280,720)
	call_deferred("_run")

func _run() -> void:
	game = (load(GAME_PATH) as PackedScene).instantiate()
	add_child(game)
	level = game.get_node("Level")
	player = game.get_node("Player")
	system = game.get_node("System")
	await _ticks(20)
	if not _require(player.is_on_floor(),"初始脚点真实落地"): return
	_require(not level.allow_scenery_overlap_outside_player_layer,"两个景别都检查实体占用")
	_require(get_tree().get_nodes_in_group("layer_objects").size()==3,"只有三件独立主实体")
	await _tap_key(KEY_F8)
	await _capture("01_initial")
	var a := level.get_node("Mid/RootGate") as LayerObject
	var b := level.get_node("Back/KeelBridge") as LayerObject
	var c := level.get_node("Back/LowRoot") as LayerObject
	for object in [a,b,c]:
		if not _require(_registered_shape_count(object)>0,"真实PhysicsServer注册轮廓："+str(object.name)): return
	if not "--demo" in OS.get_cmdline_user_args():
		if not await _click_object(a): return
		await _tap_key(KEY_S)
		if not _require(a.owner_layer.slot==0 and system.get("history").get_history_count()==0,"初始背景实际被占，失败换层不变更世界或撤回历史"): return
		Global.clear_selection()
	if "--scan" in OS.get_cmdline_user_args():
		for x in [80,200,290,360,480,550,600]:
			player.global_position=Vector2(x,1100)
			player.velocity=Vector2.ZERO
			system.reset_view_interpolation()
			await _ticks(2)
			print("SCAN_A ",x," ",system._transfer_rejection(-1,a)," B ",system._transfer_rejection(1,b))
		finished=true
		get_tree().quit()
		return
	if not await _move_to(630,180): return
	if not await _jump_to(Vector2(689,1005),false): return
	if not await _jump_to(Vector2(725,962),false): return
	if not await _jump_to(Vector2(785,912),false): return
	if not await _jump_to(Vector2(840,883),false): return
	await _capture("02_root_crown")
	if not await _click_object(b): return
	await _tap_key(KEY_W)
	if not _require(b.owner_layer.slot==0,"从根冠搬入枝桥，形成高路"): return
	Global.clear_selection()
	if not await _move_to(856): return
	if not await _jump_to(Vector2(1040,873),true): return
	if not await _move_to(1386,200): return
	if not await _jump_to(Vector2(1530,800),true): return
	if not await _move_to(1860,170): return
	if not await _click_object(c): return
	await _tap_key(KEY_W)
	if not _require(c.owner_layer.slot==0,"矮根是共同末段的唯一登高件"): return
	Global.clear_selection()
	if not await _move_to(1795): return
	if not await _jump_to(Vector2(1710,710),true): return
	if not await _move_to(1640): return
	if not await _jump_to(Vector2(1495,623.6),true): return
	if not await _move_to(820,500): return
	if not _require(level.get("goal_reached"),"高路实际到达折页上缘"): return
	await _capture("03_upper_goal")
	if not await _move_to(1490,500): return
	if not await _jump_to(Vector2(1640,710),true): return
	if not await _jump_to(Vector2(1800,800),true): return
	if not await _jump_to(Vector2(1700,710),true): return
	if not await _jump_to(Vector2(1530,800),true): return
	if not await _jump_to(Vector2(1388,886),true): return
	if not await _move_to(1020,250): return
	if not await _jump_to(Vector2(848,883),true): return
	if not await _jump_to(Vector2(785,912),false): return
	if not await _jump_to(Vector2(722,962),false): return
	if not await _jump_to(Vector2(686,1005),false): return
	if not await _jump_to(Vector2(570,1100),true): return
	if not await _move_to(360): return
	_require(true,"高路全过程无需撤回或重置可原路返回")
	if not "--demo" in OS.get_cmdline_user_args():
		if not await _move_to(290): return
		if not await _click_object(a): return
		await _tap_key(KEY_S)
		if not _require(a.owner_layer.slot==1,"高路枝桥搬出背景后，同样允许将根门送远"): return
		Global.clear_selection()
		Input.action_press("move_right")
		await _ticks(380)
		_release()
		await _ticks(4)
		if not _require(player.global_position.x>1100 and player.global_position.x<1300 and absf(player.velocity.x)<2,"同一枝桥在高位时，垂腹真实阻挡井底通行"): return
		await _tap_key(KEY_Z)
		if not _require(a.owner_layer.slot==0 and b.owner_layer.slot==0 and absf(player.global_position.x-290)<10,"Z整体恢复换景前有效状态，不把根门塞回当前玩家位置"): return
	await _tap_key(KEY_R)
	await _ticks(15)
	if not _require(a.owner_layer.slot==0 and b.owner_layer.slot==1 and c.owner_layer.slot==1,"R恢复研究基线而不触碰旧存档"): return
	if not await _move_to(480,150): return
	if not await _click_object(b): return
	await _tap_key(KEY_W)
	if not _require(b.owner_layer.slot==0,"同一枝桥在低路站位搬入，先腾出背景空腔"): return
	Global.clear_selection()
	if not await _move_to(290,150): return
	if not await _click_object(a): return
	await _tap_key(KEY_S)
	if not _require(a.owner_layer.slot==1,"卷根门退入已经腾出的背景空腔，打开地面通路"): return
	Global.clear_selection()
	await _capture("04_low_layout")
	if not await _move_to(2010,750): return
	await _capture("05_underpass_exit")
	if not await _jump_to(Vector2(1883,800),true): return
	if not await _move_to(1860): return
	if not await _click_object(c): return
	await _tap_key(KEY_W)
	if not _require(c.owner_layer.slot==0,"低路复用同一个矮根登高"): return
	Global.clear_selection()
	if not await _move_to(1795): return
	if not await _jump_to(Vector2(1710,710),true): return
	if not await _move_to(1640): return
	if not await _jump_to(Vector2(1495,623.6),true): return
	if not await _move_to(820,500): return
	await _capture("06_low_goal")
	if not await _move_to(1490,500): return
	if not await _jump_to(Vector2(1640,710),true): return
	if not await _jump_to(Vector2(1800,800),true): return
	if not await _move_to(1870): return
	if not await _jump_to(Vector2(2020,890),true): return
	if not await _move_to(360,780): return
	_require(true,"低路同样无需撤回或重置可走回前庭")
	await _capture("07_returned")
	finished=true
	_release()
	print("VERTICAL_GARDEN_REGRESSION: %d checks, 0 failures" % checks)
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
		if left_floor and player.is_on_floor() and absf(player.global_position.y-target.y)<12 and absf(player.global_position.x-target.x)<25:
			_release()
			await _ticks(8)
			return _require(player.is_on_floor() and absf(player.global_position.y-target.y)<12,"真实跳跃稳落%s；最高脚位%.1f" % [target,highest])
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
	DirAccess.make_dir_recursive_absolute("res://Exports/Vertical_Garden")
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://Exports/Vertical_Garden/%s.png" % label)


func _release() -> void:
	for action in ["move_left","move_right","jump","sprint"]:
		Input.action_release(action)


func _require(condition: bool, message: String) -> bool:
	checks += 1
	if condition:
		print("PASS: "+message)
		return true
	finished = true
	_release()
	push_error("VERTICAL_GARDEN_REGRESSION_FAIL: "+message)
	get_tree().quit(1)
	return false
