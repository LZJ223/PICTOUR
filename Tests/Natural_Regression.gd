extends Node2D

## 自然绘本核心回归：真实90px玩家、凹形实体、同类可搬、两层／四层与禁存档关卡。
## 运行场景 res://Tests/Natural_Regression.tscn；不会读写默认用户书签文件。

var checks: int = 0
var failures: int = 0
var layers: Array[DepthLayer] = []
var player: PlayerController
var arch: NaturalObject
var tree: NaturalObject

func _ready() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("NATURAL_REGRESSION: " + label)

func _frames(count: int) -> void:
	for index in range(count):
		await get_tree().physics_frame

func _make_object(kind: int, dimensions: Vector2, position: Vector2) -> NaturalObject:
	var object := preload("res://Component/Object/Natural_Object/Natural_Object.tscn").instantiate() as NaturalObject
	object.kind = kind
	object.dimensions = dimensions
	object.position = position
	layers[0].add_child(object)
	object.apply_visual_transfer(Vector2(0,360))
	return object

func _run() -> void:
	var level := Level.new()
	level.layer_count = 2
	level.current_layer_index = 0
	level.allow_uav = false
	level.allow_layer_cycle = false
	add_child(level)
	for index in range(4):
		var layer := DepthLayer.new()
		layer.layer_id = index
		layer.slot = index
		level.add_child(layer)
		layers.append(layer)
	var ground := StaticBody2D.new()
	var floor_shape := CollisionPolygon2D.new()
	floor_shape.polygon = PackedVector2Array([Vector2(-2000,600),Vector2(2000,600),Vector2(2000,800),Vector2(-2000,800)])
	ground.add_child(floor_shape)
	layers[0].add_child(ground)
	arch = _make_object(2, Vector2(380,210),Vector2(500,600))
	tree = _make_object(1, Vector2(260,220),Vector2(-400,600))
	var plant := _make_object(4, Vector2(80,110),Vector2(0,600))
	player = preload("res://Component/Player/Traveler_Large.tscn").instantiate() as PlayerController
	player.position = Vector2(500,600)
	add_child(player)
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = Vector2(100,360)
	add_child(camera)
	RenderingServer.set_default_clear_color(Color("f3e9d3"))
	await _frames(8)
	await _capture("Natural_Object_Mid")
	_check(arch.get_class() == "StaticBody2D", "拱为实体StaticBody")
	_check(arch.get_transfer_collision_parts(layers[1],Vector2(0,360)).size() >= 3,"凹拱使用多个凸实体")
	_check(plant.allows_non_solid_transfer() and plant.get_transfer_collision_parts(layers[1],Vector2(0,360)).is_empty(),"草可搬而无实体")
	_check(player.is_on_floor() and absf(player.position.y-600) < 0.1,"90px玩家可处于拱洞下方地面")
	_check(not _hits_area(Vector2(500,530),arch),"拱洞为空白点选")
	_check(_hits_area(Vector2(335,540),arch),"拱脚可点选")
	_check(_hits_area(Vector2(-500,480),tree),"树扇叶可点选")
	_check(_hits_area(Vector2(0,507),plant),"无实体扇草可点选")
	player.global_position = Vector2(500,360)
	player.reset_motion()
	await _frames(30)
	_check(player.is_on_floor() and absf(player.position.y-390) < 0.1,"拱顶可站立")
	player.global_position = Vector2(275,600)
	player.reset_motion()
	await _frames(5)
	var first_arch_step := await _jump_to_surface(18,600-85.0*210.0/240.0)
	_check(first_arch_step,"90px玩家从地面实际跳至拱外下阶")
	if first_arch_step:
		var second_arch_step := await _jump_to_surface(18,600-160.0*210.0/240.0)
		_check(second_arch_step,"90px玩家从拱下阶实际跳至中阶")
		if second_arch_step:
			_check(await _jump_to_surface(18,390),"90px玩家从中阶实际跳至拱顶")
	player.global_position = Vector2(-508, 600 - 96.0 * 220.0/250.0)
	player.reset_motion()
	await _frames(5)
	_check(player.is_on_floor(),"矮树下枝可站立")
	var landed_upper := false
	Input.action_press("move_right")
	Input.action_press("sprint")
	Input.action_press("jump")
	for index in range(45):
		await _frames(1)
		if index > 5 and player.is_on_floor() and absf(player.position.y-(600-194.0*220.0/250.0)) < 0.25:
			landed_upper = true
			break
	Input.action_release("move_right")
	Input.action_release("sprint")
	Input.action_release("jump")
	_check(landed_upper,"90px玩家实际跑跳从下枝到错开的上枝")
	if landed_upper:
		player.reset_motion()
		await _frames(3)
		Input.action_press("move_right")
		Input.action_press("jump")
		var landed_top := false
		for index in range(45):
			await _frames(1)
			if index == 8:
				Input.action_release("move_right")
			if index > 5 and player.is_on_floor() and absf(player.position.y-380.0) < 0.25:
				landed_top = true
				break
		Input.action_release("move_right")
		Input.action_release("jump")
		_check(landed_top,"90px玩家实际跳至树梢")
	var anchor := Vector2(180,360)
	arch.apply_visual_transfer(anchor)
	var before := _visible_points(arch)
	_check(arch.transfer_to(layers[1],anchor),"拱中→背景搬运")
	_check(_same_points(before,_visible_points(arch)),"中→背景屏幕轮廓连续")
	_check(arch.collision_layer == 2,"搬运使用目标层实体碰撞位")
	await _frames(3)
	await _capture("Natural_Object_Background")
	_check(arch.transfer_to(layers[0],anchor),"拱背景→中搬运")
	_check(_same_points(before,_visible_points(arch)),"背景→中屏幕轮廓连续")
	Global.layer_count = 4
	Global.current_layer_index = 1
	Global.layer_scales = [1.25,1.0,0.8,0.64]
	arch.apply_visual_transfer(anchor)
	before = _visible_points(arch)
	for target in [layers[1],layers[2],layers[3],layers[0]]:
		_check(arch.transfer_to(target,anchor),"四层搬运到%d" % target.slot)
		_check(_same_points(before,_visible_points(arch)),"四层搬运轮廓连续%d" % target.slot)
		_check(arch.collision_layer == 1 << target.layer_id,"四层搬运碰撞归属%d" % target.slot)
	level.queue_free()
	player.queue_free()
	camera.queue_free()
	layers.clear()
	Global.clear_selection()
	await _frames(3)
	await _test_system_collision()
	await _test_transfer_layers(2,0)
	await _test_transfer_layers(4,1)
	await _test_authored_scene(false)
	await _test_authored_scene(true)
	print("NATURAL_REGRESSION: %d checks, %d failures" % [checks,failures])
	get_tree().quit(0 if checks >= 250 and failures == 0 else 1)

func _hits_area(point: Vector2, object: NaturalObject) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collide_with_bodies = false
	query.collide_with_areas = true
	for result in get_world_2d().direct_space_state.intersect_point(query,32):
		if object.is_ancestor_of(result.collider):
			return true
	return false

func _visible_points(object: NaturalObject) -> PackedVector2Array:
	var output := PackedVector2Array()
	var scaling := object.dimensions / NaturalForm.nominal_size(object.kind)
	for polygon in NaturalForm.pick_polygons(object.kind,object.variation):
		for point in polygon:
			output.append(object.visual_root.global_transform * (point * scaling))
	return output

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
	get_viewport().get_texture().get_image().save_png("res://Exports/"+label+".png")

func _jump_to_surface(direction_frames: int, expected_y: float) -> bool:
	player.reset_motion()
	await _frames(3)
	Input.action_press("move_right")
	Input.action_press("jump")
	var landed := false
	for index in range(55):
		await _frames(1)
		if index == direction_frames:
			Input.action_release("move_right")
		if index > 5 and player.is_on_floor() and absf(player.position.y-expected_y) < 0.3:
			landed = true
			break
	Input.action_release("move_right")
	Input.action_release("jump")
	return landed

func _system_fixture(count: int, current: int) -> Dictionary:
	var holder := Node2D.new()
	add_child(holder)
	var fixture_level := Level.new()
	fixture_level.layer_count = count
	fixture_level.current_layer_index = current
	fixture_level.allow_layer_cycle = false
	fixture_level.allow_uav = false
	fixture_level.lock_camera_y = true
	fixture_level.camera_height = 360
	holder.add_child(fixture_level)
	var fixture_layers: Array[DepthLayer] = []
	var slots: Array = [1,2,0,3] if count == 4 else [0,1]
	for index in range(count):
		var layer := DepthLayer.new()
		layer.layer_id = index
		layer.slot = slots[index]
		fixture_level.add_child(layer)
		fixture_layers.append(layer)
	var fixture_player := preload("res://Component/Player/Traveler_Large.tscn").instantiate() as PlayerController
	fixture_player.set_physics_process(false)
	fixture_player.position = Vector2(0,360)
	holder.add_child(fixture_player)
	var fixture_camera := Camera2D.new()
	fixture_camera.position = Vector2(0,360)
	fixture_camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	holder.add_child(fixture_camera)
	var fixture_system := SystemController.new()
	fixture_system.player = fixture_player
	fixture_system.level = fixture_level
	fixture_system.camera = fixture_camera
	holder.add_child(fixture_system)
	fixture_system.camera_fixed = false
	return {"root":holder,"level":fixture_level,"layers":fixture_layers,"player":fixture_player,"camera":fixture_camera,"system":fixture_system}

func _dispose_fixture(fixture: Dictionary) -> void:
	Global.clear_selection()
	fixture.root.queue_free()
	await _frames(3)

func _fixture_object(fixture: Dictionary, kind: int, slot: int, dimensions: Vector2, position: Vector2) -> NaturalObject:
	var object := preload("res://Component/Object/Natural_Object/Natural_Object.tscn").instantiate() as NaturalObject
	object.kind = kind
	object.dimensions = dimensions
	object.position = position
	fixture.system.get_layer_at_slot(slot).add_child(object)
	object.apply_visual_transfer(fixture.camera.global_position)
	return object

func _test_system_collision() -> void:
	var fixture := _system_fixture(2,0)
	await _frames(3)
	var doorway := _fixture_object(fixture,2,1,Vector2(475,300),Vector2(625,660))
	fixture.player.global_position = Vector2(500,600)
	await _frames(3)
	_check(fixture.system._transfer_rejection(1,doorway).is_empty(),"System的凹拱查询允许角色在真实空洞内")
	_check(fixture.system.transfer(1,doorway),"System实际将洞内有玩家的拱搬入")
	await _frames(3)
	_check(fixture.system.transfer(-1,doorway),"空洞拱可返回背景")
	await _frames(3)
	fixture.player.global_position = Vector2(338,600)
	await _frames(3)
	_check(not fixture.system._transfer_rejection(1,doorway).is_empty(),"System拒绝角色被拱柱实体覆盖")
	_check(not fixture.system.transfer(1,doorway),"拒绝实际搬运拱柱到玩家身上")
	_check(doorway.owner_layer.slot == 1,"拒绝搬运后拱仍处背景")
	var grass := _fixture_object(fixture,4,1,Vector2(100,137.5),Vector2(422.5,660))
	await _frames(3)
	_check(fixture.system._transfer_rejection(1,grass).is_empty(),"System允许无实体扇草与角色视觉重叠")
	_check(fixture.system.transfer(1,grass),"无实体扇草经System真实搬入")
	await _frames(3)
	Global._pick_at(Vector2(338,516))
	_check(Global.object_selected == grass,"Global真正点选无实体扇叶，未受玩家实体阻挡")
	Global.clear_selection()
	var empty_query := PhysicsPointQueryParameters2D.new()
	empty_query.position = Vector2(338,516)
	empty_query.collide_with_bodies = true
	empty_query.collide_with_areas = false
	empty_query.collision_mask = 1
	empty_query.exclude = [fixture.player.get_rid()]
	_check(get_world_2d().direct_space_state.intersect_point(empty_query).is_empty(),"草搬入后仍不形成实体障碍")
	await _dispose_fixture(fixture)

func _test_transfer_layers(count: int, current: int) -> void:
	var fixture := _system_fixture(count,current)
	await _frames(3)
	var system: SystemController = fixture.system
	for kind in range(5):
		var object := _fixture_object(fixture,kind,0,NaturalForm.nominal_size(kind),Vector2(800,620))
		await _frames(3)
		var before := _visible_points(object)
		_check(object.can_transfer,"%d层家族%d可搬" % [count,kind])
		var sequence: Array = [1,2,3,2,1,0] if count == 4 else [1,0]
		for target_slot in sequence:
			var direction: int = object.owner_layer.slot-int(target_slot)
			var target := system.get_layer_at_slot(target_slot)
			_check(system.transfer(direction,object),"%d层家族%d通过System搬到槽%d" % [count,kind,target_slot])
			await _frames(2)
			_check(_same_points(before,_visible_points(object)),"%d层家族%d搬到槽%d投影所有角点偏差<0.02" % [count,kind,target_slot])
			_check(object.owner_layer == target and object.get_parent() == target,"%d层家族%d槽%d父层和owner一致" % [count,kind,target_slot])
			_check(object.collision_layer == 1 << target.layer_id and object.collision_mask == 1 << target.layer_id,"%d层家族%d槽%d实体位对应ID%d" % [count,kind,target_slot,target.layer_id])
		object.queue_free()
		await _frames(3)
	await _dispose_fixture(fixture)

func _test_authored_scene(four_layers: bool) -> void:
	var path := "res://Tests/Natural_Layer_Lab.tscn" if four_layers else "res://Natural_Garden_Game.tscn"
	var packed := load(path) as PackedScene
	_check(packed != null,"加载自然样板／开发实验场景")
	if packed == null:
		return
	var game := packed.instantiate()
	var level := game.get_node("Level") as NaturalGardenLevel
	level.enable_bookmarks = false
	var avatar := game.get_node("Player") as PlayerController
	avatar.set_physics_process(false)
	add_child(game)
	await _frames(5)
	var count_by_kind := [0,0,0,0,0]
	for layer in level.get_children():
		if not layer is DepthLayer:
			continue
		for child in layer.get_children():
			if child is NaturalObject:
				_check(child.can_transfer,"实景%s同类景物%s可换层" % ["四景" if four_layers else "两景",child.name])
				count_by_kind[child.kind] += 1
			elif child is LayerDecoration:
				_check(false,"自然样板不应以非可搬LayerDecoration混入树与建筑")
	for kind in range(5):
		_check(count_by_kind[kind] > 0,"实景包含家族%d可搬样例" % kind)
	var horizon := level.get_node("PlayerLayer/PaperBank") as Node2D
	_check(not horizon is LayerObject,"地平线属于明确固定的世界底面")
	Global._pick_at(Vector2(100,650))
	_check(Global.object_selected == null,"点击真实地平线墨面不会选中景物")
	if four_layers:
		_check(level.layer_count == 4 and Global.current_layer_index == 1,"开发四景实验室使用当前槽1")
		var actual_slots: Dictionary = {}
		for layer in level.get_children():
			if layer is DepthLayer:
				actual_slots[layer.layer_id] = layer.slot
		_check(actual_slots == {0:1,1:2,2:0,3:3},"四景实验室ID与slot独立映射")
		_check(not level.allow_layer_cycle,"四景开发实验室仍禁止整体轮换")
	else:
		_check(level.layer_count == 2 and Global.current_layer_index == 0,"可玩样板仍保持序章两层")
		_check(not level.allow_uav and not level.allow_layer_cycle,"可玩样板未开放无人机／整体轮换")
	_check(level.bookmarks == null,"回归场景不初始化书签且不读写用户存档")
	Global.clear_selection()
	game.queue_free()
	await _frames(3)
