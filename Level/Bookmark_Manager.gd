class_name BookmarkManager
extends Node

## 书签保存场景摆位；墨水、能力和已发现书签永远独立于摆位回退。
signal progress_changed
signal restored(bookmark_id: int)
signal message_changed(message: String)

const SAVE_VERSION: int = 1
const MARKER_SCRIPT = preload("res://Component/Bookmark/Bookmark_Marker.gd")
@export var save_path: String = "user://Natural_Garden_Save.json"
@export var fall_y: float = 960.0
@export var world_min_x: float = -240.0
@export var world_max_x: float = 4000.0
@export var show_messages: bool = true
@export var show_prompt: bool = true

var player: PlayerController
var system: SystemController
var level: Level
var last_bookmark: int = -1
var unlocked_bookmarks: Array[int] = []
var inks: Array[String] = []
var abilities: Array[String] = ["move_object"]
var map_open: bool = false
var storage_error: String = ""
var _configured: bool = false
var _bookmarks: Dictionary = {}
var _layouts: Dictionary = {}
var _initial_layout: Array[Dictionary] = []
var _objects: Dictionary = {}
var _layers: Dictionary = {}
var _markers: Dictionary = {}
var _canvas: CanvasLayer
var _prompt: Label
var _map_panel: PanelContainer
var _map_scrim: ColorRect
var _map_entries: VBoxContainer
var _map_drawing: Control
var _message: Label
var _message_time: float = 0.0
var _player_was_active: bool = true

func configure(target_player: PlayerController, target_system: SystemController, target_level: Level, bookmarks: Array[Dictionary]) -> void:
	assert(not _configured, "书签只能配置一次。")
	player = target_player
	system = target_system
	level = target_level
	assert(is_instance_valid(player) and is_instance_valid(system) and is_instance_valid(level))
	process_physics_priority = 1100
	for layer in system.layers:
		_layers[layer.layer_id] = layer
	for object in get_tree().get_nodes_in_group("layer_objects"):
		if object is LayerObject and object.can_transfer and level.is_ancestor_of(object):
			var object_id := str(object.get_meta("persistent_id", object.name))
			assert(not _objects.has(object_id), "存档物件 ID 重复：" + object_id)
			_objects[object_id] = object
	for definition in bookmarks:
		var bookmark_id := int(definition.get("id", -1))
		assert(bookmark_id >= 0 and not _bookmarks.has(bookmark_id) and definition.get("position") is Vector2)
		_bookmarks[bookmark_id] = definition.duplicate(true)
	assert(not _bookmarks.is_empty(), "至少需要一枚书签。")
	_initial_layout = _capture_layout()
	_build_markers()
	_build_interface()
	_configured = true
	if not load_save():
		var initial: int = _bookmarks.keys().min()
		activate(initial, false)
		_teleport(_bookmarks[initial].position)
		_show_message("凝墨书签记住旅程。靠近按 E 记录，R 回到书签，M 展开地图。", 9.0)
	_update_markers()

func _physics_process(delta: float) -> void:
	if not _configured:
		return
	_message_time = maxf(0, _message_time - delta)
	_message.visible = show_messages and _message_time > 0 and not map_open
	for marker in _markers.values():
		marker.apply_projection(system.camera.global_position)
	var near := _nearest_bookmark()
	_prompt.visible = show_prompt and near >= 0 and not map_open
	if near >= 0:
		_prompt.text = "E  记录于「%s」   ·   R 返回书签   ·   M 地图" % _bookmarks[near].get("title", "书签")
	if not map_open and (player.global_position.y > fall_y or player.global_position.x < world_min_x or player.global_position.x > world_max_x):
		return_to()
		_show_message("纸页接住了你。已回到书签；墨水仍在。")

func _input(event: InputEvent) -> void:
	if not _configured or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_M:
			toggle_map()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			if map_open:
				close_map()
				get_viewport().set_input_as_handled()
		KEY_R:
			return_to()
			get_viewport().set_input_as_handled()
		KEY_E:
			var near := _nearest_bookmark()
			if near >= 0 and not map_open:
				activate(near)
				get_viewport().set_input_as_handled()
	if map_open and event.physical_keycode in [KEY_A, KEY_D, KEY_W, KEY_S, KEY_Q, KEY_E, KEY_SPACE, KEY_SHIFT, KEY_PAGEUP]:
		## 地图展开时，W/S 与图层轮换也不影响背后的世界。
		get_viewport().set_input_as_handled()

func mark_ink(ink_id: String) -> bool:
	if ink_id.is_empty() or inks.has(ink_id):
		return false
	inks.append(ink_id)
	_save()
	progress_changed.emit()
	return true

func has_ink(ink_id: String) -> bool:
	return inks.has(ink_id)

func mark_ability(ability_id: String) -> bool:
	if ability_id.is_empty() or abilities.has(ability_id):
		return false
	abilities.append(ability_id)
	_save()
	progress_changed.emit()
	return true

func activate(bookmark_id: int, notify: bool = true) -> bool:
	if not _bookmarks.has(bookmark_id):
		return false
	last_bookmark = bookmark_id
	if not unlocked_bookmarks.has(bookmark_id):
		unlocked_bookmarks.append(bookmark_id)
	_layouts[str(bookmark_id)] = _capture_layout()
	_update_markers()
	_save()
	progress_changed.emit()
	if notify:
		_show_message("「%s」记住了现在的景物摆位。R 恢复这次摆位；已收集墨水保留。" % _bookmarks[bookmark_id].get("title", "书签"), 8)
	return true

func return_to(bookmark_id: int = -1) -> bool:
	var target := last_bookmark if bookmark_id < 0 else bookmark_id
	if not _bookmarks.has(target) or not unlocked_bookmarks.has(target):
		return false
	close_map()
	_apply_layout(_initial_layout)
	_apply_layout(_layouts.get(str(target), _initial_layout))
	last_bookmark = target
	_teleport(_bookmarks[target].position)
	_update_markers()
	_save()
	progress_changed.emit()
	restored.emit(target)
	_show_message("回到「%s」。恢复书签时的景物；墨水与已发现书签保留。" % _bookmarks[target].get("title", "书签"))
	return true

func _capture_layout() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for object_id in _objects:
		var object: LayerObject = _objects[object_id]
		if not is_instance_valid(object) or not is_instance_valid(object.owner_layer):
			continue
		result.append({"object_id": object_id, "layer_id": object.owner_layer.layer_id, "position": [object.position.x, object.position.y], "collision_scale": [object.collision_box.scale.x, object.collision_box.scale.y]})
	return result

func _apply_layout(layout: Array) -> void:
	for state in layout:
		if not state is Dictionary or not _valid_state(state):
			continue
		var object: LayerObject = _objects.get(state.object_id)
		var layer: DepthLayer = _layers.get(int(state.layer_id))
		if not is_instance_valid(object) or not is_instance_valid(layer):
			continue
		if object.get_parent() != layer:
			object.reparent(layer, false)
		object.owner_layer = layer
		object.position = Vector2(float(state.position[0]), float(state.position[1]))
		object.collision_box.scale = Vector2(float(state.collision_scale[0]), float(state.collision_scale[1]))
		object.set_collision_group(1, layer.layer_id + 1)
		object.set_pick_condition(false)
		object.apply_visual_transfer(system.camera.global_position)
		object.reset_physics_interpolation()

func _valid_state(state: Dictionary) -> bool:
	if not state.get("object_id") is String or not state.get("layer_id") is float and not state.get("layer_id") is int:
		return false
	var layer_id := float(state.layer_id)
	if state.object_id.is_empty() or state.object_id.length() > 128 or not is_finite(layer_id) or layer_id < 0 or layer_id > 31 or layer_id != floorf(layer_id):
		return false
	if not _valid_pair(state.get("position"), 1000000, false) or not _valid_pair(state.get("collision_scale"), 1000, true):
		return false
	return true

func _valid_pair(value: Variant, limit: float, positive: bool) -> bool:
	if not value is Array or value.size() != 2:
		return false
	for item in value:
		if not item is float and not item is int:
			return false
		var number := float(item)
		if not is_finite(number) or absf(number) > limit or (positive and number <= 0.001):
			return false
	return true

func _teleport(point: Vector2) -> void:
	Global.clear_selection()
	player.global_position = _safe_spawn(point)
	player.reset_motion()
	system.camera_fixed = true
	system.reset_view_interpolation()
	var visual := player.get_node_or_null("Visual_Body/Traveler")
	if visual != null and visual.has_method("reset_after_restore"):
		visual.reset_after_restore()
	var scarf := player.get_node_or_null("Visual_Body/Scarf")
	if scarf != null and scarf.has_method("reset_cloth"):
		scarf.reset_cloth()
	for marker in _markers.values():
		marker.apply_projection(system.camera.global_position)
		marker.reset_physics_interpolation()

## 可搬物件也能围住书签。恢复摆位后，在书签附近寻找身体能完整落下的位置。
func _safe_spawn(point: Vector2) -> Vector2:
	var shape := player.body_collision_box.shape
	if shape == null:
		return point
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = player.collision_mask
	var exclusions: Array[RID] = [player.get_rid()]
	var restored_parts: Array[Dictionary] = []
	for object in _objects.values():
		if not is_instance_valid(object):
			continue
		exclusions.append(object.get_rid())
		if (object.collision_layer & player.collision_mask) == 0:
			continue
		if (object.collision_box is CollisionShape2D and object.collision_box.disabled) or (object.collision_box is CollisionPolygon2D and object.collision_box.disabled):
			continue
		var parts: Array[Dictionary] = []
		if object.has_method("get_transfer_collision_parts"):
			parts = object.get_transfer_collision_parts(object.owner_layer, system.camera.global_position)
		else:
			parts = system._legacy_collision_parts(object, object.owner_layer)
		restored_parts.append_array(parts)
	## 刚恢复的物件还没有刷新空间宽相位；读取真实新轮廓直接做凸形状碰撞。
	## 空间查询排除这些物件，只检查未被恢复的固定地平线等实体。
	query.exclude = exclusions
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var offsets: Array[float] = [0, 48, -48, 96, -96, 144, -144, 192, -192]
	for height in [0, 90, 180, 270, 360, 540, 720]:
		for offset in offsets:
			var candidate := point + Vector2(offset, -height)
			if candidate.x < world_min_x or candidate.x > world_max_x:
				continue
			var transform := player.body_collision_box.global_transform
			transform.origin += candidate - player.global_position
			query.transform = system._contact_tolerant_transform(shape, transform)
			var occupied: bool = false
			for part in restored_parts:
				if shape.collide(query.transform, part.shape, part.transform):
					occupied = true
					break
			if occupied:
				continue
			if player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				return candidate
	## 超大自定义场景仍能从纸页上方落下，而不将人物塞入实体。
	return point + Vector2(0, -1080)

func _save() -> bool:
	storage_error = ""
	if not save_path.begins_with("user://"):
		storage_error = "书签只能写入本机游戏存档目录。"
		return false
	var payload := JSON.stringify({"last_bookmark": last_bookmark, "unlocked_bookmarks": unlocked_bookmarks, "inks": inks, "abilities": abilities, "layouts": _layouts}, "", true)
	var envelope := {"version": SAVE_VERSION, "payload_json": payload, "sha256": payload.sha256_text()}
	var absolute := ProjectSettings.globalize_path(save_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		storage_error = "无法建立书签存档目录。"
		return false
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		storage_error = "书签存档无法写入。"
		return false
	file.store_string(JSON.stringify(envelope, "\t", true))
	file.flush()
	file.close()
	## 同目录临时文件完成写入后才替换，避免中断留下半份主存档。
	var error := DirAccess.rename_absolute(temporary, absolute)
	if error != OK:
		storage_error = "书签存档替换失败。"
		return false
	return true

func load_save() -> bool:
	if not FileAccess.file_exists(save_path):
		return false
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null or file.get_length() > 4 * 1024 * 1024:
		return false
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return false
	var envelope: Variant = parser.data
	if not envelope is Dictionary:
		return false
	var version: Variant = envelope.get("version")
	if not (version is float or version is int) or float(version) != SAVE_VERSION:
		return false
	var payload: Variant = envelope.get("payload_json")
	if not payload is String or payload.sha256_text() != envelope.get("sha256", ""):
		return false
	if parser.parse(payload) != OK:
		return false
	var state: Variant = parser.data
	if not state is Dictionary or not state.get("layouts") is Dictionary or not state.get("unlocked_bookmarks") is Array:
		return false
	var restored_bookmarks: Array[int] = []
	for value in state.unlocked_bookmarks:
		if (value is float or value is int) and is_finite(float(value)) and float(value) == floorf(float(value)) and _bookmarks.has(int(value)) and not restored_bookmarks.has(int(value)):
			restored_bookmarks.append(int(value))
	var last_id: Variant = state.get("last_bookmark")
	if not (last_id is float or last_id is int) or not is_finite(float(last_id)) or float(last_id) != floorf(float(last_id)):
		return false
	var candidate := int(last_id)
	if not restored_bookmarks.has(candidate):
		return false
	var restored_layouts: Dictionary = {}
	for key in state.layouts:
		if not key is String or not key.is_valid_int() or not _bookmarks.has(key.to_int()) or not state.layouts[key] is Array:
			continue
		var valid: Array[Dictionary] = []
		for object_state in state.layouts[key]:
			if object_state is Dictionary and _valid_state(object_state):
				valid.append(object_state)
		restored_layouts[key] = valid
	if not restored_layouts.has(str(candidate)):
		return false
	unlocked_bookmarks = restored_bookmarks
	_layouts = restored_layouts
	inks = _valid_names(state.get("inks", []))
	abilities = _valid_names(state.get("abilities", ["move_object"]))
	if not abilities.has("move_object"):
		abilities.append("move_object")
	last_bookmark = candidate
	_apply_layout(_initial_layout)
	_apply_layout(_layouts[str(candidate)])
	_teleport(_bookmarks[candidate].position)
	_update_markers()
	progress_changed.emit()
	restored.emit(candidate)
	_show_message("从「%s」接续旅程。已找回本机书签、墨水和景物摆位。" % _bookmarks[candidate].get("title", "书签"), 8)
	return true

func _valid_names(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			if item is String and not item.is_empty() and item.length() <= 128 and not result.has(item):
				result.append(item)
	return result

func _nearest_bookmark() -> int:
	var result := -1
	var distance := INF
	for bookmark_id in _bookmarks:
		var definition: Dictionary = _bookmarks[bookmark_id]
		var candidate := player.global_position.distance_to(definition.position)
		if candidate <= float(definition.get("radius", 92.0)) and candidate < distance:
			distance = candidate
			result = bookmark_id
	return result

func _build_markers() -> void:
	var layer := system.get_layer_at_slot(Global.current_layer_index)
	for bookmark_id in _bookmarks:
		var marker := MARKER_SCRIPT.new() as BookmarkMarker
		marker.name = "Bookmark%d" % bookmark_id
		marker.title = _bookmarks[bookmark_id].get("title", "书签")
		layer.add_child(marker)
		marker.global_position = _bookmarks[bookmark_id].position
		_markers[bookmark_id] = marker

func _update_markers() -> void:
	for bookmark_id in _markers:
		var marker: BookmarkMarker = _markers[bookmark_id]
		marker.unlocked = unlocked_bookmarks.has(bookmark_id)
		marker.current = bookmark_id == last_bookmark
		marker.queue_visual_update()

func _build_interface() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "BookmarkInterface"
	_canvas.layer = 35
	add_child(_canvas)
	_prompt = _make_label(17, Color("594b60"))
	_prompt.position = Vector2(24, 663)
	_prompt.size = Vector2(1232, 28)
	_canvas.add_child(_prompt)
	_message = _make_label(17, Color("594b60"))
	_message.position = Vector2(24, 691)
	_message.size = Vector2(1232, 27)
	_canvas.add_child(_message)
	_map_scrim = ColorRect.new()
	_map_scrim.name = "MapPaperVeil"
	_map_scrim.color = Color(0.96, 0.92, 0.84, 0.15)
	_map_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.add_child(_map_scrim)
	_map_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_scrim.hide()
	_map_panel = PanelContainer.new()
	_map_panel.name = "BookmarkMap"
	_map_panel.position = Vector2(284, 124)
	_map_panel.size = Vector2(712, 464)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f5ead5")
	paper.border_color = Color("bbaaac")
	paper.set_border_width_all(1)
	paper.set_content_margin_all(24)
	_map_panel.add_theme_stylebox_override("panel", paper)
	_canvas.add_child(_map_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_map_panel.add_child(column)
	var title := _make_label(27, Color("44384e"))
	title.text = "凝墨书签 · 纸页地图"
	column.add_child(title)
	_map_drawing = Control.new()
	_map_drawing.custom_minimum_size = Vector2(664, 120)
	_map_drawing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_drawing.draw.connect(_draw_map)
	column.add_child(_map_drawing)
	_map_entries = VBoxContainer.new()
	_map_entries.add_theme_constant_override("separation", 10)
	column.add_child(_map_entries)
	var note := _make_label(16, Color("7d7080"))
	note.text = "选择已发现的书签，恢复在那里记录的景物摆位。\n墨水和能力保留。M / Esc 收起地图。"
	column.add_child(note)
	_map_panel.hide()

func _make_label(font_size: int, ink: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ink)
	label.add_theme_color_override("font_shadow_color", Color("f5ead5"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	return label

func _draw_map() -> void:
	if not _configured:
		return
	var ids: Array = _bookmarks.keys()
	ids.sort()
	var points := PackedVector2Array()
	var world_points: Array[Vector2] = []
	var min_x := INF
	var max_x := -INF
	for bookmark_id in ids:
		var definition: Dictionary = _bookmarks[bookmark_id]
		var coordinate: Vector2 = definition.get("map_position", definition.position)
		world_points.append(coordinate)
		min_x = minf(min_x, coordinate.x)
		max_x = maxf(max_x, coordinate.x)
	for index in range(ids.size()):
		var fraction := (world_points[index].x - min_x) / maxf(1.0, max_x - min_x)
		var point := Vector2(66 + fraction * 532.0, 60 + clampf((world_points[index].y - world_points[0].y) * 0.06, -25, 25) + (9 if index % 2 else -7))
		points.append(point)
	if points.size() >= 2:
		_map_drawing.draw_polyline(points, Color("b9aba9"), 2, true)
	for index in range(ids.size()):
		var color := Color("c96755") if unlocked_bookmarks.has(ids[index]) else Color("c9c0b4")
		_map_drawing.draw_circle(points[index], 8, color)
		_map_drawing.draw_arc(points[index], 14, 0, TAU, 24, Color("65566c"), 1.2, true)
		_map_drawing.draw_line(points[index] + Vector2(0, -15), points[index] + Vector2(5, -30), color, 3, true)

func open_map() -> void:
	if not _configured or map_open:
		return
	map_open = true
	Global.clear_selection()
	_player_was_active = player.activated
	player.activated = false
	player.reset_motion()
	for child in _map_entries.get_children():
		_map_entries.remove_child(child)
		child.queue_free()
	var ids: Array = _bookmarks.keys()
	ids.sort()
	for bookmark_id in ids:
		var button := Button.new()
		button.custom_minimum_size = Vector2(620, 42)
		var known := unlocked_bookmarks.has(bookmark_id)
		button.text = ("● " if bookmark_id == last_bookmark else "○ ") + str(_bookmarks[bookmark_id].get("title", "书签")) if known else "尚未发现的书签"
		button.disabled = not known
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_color_override("font_color", Color("594b60"))
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color("e9deca")
		normal.border_color = Color("c6b5b4")
		normal.set_border_width_all(1)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color("e1d2c2")
		var pressed := normal.duplicate() as StyleBoxFlat
		pressed.bg_color = Color("d9c8ba")
		var disabled := normal.duplicate() as StyleBoxFlat
		disabled.bg_color = Color("eee4d2")
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", pressed)
		button.add_theme_stylebox_override("disabled", disabled)
		button.add_theme_color_override("font_hover_color", Color("44384e"))
		button.add_theme_color_override("font_pressed_color", Color("44384e"))
		button.add_theme_color_override("font_disabled_color", Color("aaa097"))
		button.pressed.connect(return_to.bind(bookmark_id))
		_map_entries.add_child(button)
	_map_panel.show()
	_map_scrim.show()
	_map_drawing.queue_redraw()

func close_map() -> void:
	if not map_open:
		return
	map_open = false
	_map_panel.hide()
	_map_scrim.hide()
	player.activated = _player_was_active
	player.reset_motion()

func toggle_map() -> void:
	if map_open:
		close_map()
	else:
		open_map()

func _show_message(text: String, duration: float = 6.0) -> void:
	_message.text = text
	_message_time = duration
	message_changed.emit(text)
