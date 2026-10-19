## 选关界面只读取通关状态，关卡切换由 Main 统一执行。
extends Control

signal level_selected(level_id: int)

const COMPLETED := preload("res://Texture/Level_Icon/Level_Completed.png")
const UNLOCKED := preload("res://Texture/Level_Icon/Leve_Unlock.png")
const LOCKED := preload("res://Texture/Level_Icon/Level_Lock.png")

@export_range(1.0, 1.3, 0.01) var hover_scale: float = 1.06
@export_range(0.01, 0.5, 0.01) var hover_duration: float = 0.04
@export_range(0.0, 10.0, 0.5) var hover_rotation_degrees: float = 4.0

var _buttons: Array[Button] = []
var _visuals: Dictionary[Button, Array] = {}
var _hover_tweens: Dictionary[Button, Tween] = {}

func _ready() -> void:
	var empty := StyleBoxEmpty.new()
	for button: Button in $OptionsInterface/Level.get_children():
		_buttons.append(button)
		## 所有按钮状态均由两张贴图绘制，禁用时也不叠加原生底色。
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, empty)
		var visuals: Array[Dictionary] = []
		for visual: Sprite2D in [button.get_node("LevelIconBackground"), button.get_node("LevelIcon")]:
			visuals.append({"node": visual, "scale": visual.scale, "rotation": visual.rotation})
		_visuals[button] = visuals
		button.mouse_entered.connect(_set_hover.bind(button, true))
		button.mouse_exited.connect(_set_hover.bind(button, false))
		button.pressed.connect(_on_level_pressed.bind(button))
	visibility_changed.connect(_on_visibility_changed)
	get_window().focus_exited.connect(_reset_hover)
	refresh_progress()

func is_level_available(level_id: int) -> bool:
	return level_id >= 1 and level_id <= SaveSystem.LEVEL_COUNT and (
		level_id == 1 or SaveSystem.is_level_completed(level_id)
		or SaveSystem.is_level_completed(level_id - 1)
	)

func refresh_progress() -> void:
	_reset_hover()
	for button in _buttons:
		var level_id: int = button.get_meta(&"level_id")
		var completed := SaveSystem.is_level_completed(level_id)
		var available := is_level_available(level_id)
		(button.get_node("LevelIconBackground") as Sprite2D).texture = (
			COMPLETED if completed else UNLOCKED if available else LOCKED
		)
		button.disabled = not available
		button.focus_mode = Control.FOCUS_ALL if available else Control.FOCUS_NONE

func _on_level_pressed(button: Button) -> void:
	var level_id: int = button.get_meta(&"level_id")
	if not is_visible_in_tree() or button.disabled or SceneTransition.busy or not is_level_available(level_id):
		return
	SoundPlayer.play(&"ui_press")
	level_selected.emit(level_id)

## 两张贴图共用一个倾斜角；按钮本身的变换和命中范围始终保持原样。
func _set_hover(button: Button, active: bool) -> void:
	if button.disabled or not is_visible_in_tree() or (active and SceneTransition.busy):
		return
	_stop_hover(button)
	var angle := deg_to_rad(hover_rotation_degrees)
	var rotation_offset := randf_range(-angle, angle) if active else 0.0
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tweens[button] = tween
	for visual: Dictionary in _visuals[button]:
		tween.tween_property(visual.node, "scale", visual.scale * (hover_scale if active else 1.0), hover_duration)
		tween.tween_property(visual.node, "rotation", visual.rotation + rotation_offset, hover_duration)

func _stop_hover(button: Button) -> void:
	var tween: Tween = _hover_tweens.get(button)
	if tween != null and tween.is_valid():
		tween.kill()
	_hover_tweens.erase(button)

func _reset_hover() -> void:
	for button in _buttons:
		_stop_hover(button)
		for visual: Dictionary in _visuals[button]:
			visual.node.scale = visual.scale
			visual.node.rotation = visual.rotation

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		refresh_progress()
	else:
		_reset_hover()
