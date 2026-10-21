## 仅修饰 Icon 及可选 Label，不改变按钮命中范围；长按进度复用调用者的实际计时器。
extends Button

@export_node_path("Node2D") var icon_path: NodePath = ^"Icon"
@export var show_hold_progress: bool = true
@export_range(1.0, 1.3, 0.01) var hover_scale: float = 1.08
@export_range(0.01, 0.5, 0.01) var hover_duration: float = 0.06
@export_range(0.0, 10.0, 0.5) var hover_rotation_degrees: float = 6.0
@export_range(0.01, 1.0, 0.01) var appear_duration: float = 0.28
@export_range(0.01, 1.0, 0.01) var disappear_duration: float = 0.18
@export_range(0.0, 5.0, 0.1) var hold_shake_amplitude: float = 1.2
@export_range(0.0, 10.0, 0.5) var hold_shake_rotation_degrees: float = 3.0
@export var progress_color: Color = Color(0.08, 0.68, 0.29)
@export_range(0.0, 20.0, 1.0) var ring_padding: float = 6.0

@onready var _icon: Node2D = get_node(icon_path)
@onready var _label: Label = get_node_or_null("Label") as Label
@onready var _base_scale: Vector2 = _icon.scale
@onready var _base_position: Vector2 = _icon.position
@onready var _base_rotation: float = _icon.rotation
@onready var _base_disabled: bool = disabled
var _hover_tween: Tween
var _presentation_tween: Tween
var _hover_scale: float = 1.0
var _presentation_scale: float = 1.0
var _hold_timer: Timer
var _hold_progress: float = 0.0
var _shake_time: float = 0.0
var _icon_size: Vector2
var _hover_rotation: float = 0.0
var _shake_rotation: float = 0.0
var _label_base_scale := Vector2.ONE
var _label_base_position := Vector2.ZERO
var _label_base_rotation: float = 0.0

func _ready() -> void:
	if _label != null:
		_label_base_scale = _label.scale
		_label_base_position = _label.position
		_label_base_rotation = _label.rotation
		_label.resized.connect(_sync_label_pivot)
		_sync_label_pivot()
	_icon_size = size
	## PNG 的透明留白不应扩大进度环；图像边界只在初始化时计算一次。
	var sprite := _icon as Sprite2D
	if sprite != null and sprite.texture != null:
		_icon_size = sprite.get_rect().size
		var image := sprite.texture.get_image()
		if image != null:
			if image.is_compressed():
				image.decompress()
			_icon_size = Vector2(image.get_used_rect().size)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	if tooltip_text.is_empty():
		tooltip_text = _label.text if _label != null else (text if not text.is_empty() else name)
	text = ""
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_set_hover.bind(false))
	pressed.connect(func() -> void: SoundPlayer.play(&"ui_press"))
	visibility_changed.connect(_on_visibility_changed)
	get_window().focus_exited.connect(_reset_visuals)
	set_process(false)

func _on_mouse_entered() -> void:
	if not disabled and not SceneTransition.busy and _icon.is_visible_in_tree():
		_set_hover(true)

func _set_hover(active: bool) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_method(
		_set_hover_scale, _hover_scale, hover_scale if active else 1.0, hover_duration
	)
	var angle: float = deg_to_rad(hover_rotation_degrees)
	_hover_tween.tween_method(
		_set_hover_rotation, _hover_rotation, randf_range(-angle, angle) if active else 0.0, hover_duration
	)

## 只缩放视觉节点，Container 布局、按钮命中范围和 Sprite 原点均保持不变。
func set_presented(presented: bool, instant: bool = false) -> void:
	if _presentation_tween != null and _presentation_tween.is_valid():
		_presentation_tween.kill()
	disabled = _base_disabled or not presented
	if not presented:
		release_focus()
		if instant:
			_reset_visuals()
		else:
			stop_hold()
			_set_hover(false)
	var target: float = 1.0 if presented else 0.0
	if instant:
		_set_presentation_scale(target)
		return
	_presentation_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_presentation_tween.tween_method(
		_set_presentation_scale, _presentation_scale, target,
		appear_duration if presented else disappear_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT if presented else Tween.EASE_IN)

func _set_hover_scale(value: float) -> void:
	_hover_scale = value
	_update_scale()

func _set_presentation_scale(value: float) -> void:
	_presentation_scale = value
	_update_scale()

func _update_scale() -> void:
	## 两种 Tween 独立控制倍率，避免同时写入 scale 导致跳变或累计缩放。
	_icon.scale = _base_scale * _hover_scale * _presentation_scale
	if _label != null:
		_label.scale = _label_base_scale * _hover_scale * _presentation_scale
		_label.visible = not is_zero_approx(_presentation_scale)

func _sync_label_pivot() -> void:
	_label.pivot_offset = _label.size * 0.5

## 供响应式布局更新视觉原点；后续抖动与复位仍使用新的布局位置。
func set_icon_position(value: Vector2) -> void:
	_base_position = value
	_icon.position = value

func _set_hover_rotation(value: float) -> void:
	_hover_rotation = value
	_update_rotation()

func _update_rotation() -> void:
	## 悬停倾斜与长按抖动独立叠加，避免 Tween 和逐帧更新争抢同一个属性。
	_icon.rotation = _base_rotation + _hover_rotation + _shake_rotation
	if _label != null:
		_label.rotation = _label_base_rotation + _hover_rotation + _shake_rotation
		_label.position = _label_base_position + _icon.position - _base_position

func start_hold(timer: Timer) -> void:
	stop_hold()
	_hold_timer = timer
	set_process(true)
	queue_redraw()

func stop_hold() -> void:
	_hold_timer = null
	_hold_progress = 0.0
	_shake_time = 0.0
	_shake_rotation = 0.0
	_icon.position = _base_position
	_update_rotation()
	set_process(false)
	queue_redraw()

func _process(delta: float) -> void:
	if not is_instance_valid(_hold_timer) or not is_visible_in_tree() or disabled or SceneTransition.busy:
		stop_hold()
		return
	_hold_progress = clampf(1.0 - _hold_timer.time_left / _hold_timer.wait_time, 0.0, 1.0)
	_shake_time += delta
	var strength: float = lerpf(0.15, 1.0, _hold_progress)
	_icon.position = _base_position + Vector2(
		sin(_shake_time * 64.0), sin(_shake_time * 51.0) * 0.65
	) * hold_shake_amplitude * strength
	_shake_rotation = sin(_shake_time * 73.0) * deg_to_rad(hold_shake_rotation_degrees) * strength
	_update_rotation()
	queue_redraw()

func _draw() -> void:
	if not show_hold_progress or not is_instance_valid(_hold_timer):
		return
	var icon_size := _icon_size * _base_scale.abs() * hover_scale
	var radius: float = maxf(maxf(icon_size.x, icon_size.y), maxf(size.x, size.y)) * 0.5 + ring_padding
	if _hold_progress > 0.0:
		draw_arc(_base_position, radius, -PI * 0.5, -PI * 0.5 + TAU * _hold_progress,
			maxi(2, ceili(128.0 * _hold_progress)), progress_color, 5.0, true)

func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		_reset_visuals()

func _reset_visuals() -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_set_hover_scale(1.0)
	_hover_rotation = 0.0
	stop_hold()
