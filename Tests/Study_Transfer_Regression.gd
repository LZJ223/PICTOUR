extends Node2D
## 正式V7的固定投影Y、严格两层占用与原子整套撤回；--v6保留旧角色覆盖。不读取玩家存档。

const STUDY_SYSTEM = preload("res://System/Study/Study_System_Controller.gd")
const PLAYER = preload("res://Component/Player/V7/Traveler_V7.tscn")
const PLATFORM = preload("res://Component/Object/Transfer_Platform/Transfer_Platform.tscn")
const MULTIPART = preload("res://Component/VerticalGarden/Vertical_Object.tscn")
var checks := 0
var failures := 0
var game: Node2D
var level: Level
var player: PlayerController
var system: StudySystemController
var a: LayerObject
var b: LayerObject
var c: LayerObject
var multipart: LayerObject


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("STUDY_TRANSFER: " + message)


func _wait(count := 3) -> void:
	for tick in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _wait(2)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	Input.parse_input_event(event)
	await _wait(2)


func _run() -> void:
	_make_fixture()
	await _wait()
	_check(system.history.get_history_count() == 0, "初始无撤回记录")
	_check(not level.allow_scenery_overlap_outside_player_layer, "试验显式严格检查两层占用")
	_check(system.get_projection_anchor().is_equal_approx(Vector2(200, 720)), "投影取玩家X和固定Y720")
	_check(system.camera.global_position.is_equal_approx(Vector2(640, 450)), "镜头有自己的水平边界和纵向偏移")
	var initial_visible := a.visual_root.global_transform
	_check(initial_visible.origin.is_equal_approx(Vector2(440, 624)), "背景视觉使用固定投影基准")
	await _view_deadzone_regression()
	player.position.y = 280
	system.reset_view_interpolation()
	await _wait()
	_check(system.camera.global_position.y == 390 and system.get_projection_anchor().y == 720, "纵向取景移动不改变投影Y")
	_check(_same(a.visual_root.global_transform, initial_visible), "只上下移动镜头不改变景物相对世界的投影")
	player.position = Vector2(200, 600)
	system.reset_view_interpolation()
	var blocker := _blocker(Rect2(415, 607, 50, 34), 1)
	await _wait()
	Global.select_object(a)
	await _wait()
	var preview := system.get_preview_state()
	_check(not preview.valid and preview.target_slot == 0 and preview.anchor == Vector2(200, 720), "失败预览使用相同目标层和锚点")
	_check(preview.contacts.size() > 0, "失败预览标出实际碰撞位置")
	await _capture("01_blocked_preview")
	await _key(KEY_W)
	_check(a.owner_layer.slot == 1 and system.history.get_history_count() == 0, "失败W不移动物件也不记历史")
	blocker.queue_free()
	await _wait()
	player.velocity = Vector2(100, -20)
	player.facing_direction = -1
	var before_a := system.history.capture_state()
	await _key(KEY_W)
	_check(a.owner_layer.slot == 0, "真实W成功搬入玩家层")
	_check(system.history.get_history_count() == 1, "成功换层只记一次历史")
	_check(a.global_position.is_equal_approx(Vector2(440, 624)) and a.collision_box.scale.is_equal_approx(Vector2(0.8, 0.8)), "真实搬运与预览的固定Y结果一致")
	_check(_same(a.visual_root.global_transform, initial_visible), "换层前后可见位置和大小连续")
	player.position = Vector2(320, 310)
	system.reset_view_interpolation()
	await _wait()
	var before_b := system.history.capture_state()
	_check(system.transfer(-1, b), "第二次换层可搬往背景")
	_check(system.history.get_history_count() == 2, "两次成功有两条完整历史")
	var target_b := b.global_position
	_check(target_b.is_equal_approx(Vector2(795, 320)), "纵向镜头变化后搬往背景仍用Y720")
	# 其他物件和人物已继续变化，撤回必须恢复整个已知布局。
	c.global_position += Vector2(70, 50)
	player.position = Vector2(900, 100)
	player.velocity = Vector2(-200, 230)
	system.reset_view_interpolation()
	_check(system.undo_transfer(), "撤回最近成功换层")
	_check(_state_matches(before_b), "恢复全部对象、真实尺度和玩家根位")
	_check(player.velocity == Vector2(100, -20) and player.facing_direction == -1, "恢复必要人物运动状态")
	_check(system.history.get_history_count() == 1, "撤回仅消费一条成功历史")
	_check(system.get_projection_anchor() == before_b.anchor and _same(system.camera.global_transform, before_b.camera_pose), "整套恢复投影基准与取景")
	_check(Global.object_selected == null, "撤回清除旧选择与待执行交互")
	# 结构无效的记录先拒绝，不能恢复一半。
	var good := system.history.capture_state()
	var bad := good.duplicate(true)
	var altered: Transform2D = bad.objects[0].pose
	altered.origin.x += 100
	bad.objects[0].pose = altered
	_check(not system.history.restore_state(bad), "根位与保存碰撞不一致的历史被拒绝")
	_check(_state_matches(good), "非法历史拒绝没有改变任何实体")
	# 固定环境发生变化时，旧历史也不能把玩家塞进新墙。
	blocker = _blocker(Rect2(180, 510, 40, 90), 1)
	await _wait()
	_check(not system.undo_transfer(), "旧玩家位置被新固定墙占用时拒绝整套撤回")
	_check(_state_matches(good) and system.history.get_history_count() == 1, "失败恢复不移动任何物件且不消费历史")
	blocker.queue_free()
	await _wait()
	_check(system.undo_transfer(), "环境恢复后原历史仍可撤回")
	_check(_state_matches(before_a), "再次撤回回到第一次换层前整套布局")
	_check(not system.undo_transfer() and system.history.get_history_count() == 0, "空历史拒绝不会制造记录")
	_check(system.transfer(1, a), "键盘撤回准备")
	await _key(KEY_Z)
	_check(_state_matches(before_a) and system.history.get_history_count() == 0, "实际Z按键在物理帧撤回")
	_check(system.transfer(1, a), "初始重置准备")
	player.position = Vector2(700, 200)
	await _key(KEY_R)
	_check(a.owner_layer.slot == 1 and a.position == Vector2(500, 600) and a.collision_box.scale == Vector2.ONE, "实际R恢复初始全物件基线")
	_check(player.position == Vector2(200, 600) and player.velocity == Vector2.ZERO, "R恢复初始玩家位置和运动")
	_check(system.history.get_history_count() == 0, "R清空局部历史")
	# 严格背景也阻挡：不能用叠放豁免破坏物件空间选择。
	_check(system.transfer(1, a), "严格返回占用准备")
	blocker = _blocker(Rect2(475, 580, 50, 40), 2)
	await _wait()
	_check(not system.transfer(-1, a), "背景真实占用同样拒绝")
	_check(system.history.get_history_count() == 1, "背景失败不新增历史")
	blocker.queue_free()
	await _wait()
	await _key(KEY_Z)
	_check(a.owner_layer.slot == 1 and system.history.get_history_count() == 0, "返回失败后仍可用Z恢复成功搬出前整套状态")
	await _multipart_restore()
	await _live_extra_support_restore()
	await _live_support_restore()
	player.set_physics_process(false)
	_check(system.reset_study(), "活体落脚撤回后仍可完整R重置")
	system.projection_anchor_y = 540
	system.reset_view_interpolation()
	await _wait()
	_check(a.visual_root.global_position.is_equal_approx(Vector2(440, 588)), "非默认投影Y540的真实视觉")
	var nondefault := a.visual_root.global_transform
	_check(system.transfer(1, a) and a.global_position.is_equal_approx(Vector2(440, 588)), "非默认投影Y的搬运匹配视觉")
	_check(_same(nondefault, a.visual_root.global_transform), "非默认投影Y换层仍连续")
	_check(system.undo_transfer() and system.get_projection_anchor().y == 540, "撤回恢复对应历史锚点")
	_check(system.reset_study() and system.get_projection_anchor().y == 720, "R恢复最初投影锚点")
	if "--v6" in OS.get_cmdline_user_args():
		await _v6_small_restore()
	else:
		await _v7_small_restore()
	await _capture("02_restored")
	print("STUDY_TRANSFER: %d checks, %d failures." % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _view_deadzone_regression() -> void:
	player.position.y = 900
	system.reset_view_interpolation()
	await _wait()
	_check(system.view_use_deadzone and system.view_deadzone_y == 65 and system.camera.position.y == 750, "默认65px视野死区由新站位初始化")
	var visual_before := a.visual_root.global_transform
	player.position.y = 840
	await _wait()
	_check(system.camera.position.y == 750, "60px向上起伏在死区内不推动镜头")
	_check(system.get_projection_anchor().y == 720 and _same(a.visual_root.global_transform, visual_before), "死区取景不改变实际投影")
	player.position.y = 800
	await _wait()
	_check(system.camera.position.y == 715, "100px上升只推动越过65px死区的35px")
	player.position.y = 900
	await _wait()
	_check(system.camera.position.y == 715, "落回原高度仍在死区内时不反向拉镜头")
	player.position.y = 600
	await _wait()
	_check(system.camera.position.y == 515, "持续攀升越过死区后镜头持续跟进")
	player.position.y = 1500
	await _wait()
	_check(system.camera.position.y == system.view_max_y, "持续下落取景不越过纵向下边界")
	player.position.y = 0
	await _wait()
	_check(system.camera.position.y == system.view_min_y, "持续攀升取景不越过纵向上边界")
	system.view_use_deadzone = false
	player.position.y = 900
	await _wait()
	_check(system.camera.position.y == 750, "关闭死区可对照原直接跟随")
	system.view_use_deadzone = true
	player.position.y = 850
	await _wait()
	var state := system.history.capture_state()
	_check(system.camera.position.y == 750, "记录历史时保留死区内的实际取景偏移")
	player.position.y = 1500
	system.reset_view_interpolation()
	_check(system.history.restore_state(state), "带死区的完整历史可恢复")
	await _wait()
	_check(system.camera.position.y == 750 and player.position.y == 850, "恢复重新建立视野缓存，随后物理帧不被未来相机拉走")
	system.view_follow_y = false
	await _wait()
	_check(system.camera.position.y == level.camera_height, "关闭纵向跟随仍使用关卡固定高度")
	system.view_follow_y = true
	_check(system.reset_study(), "视野专项结束恢复初始完整基线")
	await _wait()
	_check(system.camera.position.y == 450 and system.get_projection_anchor().y == 720, "R恢复初始取景与固定解谜锚点")


func _make_fixture() -> void:
	game = Node2D.new()
	level = Level.new()
	level.name = "Level"
	level.layer_count = 2
	level.current_layer_index = 0
	level.allow_layer_cycle = false
	level.allow_uav = false
	level.allow_scenery_overlap_outside_player_layer = false
	game.add_child(level)
	for index in 2:
		var layer := DepthLayer.new()
		layer.name = "Mid" if index == 0 else "Back"
		layer.layer_id = index
		layer.slot = index
		level.add_child(layer)
	a = _object("A", Vector2(500, 600), 1)
	b = _object("B", Vector2(700, 400), 0)
	c = _object("C", Vector2(900, 300), 1)
	multipart = MULTIPART.instantiate()
	multipart.name = "Multipart"
	multipart.position = Vector2(1300, 550)
	multipart.set_meta("persistent_id", "Multipart")
	var polygons: Array[PackedVector2Array] = [PackedVector2Array([Vector2(-70, -30), Vector2(-20, -30), Vector2(-20, 0), Vector2(-70, 0)]), PackedVector2Array([Vector2(20, -40), Vector2(70, -40), Vector2(70, 0), Vector2(20, 0)])]
	multipart.set("solid_polygons", polygons)
	level.get_node("Mid").add_child(multipart)
	var player_scene: PackedScene = load("res://Component/Player/V6/Traveler_V6.tscn") if "--v6" in OS.get_cmdline_user_args() else PLAYER
	player = player_scene.instantiate()
	player.position = Vector2(200, 600)
	player.set_physics_process(false)
	game.add_child(player)
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	game.add_child(camera)
	system = STUDY_SYSTEM.new()
	system.player = player
	system.camera = camera
	system.level = level
	game.add_child(system)
	add_child(game)
	player.set_physics_process(false)


func _object(title: String, point: Vector2, slot: int) -> LayerObject:
	var object := PLATFORM.instantiate() as LayerObject
	object.name = title
	object.set_meta("persistent_id", title)
	object.set("dimensions", Vector2(80, 40))
	object.position = point
	level.get_node("Mid" if slot == 0 else "Back").add_child(object)
	return object


func _blocker(rect: Rect2, layer: int) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = layer
	body.position = rect.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	game.add_child(body)
	return body


func _state_matches(state: Dictionary) -> bool:
	if not _same(player.global_transform, state.player_pose):
		return false
	for saved: Dictionary in state.objects:
		var object: LayerObject = system.history._objects[saved.id]
		if object.owner_layer.layer_id != saved.layer_id or not _same(object.global_transform, saved.pose) or not _same(object.collision_box.transform, saved.collision_pose):
			return false
	return true


func _same(one: Transform2D, other: Transform2D) -> bool:
	return one.origin.distance_to(other.origin) < 0.002 and one.x.distance_to(other.x) < 0.002 and one.y.distance_to(other.y) < 0.002


func _capture(title: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://Exports/Study_Transfer")
	get_viewport().get_texture().get_image().save_png("res://Exports/Study_Transfer/" + title + ".png")


func _live_support_restore() -> void:
	_check(system.transfer(1, a), "真实落脚撤回准备平台")
	player.position = a.global_position + Vector2(0, -30)
	player.reset_motion()
	player.set_physics_process(true)
	system.reset_view_interpolation()
	await _wait(30)
	_check(player.is_on_floor(), "玩家真实站在可搬平台上")
	var supported := system.history.capture_state()
	_check(system.transfer(-1, a), "搬走玩家脚下平台")
	await _wait(12)
	_check(not player.is_on_floor() and player.global_position.y > Vector2(Transform2D(supported.player_pose).origin).y + 10, "玩家真实下落后再撤回")
	_check(system.undo_transfer(), "撤回恢复支撑物及玩家整套位置")
	_check(_state_matches(supported), "支撑物与玩家同时恢复，不靠安全传送另选落点")
	await _wait(2)
	_check(player.is_on_floor() and player.global_position.distance_to(Transform2D(supported.player_pose).origin) < 0.2, "撤回后真实碰撞继续承托玩家")


func _multipart_restore() -> void:
	var before := system.history.capture_state()
	_check(system.transfer(-1, multipart), "Vertical双段实体可搬远并放大1.25")
	await _wait()
	_check(multipart.collision_box.scale.is_equal_approx(Vector2(1.25, 1.25)), "双段实体实际尺度为1.25")
	_check(_registered_transforms_match(multipart), "搬运后两个直属碰撞轮廓与PhysicsServer真实尺度一致")
	_check(system.undo_transfer(), "Vertical双段实体可整套撤回")
	await _wait()
	_check(_state_matches(before) and _registered_transforms_match(multipart), "撤回恢复主轮廓与额外轮廓原始尺度")
	_check(multipart.get("_extra_solids").size() == 1, "测试实际包含额外直属碰撞轮廓")


func _live_extra_support_restore() -> void:
	player.position = multipart.global_position + Vector2(45, -55)
	player.reset_motion()
	player.set_physics_process(true)
	system.reset_view_interpolation()
	await _wait(30)
	_check(player.is_on_floor() and absf(player.position.y - 510) < 0.1, "人物真实站在第二段实体的510px踏面")
	var supported := system.history.capture_state()
	_check(system.transfer(-1, multipart), "搬走脚下非primary平台并放大1.25")
	await _wait(12)
	_check(not player.is_on_floor() and multipart.collision_box.scale.is_equal_approx(Vector2(1.25, 1.25)), "脚下双段平台已缩放离开，人物真实下落")
	_check(system.undo_transfer(), "Z整套恢复原比例双段平台与人物")
	_check(_state_matches(supported) and _registered_transforms_match(multipart), "Z当帧已恢复额外物理轮廓的原尺度")
	await _wait(2)
	_check(player.is_on_floor() and absf(player.position.y - 510) < 0.1, "Z后第二段真实承托人物而非只过手动查询")
	_check(system.transfer(-1, multipart), "R缩放恢复准备")
	await _wait(3)
	player.set_physics_process(false)
	_check(system.reset_study(), "R可从非primary支撑丢失状态重置")
	_check(multipart.owner_layer.slot == 0 and multipart.collision_box.scale == Vector2.ONE and _registered_transforms_match(multipart), "R恢复两段真实碰撞原始图层与尺度")
	_check(player.position == Vector2(200, 600) and system.history.get_history_count() == 0, "R同时恢复人物并清空历史")


func _registered_transforms_match(object: LayerObject) -> bool:
	var registered := 0
	for owner_id in object.get_shape_owners():
		if not _same(object.shape_owner_get_transform(owner_id), object.collision_box.transform):
			return false
		for index in object.shape_owner_get_shape_count(owner_id):
			var actual_index := object.shape_owner_get_shape_index(owner_id, index)
			if not _same(PhysicsServer2D.body_get_shape_transform(object.get_rid(), actual_index), object.collision_box.transform):
				return false
			registered += 1
	return registered >= 2


func _v6_small_restore() -> void:
	var visual := player.get_node("Visual_Body/Traveler")
	_check(visual.has_method("reset_after_restore"), "V6提供公共撤回复位入口")
	player.facing_direction = -1
	_check(system.transfer(1, a), "V6小距离撤回准备")
	var original := player.position
	player.position += Vector2(48, -10)
	player.facing_direction = 1
	await _wait(2)
	_check(system.undo_transfer() and player.position == original, "V6小于自动传送阈值的撤回真实恢复人物")
	var gait: RefCounted = visual.get("_gait")
	var feet: PackedVector2Array = gait.get("world_feet")
	_check(feet[0].distance_to(player.position) < 22 and feet[1].distance_to(player.position) < 22, "小距离Z当帧清掉未来位置的世界脚锚")
	_check(visual.get("pose") == visual.get("previous_pose"), "V6新旧姿态同帧重建，插值不拉回未来姿态")
	_check(int(visual.get("visual_facing")) == -1, "V6撤回立即跟随恢复的人物朝向")


func _v7_small_restore() -> void:
	var visual := player.get_node("Visual_Body/Traveler")
	var scarf := player.get_node("Visual_Body/Scarf")
	_check(visual.has_method("reset_after_restore") and scarf.has_method("reset_cloth"), "V7提供人物与围巾公共恢复入口")
	player.facing_direction = -1
	player.velocity = Vector2.ZERO
	_check(system.transfer(1, a), "V7小距离撤回准备")
	var original := player.global_position
	player.position += Vector2(48, -10)
	player.facing_direction = 1
	player.velocity = Vector2(320, -20)
	await _wait(8)
	_check(player.global_position.distance_to(original) < 100 and Vector2(visual.get("_last_position")).is_equal_approx(player.global_position), "近距离未来站位进入V7位移缓存，未触发自动传送重置")
	_check(absf(float(scarf.get("_wind"))) > 0.1, "近距离未来运动确实积累围巾惯性")
	_check(system.undo_transfer() and player.global_position == original, "V7小于自动传送阈值的Z真实恢复人物")
	_v7_restored_visual("近距离Z")
	player.position += Vector2(-32, -6)
	player.facing_direction = -1
	player.velocity = Vector2(-320, 20)
	await _wait(8)
	_check(player.global_position.distance_to(original) < 100 and absf(float(scarf.get("_wind"))) > 0.1, "近距离R之前同样积累未来姿态与围巾惯性")
	_check(system.reset_study() and player.position == Vector2(200, 600) and player.velocity == Vector2.ZERO, "V7近距离R真实恢复初始人物与运动")
	_v7_restored_visual("近距离R")
	_check(system.history.get_history_count() == 0, "V7近距离R仍清空完整换层历史")


func _v7_restored_visual(label: String) -> void:
	var visual := player.get_node("Visual_Body/Traveler")
	var scarf := player.get_node("Visual_Body/Scarf")
	# V7没有旧角色的世界脚锚。其等价恢复契约是清除位移与绘图历史，
	# 避免未来站位驱动下一物理帧或显示插值；真实落脚由上面的活体实体专项覆盖。
	_check(visual.get("pose") == visual.get("previous_pose"), label + "同帧重建前后姿态，插值不拉回未来")
	_check(Vector2(visual.get("_last_position")).is_equal_approx(player.global_position), label + "位移历史立即同步恢复站位")
	_check(float(visual.get("activity")) == 0 and float(visual.get("_step_offset")) == 0 and float(visual.get("_unsupported_time")) == 0, label + "清除动作与跨步失地历史")
	_check(int(visual.get("visual_facing")) == player.facing_direction, label + "视觉立即跟随恢复的人物朝向")
	_check(scarf.get("_points") == scarf.get("_previous_points") and scarf.get_ribbon_points().size() == 25, label + "完整围巾前后绘图历史同帧一致")
	_check(Vector2(scarf.get("_last_origin")).is_equal_approx(player.global_position) and float(scarf.get("_wind")) == 0, label + "围巾锚点历史与惯性立即重置")
