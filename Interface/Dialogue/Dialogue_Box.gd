## 三种对话框共享动画，布局、字体和纹理由各自场景配置。
class_name DialogueBox
extends Control

signal presentation_finished
signal dismissed

@export_range(0.01, 1.0, 0.01) var enter_duration: float = 0.18
@export_range(0.01, 1.0, 0.01) var exit_duration: float = 0.12
@export_range(1.0, 120.0, 1.0) var characters_per_second: float = 30.0
@export var design_size := Vector2(1920, 1080)

@onready var _visual: Control = $VisualRoot
@onready var _text: RichTextLabel = $VisualRoot/Text
var _base_scale: Vector2
var _visual_scale: Vector2
var _tween: Tween

func _ready() -> void:
	_base_scale = scale
	_visual_scale = _visual.scale
	pivot_offset = size * 0.5
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	hide()

func _update_layout() -> void:
	var ratio := get_viewport_rect().size / design_size
	scale = _base_scale * minf(ratio.x, ratio.y)

func show_line(text: String) -> void:
	_stop_tween()
	_text.text = text
	_text.visible_characters = 0
	_visual.scale = _visual_scale * 0.15
	_visual.modulate.a = 0.0
	show()
	_tween = create_tween()
	_tween.tween_property(_visual, "scale", _visual_scale, enter_duration).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(_visual, "modulate:a", 1.0, enter_duration)
	_tween.tween_property(_text, "visible_characters", _text.get_total_character_count(),
		_text.get_total_character_count() / characters_per_second)
	_tween.tween_callback(_finish_presentation)

func complete_presentation() -> void:
	_stop_tween()
	_finish_presentation()

func _finish_presentation() -> void:
	_visual.scale = _visual_scale
	_visual.modulate.a = 1.0
	_text.visible_characters = -1
	presentation_finished.emit()

func dismiss() -> void:
	_stop_tween()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_visual, "scale", _visual_scale * 0.15, exit_duration)
	_tween.tween_property(_visual, "modulate:a", 0.0, exit_duration)
	_tween.chain().tween_callback(_finish_dismissal)

func complete_dismissal() -> void:
	_stop_tween()
	_finish_dismissal()

func _finish_dismissal() -> void:
	hide()
	dismissed.emit()

func _stop_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
