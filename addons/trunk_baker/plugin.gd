@tool
extends EditorPlugin

const Baker = preload("res://addons/trunk_baker/trunk_baker.gd")
const Geometry = preload("res://addons/trunk_baker/trunk_geometry.gd")
const Profile = preload("res://addons/trunk_baker/trunk_profile.gd")
const Writer = preload("res://addons/trunk_baker/trunk_scene_writer.gd")
const Output = preload("res://addons/texture_baker_common/bake_output.gd")
const OutputControls = preload("res://addons/texture_baker_common/output_controls.gd")
const OUTPUT_DIRECTORY := "res://Generated/Trunk"

var _dock: VBoxContainer
var _selection_label: Label
var _status: Label
var _preview: TextureRect
var _inspector: EditorInspector
var _preview_button: Button
var _save_button: Button
var _seed_button: Button
var _load_button: Button
var _cancel_button: Button
var _file_dialog: EditorFileDialog
var _output_controls: OutputControls
var _profile: Profile
var _source: StaticBody2D
var _busy := false
var _cancelled := false
var _active := false


func _enter_tree() -> void:
	_active = true
	_profile = Profile.new()
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	_selection_changed()


func _exit_tree() -> void:
	_active = false
	_cancelled = true
	if EditorInterface.get_selection().selection_changed.is_connected(_selection_changed):
		EditorInterface.get_selection().selection_changed.disconnect(_selection_changed)
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Trunk Baker"
	_dock.custom_minimum_size = Vector2(310, 400)
	var title := Label.new()
	title.text = "矩形 Ground → 树干"
	_dock.add_child(title)
	_selection_label = Label.new()
	_selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(_selection_label)
	var note := Label.new()
	note.text = "矩形直角，宽度三等分：30% / 15% / 原色。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(note)
	_inspector = EditorInspector.new()
	_inspector.custom_minimum_size.y = 280
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.add_child(_inspector)
	_inspector.edit(_profile)
	_output_controls = OutputControls.new()
	_dock.add_child(_output_controls)
	_output_controls.configure(OUTPUT_DIRECTORY, "Trunk")
	var settings := HBoxContainer.new()
	_dock.add_child(settings)
	_seed_button = _button(settings, "换一组变化", _new_seed)
	_load_button = _button(settings, "加载参数", _load_profile)
	var actions := HBoxContainer.new()
	_dock.add_child(actions)
	_preview_button = _button(actions, "预览", _preview_pressed)
	_save_button = _button(actions, "生成并保存树干", _save_pressed)
	_cancel_button = _button(actions, "取消", func() -> void: _cancelled = true)
	_cancel_button.disabled = true
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(280, 160)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dock.add_child(_preview)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.text = "输出：%s" % OUTPUT_DIRECTORY
	_dock.add_child(_status)
	_file_dialog = EditorFileDialog.new()
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.filters = PackedStringArray(["*.tres ; 树干参数"])
	_file_dialog.file_selected.connect(_profile_selected)
	_dock.add_child(_file_dialog)


func _button(parent: Node, text_value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _selection_changed() -> void:
	_source = null
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is StaticBody2D and node.get_script() != null:
			if node.get_script().resource_path == Writer.LAYER_SCRIPT and node.get_node_or_null("CollisionBox") is CollisionPolygon2D and node.get_node_or_null("VisualRoot") is Node2D:
				_source = node
				break
	_selection_label.text = "当前 Ground：%s" % _source.name if _source != null else "请选择具有矩形 CollisionBox 的 Ground。"
	if not _busy:
		_preview.texture = null
	_set_busy(_busy)


func _new_seed() -> void:
	_profile.seed = randi_range(1, 2147483646)
	_inspector.edit(null)
	_inspector.edit(_profile)
	if is_instance_valid(_source):
		_preview_pressed()


func _load_profile() -> void:
	_file_dialog.popup_centered_ratio(0.65)


func _profile_selected(path: String) -> void:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is Profile:
		_status.text = "请选择 TrunkBakeProfile 参数文件。"
		return
	_profile = resource.duplicate(true) as Profile
	_inspector.edit(_profile)
	_status.text = "已加载：%s" % path


func _prepare() -> Dictionary:
	if not is_instance_valid(_source):
		return {"error": "源 Ground 已移除，请重新选择。"}
	return Baker.prepare(Geometry.source_polygon(_source), _profile)


func _preview_pressed() -> void:
	if _busy:
		return
	var prepared := _prepare()
	if not prepared.error.is_empty():
		_status.text = prepared.error
		return
	_set_busy(true)
	var result := Baker.preview(prepared)
	if result.error.is_empty():
		_preview.texture = ImageTexture.create_from_image(result.image)
		_status.text = "预览完成；完整尺寸 %d×%d，预计 RGBA8 纹理 %.2f MiB（另加分块边距）。" % [prepared.pixel_size.x, prepared.pixel_size.y, float(prepared.estimated_bytes) / 1048576.0]
	else:
		_status.text = result.error
	_set_busy(false)


func _save_pressed() -> void:
	if _busy:
		return
	var prepared := _prepare()
	if not prepared.error.is_empty():
		_status.text = prepared.error
		return
	var source := Writer.capture_source(_source)
	var output := Writer.reserve_directory(_output_controls.directory_edit.text, _output_controls.name_edit.text)
	if not output.error.is_empty():
		_status.text = output.error
		return
	_set_busy(true)
	_cancelled = false
	var profile: Profile = prepared.profile
	var size: Vector2i = prepared.pixel_size
	var columns := ceili(float(size.x) / profile.tile_size_px)
	var rows := ceili(float(size.y) / profile.tile_size_px)
	var tiles: Array[Dictionary] = []
	for row in range(rows):
		for column in range(columns):
			if _should_stop(output):
				return
			_status.text = "正在生成 %d / %d 块纹理……" % [row * columns + column + 1, rows * columns]
			await get_tree().process_frame
			if _should_stop(output):
				return
			var tile := Baker.bake_tile(prepared, Vector2i(column, row) * profile.tile_size_px)
			if not tile.error.is_empty():
				_failed(tile.error, output)
				return
			var path := Output.texture_path(output, tiles.size() + 1)
			var conflict := Output.ensure_absent(PackedStringArray([path]))
			if not conflict.is_empty():
				_failed(conflict, output)
				return
			var image: Image = tile.image
			var error := image.save_png(path)
			if error != OK:
				_failed("PNG 保存失败（错误 %d）。" % error, output)
				return
			tile.erase("image")
			tile["path"] = path
			tiles.append(tile)
	_status.text = "PNG 已保存，正在导入 %d 张纹理……" % tiles.size()
	EditorInterface.get_resource_filesystem().scan()
	for tile in tiles:
		var texture := await _import_texture(tile.path)
		if _should_stop(output):
			return
		if texture == null:
			_failed("纹理导入超时：%s" % tile.path, output)
			return
		tile["texture"] = texture
	var saved := Writer.save_result(source, prepared, tiles, output)
	if not saved.error.is_empty():
		_failed(saved.error, output)
		return
	EditorInterface.get_resource_filesystem().scan()
	var thumbnail := Baker.preview(prepared)
	if thumbnail.error.is_empty():
		_preview.texture = ImageTexture.create_from_image(thumbnail.image)
	_status.text = "完成：%s\n纹理 %d 张；游戏直接加载保存结果。" % [saved.scene_path, tiles.size()]
	_set_busy(false)


func _import_texture(path: String) -> Texture2D:
	var deadline := Time.get_ticks_msec() + 60000
	while _active and not _cancelled and Time.get_ticks_msec() < deadline:
		if ResourceLoader.exists(path, "Texture2D"):
			var texture := ResourceLoader.load(path, "Texture2D") as Texture2D
			if texture != null:
				return texture
		await get_tree().create_timer(0.15).timeout
	return null


func _should_stop(output: Dictionary) -> bool:
	if not _active:
		return true
	if _cancelled:
		_failed("生成已取消。", output)
		return true
	return false


func _failed(message: String, output: Dictionary) -> void:
	_status.text = "%s\n已写入的文件保留在：%s" % [message, output.directory]
	_set_busy(false)


func _set_busy(value: bool) -> void:
	_busy = value
	_output_controls.set_busy(value)
	_preview_button.disabled = value or not is_instance_valid(_source)
	_save_button.disabled = value or not is_instance_valid(_source)
	_seed_button.disabled = value
	_load_button.disabled = value
	_cancel_button.disabled = not value
