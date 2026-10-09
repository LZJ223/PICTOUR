@tool
extends Node
## 由真正EditorPlugin的--garden-editor-test入口运行；仅写Exports私有场景。
const CORE = preload("res://addons/pictour_garden_editor/Garden_Editor_Core.gd")
const FIXTURE := "res://Exports/Garden_Editor_Test/Editable_Garden.tscn"
var checks := 0
var failures := 0
var plugin: EditorPlugin
var _repaired_ids: Dictionary = {}


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("GARDEN_EDITOR: " + message)


func _ticks(count := 4) -> void:
	for tick in count: await get_tree().process_frame


func _history(root: Node) -> UndoRedo:
	var manager := plugin.get_undo_redo()
	return manager.get_history_undo_redo(manager.get_object_history_id(root))


func run(owner_plugin: EditorPlugin) -> void:
	plugin = owner_plugin
	await _ticks(30)
	_check(Engine.is_editor_hint(), "运行于实际编辑器进程")
	_check(plugin.get_undo_redo() is EditorUndoRedoManager, "使用Godot原生场景撤回管理器")
	_check(plugin.dock.is_inside_tree() and plugin.palette.item_count > 0, "插件停靠面板与真实素材目录已经加载")
	DirAccess.make_dir_recursive_absolute(FIXTURE.get_base_dir())
	var file := FileAccess.open(FIXTURE, FileAccess.WRITE)
	file.store_string("""[gd_scene load_steps=4 format=3]
[ext_resource type="Script" path="res://Level/Level.gd" id="1"]
[ext_resource type="Script" path="res://Component/Layer/Depth_Layer.gd" id="2"]
[sub_resource type="RectangleShape2D" id="Wall"]
size = Vector2(2000, 1200)
[node name="EditableGarden" type="Node2D"]
script = ExtResource("1")
layer_count = 2
current_layer_index = 0
allow_layer_cycle = false
allow_uav = false
[node name="Mid" type="Node2D" parent="."]
script = ExtResource("2")
layer_id = 0
slot = 0
[node name="Back" type="Node2D" parent="."]
script = ExtResource("2")
layer_id = 1
slot = 1
[node name="TestWall" type="StaticBody2D" parent="Back"]
position = Vector2(200, 300)
[node name="Shape" type="CollisionShape2D" parent="Back/TestWall"]
shape = SubResource("Wall")
""")
	file.close()
	if EditorInterface.get_open_scenes().has(FIXTURE):
		EditorInterface.reload_scene_from_path(FIXTURE)
		await _ticks(10)
	EditorInterface.open_scene_from_path(FIXTURE)
	await _ticks(30)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != FIXTURE:
		_check(false, "打开测试专用可编辑场景")
		_finish()
		return
	_check(CORE.layers_in(root).size() == 2 and plugin.layer_picker.item_count == 2, "场景切换刷新中/背景选择")
	_check(plugin.anchor_y.value == 720 and plugin.anchor_y.editable, "旧Level无导出基准时使用可输入的720回退")
	var mid := root.get_node("Mid")
	var back := root.get_node("Back")
	var entry := {"name": "测试页石", "scene": "res://Component/SceneryFamilies/Scenery_Family_Object.tscn", "piece": "res://Art/SceneryFamilies/Pieces/strata_shelf.tres"}
	var object: Node2D = plugin.insert_asset(entry, mid, Vector2(200, 600))
	await _ticks()
	if object == null:
		_check(false, "面板服务插入实际素材")
		_finish()
		return
	_check(object.owner == root and object.get_parent() == mid, "插入实例直属景别且owner可序列化")
	_check(object.position == Vector2(200, 600) and object.scale == Vector2.ONE, "使用素材原生根点，无包围盒落地与根缩放")
	_check(not CORE.polygons(object).is_empty() and not CORE.walkable_edges(object).is_empty(), "编辑器内真实实体和素材可踏边可读取")
	var id: String = object.get_meta("persistent_id")
	_check(not id.is_empty(), "新插入景物有稳定存档身份")
	_history(root).undo()
	await _ticks()
	_check(object.get_parent() == null, "真实场景Undo撤回插入")
	_history(root).redo()
	await _ticks()
	_check(object.get_parent() == mid and object.owner == root, "真实Redo恢复实例及序列化所有者")
	var collision := object.get_node("CollisionBox") as Node2D
	var before_collision := collision.transform
	_check(plugin.move_object(object, Vector2(245, 590)), "面板根位置修改进入原生历史")
	_check(object.position == Vector2(245, 590) and collision.transform == before_collision, "移动不单独偏移实体或图像")
	_history(root).undo()
	_check(object.position == Vector2(200, 600), "撤回位置修改")
	var preview := CORE.transfer_preview(root, object, back, Vector2(200, 720))
	_check(not preview.valid and not preview.contacts.is_empty(), "目标景别实际墙体产生失败接触轮廓")
	_check(preview.target_position.is_equal_approx(Vector2(200, 570)), "换层预览使用1/0.8真实世界变换")
	var wall := back.get_node("TestWall") as Node2D
	wall.position = Vector2(5000, 5000)
	await _ticks()
	preview = CORE.transfer_preview(root, object, back, Vector2(200, 720))
	_check(preview.valid, "移走测试墙后预览可通过")
	var terrain_script := load("res://Component/IllustratedGarden/Illustrated_Terrain.gd")
	var terrain: Node2D = terrain_script.new()
	terrain.name = "TestBackgroundLand"
	terrain.set("upper", PackedVector2Array([Vector2(-500,100),Vector2(900,100)]))
	terrain.set("lower", PackedVector2Array([Vector2(900,900),Vector2(-500,900)]))
	back.add_child(terrain)
	terrain.owner = root
	await _ticks()
	preview = CORE.transfer_preview(root, object, back, Vector2(200,720))
	_check(not preview.valid and not preview.contacts.is_empty(), "真实新背景地貌生成的实体也阻挡目标换层")
	_check(not CORE.walkable_edges(terrain.get_node("WorldOccupancy")).is_empty(), "背景地貌可踏上沿来自同一真实轮廓")
	back.remove_child(terrain)
	terrain.free()
	_check(plugin.assign_layer(object, back), "面板修改景别归属")
	_check(object.get_parent() == back and object.position == Vector2(200, 600) and collision.transform == before_collision, "编辑归属保留真实坐标和原尺寸")
	_history(root).undo()
	_check(object.get_parent() == mid and object.owner == root, "撤回景别归属")
	_history(root).redo()
	_check(object.get_parent() == back, "重做景别归属")
	_check(plugin.delete_object(object), "面板删除进入原生历史")
	_check(object.get_parent() == null, "删除从场景移出但由撤回引用保留")
	_history(root).undo()
	_check(object.get_parent() == back and object.owner == root and object.get_meta("persistent_id") == id, "撤回删除恢复同一对象与稳定ID")
	var new_piece := "res://Art/IllustratedGarden/Pieces/root_gate.tres"
	if ResourceLoader.exists(new_piece):
		var fresh: Node2D = plugin.insert_asset({"name":"测试卷根", "scene":"res://Component/IllustratedGarden/Illustrated_Object.tscn", "piece":new_piece}, mid, Vector2(1050, 720))
		await _ticks()
		_check(fresh != null and not CORE.polygons(fresh).is_empty(), "新绘本父素材@tool插入后立即有可见实体")
		if fresh != null:
			_check(not CORE.walkable_edges(fresh).is_empty(), "新素材的真实踏边接口可读")
			var manager := plugin.get_undo_redo()
			manager.create_action("测试原生Inspector属性", UndoRedo.MERGE_DISABLE, root)
			manager.add_do_property(fresh, "mirror_x", true)
			manager.add_undo_property(fresh, "mirror_x", false)
			manager.commit_action()
			_check(fresh.get("mirror_x"), "导出镜像参数可通过原生属性历史修改")
			_history(root).undo()
			_check(not fresh.get("mirror_x"), "镜像撤回触发@tool同步重建")
			_history(root).redo()
			manager.create_action("测试尺寸导出属性", UndoRedo.MERGE_DISABLE, root)
			manager.add_do_property(fresh, "size_multiplier", 0.75)
			manager.add_undo_property(fresh, "size_multiplier", 1.0)
			manager.commit_action()
	else:
		_check(false, "新绘本素材接口必须真实接入，不仅测试旧palette")
	var botanical := {"name":"测试铃花", "scene":"res://Component/SceneryFamilies/Derived_Crop_Object.tscn", "piece":"res://Art/SceneryFamilies/Botanical/Pieces/bell_spray.tres"}
	var plant: Node2D = plugin.insert_asset(botanical, mid, Vector2(1600,720))
	await _ticks()
	_check(plant != null and CORE.polygons(plant).is_empty(), "纯花草可以放入但不制造虚假实体")
	_check(CORE.transfer_preview(root, plant, back, Vector2(200,720)).valid, "无实体花草换层预览不误报障碍")
	var botanical_in_palette := false
	for item in plugin.entries:
		botanical_in_palette = botanical_in_palette or item.piece == botanical.piece
	_check(botanical_in_palette, "面板目录包含现有植物Resource")
	await _identity_check(root, object, plant)
	var expected_path := root.get_path_to(object)
	plugin.save_current_scene()
	await _ticks(10)
	var saved := load(FIXTURE) as PackedScene
	var copy := saved.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var saved_object := copy.get_node_or_null(expected_path)
	_check(saved_object != null, "EditorInterface保存后PackedScene存在插入节点")
	if saved_object != null:
		_check(saved_object.get_meta("persistent_id", "") == id and saved_object.position == Vector2(200,600), "保存保留身份、根位置与景别")
		_check(saved_object.get("piece").resource_path == entry.piece, "保存保留外部素材Resource引用")
	var saved_fresh := copy.get_node_or_null("Mid/测试卷根")
	_check(saved_fresh != null and bool(saved_fresh.get("mirror_x")) and is_equal_approx(float(saved_fresh.get("size_multiplier")), 0.75), "保存保留新素材导出的镜像与尺寸参数")
	var saved_ids_match := true
	for path in _repaired_ids:
		var repaired := copy.get_node_or_null(NodePath(path))
		saved_ids_match = saved_ids_match and repaired != null and repaired.get_meta("persistent_id", "") == _repaired_ids[path]
	_check(saved_ids_match and CORE.identity_repairs(copy).is_empty(), "修复身份保存后保持新ID且全体非空唯一")
	copy.free()
	EditorInterface.reload_scene_from_path(FIXTURE)
	await _ticks(30)
	var reloaded := EditorInterface.get_edited_scene_root()
	_check(reloaded != root and reloaded.get_node_or_null(expected_path) != null, "实际编辑器重载同一场景后物件仍可编辑")
	if reloaded != null:
		var new_object := reloaded.get_node(expected_path)
		_check(new_object.owner == reloaded and not CORE.polygons(new_object).is_empty(), "重载不丢owner且@tool实体重建")
		_check(CORE.identity_repairs(reloaded).is_empty(), "实际编辑器重载后不再出现重复/空身份")
	await _actual_map_check()
	_finish()


func _identity_check(root: Node, original: Node2D, plant: Node2D) -> void:
	var original_id: String = original.get_meta("persistent_id")
	var plant_id: String = plant.get_meta("persistent_id")
	# 模拟原生复制保留元数据的结果，不制作第二套复制工具。
	var clone := original.duplicate() as Node2D
	clone.name = "复制页石"
	clone.position += Vector2(700, 0)
	original.get_parent().add_child(clone)
	clone.owner = root
	var empty := plant.duplicate() as Node2D
	empty.name = "空身份花"
	empty.set_meta("persistent_id", "")
	plant.get_parent().add_child(empty)
	empty.owner = root
	var missing := plant.duplicate() as Node2D
	missing.name = "缺身份花"
	missing.remove_meta("persistent_id")
	plant.get_parent().add_child(missing)
	missing.owner = root
	await _ticks()
	_check(clone.get_meta("persistent_id") == original_id and CORE.identity_repairs(root).size() == 3, "模拟原生复制的重复身份及空/缺失身份")
	_check(plugin.repair_identities() == 3, "面板同一服务只修复三个问题身份")
	_check(original.get_meta("persistent_id") == original_id and plant.get_meta("persistent_id") == plant_id, "首个有效身份与其他原有身份保留")
	_check(CORE.identity_repairs(root).is_empty(), "修复后直属实体及花草身份全部非空唯一")
	for node in [clone, empty, missing]:
		_repaired_ids[str(root.get_path_to(node))] = node.get_meta("persistent_id")
	_history(root).undo()
	_check(clone.get_meta("persistent_id") == original_id and empty.get_meta("persistent_id") == "" and not missing.has_meta("persistent_id"), "原生Undo准确还原重复、空字符串与缺失元数据")
	_history(root).redo()
	var redo_matches := true
	for path in _repaired_ids:
		redo_matches = redo_matches and root.get_node(NodePath(path)).get_meta("persistent_id") == _repaired_ids[path]
	_check(redo_matches and CORE.identity_repairs(root).is_empty(), "Redo复用同一组新身份而非再次随机化")
	var before_version := _history(root).get_version()
	_check(plugin.repair_identities() == 0 and _history(root).get_version() == before_version, "再次检查无问题时不修改任何ID或历史")


func _actual_map_check() -> void:
	var map_path := "res://Level/Illustrated_Garden_Level.tscn"
	var original_text := FileAccess.get_file_as_string(map_path)
	plugin._open_map()
	await _ticks(30)
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != map_path:
		_check(false, "面板一键打开真实新地图Level")
		return
	_check(true, "面板一键打开真实新地图Level")
	_check(CORE.has_property(root, &"editor_projection_anchor_y") and is_equal_approx(float(root.get("editor_projection_anchor_y")), 920), "新Level持有统一920投影基准")
	_check(plugin.anchor_y.value == float(root.get("editor_projection_anchor_y")) and not plugin.anchor_y.editable, "面板自动读取新Level投影Y并禁止静默分裂")
	var gate := root.get_node("Mid/RootGate") as Node2D
	plugin._select(gate)
	await _ticks(2)
	var gate_preview: Dictionary = plugin.selected_transfer_preview()
	var anchor := Vector2(plugin.anchor_x.value, float(root.get("editor_projection_anchor_y")))
	var expected := anchor + (gate.global_position - anchor) / float(root.get("layer_scale"))
	_check(not gate_preview.is_empty() and Vector2(gate_preview.target_position).is_equal_approx(expected), "同一面板预览服务使用真实新Level基准计算目标实体")
	var layers := CORE.layers_in(root)
	_check(layers.size() == 2 and plugin.layer_picker.item_count == 2, "真实地图只有两个直属景别进入面板")
	var counts := [0, 0]
	var solid_count := 0
	var terrain_count := 0
	var all_owned := true
	var all_geometry := true
	for layer in layers:
		_check(CORE.flat_parent(root, layer), "真实景别可直接编辑且祖先单位变换：" + str(layer.name))
		for child in layer.get_children():
			if CORE.is_object(child):
				counts[int(layer.get("slot"))] += 1
				all_owned = all_owned and child.owner == root
				if not child.allows_non_solid_transfer():
					solid_count += 1
					all_geometry = all_geometry and not CORE.polygons(child).is_empty()
				plugin._select(child)
				await _ticks(2)
				_check(plugin._selected_object() == child and plugin.layer_picker.selected == layers.find(layer), "面板选中真实直属景物：" + str(child.name))
			elif child.has_method("get_editor_geometry"):
				terrain_count += 1
				all_geometry = all_geometry and not CORE.bodies_under(child).is_empty()
				for polygon in child.get_editor_geometry().get("solids", []):
					_check(not Geometry2D.decompose_polygon_in_convex(polygon).is_empty(), "真实岸体物理凸分解：" + str(child.name))
	_check(counts[0] > 0 and counts[1] > 0 and all_owned, "中背景真实景物均属于可保存的原始地图")
	_check(solid_count > 0 and terrain_count > 0 and all_geometry, "真实地图素材和背景地貌实体均可供诊断读取")
	_check(FileAccess.get_file_as_string(map_path) == original_text, "只读检查未写回默认地图")


func _finish() -> void:
	print("GARDEN_EDITOR: %d checks, %d failures." % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
