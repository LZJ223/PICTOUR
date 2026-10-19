## 游戏偏好、键位、音量和重置接入 SaveSystem。
extends Control

const RELEASED := preload("res://Texture/Button/Button_released.png")
const PRESSED := preload("res://Texture/Button/Button_Pressed.png")

@export_range(1.0, 1.2, 0.01) var sidebar_hover_scale: float = 1.06
@export_range(0.01, 0.5, 0.01) var sidebar_hover_duration: float = 0.08
@export_range(0.1, 10.0, 0.1) var clear_hold_duration: float = 5.0
@export_range(0.0, 20.0, 0.5) var clear_shake_amplitude: float = 2.0
@export_range(0.0, 10.0, 0.25) var clear_shake_rotation_degrees: float = 0.75

@onready var _tabs: Array[Button] = [$SideBar/Game, $SideBar/Audio, $SideBar/Control]
@onready var _pages: Array[Control] = [$Content/Game, $Content/Audio, $Content/Control]
@onready var _clear_button: Button = $Content/Game/Clear/Action
@onready var _clear_visual: Control = $Content/Game/Clear/Action/VisualRoot
@onready var _clear_visual_position: Vector2 = _clear_visual.position
@onready var _clear_visual_rotation: float = _clear_visual.rotation
@onready var _clear_progress: ProgressBar = $Content/Game/Clear/Action/VisualRoot/Progress
@onready var _clear_timer: Timer = $ClearTimer
@onready var _binding_hint: Label = $Content/Control/BindingHint

var _label_scales: Dictionary[Label, Vector2] = {}
var _label_tweens: Dictionary[Label, Tween] = {}
var _listening_button: Button
var _binding_buttons: Dictionary[StringName, Button] = {}
var _clear_shake_time: float = 0.0

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
		if row.has_node("Slider"):
			var slider: HSlider = row.get_node("Slider")
			var value: Label = row.get_node("Value")
			slider.set_value_no_signal(SaveSystem.get_audio_volume(row.name))
			slider.value_changed.connect(_on_audio_changed.bind(row.name, value))
			_update_percentage(slider.value, value)
	SaveSystem.audio_changed.connect(_sync_audio_sliders)
	for row in $Content/Control.get_children():
		if not row.has_node("Key"):
			continue
		var button: Button = row.get_node("Key")
		var action: StringName = button.get_meta(&"action")
		_binding_buttons[action] = button
		button.pressed.connect(_listen_for_key.bind(button))
	SaveSystem.key_bindings_changed.connect(_sync_key_bindings)
	_sync_key_bindings()
	_clear_button.button_down.connect(_begin_clear_hold)
	_clear_button.button_up.connect(_cancel_clear_hold)
	_clear_button.mouse_exited.connect(_cancel_clear_hold)
	_clear_timer.timeout.connect(_finish_clear_hold)
	$Content/Game/Fullscreen/Toggle.toggled.connect(_on_preference_toggled.bind("fullscreen"))
	$Content/Game/Dialogue/Toggle.toggled.connect(_on_preference_toggled.bind("skip_dialogue"))
	$Content/Game/Progress/Toggle.toggled.connect(_on_preference_toggled.bind("progress_limit_enabled"))
	SaveSystem.preferences_changed.connect(_sync_game_settings)
	_sync_game_settings()
	visibility_changed.connect(_on_visibility_changed)
	get_window().focus_exited.connect(_cancel_interactions)
	_select_page(0)
	set_process(false)

func _sync_game_settings() -> void:
	$Content/Game/Fullscreen/Toggle.set_pressed_no_signal(SaveSystem.fullscreen)
	$Content/Game/Dialogue/Toggle.set_pressed_no_signal(SaveSystem.skip_dialogue)
	$Content/Game/Progress/Toggle.set_pressed_no_signal(SaveSystem.progress_limit_enabled)

func _on_preference_toggled(pressed: bool, key: String) -> void:
	SaveSystem.set_preference(key, pressed)
	_sync_game_settings()

func _on_tab_toggled(pressed: bool, index: int) -> void:
	if pressed:
		SoundPlayer.play(&"ui_press")
		_select_page(index)

func _on_audio_changed(value: float, channel: String, label: Label) -> void:
	_update_percentage(value, label)
	SaveSystem.set_audio_volume(channel, value)

func _sync_audio_sliders() -> void:
	for row in $Content/Audio.get_children():
		if not row.has_node("Slider"):
			continue
		var slider: HSlider = row.get_node("Slider")
		slider.set_value_no_signal(SaveSystem.get_audio_volume(row.name))
		_update_percentage(slider.value, row.get_node("Value"))

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
	SignalSystem.key_binding_listener = self
	_key_label(button).text = ""
	_binding_hint.text = "请输入按键..."
	_binding_hint.show()

func _sync_key_bindings() -> void:
	for action in _binding_buttons:
		var button := _binding_buttons[action]
		if button == _listening_button:
			continue
		var key := SaveSystem.get_key_binding(action)
		_key_label(button).text = _key_name(key) if key != null else "未绑定"

func _key_label(button: Button) -> Label:
	return button.get_node("Text") as Label

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _listening_button == null or SceneTransition.busy:
		return
	## 等待输入时也接收返回键；鼠标和重复键不参与绑定。
	if not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_NONE and event.physical_keycode == KEY_NONE:
		return
	var action: StringName = _listening_button.get_meta(&"action")
	var error := SaveSystem.set_key_binding(action, event)
	if error != OK:
		_binding_hint.text = "保存失败，请重新输入..." if error != ERR_INVALID_PARAMETER else "请输入按键..."
		return
	_cancel_listening()
	SoundPlayer.play(&"ui_press")

func _key_name(event: InputEventKey) -> String:
	var code := event.physical_keycode if event.physical_keycode != 0 else event.keycode
	match code:
		KEY_SPACE:
			return "空格"
		KEY_ESCAPE:
			return "Esc"
		KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META:
			var side := "右 " if event.location == KEY_LOCATION_RIGHT else "左 " if event.location == KEY_LOCATION_LEFT else ""
			return side + OS.get_keycode_string(code)
	return OS.get_keycode_string(code)

func _cancel_listening() -> void:
	if SignalSystem.key_binding_listener == self:
		SignalSystem.key_binding_listener = null
	if _listening_button != null:
		_listening_button = null
		_sync_key_bindings()
	_binding_hint.hide()

func _exit_tree() -> void:
	if SignalSystem.key_binding_listener == self:
		SignalSystem.key_binding_listener = null

func _begin_clear_hold() -> void:
	if not _clear_button.is_visible_in_tree() or SceneTransition.busy:
		return
	_cancel_clear_hold()
	_clear_timer.start(clear_hold_duration)
	_clear_progress.show()
	set_process(true)

func _process(delta: float) -> void:
	if not _clear_button.is_visible_in_tree() or SceneTransition.busy:
		_cancel_clear_hold()
		return
	var progress := clampf(1.0 - _clear_timer.time_left / _clear_timer.wait_time, 0.0, 1.0)
	_clear_progress.value = progress
	_clear_shake_time += delta
	var strength := lerpf(0.1, 1.0, progress * progress)
	_clear_visual.position = _clear_visual_position + Vector2(
		sin(_clear_shake_time * 61.0), sin(_clear_shake_time * 47.0) * 0.7
	) * clear_shake_amplitude * strength
	_clear_visual.rotation = _clear_visual_rotation + sin(_clear_shake_time * 73.0) * deg_to_rad(clear_shake_rotation_degrees) * strength

func _cancel_clear_hold() -> void:
	_clear_timer.stop()
	_clear_progress.value = 0.0
	_clear_progress.hide()
	_reset_clear_visual()
	set_process(false)

func _finish_clear_hold() -> void:
	if not _clear_button.is_visible_in_tree() or SceneTransition.busy:
		_cancel_clear_hold()
		return
	set_process(false)
	_reset_clear_visual()
	if SaveSystem.reset_progress() == OK:
		SoundPlayer.play(&"ui_press")
		_clear_progress.value = 1.0
	else:
		_cancel_clear_hold()

func _reset_clear_visual() -> void:
	_clear_shake_time = 0.0
	_clear_visual.position = _clear_visual_position
	_clear_visual.rotation = _clear_visual_rotation

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
