extends Node2D

var _checks := 0
var _failures := 0
var _world: Node2D
var _level: Level
var _player: PlayerController
var _system: SystemController

func _ready() -> void:
	for count in [2,4]:
		_build_world(count)
		for family in SceneryFamilyLibrary.FAMILIES:
			for id in SceneryFamilyLibrary.PIECES[family]:
				await _check_piece(id,count)
		remove_child(_world)
		_world.free()
		await get_tree().physics_frame
	print("Scenery families: %s checks, %s failures"%[_checks,_failures])
	get_tree().quit(0 if _failures==0 else 1)

func _build_world(count: int) -> void:
	_world = Node2D.new()
	add_child(_world)
	_level = Level.new()
	_level.layer_count = count
	_level.current_layer_index = 1 if count==4 else 0
	_level.allow_uav = false
	_level.allow_layer_cycle = false
	_level.allow_scenery_overlap_outside_player_layer = true
	_world.add_child(_level)
	for index in range(count):
		var layer := DepthLayer.new()
		layer.layer_id = index
		layer.slot = index
		_level.add_child(layer)
	_player = preload("res://Component/Player/V3/Traveler_V3.tscn").instantiate() as PlayerController
	_player.position = Vector2(-5000,-5000)
	_world.add_child(_player)
	_player.activated = false
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = Vector2(640,360)
	_world.add_child(camera)
	_system = SystemController.new()
	_system.player = _player
	_system.camera = camera
	_system.camera_fixed = false
	_system.level = _level
	_world.add_child(_system)

func _check_piece(id: String, count: int) -> void:
	var object := SceneryFamilyLibrary.create_piece(id)
	_check(object!=null,"资源存在 %s"%id)
	if object==null:
		return
	object.position = Vector2(640,600)
	_system.get_layer_at_slot(Global.current_layer_index).add_child(object)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var data := object.piece
	_check(data.parent_texture!=null and data.region.has_area(),"父图与裁切记录 %s"%id)
	_check((object.texture_override as AtlasTexture).atlas==data.parent_texture,"直接引用父图不重复存图 %s"%id)
	_check(not object._collision_parts.is_empty(),"自然实体凸分解 %s"%id)
	var shape_count := 0
	for owner_id in object.get_shape_owners():
		shape_count += object.shape_owner_get_shape_count(owner_id)
	_check(shape_count>0,"物理服务器注册形状 %s"%id)
	_check(not object.get_footholds().is_empty(),"自然断口踏面记录 %s"%id)
	for empty in data.empty_points:
		var local := data.local_point(empty,object.dimensions)
		var filled := false
		for shape in object._collision_parts:
			filled = filled or Geometry2D.is_point_in_polygon(local,(shape as ConvexPolygonShape2D).points)
		_check(not filled,"洞口实体为空 %s"%id)
		var picked := false
		for polygon in object.get_node("VisualRoot/Area2D").get_children():
			picked = picked or Geometry2D.is_point_in_polygon(local,(polygon as CollisionPolygon2D).polygon)
		_check(not picked,"洞口不截获选择 %s"%id)
	var original_visual := object.visual_root.global_transform
	for target in range(count):
		while object.owner_layer.slot!=target:
			var direction := 1 if object.owner_layer.slot>target else -1
			_check(_system.transfer(direction,object),"允许换到槽位 %s / %s"%[target,id])
			_check(object.visual_root.global_transform.is_equal_approx(original_visual),"换层画面连续 %s"%id)
			_check(object.collision_layer==1<<object.owner_layer.layer_id,"碰撞随固定 layer_id %s"%id)
			await get_tree().physics_frame
			if object.owner_layer.slot!=target and not _system._transfer_rejection(direction,object).is_empty():
				break
	while object.owner_layer.slot!=Global.current_layer_index:
		var direction := 1 if object.owner_layer.slot>Global.current_layer_index else -1
		if not _system.transfer(direction,object):
			_check(false,"返回玩家层 %s"%id)
			break
		await get_tree().physics_frame
	if count==2:
		await _check_landing(object)
		object.mirror_x = true
		await get_tree().physics_frame
		await _check_landing(object)
	object.get_parent().remove_child(object)
	object.free()
	await get_tree().physics_frame

func _check_landing(object: SceneryFamilyObject) -> void:
	var surfaces := object.get_footholds()
	if surfaces.is_empty():
		return
	## 每个标出的结构断面均通过真实玩家落脚；不能把内部砖缝误标成踏面。
	for index in range(surfaces.size()):
		var edge := surfaces[index]
		var landing := (edge[0]+edge[1])*0.5+object.global_position
		_player.position = landing+Vector2(0,-28)
		_player.velocity = Vector2.ZERO
		_player.reset_physics_interpolation()
		for frame in range(35):
			await get_tree().physics_frame
			_player.velocity.y += 1800.0/60.0
			_player.move_and_slide()
			if _player.is_on_floor():
				break
		_check(_player.is_on_floor() and absf(_player.global_position.y-landing.y)<14.0,"真实落脚 %s foothold=%s mirror=%s got=%s wanted=%s"%[object.piece.piece_id,index,object.mirror_x,_player.global_position.y,landing.y])
		_player.position = Vector2(-5000,-5000)
		_player.velocity = Vector2.ZERO
		await get_tree().physics_frame

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
