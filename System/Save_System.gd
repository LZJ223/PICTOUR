## 仅持久化十二个关卡的通关状态；关卡编号为 1～12，数组索引为 0～11。
extends Node

const LEVEL_COUNT: int = 12
const SAVE_PATH: String = "user://progress.json"

var _completed_levels: Array[bool] = []

func _init() -> void:
	_completed_levels.resize(LEVEL_COUNT)
	_completed_levels.fill(false)

func _ready() -> void:
	load_progress()

func is_level_completed(level_id: int) -> bool:
	return level_id >= 1 and level_id <= LEVEL_COUNT and _completed_levels[level_id - 1]

## 文件不存在时创建初始存档；无效文件保留原样，不将错误数据当作通关进度。
func load_progress() -> Error:
	if not FileAccess.file_exists(SAVE_PATH):
		_completed_levels.fill(false)
		return save_progress()
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		var error := FileAccess.get_open_error()
		push_error("读取通关存档失败：%s" % error_string(error))
		return error
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Array or data.size() != LEVEL_COUNT:
		push_warning("通关存档必须包含十二个布尔值：%s" % SAVE_PATH)
		return ERR_FILE_CORRUPT
	for value: Variant in data:
		if not value is bool:
			push_warning("通关存档包含非布尔值：%s" % SAVE_PATH)
			return ERR_FILE_CORRUPT
	_completed_levels.assign(data)
	return OK

## 每次通关立即落盘；先写临时文件，成功后替换旧存档。
func complete_level(level_id: int) -> Error:
	if level_id < 1 or level_id > LEVEL_COUNT:
		return ERR_INVALID_PARAMETER
	_completed_levels[level_id - 1] = true
	return save_progress()

func save_progress() -> Error:
	var temporary_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		var error := FileAccess.get_open_error()
		push_error("写入通关存档失败：%s" % error_string(error))
		return error
	file.store_string(JSON.stringify(_completed_levels))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temporary_path),
			ProjectSettings.globalize_path(SAVE_PATH)
		)
	if error != OK:
		push_error("保存通关存档失败：%s" % error_string(error))
	return error
