extends "res://Component/SceneryFamilies/Scenery_Family_Check.gd"

func _ready() -> void:
	for count in [2,4]:
		_build_world(count)
		for id in DerivedCropLibrary.IDS+DerivedCropLibrary.BOTANICAL_IDS:
			var object := DerivedCropLibrary.create_botanical(id) if DerivedCropLibrary.BOTANICAL_IDS.has(id) else DerivedCropLibrary.create_piece(id)
			_check(object!=null,"局部派生资源 %s"%id)
			if object==null:
				continue
			object.position = Vector2(640,600)
			_system.get_layer_at_slot(Global.current_layer_index).add_child(object)
			await get_tree().physics_frame
			await get_tree().physics_frame
			var crop := object.piece as DerivedCropPiece
			_check(object._collision_parts.is_empty()==crop.non_solid,"薄冠无实体 / 断片有实体 %s"%id)
			var body_shapes := 0
			for owner_id in object.get_shape_owners():
				body_shapes += object.shape_owner_get_shape_count(owner_id)
			_check((body_shapes==0)==crop.non_solid,"物理服务器不注册薄植物实体 %s"%id)
			_check(object.get_node("VisualRoot/Area2D").get_child_count()>0,"薄冠与断片均可点选 %s"%id)
			var pick_area := object.get_node("VisualRoot/Area2D") as Area2D
			var pick_shapes := 0
			for owner_id in pick_area.get_shape_owners():
				pick_shapes += pick_area.shape_owner_get_shape_count(owner_id)
			_check(pick_shapes>0,"细茎轮廓已注册为实际点选形状 %s"%id)
			var outline := pick_area.get_child(0) as CollisionPolygon2D
			var triangles := Geometry2D.triangulate_polygon(outline.polygon)
			if triangles.size()>=3:
				var point := (outline.polygon[triangles[0]]+outline.polygon[triangles[1]]+outline.polygon[triangles[2]])/3.0
				var query := PhysicsPointQueryParameters2D.new()
				query.position = pick_area.global_transform*point
				query.collide_with_areas = true
				query.collide_with_bodies = false
				var picked := false
				for hit in get_world_2d().direct_space_state.intersect_point(query):
					picked = picked or hit.collider==pick_area
				_check(picked,"实际物理点选命中派生景物 %s"%id)
			else:
				_check(false,"派生点选轮廓可三角化 %s"%id)
			_check(object.texture_override is AtlasTexture,"保留父图 Atlas 裁框 %s"%id)
			for mask in crop.visual_masks:
				_check(not Geometry2D.triangulate_polygon(mask).is_empty(),"自然掩片无自交 %s"%id)
			_check(object.get_node("VisualRoot/Art").get_child_count()==crop.visual_masks.size(),"局部掩片或完整透明植物 %s"%id)
			_check(object.get_node("VisualRoot/Sprite2D").visible==crop.visual_masks.is_empty(),"按素材类型选择 UV 掩片 / Atlas 绘制 %s"%id)
			var original := object.visual_root.global_transform
			for target in range(count):
				while object.owner_layer.slot!=target:
					var direction := 1 if object.owner_layer.slot>target else -1
					if not _system.transfer(direction,object):
						_check(false,"局部景物换景 %s"%id)
						break
					_check(object.visual_root.global_transform.is_equal_approx(original),"局部裁片换景画面连续 %s"%id)
					await get_tree().physics_frame
			while object.owner_layer.slot!=Global.current_layer_index:
				if not _system.transfer(1 if object.owner_layer.slot>Global.current_layer_index else -1,object):
					_check(false,"返回玩家景别 %s"%id)
					break
				await get_tree().physics_frame
			if count==2 and not crop.non_solid:
				await _check_landing(object)
				object.mirror_x = true
				await get_tree().physics_frame
				await _check_landing(object)
			object.get_parent().remove_child(object)
			object.free()
			await get_tree().physics_frame
		remove_child(_world)
		_world.free()
		await get_tree().physics_frame
	print("Derived crops: %s checks, %s failures"%[_checks,_failures])
	get_tree().quit(0 if _failures==0 else 1)
