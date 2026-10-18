@tool
extends VBoxContainer

var name_edit: LineEdit
var directory_edit: LineEdit
var _browse_button: Button
var _directory_dialog: EditorFileDialog


func configure(default_parent: String, prefix: String) -> void:
	var name_label := Label.new()
	name_label.text = "素材名称（留空自动编号）"
	add_child(name_label)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "%s_001" % prefix
	name_edit.tooltip_text = "填写文件名，不含扩展名。将创建同名文件夹；已存在则拒绝输出。"
	add_child(name_edit)
	var directory_label := Label.new()
	directory_label.text = "输出父目录（留空使用默认）"
	add_child(directory_label)
	var row := HBoxContainer.new()
	add_child(row)
	directory_edit = LineEdit.new()
	directory_edit.placeholder_text = default_parent
	directory_edit.tooltip_text = "项目内的父目录；最终保存到 父目录/素材名称/。"
	directory_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(directory_edit)
	_browse_button = Button.new()
	_browse_button.text = "选择…"
	row.add_child(_browse_button)
	_directory_dialog = EditorFileDialog.new()
	_directory_dialog.title = "选择素材输出父目录"
	_directory_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_directory_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	_directory_dialog.dir_selected.connect(func(path: String) -> void: directory_edit.text = path)
	add_child(_directory_dialog)
	_browse_button.pressed.connect(func() -> void: _directory_dialog.popup_centered_ratio(0.65))


func set_busy(value: bool) -> void:
	name_edit.editable = not value
	directory_edit.editable = not value
	_browse_button.disabled = value
