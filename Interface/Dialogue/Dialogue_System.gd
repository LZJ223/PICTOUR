## Game 所有的开场演出；不持有跨场景节点，也不暂停整个游戏。
class_name DialogueSystem
extends Node2D

const DialogueLine = preload("res://Interface/Dialogue/Dialogue_Line.gd")
const DialogueBox = preload("res://Interface/Dialogue/Dialogue_Box.gd")

signal finished

enum State { IDLE, CAMERA_IN, SPIRIT_IN, PRESENTING, WAITING, BOX_OUT, FINISHING }

@export var spirit_offset := Vector2(85, -135)
@export_range(0.05, 1.0, 0.01) var spirit_duration: float = 0.28
@export var spirit_float_amplitude: float = 4.0
@export var spirit_float_period: float = 1.6

@onready var _boxes: Array[DialogueBox] = [
	$DialogueUI/Screen/Voiceover, $DialogueUI/Screen/BookSpirit, $DialogueUI/Screen/Player,
]
@onready var _spirit: Node2D = $BookSpirit
@onready var _spirit_visual: Node2D = $BookSpirit/VisualRoot
@onready var _smoke: CPUParticles2D = $BookSpirit/SmokeParticles
var _lines: Array[DialogueLine] = []
var _controller: LayerControllerSystem
var _state: State = State.IDLE
var _index: int = 0
var _box: DialogueBox
var _spirit_shown: bool = false
var _float_time: float = 0.0
var _spirit_tween: Tween
var _finish_tween: Tween

func _ready() -> void:
	_spirit.hide()
	for box in _boxes:
		box.presentation_finished.connect(_on_presented)
		box.dismissed.connect(_on_dismissed)
	SignalSystem.dialogue_advance.connect(advance)

func start(lines: Array[DialogueLine], controller: LayerControllerSystem) -> void:
	if _state != State.IDLE:
		return
	## 过滤空资源槽位，但不改动关卡保存的原始数组。
	_lines.clear()
	for line in lines:
		if line != null:
			_lines.append(line)
	if _lines.is_empty():
		_finish()
		return
	_controller = controller
	_index = 0
	_float_time = 0.0
	_state = State.CAMERA_IN
	SignalSystem.set_dialogue_active(true)
	_controller.set_dialogue_view(true).finished.connect(_show_current)

func _process(delta: float) -> void:
	if not _spirit_shown:
		return
	_spirit.global_position = Global.player.global_position + spirit_offset
	if _state != State.SPIRIT_IN and _state != State.FINISHING:
		_float_time += delta
		_spirit_visual.position.y = sin(_float_time * TAU / maxf(spirit_float_period, 0.01)) * spirit_float_amplitude

func advance() -> void:
	if get_tree().paused or SceneTransition.busy or _state == State.IDLE:
		return
	SoundPlayer.play(&"ui_press")
	match _state:
		State.CAMERA_IN:
			_controller.complete_dialogue_view(true)
			_show_current()
			_complete_current()
		State.SPIRIT_IN:
			_complete_current()
		State.PRESENTING:
			_box.complete_presentation()
		State.WAITING:
			SoundPlayer.stop(&"dialogue")
			_state = State.BOX_OUT
			_box.dismiss()
		State.BOX_OUT:
			_box.complete_dismissal()
		State.FINISHING:
			_finish_tween.kill()
			_stop_spirit_tween()
			_controller.complete_dialogue_view(false)
			_finish()

func _complete_current() -> void:
	if _state == State.SPIRIT_IN:
		_stop_spirit_tween()
		_spirit_visual.position = Vector2.ZERO
		_spirit_visual.scale = Vector2.ONE
		_spirit_visual.modulate.a = 1.0
		_present_current()
	if _state == State.PRESENTING:
		_box.complete_presentation()

func _show_current() -> void:
	if _index >= _lines.size():
		_end_dialogue()
		return
	if _lines[_index].speaker == DialogueLine.Speaker.BOOK_SPIRIT and not _spirit_shown:
		_state = State.SPIRIT_IN
		_spirit_shown = true
		_spirit.global_position = Global.player.global_position + spirit_offset
		_spirit.show()
		_play_spirit(true)
		_spirit_tween.finished.connect(_present_current)
	else:
		_present_current()

func _present_current() -> void:
	_state = State.PRESENTING
	var line := _lines[_index]
	SoundPlayer.play_dialogue(line.speaker)
	_box = _boxes[line.speaker]
	_box.show_line(line.text)

func _on_presented() -> void:
	_state = State.WAITING

func _on_dismissed() -> void:
	_index += 1
	_show_current()

func _play_spirit(appearing: bool) -> void:
	_stop_spirit_tween()
	_smoke.restart()
	_smoke.emitting = true
	if appearing:
		_spirit_visual.position = Vector2(0, 35)
		_spirit_visual.scale = Vector2.ONE * 0.2
		_spirit_visual.modulate.a = 0.0
	_spirit_tween = create_tween().set_parallel(true)
	_spirit_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_spirit_tween.tween_property(_spirit_visual, "position:y", 0.0 if appearing else -30.0, spirit_duration)
	_spirit_tween.tween_property(_spirit_visual, "scale", Vector2.ONE * (1.0 if appearing else 0.2), spirit_duration)
	_spirit_tween.tween_property(_spirit_visual, "modulate:a", 1.0 if appearing else 0.0, spirit_duration)

func _stop_spirit_tween() -> void:
	if _spirit_tween != null and _spirit_tween.is_valid():
		_spirit_tween.kill()
	_spirit_tween = null

func _end_dialogue() -> void:
	SoundPlayer.stop(&"dialogue")
	_state = State.FINISHING
	_controller.set_dialogue_view(false)
	var duration := _controller.dialogue_camera_duration
	if _spirit_shown:
		_play_spirit(false)
		duration = maxf(duration, maxf(spirit_duration, _smoke.lifetime))
	_finish_tween = create_tween()
	_finish_tween.tween_interval(duration)
	_finish_tween.tween_callback(_finish)

func _finish() -> void:
	SoundPlayer.stop(&"dialogue")
	_state = State.IDLE
	_spirit_shown = false
	_spirit.hide()
	_smoke.emitting = false
	SignalSystem.set_dialogue_active(false)
	finished.emit()
