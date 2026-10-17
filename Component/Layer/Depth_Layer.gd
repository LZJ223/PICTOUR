## 此脚本挂载在Layer节点上，负责管理图层槽位，调用子物件进行视觉更新

class_name DepthLayer
extends CanvasGroup

signal cycle_finished

const Z_INDEX_STEP: int = 100
const HAZE_Z_OFFSET: int = 1
const HAZE_VIEWPORT_MARGIN: float = 2.0
## 仅图层最终合成接收夜间照明，子物体不再重复受光。
const NIGHT_LIGHT_MASK: int = 1 << 16

## 图层信息
@export var layer_id: int = 0
@export var slot: int = 1

@export_group("轮换受阻反馈")
@export_range(0.0, 32.0, 0.5) var blocked_shake_amplitude: float = 8.0
@export_range(0.01, 0.5, 0.01) var blocked_shake_duration: float = 0.20

@onready var haze_plane: Polygon2D = $HazePlane
var visual_scale: float = 1.0
var cycle_opacity: float = 1.0
var blocked_shake_offset: Vector2 = Vector2.ZERO
var _filter_material: ShaderMaterial
var _haze_material: ShaderMaterial
var _cycle_tween: Tween
var _blocked_shake_tween: Tween
var _draw_order_update_queued: bool = false
var _level: Level
var _anchor_position: Vector2
var _camera_zoom: Vector2 = Vector2.ONE
var _has_view: bool = false

## 初始化
func _ready() -> void:
	add_to_group("depth_layers")
	visibility_layer = (visibility_layer & ~LayerObject.RECEIVER_MASK_BITS) | LayerObject.receiver_mask_bit(layer_id)
	_level = get_parent() as Level
	assert(_level != null, "DepthLayer 必须直接位于 Level 下")
	_filter_material = material as ShaderMaterial
	light_mask = NIGHT_LIGHT_MASK
	_haze_material = haze_plane.material as ShaderMaterial
	assert(_filter_material != null, "DepthLayer 需要使用图层滤镜 ShaderMaterial")
	assert(_haze_material != null, "DepthLayer 需要使用雾效 ShaderMaterial")
	_filter_material.set_shader_parameter("is_night", _level.is_night)
	_haze_material.set_shader_parameter("layer_id", float(layer_id))
	_haze_material.set_shader_parameter("is_night", _level.is_night)

## 更新位置
func apply_slot_state(anchor_position: Vector2, camera_zoom: Vector2) -> void:
	_anchor_position = anchor_position
	_camera_zoom = camera_zoom
	_has_view = true
	_update_haze(anchor_position, camera_zoom)
	for child in get_children():
		if child is LayerObject:
			child.apply_visual_transfer(anchor_position, camera_zoom)

## 槽位负责逻辑状态；浮点视觉槽位同时驱动排序、视差与两份着色器。
func _apply_visual_slot(visual_slot: float) -> void:
	var depth_z_index: float = (_level.current_layer_index - visual_slot) * Z_INDEX_STEP
	var outside: float = maxf(-visual_slot, visual_slot - (_level.layer_count - 1))
	cycle_opacity = 1.0 - clampf(outside * 2.0, 0.0, 1.0)
	visual_scale = pow(_level.layer_scale, visual_slot - _level.current_layer_index)
	z_index = roundi(depth_z_index)
	use_mipmaps = _cycle_tween != null or z_index != 0
	_filter_material.set_shader_parameter("layer_z_index", depth_z_index)
	_filter_material.set_shader_parameter("cycle_opacity", cycle_opacity)
	haze_plane.z_index = z_index + HAZE_Z_OFFSET
	haze_plane.visible = depth_z_index < 0.0 and cycle_opacity > 0.0
	_haze_material.set_shader_parameter("layer_z_index", depth_z_index)
	_haze_material.set_shader_parameter("cycle_opacity", cycle_opacity)
	## Tween 在 _process 后推进，立即刷新物件以免视差落后一帧。
	if _has_view:
		apply_slot_state(_anchor_position, _camera_zoom)

## 三次位移曲线产生抛物线形速度：起止缓慢，中点最快且恰好透明跨界。
func _set_cycle_phase(progress: float, previous_slot: int, direction: int) -> void:
	var phase: float = progress * progress * (3.0 - 2.0 * progress)
	var visual_slot: float = fposmod(
		previous_slot + direction * phase + 0.5, _level.layer_count
	) - 0.5
	_apply_visual_slot(visual_slot)

func play_cycle(direction: int, duration: float) -> void:
	cancel_cycle()
	var previous_slot: int = posmod(slot - direction, _level.layer_count)
	_cycle_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_cycle_tween.set_trans(Tween.TRANS_LINEAR)
	_set_cycle_phase(0.0, previous_slot, direction)
	_cycle_tween.tween_method(
		_set_cycle_phase.bind(previous_slot, direction), 0.0, 0.5, duration * 0.5
	)
	_cycle_tween.tween_callback(_set_cycle_phase.bind(0.5, previous_slot, direction))
	_cycle_tween.tween_method(
		_set_cycle_phase.bind(previous_slot, direction), 0.5, 1.0, duration * 0.5
	)
	_cycle_tween.finished.connect(_on_cycle_finished)

func cancel_cycle() -> void:
	if _cycle_tween != null and _cycle_tween.is_valid():
		_cycle_tween.kill()
	_cycle_tween = null
	_stop_blocked_shake()
	_apply_visual_slot(float(slot))

func _on_cycle_finished() -> void:
	_cycle_tween = null
	_apply_visual_slot(float(slot))
	cycle_finished.emit()

## 只移动可见内容；重复受阻时重新从静止状态播放。
func play_cycle_blocked() -> void:
	_stop_blocked_shake()
	if blocked_shake_amplitude <= 0.0:
		return
	_blocked_shake_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	var previous_offset := Vector2.ZERO
	for amount in [1.0, -0.8, 0.55, -0.3, 0.0]:
		var next_offset := Vector2(blocked_shake_amplitude * amount, 0.0)
		_blocked_shake_tween.tween_method(
			_set_blocked_shake_offset,
			previous_offset,
			next_offset,
			blocked_shake_duration / 5.0
		).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		previous_offset = next_offset
	_blocked_shake_tween.finished.connect(_on_blocked_shake_finished)

func _set_blocked_shake_offset(offset: Vector2) -> void:
	blocked_shake_offset = offset
	if _has_view:
		apply_slot_state(_anchor_position, _camera_zoom)

func _stop_blocked_shake() -> void:
	if _blocked_shake_tween != null and _blocked_shake_tween.is_valid():
		_blocked_shake_tween.kill()
	_blocked_shake_tween = null
	_set_blocked_shake_offset(Vector2.ZERO)

func _on_blocked_shake_finished() -> void:
	_blocked_shake_tween = null
	_set_blocked_shake_offset(Vector2.ZERO)

## 雾平面独立覆盖整个视口，并在物理世界坐标中跟随所属图层产生透视视差。
func _update_haze(anchor_position: Vector2, camera_zoom: Vector2) -> void:
	_haze_material.set_shader_parameter("anchor_position", anchor_position)
	_haze_material.set_shader_parameter("layer_scale", _level.layer_scale)
	_haze_material.set_shader_parameter(
		"visual_offset",
		Vector2(
			blocked_shake_offset.x / maxf(camera_zoom.x, 0.0001),
			blocked_shake_offset.y / maxf(camera_zoom.y, 0.0001)
		)
	)
	var screen_to_world := get_canvas_transform().affine_inverse()
	var viewport_size := get_viewport_rect().size
	var margin := Vector2.ONE * HAZE_VIEWPORT_MARGIN
	haze_plane.polygon = PackedVector2Array([
		screen_to_world * -margin,
		screen_to_world * Vector2(viewport_size.x + margin.x, -margin.y),
		screen_to_world * (viewport_size + margin),
		screen_to_world * Vector2(-margin.x, viewport_size.y + margin.y),
	])

## 保持所有物体与 CanvasGroup 同 Z，仅用同 Z 下的兄弟顺序区分普通与前置物体。
func update_object_draw_order() -> void:
	if is_node_ready():
		_sort_layer_objects()
	elif not _draw_order_update_queued:
		_draw_order_update_queued = true
		_sort_layer_objects.call_deferred()

func _sort_layer_objects() -> void:
	_draw_order_update_queued = false
	for child in get_children():
		if child is LayerObject and not child.front:
			move_child(child, get_child_count() - 1)
	for child in get_children():
		if child is LayerObject and child.front:
			move_child(child, get_child_count() - 1)
