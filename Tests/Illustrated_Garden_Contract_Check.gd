extends Node
var checks := 0
var failed := false
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	var game := (load("res://Illustrated_Garden_Game.tscn") as PackedScene).instantiate()
	add_child(game)
	await _ticks(8)
	var system := game.get_node("System") as StudySystemController
	var level := game.get_node("Level")
	for pair in [["Back/RootShard","Back/RootLeftFold"],["Back/PageHeelEcho","Back/PageRearFloor"],["Mid/SkyShard","Mid/SkyRim"],["Back/PageCrownEcho","Back/EastRearCrest"]]:
		var prop := level.get_node(pair[0]) as IllustratedGardenObject
		var shore := level.get_node(pair[1]) as IllustratedGardenTerrain
		var allowed_y := INF
		for polygon in prop.get_editor_geometry().solids:
			for index in polygon.size():
				var a: Vector2 = polygon[index]
				var b: Vector2 = polygon[(index+1)%polygon.size()]
				for step in maxi(1,int(a.distance_to(b)/3.0))+1:
					var p := a.lerp(b,float(step)/float(maxi(1,int(a.distance_to(b)/3.0))))
					allowed_y = minf(allowed_y,StoryLandformArt.edge_height(shore.walkable,prop.position.x+p.x)-p.y-0.25)
		print("FIT_Y ",prop.name," ",allowed_y)
	var initial_reason := system.history._validate(system.history.capture_state())
	var excludes: Array[RID] = [system.player.get_rid()]
	for object in get_tree().get_nodes_in_group("layer_objects"): excludes.append(object.get_rid())
	for object in get_tree().get_nodes_in_group("layer_objects"):
		for part in object.get_transfer_collision_parts(object.owner_layer,system.get_projection_anchor()):
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = part.shape
			query.transform = system._contact_tolerant_transform(part.shape,part.transform)
			query.collision_mask = 1 << object.owner_layer.layer_id
			query.exclude = excludes
			var hits := system.player.get_world_2d().direct_space_state.intersect_shape(query,64)
			if not hits.is_empty(): print("FIXED_OCCUPANCY ",object.name," ",hits)
	_require(initial_reason.is_empty(),"初始所有真实实体占用合法："+initial_reason)
	_require(system.projection_anchor_y==level.editor_projection_anchor_y,"运行投影读取Level单一源")
	_require(game.get_node("Player").position.distance_to(level.spawn)<2,"实际出生点读取Level.spawn")
	for layer in [level.get_node("Mid"),level.get_node("Back")]:
		for node in layer.get_children():
			if node.has_method("get_editor_geometry"):
				var geometry: Dictionary = node.get_editor_geometry()
				for polygon in geometry.solids:
					_require(not Geometry2D.decompose_polygon_in_convex(polygon).is_empty(),"物理凸分解："+str(node.name))
	game.queue_free()
	await _ticks(2)
	var changed := (load("res://Illustrated_Garden_Game.tscn") as PackedScene).instantiate()
	changed.get_node("Level").spawn = Vector2(410,1300)
	changed.get_node("Level").editor_projection_anchor_y = 880.0
	add_child(changed)
	await _ticks(6)
	_require(changed.get_node("Player").position.distance_to(Vector2(410,1300))<2,"变参出生点在入树前生效")
	_require(changed.get_node("System").projection_anchor_y==880.0,"变参投影在历史初始化前生效")
	var changed_system := changed.get_node("System") as StudySystemController
	_require(changed_system.history._initial.anchor.y==880.0,"R基线保存变参投影")
	if checks>=1: print("ILLUSTRATED_GARDEN_CONTRACT: %d checks"%checks)
	get_tree().quit(1 if failed else 0)
func _ticks(count: int) -> void:
	for n in count: await get_tree().physics_frame
func _require(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("ILLUSTRATED_CONTRACT_FAIL: "+message)
		get_tree().quit(1)
	else: print("PASS: "+message)
