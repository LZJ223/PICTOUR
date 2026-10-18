## 设置界面原型：交互只保存在本节点，不写配置、InputMap 或存档。
extends Control

const RELEASED := preload("res://Texture/Button/Button_released.png")
const PRESSED := preload("res://Texture/Button/Button_Pressed.png")
const PREVIEW_HINT := "界面预览 · 暂不应用或保存设置"

@export_range(1.0, 1.2, 0.01) var sidebar_hover_scale: float = 1.06
@export_range(0.01, 0.5, 0.01) var sidebar_hover_duration: float = 0.08
@export_range(0.1, 10.0, 0.1) var clear_hold_duration: float = 5.0

@onready var _tabs: Array[Button] = [$SideBar/Game, $SideBar/Audio, $SideBar/Control]
@onready var _pages: Array[Control] = [$Content/Game, $Content/Audio, $Content/Control]
@onready var _clear_button: Button = $Content/Game/Clear/Action
@onready var _clear_progress: ProgressBar = $Content/Game/Clear/Action/Progress
@onready var _clear_timer: Timer = $ClearTimer
@onready var _hint: Label = $Hint

var _label_scales: Dictionary[Label, Vector2] = {}
var _label_tweens: Dictionary[Label, Tween] = {}
var _listening_button: Button
var _previous_key_text: String

func _ready() -> void:
	var empty := StyleBoxEmpty.new()
	for index in _tabs.size():
		var button := _tabs[index]
		var label: Label = button.get_node("Text")
		_label_scales[label] = label.scale
		label.pivot_offset = label.size * 0.5
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, empty)
		button.toggled.connect(_on_tab_toggled.bind(index))
		button.mouse_entered.connect(_hover_label.bind(label, true))
		button.mouse_exited.connect(_hover_label.bind(label, false))
	for row in $Content/Audio.get_children():
		if row is HBoxContainer:
			var slider: HSlider = row.get_node("Slider")
			var value: Label = row.get_node("Value")
			slider.value_changed.connect(_update_percentage.bind(value))
			_update_percentage(slider.value, value)
	for column in $Content/Control/Columns.get_children():
		for row in column.get_children():
			var button: Button = row.get_node("Key")
			var action: StringName = button.get_meta(&"action")
			button.text = "未绑定"
			for event in InputMap.action_get_events(action):
				if event is InputEventKey:
					button.text = _key_name(event)
					break
			button.pressed.connect(_listen_for_key.bind(button))
	_clear_button.button_down.connect(_begin_clear_hold)
	_clear_button.button_up.connect(_cancel_clear_hold)
	_clear_button.mouse_exited.connect(_cancel_clear_hold)
	_clear_timer.timeout.connect(_finish_clear_hold)
	visibility_changed.connect(_on_visibility_changed)
	get_window().focus_exited.connect(_cancel_interactions)
	_select_page(0)
	set_process(false)

func _on_tab_toggled(pressed: bool, index: int) -> void:
	if pressed:
		_select_page(index)

func _select_page(index: int) -> void:
	_cancel_interactions()
	for tab_index in _tabs.size():
		var selected := tab_index == index
		_tabs[tab_index].set_pressed_no_signal(selected)
		_tabs[tab_index].get_node("Icon").texture = PRESSED if selected else RELEASED
		_pages[tab_index].visible = selected

func _hover_label(label: Label, active: bool) -> void:
	var previous: Tween = _label_tweens.get(label)
	if previous != null and previous.is_valid():
		previous.kill()
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_label_tweens[label] = tween
	tween.tween_property(label, "scale", _label_scales[label] * (
		sidebar_hover_scale if active else 1.0
	), sidebar_hover_duration)

func _update_percentage(value: float, label: Label) -> void:
	label.text = "%d%%" % roundi(value)

func _listen_for_key(button: Button) -> void:
	_cancel_listening()
	_listening_button = button
	_previous_key_text = button.text
	button.text = "按键…"
	_hint.text = "请按下新按键 · Esc 返回"

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _listening_button == null or SceneTransition.busy:
		return
	## 返回仍由 Main / Pause 处理，监听不会吞掉 Esc；鼠标和重复键不参与绑定。
	if not event is InputEventKey or not event.pressed or event.echo or event.is_action("back"):
		return
	if event.keycode == KEY_NONE and event.physical_keycode == KEY_NONE:
		return
	_listening_button.text = _key_name(event)
	_listening_button = null
	_hint.text = "按键已更新（仅界面预览） · Esc 返回"
	get_viewport().set_input_as_handled()

func _key_name(event: InputEventKey) -> String:
	var code := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	match code:
		KEY_SPACE:
			return "空格"
		KEY_ESCAPE:
			return "Esc"
		KEY_SHIFT:
			return "右 Shift" if event.location == KEY_LOCATION_RIGHT else "左 Shift"
	return OS.get_keycode_string(code)

func _cancel_listening() -> void:
	if _listening_button != null:
		_listening_button.text = _previous_key_text
		_listening_button = null
	_hint.text = PREVIEW_HINT

func _begin_clear_hold() -> void:
	if not is_visible_in_tree() or SceneTransition.busy:
		return
	_clear_timer.start(clear_hold_duration)
	_clear_progress.value = 0.0
	_clear_progress.show()
	set_process(true)

func _process(_delta: float) -> void:
	_clear_progress.value = 1.0 - _clear_timer.time_left / _clear_timer.wait_time
	_clear_button.text = "按住 %.1f 秒" % _clear_timer.time_left

func _cancel_clear_hold() -> void:
	_clear_timer.stop()
	_clear_progress.value = 0.0
	_clear_progress.hide()
	_clear_button.text = "长按 %s 秒" % str(clear_hold_duration).trim_suffix(".0")
	set_process(false)

func _finish_clear_hold() -> void:
	set_process(false)
	_clear_progress.value = 1.0
	_clear_button.text = "已完成（预览）"
	_hint.text = "长按完成 · 当前仅预览，不会删除存档"

func _cancel_interactions() -> void:
	_cancel_clear_hold()
	_cancel_listening()

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_select_page(0)
	else:
		_cancel_interactions()
	for label in _label_scales:
		var tween: Tween = _label_tweens.get(label)
		if tween != null and tween.is_valid():
			tween.kill()
		label.scale = _label_scales[label]
