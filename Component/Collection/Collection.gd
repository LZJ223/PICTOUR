## 拖入 DepthLayer 的字母收集物；实体不碰撞，拾取区域随景深和浮动动画移动。
@tool
class_name LetterCollectible
extends LayerObject

enum State { IDLE, COLLECTING, DISABLED }

const TEXTURES := {
	"P": preload("res://Texture/Logo/Collection_P.png"),
	"I": preload("res://Texture/Logo/Collection_I.png"),
	"C": preload("res://Texture/Logo/Collection_C.png"),
	"T": preload("res://Texture/Logo/Collection_T.png"),
	"O": preload("res://Texture/Logo/Collection_O.png"),
	"U": preload("res://Texture/Logo/Collection_U.png"),
	"R": preload("res://Texture/Logo/Collection_R.png"),
}

@export_group("收集物")
@export_enum("P", "I", "C", "T", "O", "U", "R") var character: String = "P":
	set(value):
		character = value.to_upper()
		_sync_texture()
		if is_node_ready() and not Engine.is_editor_hint() and _state != State.COLLECTING:
			_sync_saved_state()

@export_group("待机动画")
@export_range(0.0, 32.0, 0.5) var float_amplitude: float = 8.0
@export_range(0.2, 5.0, 0.1) var float_period: float = 1.8
@export_range(0.0, 30.0, 0.5) var idle_rotation_degrees: float = 7.0

@export_group("收集动画")
@export_range(0.0, 64.0, 1.0) var sink_distance: float = 16.0
@export_range(0.01, 1.0, 0.01) var sink_duration: float = 0.12
@export_range(1.0, 240.0, 1.0) var rise_distance: float = 100.0
@export_range(0.05, 2.0, 0.01) var rise_duration: float = 0.48

@onready var _motion: Node2D = $VisualRoot/Motion
@onready var _area: Area2D = $VisualRoot/Motion/Area2D
@onready var _area_shape: CollisionShape2D = $VisualRoot/Motion/Area2D/CollisionShape2D
var _state: State = State.IDLE
var _motion_origin := Vector2.ZERO
var _idle_time: float = 0.0
var _rotation_tween: Tween
var _collection_tween: Tween
var _pickup_character: String

func _init() -> void:
	can_transfer = false
	can_leave_shadow = false
	can_be_shadowed = false
	front = true

func _ready() -> void:
	_sync_texture()
	if Engine.is_editor_hint():
		set_process(false)
		set_physics_process(false)
		return
	can_transfer = false
	can_leave_shadow = false
	can_be_shadowed = false
	front = true
	input_pickable = false
	_motion_origin = _motion.position
	super._ready()
	_area.body_entered.connect(_on_body_entered)
	SaveSystem.collection_changed.connect(_sync_saved_state)
	_sync_saved_state()

func _sync_texture() -> void:
	var sprite := get_node_or_null("VisualRoot/Motion/Sprite") as Sprite2D
	if sprite != null:
		sprite.texture = TEXTURES.get(character)

# 无实体碰撞箱、点击区域或选择描边；仍复用基类的景深变换和层内排序。
func _setup_selection_outlines() -> void:
	pass

func set_pick_condition(_condition: bool = false) -> void:
	pass

func update_layer_slot() -> void:
	super.update_layer_slot()
	collision_layer = 0
	collision_mask = 0
	_area.collision_layer = 0
	_area.collision_mask = 0 if _state == State.DISABLED else 1 << owner_layer.layer_id

func _sync_saved_state() -> void:
	if _state == State.COLLECTING:
		return
	if not TEXTURES.has(character) or SaveSystem.is_character_collected(character):
		_disable()
	elif _state == State.DISABLED or _rotation_tween == null:
		_activate()

func _activate() -> void:
	_state = State.IDLE
	process_mode = Node.PROCESS_MODE_INHERIT
	_motion.position = _motion_origin
	_motion.rotation = 0.0
	_motion.modulate.a = 1.0
	_idle_time = randf_range(0.0, float_period)
	show()
	set_process(true)
	set_physics_process(true)
	update_layer_slot()
	_area.set_deferred("monitoring", true)
	_area_shape.set_deferred("disabled", false)
	_start_rotation()

func _process(delta: float) -> void:
	if _state != State.IDLE:
		return
	_idle_time += delta
	_motion.position = _motion_origin + Vector2(0.0, sin(_idle_time * TAU / float_period) * float_amplitude)

func _start_rotation() -> void:
	if _state != State.IDLE:
		return
	_rotation_tween = create_tween()
	_rotation_tween.tween_property(_motion, "rotation", deg_to_rad(randf_range(-idle_rotation_degrees, idle_rotation_degrees)), randf_range(0.8, 1.5)
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_rotation_tween.tween_callback(_start_rotation)

# 已经重叠时换层、收回无人机或结束对话，也能重新判断玩家是否可以拾取。
func _physics_process(_delta: float) -> void:
	if _state != State.IDLE or not _can_collect(Global.player):
		return
	if _area.overlaps_body(Global.player):
		_on_body_entered(Global.player)

func _can_collect(body: Node2D) -> bool:
	return (
		is_instance_valid(body) and body == Global.player
		and Global.player.current_state == PlayerController.PlayerState.NORMAL
		and owner_layer.slot == Global.current_layer_index
		and body.get_collision_layer_value(owner_layer.layer_id + 1)
		and not SceneTransition.busy and not get_tree().paused
		and not SignalSystem.dialogue_active
		and (not is_instance_valid(Global.goal) or not Global.goal.completed)
	)

func _on_body_entered(body: Node2D) -> void:
	if _state != State.IDLE or not _can_collect(body):
		return
	_state = State.COLLECTING
	_pickup_character = character
	SoundPlayer.play(&"collection_triangle")
	set_process(false)
	set_physics_process(false)
	_area.set_deferred("monitoring", false)
	_area_shape.set_deferred("disabled", true)
	if _rotation_tween != null and _rotation_tween.is_valid():
		_rotation_tween.kill()
	_rotation_tween = null
	_collection_tween = create_tween()
	_collection_tween.tween_property(_motion, "position:y", _motion.position.y + sink_distance, sink_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_collection_tween.tween_property(_motion, "position:y", _motion_origin.y - rise_distance, rise_duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_collection_tween.parallel().tween_property(_motion, "modulate:a", 0.0, rise_duration)
	_collection_tween.tween_callback(_finish_collection)

func _finish_collection() -> void:
	_collection_tween = null
	if SaveSystem.collect_character(_pickup_character) == OK:
		_disable()
	else:
		# 落盘失败时恢复原物件，玩家仍可重试。
		_activate()

func _disable() -> void:
	_state = State.DISABLED
	if _rotation_tween != null and _rotation_tween.is_valid():
		_rotation_tween.kill()
	_rotation_tween = null
	_area.set_deferred("monitoring", false)
	_area_shape.set_deferred("disabled", true)
	_area.collision_layer = 0
	_area.collision_mask = 0
	collision_layer = 0
	collision_mask = 0
	hide()
	set_process(false)
	set_physics_process(false)
	process_mode = Node.PROCESS_MODE_DISABLED
