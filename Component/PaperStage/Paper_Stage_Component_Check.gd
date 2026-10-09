extends Node2D

var _checks := 0
var _failures := 0

func _ready() -> void:
	var level := Level.new()
	level.layer_count = 2
	level.current_layer_index = 0
	add_child(level)
	var front := DepthLayer.new()
	front.layer_id = 0
	front.slot = 0
	level.add_child(front)
	var back := DepthLayer.new()
	back.layer_id = 1
	back.slot = 1
	level.add_child(back)
	var tree := preload("res://Component/PaperStage/Hero_Fan_Tree.tscn").instantiate() as PaperStageObject
	front.add_child(tree)
	var arch := preload("res://Component/PaperStage/Broken_Arch_AI.tscn").instantiate() as PaperStageObject
	arch.position = Vector2(650,0)
	front.add_child(arch)
	for object in [tree,arch]:
		_check(object._collision_parts.size() > 0,"生成图追踪轮廓有效分解")
		_check(object.get_node("VisualRoot/Area2D").get_child_count()>0,"alpha透明轮廓可选择")
		_check(object.get_node("VisualRoot/Sprite2D").visible,"使用生成图而非native回退")
		var anchor := Vector2(320,360)
		object.apply_visual_transfer(anchor)
		var old_visual: Transform2D = object.visual_root.global_transform
		object.transfer_to(back,anchor)
		_check(object.visual_root.global_transform.is_equal_approx(old_visual),"移远保留画面位置与尺寸")
		object.transfer_to(front,anchor)
		_check(object.visual_root.global_transform.is_equal_approx(old_visual),"移回保留画面位置与尺寸")
	var arch_hole := Vector2(75,-100)
	var solid_inside := false
	for shape in arch._collision_parts:
		solid_inside = solid_inside or Geometry2D.is_point_in_polygon(arch_hole,(shape as ConvexPolygonShape2D).points)
	_check(not solid_inside,"残拱洞口无实体")
	var picked_inside := false
	for shape in arch.get_node("VisualRoot/Area2D").get_children():
		picked_inside = picked_inside or Geometry2D.is_point_in_polygon(arch_hole,(shape as CollisionPolygon2D).polygon)
	_check(not picked_inside,"残拱洞口不截获点选")
	for profile in range(5):
		var object := preload("res://Component/PaperStage/Paper_Stage_Object.tscn").instantiate() as PaperStageObject
		object.profile = profile
		object.dimensions = PaperStageForm.size_for(profile)
		front.add_child(object)
		_check(object._collision_parts.is_empty() == (profile == PaperStageForm.Profile.SEED_PLANT),"原生景物实体分类 %s"%profile)
		_check(object.get_node("VisualRoot/Area2D").get_child_count()>0,"原生景物可点选 %s"%profile)
	var island := PaperIsland.new()
	island.edge = PackedVector2Array([Vector2(0,510),Vector2(790,510)])
	island.thickness = 125
	add_child(island)
	var bottom := 0.0
	for point in (island.get_node("WorldBase") as CollisionPolygon2D).polygon:
		bottom = maxf(bottom,point.y)
	_check(bottom<690 and bottom>540,"岛下沿在视口内终止并留下纸面")
	_check(not Geometry2D.triangulate_polygon((island.get_node("WorldBase") as CollisionPolygon2D).polygon).is_empty(),"岛屿轮廓无交叉且可绘制")
	var atmosphere := PaperAtmosphere.new()
	add_child(atmosphere)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for object in [tree,arch]:
		var shape_count := 0
		for shape_owner in object.get_shape_owners():
			shape_count += object.shape_owner_get_shape_count(shape_owner)
		_check(shape_count>0,"Godot物理体注册实际实体形状")
	var body_point := PhysicsPointQueryParameters2D.new()
	body_point.position = arch.global_position + Vector2(-100,-30)
	body_point.collision_mask = 1
	body_point.collide_with_areas = false
	var body_hit := false
	for hit in get_world_2d().direct_space_state.intersect_point(body_point):
		body_hit = body_hit or hit.collider==arch
	_check(body_hit,"物理空间查询实际命中残拱左腿")
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screenshot := get_viewport().get_texture().get_image()
		var ink := screenshot.get_pixel(400,530)
		_check(ink.r<0.8 and ink.g<0.7 and ink.b<0.7,"GPU岛面确实绘制深墨色")
		var wash_center := screenshot.get_pixel(1100,100)
		var bare_paper := screenshot.get_pixel(900,650)
		var wash_difference := absf(wash_center.r-bare_paper.r)+absf(wash_center.g-bare_paper.g)+absf(wash_center.b-bare_paper.b)
		_check(wash_difference>0.015,"GPU裸纸各处显示实际不同的淡墨色洗")
		print("Paper wash GPU samples: ",wash_center.to_html()," / ",bare_paper.to_html())
		DirAccess.make_dir_recursive_absolute("res://Exports/Paper_Stage")
		screenshot.save_png("res://Exports/Paper_Stage/component_island.png")
	print("PaperStage components: %s checks, %s failures"%[_checks,_failures])
	get_tree().quit(0 if _failures==0 else 1)

func _check(condition: bool,message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
