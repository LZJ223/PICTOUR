@tool
extends EditorPlugin

const Profile = preload("res://addons/cloud_box_rounder/cloud_round_profile.gd")
const Geometry = preload("res://addons/cloud_box_rounder/cloud_round_geometry.gd")
const Adapter = preload("res://addons/cloud_box_rounder/cloud_node_adapter.gd")
const Writer = preload("res://addons/cloud_box_rounder/cloud_scene_writer.gd")
const OutputControls = preload("res://addons/texture_baker_common/output_controls.gd")

var _dock: VBoxContainer
var _selection_label: Label
var _bindings_label: Label
var _status: Label
var _inspector: EditorInspector
var _preview_button: Button
var _clear_button: Button
var _save_button: Button
var _load_button: Button
var _file_dialog: EditorFileDialog
var _output_controls: OutputControls
var _source: Node2D
var _profile: Profile
var _preview_polygon := PackedVector2Array()
var _preview_original := PackedVector2Array()
var _busy := false


func _enter_tree() -> void:
	_profile = Profile.new()
	_build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)
	set_force_draw_over_forwarding_enabled()
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	set_process(false)
	_selection_changed()


func _exit_tree() -> void:
	if EditorInterface.get_selection().selection_changed.is_connected(_selection_changed):
		EditorInterface.get_selection().selection_changed.disconnect(_selection_changed)
	_clear_preview()
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "CloudBox Rounder"
	_dock.custom_minimum_size = Vector2(310, 400)
	var title := Label.new()
	title.text = "ShadowedGeometry → CloudBox 圆角"
	_dock.add_child(title)
	_selection_label = _label("请选择场景中的 ShadowedGeometry。")
	var note := _label("半径单位：CollisionBox 本地单位。保存时按面积质心居中并清除根变换；保留贴图缩放、材质与物理设置。")
	note.modulate.a = 0.8
	_bindings_label = _label("")
	_inspector = EditorInspector.new()
	_inspector.custom_minimum_size.y = 190
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.add_child(_inspector)
	_inspector.edit(_profile)
	_inspector.property_edited.connect(func(_property: String) -> void: _clear_preview())
	_output_controls = OutputControls.new()
	_dock.add_child(_output_controls)
	_output_controls.configure("res://Generated/CloudBox", "CloudBox")
	var actions := HBoxContainer.new()
	_dock.add_child(actions)
	_preview_button = _button(actions, "预览圆角", _preview_pressed)
	_clear_button = _button(actions, "清除预览", _clear_preview)
	_save_button = _button(actions, "生成并保存", _save_pressed)
	var settings := HBoxContainer.new()
	_dock.add_child(settings)
	_load_button = _button(settings, "加载圆角参数", _load_profile)
	_status = _label("预览显示黄色原轮廓与青色圆角轮廓；生成结果保存为完整场景。")
	_file_dialog = EditorFileDialog.new()
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.tres ; CloudRoundProfile 圆角参数"])
	_file_dialog.file_selected.connect(_profile_selected)
	_dock.add_child(_file_dialog)


func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(label)
	return label


func _button(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _selection_changed() -> void:
	_clear_preview()
	_source = null
	for node in EditorInterface.get_selection().get_selected_nodes():
		if Adapter.is_source(node):
			_source = node
			break
	_selection_label.text = "当前节点：%s" % _source.name if _source != null else "请选择场景中的 ShadowedGeometry。"
	_bindings_label.text = ""
	if _source != null:
		var inspected := Adapter.inspect_source(_source)
		if inspected.error.is_empty():
			_show_bindings(inspected.bindings)
		else:
			_bindings_label.text = inspected.error
	_set_busy(false)


func _show_bindings(bindings: Array[Dictionary]) -> void:
	var paths := PackedStringArray()
	for binding in bindings:
		paths.append(binding.path)
	_bindings_label.text = "同步 %d 个轮廓节点：\n%s" % [bindings.size(), "\n".join(paths)]


func _prepare() -> Dictionary:
	var inspected := Adapter.inspect_source(_source)
	if not inspected.error.is_empty():
		return inspected
	var rounded := Geometry.round_polygon(inspected.polygon, _profile)
	if rounded.error.is_empty():
		rounded["bindings"] = inspected.bindings
		rounded["original_polygon"] = inspected.polygon
	return rounded


func _preview_pressed() -> void:
	if _busy:
		return
	var rounded := _prepare()
	if not rounded.error.is_empty():
		_status.text = rounded.error
		_clear_preview()
		return
	_show_preview(rounded)
	_status.text = "预览完成：%d → %d 个顶点。%s" % [rounded.original_polygon.size(), rounded.polygon.size(), "\n".join(rounded.warnings)]


func _show_preview(rounded: Dictionary) -> void:
	_preview_polygon = rounded.polygon.duplicate()
	_preview_original = rounded.original_polygon.duplicate()
	_show_bindings(rounded.bindings)
	set_process(true)
	update_overlays()


func _clear_preview() -> void:
	_preview_polygon.clear()
	_preview_original.clear()
	set_process(false)
	update_overlays()


func _process(_delta: float) -> void:
	if not is_instance_valid(_source):
		_clear_preview()
		return
	var collision := _source.get_node_or_null("CollisionBox") as CollisionPolygon2D
	if collision == null or collision.polygon != _preview_original:
		_clear_preview()


func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	if _preview_polygon.is_empty() or not is_instance_valid(_source):
		return
	var collision := _source.get_node_or_null("CollisionBox") as CollisionPolygon2D
	if collision == null:
		return
	var transform := collision.get_global_transform_with_canvas()
	var original := _preview_original.duplicate()
	original.append(original[0])
	var rounded := _preview_polygon.duplicate()
	rounded.append(rounded[0])
	overlay.draw_polyline(transform * original, Color(1.0, 0.75, 0.15, 0.8), 1.0, true)
	overlay.draw_polyline(transform * rounded, Color(0.1, 0.95, 0.9, 1.0), 2.0, true)


func _save_pressed() -> void:
	if _busy:
		return
	var rounded := _prepare()
	if not rounded.error.is_empty():
		_status.text = rounded.error
		return
	var output := Writer.reserve_directory(_output_controls.directory_edit.text, _output_controls.name_edit.text)
	if not output.error.is_empty():
		_status.text = output.error
		return
	_set_busy(true)
	var saved := Writer.save_result(_source, rounded, rounded.bindings, _profile, output)
	_set_busy(false)
	if not saved.error.is_empty():
		_status.text = "%s\n已写入文件保留在：%s" % [saved.error, output.directory]
		return
	EditorInterface.get_resource_filesystem().scan()
	_show_preview(rounded)
	_status.text = "完成：%s\n已按面积质心居中，根变换已清除。\n同步 %d 个轮廓节点，共 %d 个顶点。%s" % [saved.scene_path, rounded.bindings.size(), rounded.polygon.size(), "\n".join(rounded.warnings)]


func _set_busy(value: bool) -> void:
	_busy = value
	_preview_button.disabled = value or not is_instance_valid(_source)
	_save_button.disabled = value or not is_instance_valid(_source)
	_clear_button.disabled = value
	_load_button.disabled = value
	_output_controls.set_busy(value)


func _load_profile() -> void:
	_file_dialog.popup_centered_ratio(0.65)


func _profile_selected(path: String) -> void:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is Profile:
		_status.text = "请选择 CloudRoundProfile 圆角参数文件。"
		return
	_profile = resource.duplicate(true) as Profile
	_inspector.edit(_profile)
	_clear_preview()
	_status.text = "已加载：" + path
