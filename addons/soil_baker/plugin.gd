@tool
extends EditorPlugin

const Baker = preload("res://addons/soil_baker/soil_baker.gd")
const Profile = preload("res://addons/soil_baker/soil_profile.gd")
const OUTPUT_DIRECTORY := "res://Generated/Soil"

var _dock: VBoxContainer
var _selection_label: Label
var _status_label: Label
var _preview: TextureRect
var _preview_button: Button
var _bake_button: Button
var _profile: Profile
var _selected_ground: StaticBody2D
var _busy: bool = false


func _enter_tree() -> void:
	_profile = Profile.new()
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func _exit_tree() -> void:
	if EditorInterface.get_selection().selection_changed.is_connected(_on_selection_changed):
		EditorInterface.get_selection().selection_changed.disconnect(_on_selection_changed)
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Soil Baker"
	_dock.custom_minimum_size = Vector2(300, 360)
	var title := Label.new()
	title.text = "Ground → Soil 贴图烘焙"
	_dock.add_child(title)
	_selection_label = Label.new()
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(_selection_label)
	var inspector := EditorInspector.new()
	inspector.custom_minimum_size.y = 300.0
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.add_child(inspector)
	inspector.edit(_profile)
	var buttons := HBoxContainer.new()
	_dock.add_child(buttons)
	_preview_button = Button.new()
	_preview_button.text = "预览"
	_preview_button.pressed.connect(_on_preview_pressed)
	buttons.add_child(_preview_button)
	_bake_button = Button.new()
	_bake_button.text = "生成并保存 Soil"
	_bake_button.pressed.connect(_on_bake_pressed)
	buttons.add_child(_bake_button)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(260, 140)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dock.add_child(_preview)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.text = "输出目录：%s" % OUTPUT_DIRECTORY
	_dock.add_child(_status_label)


func _on_selection_changed() -> void:
	_selected_ground = null
	for node in EditorInterface.get_selection().get_selected_nodes():
		if _is_ground_source(node):
			_selected_ground = node as StaticBody2D
			break
	_selection_label.text = (
		"当前 Ground：%s" % _selected_ground.name
		if _selected_ground != null
		else "请在场景树中选中 Ground（StaticBody2D / LayerObject）。"
	)
	_preview_button.disabled = _selected_ground == null or _busy
	_bake_button.disabled = _selected_ground == null or _busy
	_preview.texture = null


func _is_ground_source(node: Node) -> bool:
	if not node is StaticBody2D:
		return false
	var script := node.get_script() as Script
	if script == null or script.resource_path != "res://Component/Object/Layer_Object.gd":
		return false
	if not node.get_node_or_null("CollisionBox") is CollisionPolygon2D:
		return false
	return node.get_node_or_null("VisualRoot") is Node2D


func _on_preview_pressed() -> void:
	if _selected_ground == null:
		return
	_set_busy(true)
	var result: Dictionary = Baker.bake_image(
		Baker.source_polygon(_selected_ground), _profile, 960
	)
	if not result.error.is_empty():
		_status_label.text = result.error
	else:
		_preview.texture = ImageTexture.create_from_image(result.image)
		_status_label.text = "预览完成。保存后会以完整分辨率重新生成。"
	_set_busy(false)


func _on_bake_pressed() -> void:
	if _selected_ground == null or _busy:
		return
	_set_busy(true)
	var source := _selected_ground
	var points: PackedVector2Array = Baker.source_polygon(source)
	var prepared: Dictionary = Baker.prepare(points, _profile)
	if not prepared.error.is_empty():
		_finish_with_error(prepared.error)
		return
	var absolute_directory := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK:
		_finish_with_error("无法创建输出目录（错误 %d）。" % directory_error)
		return
	var scene_name := _next_soil_name()
	var base_path := OUTPUT_DIRECTORY.path_join(scene_name)
	var scene_path := base_path + ".tscn"
	var profile_path := base_path + ".tres"
	var recipe_path := base_path + ".recipe.json"
	var tiles: Array[Dictionary] = []
	var output_size: Vector2i = prepared.size
	var columns := ceili(float(output_size.x) / float(_profile.tile_size_px))
	var rows := ceili(float(output_size.y) / float(_profile.tile_size_px))
	for row in range(rows):
		for column in range(columns):
			var origin := Vector2i(column, row) * _profile.tile_size_px
			if not Baker.tile_has_decoration(prepared, _profile, origin):
				continue
			var tile: Dictionary = Baker.bake_tile(prepared, _profile, origin)
			if not tile.error.is_empty():
				_finish_with_error(tile.error)
				return
			var image: Image = tile.image
			if image == null:
				continue
			var path := "%s_%03d_%03d.png" % [base_path, row, column]
			var save_error: Error = image.save_png(path)
			if save_error != OK:
				_finish_with_error("PNG 保存失败（错误 %d）：%s" % [save_error, path])
				return
			tile.erase("image")
			tile["path"] = path
			tiles.append(tile)
		_status_label.text = "已渲染 %d / %d 行；保存 %d 块纹理。" % [row + 1, rows, tiles.size()]
		await get_tree().process_frame
	if not is_instance_valid(source):
		_finish_with_error("源 Ground 已从编辑器场景中移除。")
		return
	_status_label.text = "已保存 %d 块纹理，正在等待 Godot 导入……" % tiles.size()
	EditorInterface.get_resource_filesystem().scan()
	for index in range(tiles.size()):
		var texture := await _wait_for_imported_texture(tiles[index].path)
		if texture == null:
			_finish_with_error("纹理导入超时：%s" % tiles[index].path)
			return
		tiles[index]["texture"] = texture
	if not is_instance_valid(source):
		_finish_with_error("源 Ground 已从编辑器场景中移除。")
		return
	var scene: PackedScene = Baker.make_scene(
		source, prepared.contour, tiles, prepared.bounds, prepared.density,
		_profile.soil_color, scene_name
	)
	if scene == null:
		_finish_with_error("无法打包 Soil 场景。")
		return
	var save_error := ResourceSaver.save(scene, scene_path)
	if save_error != OK:
		_finish_with_error("场景保存失败（错误 %d）。" % save_error)
		return
	save_error = ResourceSaver.save(_profile.duplicate(true), profile_path)
	if save_error != OK:
		_finish_with_error("场景已保存，但参数配置保存失败（错误 %d）。" % save_error)
		return
	var recipe_error := _write_recipe(recipe_path, source, points, profile_path)
	EditorInterface.get_resource_filesystem().scan()
	_status_label.text = "完成：%s\n贴图分块：%d 张（%d×%d 区域）" % [
		scene_path, tiles.size(), columns, rows
	]
	if recipe_error != OK:
		_status_label.text += "\n生成记录保存失败（错误 %d）。" % recipe_error
	_set_busy(false)


func _wait_for_imported_texture(path: String) -> Texture2D:
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		if ResourceLoader.exists(path, "Texture2D"):
			var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
			if texture != null:
				return texture
		await get_tree().create_timer(0.15).timeout
	return null


func _next_soil_name() -> String:
	var index := 1
	var files := DirAccess.get_files_at(OUTPUT_DIRECTORY)
	while _name_is_used(files, "Soil_%03d" % index):
		index += 1
	return "Soil_%03d" % index


func _name_is_used(files: PackedStringArray, name: String) -> bool:
	for file in files:
		if file.begins_with(name + ".") or file.begins_with(name + "_"):
			return true
	return false


func _write_recipe(
	path: String, source: StaticBody2D, points: PackedVector2Array, profile_path: String
) -> Error:
	var coordinates: Array[Array] = []
	for point in points:
		coordinates.append([point.x, point.y])
	var recipe := {
		"source_scene": source.scene_file_path,
		"source_node": str(source.get_path()),
		"source_polygon_local": coordinates,
		"profile": profile_path,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(recipe, "  "))
	file.close()
	return OK


func _set_busy(value: bool) -> void:
	_busy = value
	_preview_button.disabled = value or _selected_ground == null
	_bake_button.disabled = value or _selected_ground == null


func _finish_with_error(message: String) -> void:
	_status_label.text = message
	push_error("Soil Baker: " + message)
	_set_busy(false)
