extends AnimatedSprite2D
## AI 生成手绘风图集的播放器；AtlasTexture 只裁取原图，不重绘人物。
## 所有帧共享足底根锚，物理帧只消费真实位移，围巾独立连续求解。

const FRAMES_PATH := "res://Art/Player/V4/Traveler_V4_Frames.tres"
const METADATA_PATH := "res://Art/Player/V4/Traveler_V4_Metadata.json"

@export var walk_stride: float = 108.0
@export var run_stride: float = 152.0
@onready var player: PlayerController = get_parent().get_parent() as PlayerController
var visual_facing: int = 1
var collar_offset := Vector2(-4.0, -73.0)
var stride_phase: float = 0.0
var measured_distance: float = 0.0
var _clock: float = 0.0
var _previous_position := Vector2.ZERO
var _previous_speed: float = 0.0
var _previous_grounded: bool = false
var _transition: StringName = &""
var _transition_left: float = 0.0
var _transition_duration: float = 0.0
var _metadata: Dictionary = {}
var _art_ready: bool = false


func _ready() -> void:
	process_physics_priority = 1
	_previous_position = player.global_position
	stop()
	if not ResourceLoader.exists(FRAMES_PATH) or not FileAccess.file_exists(METADATA_PATH):
		push_warning("TRAVELER_V4: 位图帧与锚点尚未导入。")
		return
	sprite_frames = load(FRAMES_PATH)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(METADATA_PATH))
	if not parsed is Dictionary:
		push_error("TRAVELER_V4: 锚点元数据无效。")
		return
	_metadata = parsed
	var art_scale: float = float(_metadata.get("scale", 0.25))
	scale = Vector2.ONE * art_scale
	var canvas: Array = _metadata.get("canvas", [512, 640])
	var pivot: Array = _metadata.get("canvas_pivot", [256, 580])
	position = (Vector2(canvas[0], canvas[1]) * 0.5 - Vector2(pivot[0], pivot[1])) * art_scale
	walk_stride = float(_metadata.get("walk_stride", walk_stride))
	run_stride = float(_metadata.get("run_stride", run_stride))
	_art_ready = true
	_apply_pose(&"idle", 0.0)


func _begin(action: StringName, duration: float) -> void:
	_transition = action
	_transition_left = duration
	_transition_duration = duration


func _physics_process(delta: float) -> void:
	if not _art_ready or not is_instance_valid(player) or player.UAV_activated:
		return
	_clock += delta
	var displacement := player.global_position - _previous_position
	var teleported: bool = displacement.length() > 100.0
	var grounded: bool = player.is_on_floor()
	var speed: float = absf(player.velocity.x)
	measured_distance = 0.0 if teleported else absf(displacement.x)
	if teleported:
		_transition_left = 0.0
		_previous_grounded = grounded
		_previous_speed = speed
	var new_facing := visual_facing
	if speed > 12.0:
		new_facing = int(signf(player.velocity.x))
	elif speed < 3.0:
		new_facing = player.facing_direction
	if not _previous_grounded and grounded:
		_begin(&"land", 0.09)
	elif grounded and new_facing != visual_facing:
		_begin(&"brake", 0.07)
	elif grounded and _previous_speed > 90.0 and speed < _previous_speed - 20.0 and _transition_left <= 0.0:
		_begin(&"brake", 0.07)
	visual_facing = new_facing
	flip_h = visual_facing < 0
	_transition_left = maxf(0.0, _transition_left - delta)
	var action: StringName = &"idle"
	var phase: float = 0.0
	if player.dash_active:
		action = &"run"
		stride_phase = fposmod(stride_phase + measured_distance / run_stride, 1.0)
		phase = stride_phase
	elif not grounded:
		action = &"rise" if player.velocity.y < -55.0 else (&"apex" if player.velocity.y < 100.0 else &"fall")
	elif _transition_left > 0.0:
		action = _transition
		phase = 1.0 - _transition_left / _transition_duration
	elif measured_distance > 0.02:
		action = &"run" if player.is_running or speed > 230.0 else &"walk"
		stride_phase = fposmod(stride_phase + measured_distance / (run_stride if action == &"run" else walk_stride), 1.0)
		phase = stride_phase
	else:
		phase = fposmod(_clock * 0.5, 1.0)
	_apply_pose(action, phase)
	_previous_grounded = grounded
	_previous_speed = speed
	_previous_position = player.global_position


func _apply_pose(action: StringName, phase: float) -> void:
	if not sprite_frames.has_animation(action):
		action = &"idle"
	animation = action
	var count := sprite_frames.get_frame_count(action)
	var frame_position: float = clampf(phase, 0.0, 0.99999) * count
	set_frame_and_progress(mini(int(frame_position), count - 1), fposmod(frame_position, 1.0))
	var animation_meta: Array = _metadata.get("animations", {}).get(str(action), [])
	if frame < animation_meta.size():
		var collar: Array = animation_meta[frame].get("collar", [-4.0, -73.0])
		collar_offset = Vector2(float(collar[0]) * visual_facing, float(collar[1]))


func get_metadata() -> Dictionary:
	return _metadata.duplicate(true)
