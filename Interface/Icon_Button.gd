## 仅修饰 Icon，不改变按钮命中范围；长按进度复用调用者的实际计时器。
extends Button

@export_range(1.0, 1.3, 0.01) var hover_scale: float = 1.08
@export_range(0.01, 0.5, 0.01) var hover_duration: float = 0.06
@export_range(0.0, 10.0, 0.5) var hover_rotation_degrees: float = 6.0
@export_range(0.0, 5.0, 0.1) var hold_shake_amplitude: float = 1.2
@export_range(0.0, 10.0, 0.5) var hold_shake_rotation_degrees: float = 3.0
@export var progress_color: Color = Color(0.08, 0.68, 0.29)
@export_range(0.0, 20.0, 1.0) var ring_padding: float = 6.0

@onready var _icon: Sprite2D = $Icon
@onready var _base_scale: Vector2 = _icon.scale
@onready var _base_position: Vector2 = _icon.position
@onready var _base_rotation: float = _icon.rotation
var _hover_tween: Tween
var _hold_timer: Timer
var _hold_progress: float = 0.0
var _shake_time: float = 0.0
var _icon_size: Vector2
var _hover_rotation: float = 0.0
var _shake_rotation: float = 0.0

func _ready() -> void:
	_icon_size = _icon.get_rect().size
	## PNG 的透明留白不应扩大进度环；图像边界只在初始化时计算一次。
	if _icon.texture != null:
		var image := _icon.texture.get_image()
		if image != null:
			if image.is_compressed():
				image.decompress()
			_icon_size = Vector2(image.get_used_rect().size)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)
	if tooltip_text.is_empty():
		tooltip_text = text if not text.is_empty() else name
	text = ""
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_set_hover.bind(false))
	visibility_changed.connect(_on_visibility_changed)
	get_window().focus_exited.connect(_reset_visuals)
	set_process(false)

func _on_mouse_entered() -> void:
	if not disabled and not SceneTransition.busy:
		_set_hover(true)

func _set_hover(active: bool) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(
		_icon, "scale", _base_scale * (hover_scale if active else 1.0), hover_duration
	)
	var angle: float = deg_to_rad(hover_rotation_degrees)
	_hover_tween.tween_method(
		_set_hover_rotation, _hover_rotation, randf_range(-angle, angle) if active else 0.0, hover_duration
	)

func _set_hover_rotation(value: float) -> void:
	_hover_rotation = value
	_update_rotation()

func _update_rotation() -> void:
	## 悬停倾斜与长按抖动独立叠加，避免 Tween 和逐帧更新争抢同一个属性。
	_icon.rotation = _base_rotation + _hover_rotation + _shake_rotation

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
	if not is_instance_valid(_hold_timer):
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
	_icon.scale = _base_scale
	_hover_rotation = 0.0
	stop_hold()
