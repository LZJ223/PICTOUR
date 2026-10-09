extends Node2D
## 新庭院的实际三件成图实体 + W/S/Z/R 整合；不修改关卡、不访问存档。

var game: Node2D
var system: StudySystemController
var player: PlayerController
var checks := 0
var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("STUDY_LEVEL_CHECK: " + message)


func _wait(count := 2) -> void:
	for tick in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _wait()
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	Input.parse_input_event(event)
	await _wait()


func _walk_to(target: float) -> bool:
	for tick in 180:
		var distance := target - player.position.x
		if absf(distance) <= 2.0:
			break
		Input.action_press("move_right" if distance > 0 else "move_left")
		Input.action_release("move_left" if distance > 0 else "move_right")
		await _wait(1)
	Input.action_release("move_left")
	Input.action_release("move_right")
	await _wait(12)
	return absf(target - player.position.x) < 10 and player.is_on_floor()


func _run() -> void:
	game = (load("res://Vertical_Garden_Game.tscn") as PackedScene).instantiate()
	add_child(game)
	system = game.get_node("System") as StudySystemController
	player = game.get_node("Player") as PlayerController
	await _wait(20)
	_check(system.history._objects.size() == 3, "实际新庭院只有三件主实体进入历史")
	var initial_error := system.history._validate(system.history._initial)
	_check(initial_error.is_empty(), "三件成图实体与地貌初始基线有效：" + initial_error)
	_check(system.reset_study(), "实际关卡初始R能够恢复完整基线")
	await _wait(5)
	await _jump_camera_check()
	var b := game.get_node("Level/Back/KeelBridge") as LayerObject
	var a := game.get_node("Level/Mid/RootGate") as LayerObject
	_check(await _walk_to(480), "真实步行到垂腹枝观察站位")
	var before_b := system.history.capture_state()
	Global.select_object(b)
	await _key(KEY_W)
	_check(b.owner_layer.slot == 0 and system.history.get_history_count() == 1, "实际W搬近B且记录全场状态")
	_check(_registered_scales_match(b), "B凹轮廓分解后的真实物理形状同步0.8尺度")
	_check(await _walk_to(290), "真实步行到卷根门送远站位")
	var before_a := system.history.capture_state()
	Global.select_object(a)
	await _key(KEY_S)
	_check(a.owner_layer.slot == 1 and system.history.get_history_count() == 2, "实际S送远A且严格背景占用通过")
	_check(_registered_scales_match(a), "A凹轮廓分解后的真实物理形状同步1.25尺度")
	_check(await _walk_to(350), "换层后人物继续实际行走")
	await _key(KEY_Z)
	_check(_matches(before_a), "第一次Z恢复A/B/C与操作前人物站位")
	_check(a.owner_layer.slot == 0 and b.owner_layer.slot == 0 and system.history.get_history_count() == 1, "第一次Z保留前一次B搬近结果")
	_check(_registered_scales_match(a) and _registered_scales_match(b), "第一次Z后A/B真实分块实体尺度有效")
	await _key(KEY_Z)
	_check(_matches(before_b), "第二次Z恢复最早操作前的三物件和人物站位")
	_check(a.owner_layer.slot == 0 and b.owner_layer.slot == 1 and system.history.get_history_count() == 0, "第二次Z恢复B背景身份且历史归零")
	_check(player.is_on_floor(), "两次撤回后人物仍受实际地貌承托")
	Global.select_object(b)
	await _key(KEY_W)
	await _key(KEY_R)
	_check(_matches(system.history._initial), "实际R恢复初始三物件和初始人物")
	_check(system.history.get_history_count() == 0 and _registered_scales_match(a) and _registered_scales_match(b), "R清历史且A/B所有真实形状恢复尺度")
	_check(system.get_projection_anchor().y == 720, "整个实际操作过程保持投影Y720")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://Exports/Study_Transfer")
		get_viewport().get_texture().get_image().save_png("res://Exports/Study_Transfer/03_actual_level_restored.png")
	print("STUDY_LEVEL_CHECK: %d checks, %d failures." % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _jump_camera_check() -> void:
	var origin_y := player.global_position.y
	var initial_camera_y := system.camera.global_position.y
	var highest_y := origin_y
	var minimum_camera_y := initial_camera_y
	var camera_within_deadzone := true
	Input.action_press("jump")
	for tick in 60:
		await _wait(1)
		highest_y = minf(highest_y, player.global_position.y)
		minimum_camera_y = minf(minimum_camera_y, system.camera.global_position.y)
		if tick < 15 and absf(player.global_position.y + system.view_offset_y - initial_camera_y) < 65:
			camera_within_deadzone = camera_within_deadzone and is_equal_approx(system.camera.global_position.y, initial_camera_y)
		if tick == 30:
			Input.action_release("jump")
	Input.action_release("jump")
	_check(origin_y - highest_y > 100 and player.is_on_floor(), "V6实际完整跳跃后回到真实岸面")
	_check(camera_within_deadzone, "真实跳跃在65px死区内的上升阶段保持镜头")
	_check(initial_camera_y - minimum_camera_y < 45, "约108px完整跳跃只引起小于45px取景移动")
	_check(system.get_projection_anchor().y == 720, "真实跳跃取景不改变解谜纵向关系")
	_check(system.reset_study(), "真实跳跃后R仍清除死区偏移恢复初始基线")
	await _wait(5)
	_check(is_equal_approx(system.camera.global_position.y, initial_camera_y), "R后下一物理帧保持初始视野，无旧死区拉回")


func _matches(state: Dictionary) -> bool:
	if player.global_position.distance_to(Transform2D(state.player_pose).origin) > 0.25:
		return false
	for saved: Dictionary in state.objects:
		var object: LayerObject = system.history._objects[saved.id]
		if object.owner_layer.layer_id != saved.layer_id or not _same(object.global_transform, saved.pose) or not _same(object.collision_box.transform, saved.collision_pose):
			return false
	return true


func _registered_scales_match(object: LayerObject) -> bool:
	var count := 0
	for owner in object.get_shape_owners():
		for index in object.shape_owner_get_shape_count(owner):
			var actual_index := object.shape_owner_get_shape_index(owner, index)
			if not _same(PhysicsServer2D.body_get_shape_transform(object.get_rid(), actual_index), object.collision_box.transform):
				return false
			count += 1
	return count > 1


func _same(a: Transform2D, b: Transform2D) -> bool:
	return a.origin.distance_to(b.origin) < 0.002 and a.x.distance_to(b.x) < 0.002 and a.y.distance_to(b.y) < 0.002
