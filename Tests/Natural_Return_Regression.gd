extends Node2D
## 背景叠景的可逆搬运与占用边界；禁用样板书签，不访问玩家进度。

var checks: int = 0
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await _authored_return("PassageArch")
	await _authored_return("RootBridge")
	await _family_roundtrips(2, 0)
	await _family_roundtrips(4, 1)
	await _player_layer_guards()
	await _inactive_layer_guards()
	print("NATURAL_RETURN_REGRESSION: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if checks == 172 and failures == 0 else 1)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("NATURAL_RETURN_REGRESSION: " + label)

func _frames(count: int = 3) -> void:
	for frame in range(count):
		await get_tree().physics_frame

func _tap_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	Input.parse_input_event(event)
	await _frames(2)

func _authored_return(title: String) -> void:
	var game := preload("res://Natural_Garden_Game.tscn").instantiate()
	var level := game.get_node("Level") as NaturalGardenLevel
	level.enable_bookmarks = false
	_check(level.allow_scenery_overlap_outside_player_layer, "样板显式开启非玩家叠景")
	level.allow_scenery_overlap_outside_player_layer = false
	var player := game.get_node("Player") as PlayerController
	player.set_physics_process(false)
	player.position = Vector2(800, 600)
	add_child(game)
	player.set_physics_process(false)
	await _frames(5)
	var system := game.get_node("System") as SystemController
	var object := level.get_node("BackgroundLayer/" + title) as NaturalObject
	var original := object.global_position
	var original_scale := object.collision_box.scale
	var outline := _visible_points(object)
	if title == "PassageArch":
		await _capture("Before")
	Global.select_object(object)
	await _tap_key(KEY_W)
	_check(object.owner_layer.slot == 0, title + "真实W按键可搬入玩家层")
	_check(_same_points(outline, _visible_points(object)), title + "搬入轮廓连续")
	if title == "PassageArch":
		await _capture("Middle")
	var middle_position := object.global_position
	await _tap_key(KEY_S)
	_check(object.owner_layer.slot == 0, title + "复现旧占用规则使S不能返回")
	_check(object.global_position.is_equal_approx(middle_position), title + "旧拒绝不修改位置")
	level.allow_scenery_overlap_outside_player_layer = true
	await _tap_key(KEY_S)
	_check(object.owner_layer.slot == 1, title + "新规则真实S按键允许返回叠景")
	_check(object.global_position.distance_to(original) < 0.02, title + "返回原根位置，不吸附或偏移")
	_check(object.collision_box.scale.distance_to(original_scale) < 0.0001, title + "返回原实体尺度")
	_check(_same_points(outline, _visible_points(object)), title + "往返可见轮廓完全连续")
	if title == "PassageArch":
		await _capture("Returned")
	_check(level.bookmarks == null, title + "回归不初始化或读写玩家存档")
	Global.clear_selection()
	game.queue_free()
	await _frames()

func _fixture(count: int, current: int) -> Dictionary:
	var holder := Node2D.new()
	add_child(holder)
	var level := Level.new()
	level.layer_count = count
	level.current_layer_index = current
	level.allow_layer_cycle = false
	level.allow_uav = false
	level.allow_scenery_overlap_outside_player_layer = true
	holder.add_child(level)
	var slots: Array = [1, 2, 0, 3] if count == 4 else [0, 1]
	for id in range(count):
		var layer := DepthLayer.new()
		layer.layer_id = id
		layer.slot = slots[id]
		level.add_child(layer)
	var player := preload("res://Component/Player/Traveler_Large.tscn").instantiate() as PlayerController
	player.position = Vector2(0, 360)
	player.set_physics_process(false)
	holder.add_child(player)
	player.set_physics_process(false)
	var camera := Camera2D.new()
	camera.position = Vector2(0, 360)
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	holder.add_child(camera)
	var system := SystemController.new()
	system.level = level
	system.player = player
	system.camera = camera
	holder.add_child(system)
	system.camera_fixed = false
	return {"root":holder, "level":level, "player":player, "camera":camera, "system":system}

func _object(fixture: Dictionary, kind: int, slot: int, point: Vector2, size: Vector2 = Vector2.ZERO) -> NaturalObject:
	var object := preload("res://Component/Object/Natural_Object/Natural_Object.tscn").instantiate() as NaturalObject
	object.kind = kind
	object.dimensions = NaturalForm.nominal_size(kind) if size == Vector2.ZERO else size
	object.position = point
	fixture.system.get_layer_at_slot(slot).add_child(object)
	object.apply_visual_transfer(fixture.camera.global_position)
	return object

func _body(fixture: Dictionary, slot: int, point: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	var layer: DepthLayer = fixture.system.get_layer_at_slot(slot)
	body.collision_layer = 1 << layer.layer_id
	body.collision_mask = body.collision_layer
	body.position = point
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	body.add_child(shape)
	layer.add_child(body)
	return body

func _dispose(fixture: Dictionary) -> void:
	Global.clear_selection()
	fixture.root.queue_free()
	await _frames()

func _family_roundtrips(count: int, current: int) -> void:
	var fixture := _fixture(count, current)
	var system: SystemController = fixture.system
	await _frames()
	for slot in range(count):
		if slot != current:
			var anchor: Vector2 = fixture.camera.global_position
			var point: Vector2 = anchor + (Vector2(800, 600) - anchor) / Global.layer_scales[slot]
			_object(fixture, NaturalForm.Kind.ROCK, slot, point, Vector2(1600, 1200))
	await _frames()
	for kind in range(5):
		var object := _object(fixture, kind, current, Vector2(800, 600))
		await _frames()
		var outline := _visible_points(object)
		fixture.level.allow_scenery_overlap_outside_player_layer = false
		var strict_reason: String = system._transfer_rejection(-1, object)
		_check(strict_reason.is_empty() == (kind == NaturalForm.Kind.PLANT), "%d层家族%d关闭叠景保持旧实体占用规则" % [count, kind])
		fixture.level.allow_scenery_overlap_outside_player_layer = true
		var targets: Array = [1, 0] if count == 2 else [2, 3, 2, 1, 0, 1]
		for slot in targets:
			var target: DepthLayer = system.get_layer_at_slot(slot)
			_check(system.transfer(object.owner_layer.slot - int(slot), object), "%d层家族%d可进入叠放槽%d" % [count, kind, slot])
			await _frames(2)
			_check(_same_points(outline, _visible_points(object)), "%d层家族%d叠景往返不改变可见轮廓%d" % [count, kind, slot])
			_check(object.owner_layer == target and object.collision_layer == 1 << target.layer_id, "%d层家族%d使用固定ID碰撞归属%d" % [count, kind, target.layer_id])
		_check(object.global_position.distance_to(Vector2(800, 600)) < 0.02 and object.collision_box.scale.is_equal_approx(Vector2.ONE), "%d层家族%d循环返回原位原尺度" % [count, kind])
		object.queue_free()
		await _frames()
	await _dispose(fixture)

func _player_layer_guards() -> void:
	var fixture := _fixture(2, 0)
	var object := _object(fixture, NaturalForm.Kind.ROCK, 1, Vector2(1000, 660))
	var system: SystemController = fixture.system
	await _frames()
	var tree := _object(fixture, NaturalForm.Kind.SHORT_TREE, 0, Vector2(800, 600))
	await _frames()
	_check(not system.transfer(1, object), "玩家层仍拒绝岩石穿入树实体")
	_check(object.owner_layer.slot == 1 and object.global_position.is_equal_approx(Vector2(1000, 660)), "玩家层拒绝不改归属和位置")
	tree.queue_free()
	await _frames()
	fixture.player.global_position = Vector2(800, 600)
	await _frames()
	_check(not system.transfer(1, object), "玩家层仍拒绝景物穿入90px人物")
	fixture.player.global_position = Vector2(0, 360)
	var ground := _body(fixture, 0, Vector2(800, 580), Vector2(220, 40))
	await _frames()
	_check(not system.transfer(1, object), "玩家层仍拒绝穿入固定地形")
	ground.queue_free()
	await _frames()
	_check(system.transfer(1, object), "移除真实占用后玩家层允许正常搬入")
	await _dispose(fixture)

func _inactive_layer_guards() -> void:
	var fixture := _fixture(2, 0)
	var system: SystemController = fixture.system
	var object := _object(fixture, NaturalForm.Kind.ROCK, 0, Vector2(800, 600))
	for index in range(40):
		_object(fixture, NaturalForm.Kind.ROCK, 1, Vector2(1000, 660), Vector2(260, 180))
	await _frames()
	_check(system._transfer_rejection(-1, object).is_empty(), "非玩家景别允许超过查询默认上限的40件景物叠放")
	var wall := _body(fixture, 1, Vector2(1000, 620), Vector2(260, 140))
	await _frames()
	_check(not system.transfer(-1, object), "40件允许景物后方的真实墙体仍拒绝搬入")
	wall.queue_free()
	await _frames()
	fixture.player.global_position = Vector2(1000, 660)
	fixture.player.set_collision_group(2)
	await _frames()
	_check(not system.transfer(-1, object), "非玩家景别中的角色实体仍拒绝搬入")
	fixture.player.global_position = Vector2(0, 360)
	fixture.player.set_collision_group(1)
	var legacy := preload("res://Component/Object/Transfer_Platform/Transfer_Platform.tscn").instantiate() as LayerObject
	legacy.position = Vector2(800, 600)
	system.get_layer_at_slot(0).add_child(legacy)
	await _frames()
	_check(not system.transfer(-1, legacy), "旧物件不获得自然景物叠放豁免")
	legacy.queue_free()
	await _frames()
	_check(system.transfer(-1, object), "真实障碍移走后背景搬入通过")
	await _frames()
	_check(system.transfer(1, object), "40件背景叠景中的物件仍可返回空闲玩家层")
	var default_level := Level.new()
	_check(not default_level.allow_scenery_overlap_outside_player_layer, "Level默认参数保持旧原型的严格占用")
	default_level.free()
	await _dispose(fixture)

func _visible_points(object: NaturalObject) -> PackedVector2Array:
	var points := PackedVector2Array()
	var scaling := object.dimensions / NaturalForm.nominal_size(object.kind)
	for polygon in NaturalForm.pick_polygons(object.kind, object.variation):
		for point in polygon:
			points.append(object.visual_root.global_transform * (point * scaling))
	return points

func _same_points(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if first[index].distance_to(second[index]) > 0.02:
			return false
	return true

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://Exports/Natural_Return_" + label + ".png")
