@tool
extends EditorPlugin
## 地图仍是原生.tscn；本面板只组织项目已有操作，不维护第二份布局数据。

const CORE = preload("Garden_Editor_Core.gd")
const MAP_PATH := "res://Level/Illustrated_Garden_Level.tscn"
const CATALOGS := [
	["新绘本", "res://Art/IllustratedGarden/Pieces", "res://Component/IllustratedGarden/Illustrated_Object.tscn"],
	["父素材", "res://Art/SceneryFamilies/Pieces", "res://Component/SceneryFamilies/Scenery_Family_Object.tscn"],
	["派生素材", "res://Art/SceneryFamilies/Crops", "res://Component/SceneryFamilies/Derived_Crop_Object.tscn"],
	["花草", "res://Art/SceneryFamilies/Botanical/Pieces", "res://Component/SceneryFamilies/Derived_Crop_Object.tscn"],
]
var dock: VBoxContainer
var _dock_scroll: ScrollContainer
var palette: ItemList
var layer_picker: OptionButton
var search: LineEdit
var x_field: SpinBox
var y_field: SpinBox
var anchor_x: SpinBox
var anchor_y: SpinBox
var info: Label
var selection_info: Label
var collision_toggle: CheckBox
var foothold_toggle: CheckBox
var preview_toggle: CheckBox
var click_place: CheckButton
var entries: Array[Dictionary] = []
var visible_entries: Array[Dictionary] = []
var _layers: Array[Node] = []
var _poll_time := 0.0


func _enter_tree() -> void:
	_build_dock()
	_dock_scroll = ScrollContainer.new()
	_dock_scroll.name = "布景台"
	_dock_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dock_scroll.custom_minimum_size.x = 290
	dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock_scroll.add_child(dock)
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock_scroll)
	set_force_draw_over_forwarding_enabled()
	scene_changed.connect(_on_scene_changed)
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	_refresh_catalog()
	_refresh_layers()
	set_process(true)
	if "--garden-editor-test" in OS.get_cmdline_user_args():
		call_deferred("_run_editor_tests")


func _exit_tree() -> void:
	set_process(false)
	if EditorInterface.get_selection().selection_changed.is_connected(_selection_changed):
		EditorInterface.get_selection().selection_changed.disconnect(_selection_changed)
	remove_control_from_docks(_dock_scroll)
	_dock_scroll.queue_free()


func _handles(object: Object) -> bool:
	return object is Node2D


func _process(delta: float) -> void:
	_poll_time += delta
	if _poll_time > 0.2:
		_poll_time = 0
		_sync_projection_anchor(false)
		if collision_toggle.button_pressed or foothold_toggle.button_pressed or preview_toggle.button_pressed:
			update_overlays()


func _build_dock() -> void:
	dock = VBoxContainer.new()
	dock.name = "布景台"
	dock.custom_minimum_size.x = 290
	_button("打开新绘本地图", _open_map)
	_button("保存当前场景  ·  Ctrl+S", save_current_scene)
	search = LineEdit.new()
	search.placeholder_text = "搜索素材名 / 路径"
	search.text_changed.connect(func(_text): _filter_catalog())
	dock.add_child(search)
	palette = ItemList.new()
	palette.custom_minimum_size.y = 205
	palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	palette.max_columns = 2
	palette.fixed_icon_size = Vector2i(100, 82)
	palette.icon_mode = ItemList.ICON_MODE_TOP
	palette.fixed_column_width = 128
	palette.item_selected.connect(func(_index): _asset_info())
	dock.add_child(palette)
	_button("刷新素材目录", _refresh_catalog)
	layer_picker = OptionButton.new()
	layer_picker.item_selected.connect(func(_index): update_overlays())
	dock.add_child(layer_picker)
	var row := HBoxContainer.new()
	dock.add_child(row)
	x_field = _number(row, "根 X", 640)
	y_field = _number(row, "根 Y", 720)
	_button("在根坐标放入素材", _insert_selected)
	click_place = CheckButton.new()
	click_place.text = "下一次点击画布放入（Esc取消）"
	click_place.tooltip_text = "使用素材自身根点；不按包围盒底部自动落地。"
	dock.add_child(click_place)
	selection_info = Label.new()
	selection_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock.add_child(selection_info)
	_button("将所选根节点移至 X / Y", _move_selected)
	_button("将所选归入此景别（保留坐标）", _assign_selected_layer)
	_button("删除所选景物（可撤回）", _delete_selected)
	_button("检查 / 修复重复身份（可撤回）", _repair_identities_clicked)
	var separator := HSeparator.new()
	dock.add_child(separator)
	collision_toggle = _toggle("显示真实实体轮廓", true)
	foothold_toggle = _toggle("标出实际可踏边", false)
	preview_toggle = _toggle("预览所选 → 另一景别实体落点", false)
	row = HBoxContainer.new()
	dock.add_child(row)
	anchor_x = _number(row, "观察 X", 360)
	anchor_y = _number(row, "基准 Y", 720)
	anchor_x.value_changed.connect(func(_value): update_overlays())
	anchor_y.value_changed.connect(func(_value): update_overlays())
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = "直接编辑地图.tscn。Ctrl+Z / Ctrl+Shift+Z使用Godot场景历史；尺寸、镜像在Inspector调整。"
	dock.add_child(info)


func _button(title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.tooltip_text = title
	button.clip_text = true
	button.pressed.connect(callback)
	dock.add_child(button)
	return button


func _number(row: HBoxContainer, title: String, value: float) -> SpinBox:
	var label := Label.new()
	label.text = title
	row.add_child(label)
	var number := SpinBox.new()
	number.min_value = -100000
	number.max_value = 100000
	number.step = 1
	number.value = value
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(number)
	return number


func _toggle(title: String, pressed: bool) -> CheckBox:
	var toggle := CheckBox.new()
	toggle.text = title
	toggle.button_pressed = pressed
	toggle.toggled.connect(func(_value): update_overlays())
	dock.add_child(toggle)
	return toggle


func _refresh_catalog() -> void:
	entries.clear()
	for catalog in CATALOGS:
		if not DirAccess.dir_exists_absolute(catalog[1]) or not ResourceLoader.exists(catalog[2]):
			continue
		var files := DirAccess.get_files_at(catalog[1])
		files.sort()
		for file in files:
			if not str(file).ends_with(".tres"): continue
			var path: String = str(catalog[1]).path_join(file)
			var resource := load(path)
			if resource == null: continue
			var title: String = str(resource.get("display_name")) if CORE.has_property(resource, &"display_name") else str(file).get_basename()
			var icon: Texture2D
			if resource.has_method("atlas_texture"):
				icon = resource.atlas_texture()
			elif CORE.has_property(resource, &"parent_texture"):
				icon = resource.get("parent_texture")
			elif CORE.has_property(resource, &"painting"):
				icon = resource.get("painting")
				if icon != null and CORE.has_property(resource, &"source_region") and Rect2(resource.get("source_region")).has_area():
					var atlas := AtlasTexture.new()
					atlas.atlas = icon
					atlas.region = resource.get("source_region")
					icon = atlas
			entries.append({"name": title, "family": catalog[0], "piece": path, "scene": catalog[2], "icon": icon})
	_filter_catalog()


func _filter_catalog() -> void:
	palette.clear()
	visible_entries.clear()
	for entry in entries:
		var text := str(entry.name) + " " + str(entry.family) + " " + str(entry.piece)
		if not search.text.is_empty() and not text.to_lower().contains(search.text.to_lower()): continue
		var index := palette.add_item(str(entry.name), entry.icon)
		palette.set_item_tooltip(index, str(entry.family) + "\n" + str(entry.piece))
		visible_entries.append(entry)
	if palette.item_count > 0:
		palette.select(0)


func _asset_info() -> void:
	var selected := palette.get_selected_items()
	if not selected.is_empty():
		info.text = str(visible_entries[selected[0]].name) + "：根点由素材定义，位置由你决定。"


func _on_scene_changed(_root: Node) -> void:
	_refresh_layers()
	_selection_changed()
	update_overlays()


func _refresh_layers() -> void:
	_layers = CORE.layers_in(EditorInterface.get_edited_scene_root())
	layer_picker.clear()
	for layer in _layers:
		var title := "中景" if int(layer.get("slot")) == 0 else ("背景" if int(layer.get("slot")) == 1 else "景别%d" % int(layer.get("slot")))
		layer_picker.add_item("%s · %s" % [title, layer.name])
	_sync_projection_anchor(true)


func _sync_projection_anchor(reset_fallback: bool) -> void:
	var level := CORE.level_for(EditorInterface.get_edited_scene_root())
	var from_level := is_instance_valid(level) and CORE.has_property(level, &"editor_projection_anchor_y")
	anchor_y.editable = not from_level
	if from_level:
		anchor_y.set_value_no_signal(float(level.get("editor_projection_anchor_y")))
		anchor_y.tooltip_text = "来自Level的统一投影基准；请在Level Inspector中修改。"
	else:
		if reset_fallback: anchor_y.set_value_no_signal(720)
		anchor_y.tooltip_text = "旧地图没有统一导出值，默认720；可输入实际运行使用的基准。"


func _selected_object() -> Node2D:
	for node in EditorInterface.get_selection().get_selected_nodes():
		if CORE.is_object(node): return node
	return null


func _selection_changed() -> void:
	var object := _selected_object()
	selection_info.text = "所选：" + str(object.name) if object != null else "所选：在场景树或画布点选景物"
	if object != null:
		x_field.value = object.position.x
		y_field.value = object.position.y
		var index := _layers.find(object.get_parent())
		if index >= 0: layer_picker.select(index)
	update_overlays()


func _target_layer() -> Node:
	var index := layer_picker.selected
	return _layers[index] if index >= 0 and index < _layers.size() else null


func _open_map() -> void:
	if not ResourceLoader.exists(MAP_PATH):
		info.text = "新地图尚未落盘，请先打开要编辑的Level场景。"
		return
	EditorInterface.open_scene_from_path(MAP_PATH)
	EditorInterface.set_main_screen_editor("2D")


func save_current_scene() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path.is_empty():
		info.text = "请先用Godot的另存为，为当前场景选择路径。"
		return
	if DisplayServer.get_name() == "headless":
		# 无显示设备时不请求GPU场景缩略图；仍经真实EditorInterface保存。
		EditorInterface.save_scene_as(root.scene_file_path, false)
		info.text = "已请求无缩略图保存：" + root.scene_file_path
	else:
		var error := EditorInterface.save_scene()
		info.text = "已保存：" + root.scene_file_path if error == OK else "场景保存失败，错误码：%d" % error


func _insert_selected() -> void:
	var selected := palette.get_selected_items()
	if selected.is_empty(): return
	insert_asset(visible_entries[selected[0]], _target_layer(), Vector2(x_field.value, y_field.value))


func insert_asset(entry: Dictionary, layer: Node, position: Vector2) -> Node2D:
	var root := EditorInterface.get_edited_scene_root()
	if not CORE.flat_parent(root, layer):
		info.text = "请打开Level原场景编辑；景别及祖先需保持零位移/旋转、单位缩放。"
		return null
	var object := CORE.instantiate_asset(entry)
	if object == null:
		info.text = "素材场景无效。"
		return null
	object.position = position
	var history := get_undo_redo()
	history.create_action("布景：放入" + str(entry.name), UndoRedo.MERGE_DISABLE, root)
	history.add_do_method(self, "_attach", object, layer, root, -1)
	history.add_undo_method(self, "_detach", object)
	history.add_do_reference(object)
	history.commit_action()
	_select(object)
	info.text = "已放入，Ctrl+Z可撤回；Ctrl+S保存场景。"
	return object


func _attach(object: Node, parent: Node, root: Node, index: int) -> void:
	if object.get_parent() != null: object.get_parent().remove_child(object)
	parent.add_child(object, true)
	object.owner = root
	if index >= 0: parent.move_child(object, mini(index, parent.get_child_count() - 1))
	update_overlays()


func _detach(object: Node) -> void:
	EditorInterface.get_selection().remove_node(object)
	if object.get_parent() != null: object.get_parent().remove_child(object)
	update_overlays()


func _select(object: Node) -> void:
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(object)
	EditorInterface.edit_node(object)


func move_object(object: Node2D, position: Vector2) -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if not CORE.editable(root, object) or not CORE.flat_parent(root, object.get_parent()): return false
	var history := get_undo_redo()
	history.create_action("布景：移动根节点", UndoRedo.MERGE_DISABLE, root)
	history.add_do_property(object, "position", position)
	history.add_undo_property(object, "position", object.position)
	history.commit_action()
	update_overlays()
	return true


func assign_layer(object: Node2D, target: Node) -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if not CORE.editable(root, object) or not CORE.flat_parent(root, target) or target == object.get_parent(): return false
	var history := get_undo_redo()
	history.create_action("布景：修改景别归属", UndoRedo.MERGE_DISABLE, root)
	history.add_do_method(self, "_attach", object, target, root, -1)
	history.add_undo_method(self, "_attach", object, object.get_parent(), root, object.get_index())
	history.commit_action()
	_select(object)
	return true


func delete_object(object: Node2D) -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if not CORE.editable(root, object): return false
	var history := get_undo_redo()
	history.create_action("布景：删除景物", UndoRedo.MERGE_DISABLE, root)
	history.add_do_method(self, "_detach", object)
	history.add_undo_method(self, "_attach", object, object.get_parent(), root, object.get_index())
	history.add_undo_reference(object)
	history.commit_action()
	return true


func repair_identities() -> int:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		info.text = "请先打开地图Level场景。"
		return -1
	var repairs := CORE.identity_repairs(root)
	for repair in repairs:
		if not CORE.editable(root, repair.object):
			info.text = "重复/空身份位于嵌套场景内部；请打开原Level再修复。"
			return -1
	if repairs.is_empty():
		info.text = "检查通过：所有直属景物身份均非空且唯一，没有修改。"
		return 0
	var history := get_undo_redo()
	history.create_action("布景：修复重复与空身份", UndoRedo.MERGE_DISABLE, root)
	for repair in repairs:
		history.add_do_method(repair.object, "set_meta", &"persistent_id", repair.new)
		if repair.had_id:
			history.add_undo_method(repair.object, "set_meta", &"persistent_id", repair.old)
		else:
			history.add_undo_method(repair.object, "remove_meta", &"persistent_id")
	history.commit_action()
	info.text = "已修复%d个重复/空身份，首个有效身份保持不变；Ctrl+Z可整批撤回。" % repairs.size()
	return repairs.size()


func _repair_identities_clicked() -> void:
	repair_identities()


func _move_selected() -> void:
	if not move_object(_selected_object(), Vector2(x_field.value, y_field.value)):
		info.text = "请选择当前Level场景自己的景物根节点。"


func _assign_selected_layer() -> void:
	info.text = "景别归属改变；真实坐标与尺寸保留。这是地图编辑，不执行游戏W/S搬运。" if assign_layer(_selected_object(), _target_layer()) else "请选择其他景别与本场景景物。"


func _delete_selected() -> void:
	if not delete_object(_selected_object()): info.text = "请选择本场景自己的景物；不能删除嵌套场景的内部节点。"


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not click_place.button_pressed: return false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		click_place.button_pressed = false
		return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var root := EditorInterface.get_edited_scene_root() as Node2D
		if root == null: return false
		var point: Vector2 = root.get_canvas_transform().affine_inverse() * event.position
		x_field.value = point.x
		y_field.value = point.y
		_insert_selected()
		click_place.button_pressed = false
		return true
	return false


func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	var root := EditorInterface.get_edited_scene_root() as Node2D
	if root == null: return
	var canvas := root.get_canvas_transform()
	if collision_toggle.button_pressed or foothold_toggle.button_pressed:
		for layer in CORE.layers_in(root):
			for body in CORE.bodies_under(layer):
				var color := Color(0.30, 0.73, 0.79, 0.78) if int(layer.get("slot")) == 0 else Color(0.72, 0.50, 0.84, 0.72)
				if collision_toggle.button_pressed:
					for polygon in CORE.polygons(body): _draw_outline(overlay, canvas * polygon, color)
				if foothold_toggle.button_pressed:
					for edge in CORE.walkable_edges(body):
						if edge.size() > 1: overlay.draw_polyline(canvas * edge, Color(0.89, 0.68, 0.26, 0.96), 3, true)
	if preview_toggle.button_pressed:
		var object := _selected_object()
		if object == null: return
		var preview := selected_transfer_preview()
		if preview.is_empty(): return
		var color := Color(0.27, 0.77, 0.47, 0.95) if preview.valid else Color(0.95, 0.3, 0.27, 0.95)
		for polygon in preview.outlines: _draw_outline(overlay, canvas * polygon, color)
		for polygon in preview.contacts: _draw_outline(overlay, canvas * polygon, Color(1, 0.64, 0.2), 3)
		overlay.draw_line(canvas * object.global_position, canvas * Vector2(preview.target_position), color, 1, true)
		info.text = str(preview.reason) + "\n预览是编辑坐标中的目标实体；游戏内以运行检查为准。"


func selected_transfer_preview() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var object := _selected_object()
	if object == null: return {}
	for layer in CORE.layers_in(root):
		if layer != object.get_parent():
			return CORE.transfer_preview(root, object, layer, Vector2(anchor_x.value, anchor_y.value))
	return {}


func _draw_outline(overlay: Control, points: PackedVector2Array, color: Color, width := 1.5) -> void:
	if points.size() < 3: return
	var closed := points.duplicate()
	closed.append(points[0])
	overlay.draw_polyline(closed, color, width, true)


func _run_editor_tests() -> void:
	var script := load("res://Tests/Garden_Editor_Regression.gd")
	if script != null:
		var test = script.new()
		add_child(test)
		test.run(self)
