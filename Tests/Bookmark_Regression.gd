extends Node

const PLAYER_SCENE = preload("res://Component/Player/Player.tscn")
const OBJECT_SCENE = preload("res://Component/Object/Transfer_Platform/Transfer_Platform.tscn")
const MANAGER_SCRIPT = preload("res://Level/Bookmark_Manager.gd")
const STORAGE_PATH := "user://Tests/Bookmark_Regression_Save.json"
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_remove_test_save()
	var fixture: Dictionary = await _make_fixture(2)
	var manager: BookmarkManager = fixture.manager
	var tree: LayerObject = fixture.tree
	var box: LayerObject = fixture.box
	var original_tree := tree.position
	var original_scale := tree.collision_box.scale
	_check(manager.last_bookmark == 0 and manager.unlocked_bookmarks == [0], "首次配置从第一枚书签开始")
	_check(FileAccess.file_exists(STORAGE_PATH) and manager.storage_error.is_empty(), "首次记录写盘成功")
	_check(manager._objects.size() == 2, "记录全部可搬对象，固定地平线不纳入摆位")
	_check(not manager.return_to(1), "地图不能返回尚未发现的书签")
	_check(not manager.activate(99), "未知书签不会被创建")
	tree.transfer_to(fixture.background, fixture.system.camera.global_position)
	tree.position = Vector2(620, 530)
	box.position = Vector2(1030, 490)
	_check(manager.activate(1), "第二枚书签记录当前布局")
	var recorded_tree := tree.position
	var recorded_scale := tree.collision_box.scale
	_check(manager.unlocked_bookmarks == [0, 1], "两枚书签永久解锁")
	_check(manager.mark_ink("high_ink"), "墨水首次收集写永久进度")
	_check(not manager.mark_ink("high_ink"), "同一墨水不会重复收集")
	_check(manager.mark_ability("move_shadow"), "能力写永久进度")
	tree.position = Vector2(1600, 100)
	box.transfer_to(fixture.middle, fixture.system.camera.global_position)
	box.position = Vector2(1300, 300)
	fixture.player.velocity = Vector2(500, -200)
	Global.select_object(box)
	_check(manager.return_to(), "R 接口返回最近书签")
	_check(tree.position == recorded_tree and tree.owner_layer == fixture.background, "恢复树的层身份与书签位置")
	_check(tree.collision_box.scale.is_equal_approx(recorded_scale), "恢复物件实际碰撞尺度")
	_check(box.owner_layer == fixture.background and box.position == Vector2(1030, 490), "恢复第二个物件的层与位置")
	_check(fixture.player.global_position == Vector2(1220, 600) and fixture.player.velocity == Vector2.ZERO, "恢复脚底坐标并清运动")
	_check(Global.object_selected == null, "恢复清除选中引用")
	_check(manager.has_ink("high_ink") and manager.abilities.has("move_shadow"), "恢复摆位不撤销墨水与能力")
	manager.open_map()
	_check(manager.map_open and not fixture.player.activated, "展开地图冻结玩家运动")
	_check(manager._map_entries.get_child_count() == 2 and not manager._map_entries.get_child(0).disabled, "地图包含已发现的地点按钮")
	manager._map_entries.get_child(0).pressed.emit()
	_check(not manager.map_open and fixture.player.activated, "地图选择后收起并恢复控制")
	_check(manager.last_bookmark == 0 and tree.position == original_tree and tree.collision_box.scale == original_scale and tree.owner_layer == fixture.middle, "地图回到第一书签独立保存的布局")
	_check(manager.has_ink("high_ink") and manager.unlocked_bookmarks.size() == 2, "地图回退保留永久进度")
	manager.return_to(1)
	var absolute := ProjectSettings.globalize_path(STORAGE_PATH)
	_check(not FileAccess.file_exists(STORAGE_PATH + ".tmp"), "写盘替换完成后没有半成品临时文件")
	await _destroy_fixture(fixture)
	fixture = await _make_fixture(2)
	manager = fixture.manager
	_check(manager.last_bookmark == 1 and fixture.player.global_position == Vector2(1220, 600), "新会话从最近书签续接")
	_check(fixture.tree.position == recorded_tree and fixture.tree.owner_layer == fixture.background, "新会话加载跨层摆位")
	_check(manager.has_ink("high_ink") and manager.unlocked_bookmarks.size() == 2 and manager.abilities.has("move_shadow"), "新会话加载全部永久进度")
	manager._layouts["1"].append({"object_id": "deleted_arch", "layer_id": 1, "position": [900, 500], "collision_scale": [1, 1]})
	manager._layouts["1"].append({"object_id": "Tree", "layer_id": 31, "position": [999, 999], "collision_scale": [1, 1]})
	manager._layouts["1"].append({"object_id": "Tree", "layer_id": 1, "position": [999, 999], "collision_scale": [-1, 1]})
	manager._save()
	_check(manager.load_save() and fixture.tree.position == recorded_tree, "未知物件、未知层和非法尺度安全略过")
	fixture.player.global_position = Vector2(1220, 1200)
	await _tick(2)
	_check(fixture.player.global_position.y < 605 and manager.last_bookmark == 1, "坠落自动回书签")
	_check(manager.has_ink("high_ink"), "坠落不丢墨水")
	fixture.tree.transfer_to(fixture.middle, fixture.system.camera.global_position)
	fixture.tree.position = Vector2(1220, 540)
	manager.activate(1)
	await _tick(2)
	manager.return_to(1)
	_check(fixture.player.global_position != Vector2(1220, 600), "书签脚点被实体占用时选择近邻安全落点")
	_check(fixture.tree.position == Vector2(1220, 540), "安全落点不额外更改已记录景物")
	fixture.tree.transfer_to(fixture.background, fixture.system.camera.global_position)
	fixture.tree.position = Vector2(1800, 300)
	await _tick(2)
	manager.return_to(1)
	_check(fixture.player.global_position != Vector2(1220, 600), "同一调用恢复实体到书签脚点后立即选安全邻位")
	await _tick(8)
	_check(_player_clear(fixture.player, fixture.system), "恢复后八帧人物未穿入树或地面")
	_check(absf(fixture.player.global_position.x - 1220) <= 193 and fixture.player.global_position.y <= 605 and manager.last_bookmark == 1, "恢复后人物停在书签近邻，未弹出或坠落循环")
	await _destroy_fixture(fixture)
	fixture = await _make_fixture(2)
	manager = fixture.manager
	_check(fixture.tree.owner_layer == fixture.middle and fixture.tree.position == Vector2(1220, 540), "跨会话恢复树到书签脚点")
	_check(fixture.player.global_position != Vector2(1220, 600), "读盘同帧恢复占位实体后选择安全邻位")
	await _tick(8)
	_check(_player_clear(fixture.player, fixture.system) and absf(fixture.player.global_position.x - 1220) <= 193 and fixture.player.global_position.y <= 605, "跨会话恢复后八帧没有穿入、弹出或坠落循环")
	var file := FileAccess.open(STORAGE_PATH, FileAccess.WRITE)
	file.store_string("{broken_json")
	file.close()
	_check(not manager.load_save(), "损坏 JSON 不覆盖当前状态")
	_check(manager.last_bookmark == 1 and manager.has_ink("high_ink"), "损坏存档不会抹掉运行中的进度")
	await _destroy_fixture(fixture)
	fixture = await _make_fixture(4)
	manager = fixture.manager
	_check(manager.last_bookmark == 0 and not manager.has_ink("high_ink"), "坏 JSON 新会话回退到安全初始布局")
	_check(manager._layers.size() == 4, "非默认四层配置识别全部层身份")
	fixture.tree.transfer_to(fixture.far, fixture.system.camera.global_position)
	fixture.tree.position = Vector2(1500, 400)
	manager.activate(1)
	fixture.tree.transfer_to(fixture.middle, fixture.system.camera.global_position)
	_check(manager.return_to(1) and fixture.tree.owner_layer == fixture.far and fixture.tree.position == Vector2(1500, 400), "四层配置恢复远景物件身份与位置")
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(STORAGE_PATH))
	envelope.sha256 = "incorrect"
	file = FileAccess.open(STORAGE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(envelope))
	file.close()
	_check(not manager.load_save(), "校验不符的半写或篡改存档被拒绝")
	await _destroy_fixture(fixture)
	_remove_test_save()
	_check(not FileAccess.file_exists(STORAGE_PATH), "测试独立存档已清理")
	print("BOOKMARK_REGRESSION: %d checks, %d failures; isolated save %s" % [_checks, _failures.size(), absolute])
	for failure in _failures:
		push_error(failure)
	get_tree().quit(0 if _checks > 0 and _failures.is_empty() else 1)

func _make_fixture(layer_count: int) -> Dictionary:
	var root := Node2D.new()
	root.name = "BookmarkFixture"
	var level := Level.new()
	level.name = "Level"
	level.layer_count = layer_count
	level.current_layer_index = 0
	level.allow_layer_cycle = false
	level.allow_uav = false
	level.lock_camera_y = true
	level.camera_height = 360
	root.add_child(level)
	var layers: Array[DepthLayer] = []
	for index in range(layer_count):
		var layer := DepthLayer.new()
		layer.name = "Layer%d" % index
		layer.layer_id = index
		layer.slot = index
		level.add_child(layer)
		layers.append(layer)
	var floor := OBJECT_SCENE.instantiate() as TransferPlatform
	floor.name = "FixedHorizon"
	floor.can_transfer = false
	floor.position = Vector2(900, 700)
	floor.dimensions = Vector2(2400, 200)
	layers[0].add_child(floor)
	var tree := OBJECT_SCENE.instantiate() as TransferPlatform
	tree.name = "Tree"
	tree.set_meta("persistent_id", "Tree")
	tree.position = Vector2(380, 550)
	tree.dimensions = Vector2(100, 100)
	layers[0].add_child(tree)
	var box := OBJECT_SCENE.instantiate() as TransferPlatform
	box.name = "Box"
	box.set_meta("persistent_id", "Box")
	box.position = Vector2(900, 600)
	box.dimensions = Vector2(100, 100)
	layers[1].add_child(box)
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.name = "Player"
	player.position = Vector2(180, 600)
	root.add_child(player)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	root.add_child(camera)
	var system := SystemController.new()
	system.name = "System"
	system.player = player
	system.level = level
	system.camera = camera
	root.add_child(system)
	add_child(root)
	await _tick(3)
	var manager := MANAGER_SCRIPT.new() as BookmarkManager
	manager.save_path = STORAGE_PATH
	root.add_child(manager)
	var bookmarks: Array[Dictionary] = [{"id": 0, "title": "纸页初处", "position": Vector2(180, 600)}, {"id": 1, "title": "弯枝庭院", "position": Vector2(1220, 600)}]
	manager.configure(player, system, level, bookmarks)
	return {"root": root, "level": level, "player": player, "system": system, "manager": manager, "tree": tree, "box": box, "middle": layers[0], "background": layers[1], "far": layers[layer_count - 1]}

func _destroy_fixture(fixture: Dictionary) -> void:
	Global.clear_selection()
	fixture.root.queue_free()
	await _tick(2)

func _tick(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame

func _remove_test_save() -> void:
	for suffix in ["", ".tmp"]:
		var absolute := ProjectSettings.globalize_path(STORAGE_PATH + suffix)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _player_clear(player: PlayerController, system: SystemController) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = player.body_collision_box.shape
	query.transform = system._contact_tolerant_transform(query.shape, player.body_collision_box.global_transform)
	query.collision_mask = player.collision_mask
	query.exclude = [player.get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()
