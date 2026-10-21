## 分层 Logo 复用图标按钮的视觉反馈；贡献者面板独立于世界相机，背景持续运行。
extends "res://Interface/UI/Icon_Button.gd"

signal credits_started

@export_range(0.1, 10.0, 0.1) var hold_duration: float = 5.0
@export_range(0.0, 2.0, 0.05) var credits_appear_delay: float = 0.35
@export_range(0.1, 10.0, 0.1, "or_greater") var credits_stay_duration: float = 4.0
@export_range(0.1, 2.0, 0.05) var credits_slide_duration: float = 0.65

@onready var _overlay: Control = $Credits/Screen
@onready var _contributer: TextureRect = $Credits/Screen/Contributer

var playing: bool = false
var _available: bool = false
var _hold: Timer
var _sequence: Tween
var _credits_progress: float = 0.0

func _ready() -> void:
	super._ready()
	tooltip_text = ""
	_hold = Timer.new()
	_hold.one_shot = true
	add_child(_hold)
	_hold.timeout.connect(_show_credits)
	button_down.connect(_begin_hold)
	button_up.connect(_cancel_hold)
	mouse_exited.connect(_cancel_hold)
	get_window().focus_exited.connect(_cancel_hold)
	get_viewport().size_changed.connect(_update_credits_layout)
	SaveSystem.collection_changed.connect(_refresh_availability)
	_update_credits_layout()
	_refresh_availability()

func set_available(available: bool) -> void:
	_available = available
	_refresh_availability()

func _refresh_availability() -> void:
	disabled = not _available or playing or not SaveSystem.COLLECTION_CHARACTERS.all(SaveSystem.is_character_collected)
	if disabled:
		_cancel_hold()
		_reset_visuals()

func set_presented(presented: bool, instant: bool = false) -> void:
	super.set_presented(presented, instant)
	if presented:
		_refresh_availability()

func _begin_hold() -> void:
	if disabled or playing or SceneTransition.busy or not _icon.is_visible_in_tree():
		return
	_hold.start(hold_duration)
	start_hold(_hold)

func _cancel_hold() -> void:
	_hold.stop()
	stop_hold()

func _show_credits() -> void:
	if disabled or playing or SceneTransition.busy or not _icon.is_visible_in_tree():
		_cancel_hold()
		return
	playing = true
	_cancel_hold()
	## 先挡住菜单输入，再缩小 Logo；只改变视觉，不暂停动态背景。
	_overlay.show()
	credits_started.emit()
	set_presented(false)
	_sequence = create_tween()
	_sequence.tween_interval(disappear_duration)
	_sequence.tween_interval(credits_appear_delay)
	_sequence.tween_method(_set_credits_progress, 0.0, 1.0, credits_slide_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_sequence.tween_interval(credits_stay_duration)
	_sequence.tween_method(_set_credits_progress, 1.0, 0.0, credits_slide_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_sequence.tween_callback(set_presented.bind(true))
	_sequence.tween_interval(appear_duration)
	_sequence.tween_callback(_finish_credits)

func _finish_credits() -> void:
	_overlay.hide()
	playing = false
	_refresh_availability()

func _set_credits_progress(value: float) -> void:
	_credits_progress = value
	_update_credits_layout()

func _update_credits_layout() -> void:
	var view_size := get_viewport_rect().size
	var texture_size := Vector2(_contributer.texture.get_size())
	var fit_scale := minf(view_size.x * 0.41 / texture_size.x, view_size.y * 0.41 / texture_size.y)
	_contributer.size = texture_size * fit_scale
	var top := -_contributer.size.y - 32.0
	var target := view_size * Vector2(0.5, 0.25) - _contributer.size * 0.5
	_contributer.position = Vector2(target.x, lerpf(top, target.y, _credits_progress))
