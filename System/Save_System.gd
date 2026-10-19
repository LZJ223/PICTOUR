## 持久化十二关通关状态、游戏偏好和键位，兼容旧存档。
extends Node

signal progress_changed
signal preferences_changed
signal key_bindings_changed

const LEVEL_COUNT: int = 12
const SAVE_PATH: String = "user://progress.json"
const REBINDABLE_ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right", &"jump",
	&"UAV", &"forward", &"backward", &"look_at_destination", &"back",
]
const DEFAULT_PREFERENCES := {
	"fullscreen": false,
	"skip_dialogue": false,
	"progress_limit_enabled": true,
}

var _completed_levels: Array[bool] = []
var _preferences: Dictionary = DEFAULT_PREFERENCES.duplicate()
var _default_key_bindings: Dictionary[StringName, InputEventKey] = {}
var _key_bindings: Dictionary[StringName, InputEventKey] = {}

var fullscreen: bool:
	get:
		return _preferences["fullscreen"]
var skip_dialogue: bool:
	get:
		return _preferences["skip_dialogue"]
var progress_limit_enabled: bool:
	get:
		return _preferences["progress_limit_enabled"]

func _init() -> void:
	_completed_levels.resize(LEVEL_COUNT)
	_completed_levels.fill(false)

func _ready() -> void:
	## 只在启动时捕获项目默认值，后续读旧存档不会把自定义键位当作默认值。
	for action in REBINDABLE_ACTIONS:
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				_default_key_bindings[action] = _normalize_key(event)
				break
	_key_bindings = _default_key_bindings.duplicate()
	load_progress()

func is_level_completed(level_id: int) -> bool:
	return level_id >= 1 and level_id <= LEVEL_COUNT and _completed_levels[level_id - 1]

## 文件不存在时创建初始存档；无效文件保留原样，不将错误数据当作通关进度。
func load_progress() -> Error:
	if not FileAccess.file_exists(SAVE_PATH):
		_completed_levels.fill(false)
		_preferences = DEFAULT_PREFERENCES.duplicate()
		_key_bindings = _default_key_bindings.duplicate()
		return _publish_loaded_state(save_progress())
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		var error := FileAccess.get_open_error()
		push_error("读取存档失败：%s" % error_string(error))
		return error
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var legacy := data is Array
	var levels: Variant = data if legacy else data.get("completed_levels") if data is Dictionary else null
	var preferences: Dictionary = DEFAULT_PREFERENCES.duplicate()
	var bindings: Dictionary[StringName, InputEventKey] = _default_key_bindings.duplicate()
	var migrate_bindings: bool = false
	if not levels is Array or levels.size() != LEVEL_COUNT:
		push_warning("通关存档必须包含十二个布尔值：%s" % SAVE_PATH)
		return ERR_FILE_CORRUPT
	for value: Variant in levels:
		if not value is bool:
			push_warning("通关存档包含非布尔值：%s" % SAVE_PATH)
			return ERR_FILE_CORRUPT
	if not legacy:
		var stored_preferences: Variant = data.get("preferences", {})
		if not stored_preferences is Dictionary:
			return ERR_FILE_CORRUPT
		for key: String in DEFAULT_PREFERENCES:
			var value: Variant = stored_preferences.get(key, DEFAULT_PREFERENCES[key])
			if not value is bool:
				push_warning("存档偏好必须是布尔值：%s" % key)
				return ERR_FILE_CORRUPT
			preferences[key] = value
		if data.has("key_bindings"):
			var stored_bindings: Variant = data.key_bindings
			if not stored_bindings is Dictionary:
				return ERR_FILE_CORRUPT
			for action in REBINDABLE_ACTIONS:
				# 九项键位的旧存档补上默认返回键，其余缺项仍视为损坏。
				if action == &"back" and not stored_bindings.has("back"):
					migrate_bindings = true
					continue
				var stored: Variant = stored_bindings.get(String(action))
				if not stored is Dictionary:
					return ERR_FILE_CORRUPT
				var code: Variant = stored.get("physical_keycode")
				var location: Variant = stored.get("location")
				if not _is_integer_in_range(code, 1, KEY_UNKNOWN - 1) or not _is_integer_in_range(location, 0, 2):
					return ERR_FILE_CORRUPT
				var key := InputEventKey.new()
				key.physical_keycode = int(code)
				key.location = int(location)
				bindings[action] = _normalize_key(key)
				if bindings[action] == null:
					return ERR_FILE_CORRUPT
			if not _bindings_are_unique(bindings):
				return ERR_FILE_CORRUPT
	## 全部验证通过后再更新内存；旧存档自动补齐偏好和键位并迁移。
	_completed_levels.assign(levels)
	_preferences = preferences
	_key_bindings = bindings
	return _publish_loaded_state(save_progress() if legacy or not data.has("key_bindings") or migrate_bindings else OK)

func _publish_loaded_state(error: Error) -> Error:
	_apply_fullscreen()
	_apply_key_bindings()
	progress_changed.emit()
	preferences_changed.emit()
	key_bindings_changed.emit()
	return error

func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and value >= minimum and value <= maximum and value == floor(value)

## 每项操作绑定一个物理按键，左右修饰键分别记录，不保存按下状态或组合修饰标记。
func _normalize_key(event: InputEventKey) -> InputEventKey:
	if event == null:
		return null
	var code := event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if code <= KEY_NONE or code >= KEY_UNKNOWN or OS.get_keycode_string(code).is_empty():
		return null
	if event.location < KEY_LOCATION_UNSPECIFIED or event.location > KEY_LOCATION_RIGHT:
		return null
	var key := InputEventKey.new()
	key.physical_keycode = code
	if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		key.location = event.location
	return key

func _keys_overlap(first: InputEventKey, second: InputEventKey) -> bool:
	return first.physical_keycode == second.physical_keycode and (
		first.location == second.location or first.location == KEY_LOCATION_UNSPECIFIED
		or second.location == KEY_LOCATION_UNSPECIFIED
	)

func _bindings_are_unique(bindings: Dictionary[StringName, InputEventKey]) -> bool:
	var seen: Array[InputEventKey] = []
	for key in bindings.values():
		for previous in seen:
			if _keys_overlap(key, previous):
				return false
		seen.append(key)
	return true

func get_key_binding(action: StringName) -> InputEventKey:
	var key: InputEventKey = _key_bindings.get(action)
	return key.duplicate() as InputEventKey if key != null else null

## 冲突时交换两项操作的键位，保证每项操作始终有键可用。
func set_key_binding(action: StringName, event: InputEventKey) -> Error:
	var key := _normalize_key(event)
	if not REBINDABLE_ACTIONS.has(action) or key == null:
		return ERR_INVALID_PARAMETER
	var previous := _key_bindings.duplicate()
	var candidate := _key_bindings.duplicate()
	for other in REBINDABLE_ACTIONS:
		if other != action and _keys_overlap(key, _key_bindings[other]):
			candidate[other] = _key_bindings[action]
			break
	candidate[action] = key
	## 未区分左右的修饰键可能同时覆盖两项操作，不能写入这种歧义绑定。
	if not _bindings_are_unique(candidate):
		return ERR_INVALID_PARAMETER
	_key_bindings = candidate
	var error := save_progress()
	if error != OK:
		_key_bindings = previous
		return error
	_apply_key_bindings()
	key_bindings_changed.emit()
	return OK

func _apply_key_bindings() -> void:
	for action in REBINDABLE_ACTIONS:
		## 清理改键前的长按状态；保留非键盘输入和鼠标选取。
		Input.action_release(action)
		for event in InputMap.action_get_events(action):
			if event is InputEventKey:
				InputMap.action_erase_event(action, event)
		InputMap.action_add_event(action, _key_bindings[action].duplicate())

## 先落盘再应用，写入失败时恢复原值，避免 UI 显示未保存的偏好。
func set_preference(key: String, value: bool) -> Error:
	if not DEFAULT_PREFERENCES.has(key):
		return ERR_INVALID_PARAMETER
	var previous: bool = _preferences[key]
	if previous == value:
		return OK
	_preferences[key] = value
	var error := save_progress()
	if error != OK:
		_preferences[key] = previous
		return error
	if key == "fullscreen":
		_apply_fullscreen()
	preferences_changed.emit()
	return OK

func _apply_fullscreen() -> void:
	## 编辑器嵌入窗口不支持模式切换；偏好照常保存，独立运行时应用。
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		return
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)

## 重置只清空通关记录，保留用户偏好与当前运行中的关卡。
func reset_progress() -> Error:
	var previous := _completed_levels.duplicate()
	_completed_levels.fill(false)
	var error := save_progress()
	if error != OK:
		_completed_levels.assign(previous)
		return error
	progress_changed.emit()
	return OK

## 每次通关立即落盘；先写临时文件，成功后替换旧存档。
func complete_level(level_id: int) -> Error:
	if level_id < 1 or level_id > LEVEL_COUNT:
		return ERR_INVALID_PARAMETER
	var previous := _completed_levels[level_id - 1]
	_completed_levels[level_id - 1] = true
	var error := save_progress()
	if error != OK:
		_completed_levels[level_id - 1] = previous
		return error
	progress_changed.emit()
	return OK

func save_progress() -> Error:
	var bindings: Dictionary = {}
	for action in REBINDABLE_ACTIONS:
		var key := _key_bindings[action]
		bindings[String(action)] = {"physical_keycode": key.physical_keycode, "location": key.location}
	var temporary_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		var error := FileAccess.get_open_error()
		push_error("写入存档失败：%s" % error_string(error))
		return error
	file.store_string(JSON.stringify({
		"version": 2,
		"completed_levels": _completed_levels,
		"preferences": _preferences,
		"key_bindings": bindings,
	}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temporary_path),
			ProjectSettings.globalize_path(SAVE_PATH)
		)
	if error != OK:
		push_error("保存存档失败：%s" % error_string(error))
	return error
