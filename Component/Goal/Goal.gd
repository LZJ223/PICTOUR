class_name LevelGoal
extends Area2D

@export_range(0.0, 64.0, 1.0) var float_amplitude: float = 8.0
@export_range(0.1, 5.0, 0.1) var float_period: float = 1.2
@export_range(0.05, 1.0, 0.01) var appear_duration: float = 0.18
@export_range(0.05, 1.0, 0.01) var disappear_duration: float = 0.12

@onready var _indicator: Sprite2D = $Goal
@onready var _indicator_position: Vector2 = _indicator.position
@onready var _indicator_scale: Vector2 = _indicator.scale
var completed: bool = false
var _float_tween: Tween
var _scale_tween: Tween

func _ready() -> void:
	var level := get_parent() as Level
	assert(level != null, "Goal 必须直接位于 Level 下")
	collision_mask = (1 << level.layer_count) - 1
	_indicator.hide()
	_indicator.scale = Vector2.ZERO
	body_entered.connect(_on_body_entered)
	SignalSystem.destination_view_changed.connect(_set_preview)

func _set_preview(active: bool) -> void:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	if not active and not _indicator.visible:
		return
	_scale_tween = create_tween()
	if active:
		_indicator.show()
		if _float_tween == null or not _float_tween.is_valid():
			_start_floating()
		_scale_tween.tween_property(
			_indicator, "scale", _indicator_scale, appear_duration
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_scale_tween.tween_property(
			_indicator, "scale", Vector2.ZERO, disappear_duration
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_scale_tween.tween_callback(_hide_indicator)

## 消失动画完成后才隐藏并复位，快速重新按住 Shift 时直接从当前大小接续。
func _hide_indicator() -> void:
	_indicator.hide()
	if _float_tween != null and _float_tween.is_valid():
		_float_tween.kill()
	_float_tween = null
	_indicator.position = _indicator_position

func _start_floating() -> void:
	_float_tween = create_tween().set_loops()
	_float_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_float_tween.tween_property(
		_indicator, "position:y", _indicator_position.y - float_amplitude, float_period * 0.5
	)
	_float_tween.tween_property(
		_indicator, "position:y", _indicator_position.y, float_period * 0.5
	)

func _on_body_entered(body: Node2D) -> void:
	if completed or SceneTransition.busy or SignalSystem.dialogue_active or body != Global.player:
		return
	if Global.player.current_state != PlayerController.PlayerState.NORMAL:
		return
	completed = true
	_complete_level.call_deferred()

func _complete_level() -> void:
	## 淡出期间继续结算演出，全黑后再统一替换整个 Game。
	var level := get_parent() as Level
	var error: Error
	if level.level_id < 12:
		error = await SceneTransition.enter_level(level.level_id + 1, true)
	else:
		error = await SceneTransition.enter_main_menu(true)
	if error != OK:
		completed = false
