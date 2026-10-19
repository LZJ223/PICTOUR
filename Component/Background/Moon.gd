## 初始位置使用关卡局部坐标；只更新位置，保留精灵本身的缩放。
extends Sprite2D

@export var initial_position: Vector2 = Vector2.ZERO
## 横向相对位移比例，越接近 0 表示越远。
@export_range(0.0, 1.0, 0.001) var parallax_ratio_x: float = 0.02
## 纵向相对位移比例，越接近 0 表示越远。
@export_range(0.0, 1.0, 0.001) var parallax_ratio_y: float = 0.02
## 中心到上下左右采样点的距离，使用精灵本地坐标，随月亮缩放。
@export_range(0.0, 512.0, 1.0, "or_greater") var sample_distance: float = 108.0

## 独立于承影位 9～12 和角色透视位 13～15，只在此节点存活时标记。
const OCCLUDER_BIT: int = 1 << 15
const QUERY_SHADER: String = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D coverage : repeat_disable, filter_nearest;
uniform vec2 sample_uv[5];
uniform float sample_valid[5];
void fragment() {
	int index = clamp(int(UV.x * 5.0), 0, 4);
	float alpha = textureLod(coverage, sample_uv[index], 0.0).a;
	float exposed = sample_valid[index] > 0.5 && alpha < 0.95 ? 1.0 : 0.0;
	COLOR = vec4(alpha, sample_valid[index], exposed, 1.0);
}
"""

var _player_origin: Vector2
var _has_player_origin: bool = false
var _is_exposed: bool = false
var _query_pending: bool = false
var _result: SubViewport
var _coverage: SubViewport
var _query_material: ShaderMaterial
var _marked: Dictionary[int, CanvasItem] = {}
var _held_expiry: bool = false
var _held_time_left: float = 0.0

func _ready() -> void:
	position = initial_position
	# Signal 的状态同步为 -100；在默认优先级的 Timer 扣时之前重置/暂存到期。
	process_priority = -50
	RenderingServer.frame_pre_draw.connect(_prepare_query)

func _process(delta: float) -> void:
	# 下一帧开始时读取已绘制的结果，让 GPU 有机会完成上一帧，减少同步等待。
	_read_query()
	if not is_instance_valid(Global.player):
		return
	var player_position: Vector2 = (get_parent() as Node2D).to_local(Global.player.global_position)
	if not _has_player_origin:
		_player_origin = player_position
		_has_player_origin = true
	position = initial_position + (player_position - _player_origin) * Vector2(1.0 - parallax_ratio_x, 1.0 - parallax_ratio_y)
	if not _can_check():
		_release_expiry(false)
		return
	if _is_exposed:
		SignalSystem.timer_reset()
	var timer: Timer = SignalSystem.timer
	# 最后一个计时帧暂存到下一次读取后结算，避免先切割、后发现月亮露出。
	if _query_pending and not timer.is_stopped() and not timer.paused and timer.time_left <= delta:
		_held_expiry = true
		_held_time_left = timer.time_left
		timer.paused = true

func _can_check() -> bool:
	return (
		is_inside_tree() and not get_tree().paused and not SceneTransition.busy
		and is_instance_valid(Global.level) and Global.level == get_parent()
		and is_instance_valid(Global.player) and is_instance_valid(Global.goal)
		and not Global.goal.completed and not SignalSystem.dialogue_active
		and not SignalSystem.looking_at_destination and SignalSystem.timer != null
		and is_visible_in_tree()
	)

func _create_query() -> void:
	_result = SubViewport.new()
	_result.name = "MoonVisibility"
	_result.world_2d = World2D.new()
	# SubViewport 的最小高度为 2，每列保存一个采样结果。
	_result.size = Vector2i(5, 2)
	_result.disable_3d = true
	_result.transparent_bg = true
	_result.gui_disable_input = true
	_result.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_result)
	_coverage = SubViewport.new()
	_coverage.name = "WorldCoverage"
	_coverage.world_2d = get_viewport().find_world_2d()
	_coverage.disable_3d = true
	_coverage.transparent_bg = true
	_coverage.gui_disable_input = true
	_coverage.canvas_cull_mask = OCCLUDER_BIT
	_coverage.msaa_2d = get_viewport().msaa_2d
	_coverage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_result.add_child(_coverage)
	var shader := Shader.new()
	shader.code = QUERY_SHADER
	_query_material = ShaderMaterial.new()
	_query_material.shader = shader
	_query_material.set_shader_parameter("coverage", _coverage.get_texture())
	var quad := ColorRect.new()
	quad.size = Vector2(5, 2)
	quad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quad.material = _query_material
	_result.add_child(quad)

func _prepare_query() -> void:
	_clear_marks()
	_query_pending = false
	if _result != null:
		_result.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_coverage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if not _can_check():
		_is_exposed = false
		_release_expiry(false)
		return
	var screen := get_viewport_rect()
	var transform := get_global_transform_with_canvas()
	var center := get_rect().get_center()
	var offsets := PackedVector2Array([Vector2.ZERO, Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT])
	var points := PackedVector2Array()
	var valid := PackedFloat32Array()
	var bounds := Rect2()
	var has_point: bool = false
	for offset in offsets:
		var point := transform * (center + offset * sample_distance)
		points.append(point)
		var on_screen := screen.has_point(point)
		valid.append(1.0 if on_screen else 0.0)
		if on_screen:
			bounds = bounds.expand(point) if has_point else Rect2(point, Vector2.ZERO)
			has_point = true
	if not has_point:
		_is_exposed = false
		_release_expiry(false)
		return
	if _result == null:
		_create_query()
	# 保留完整景深采样边缘，裁切后的像素密度与主画面相同。
	var margin := ceilf(pow(2.0, Renderer.maximum_blur_lod)) * 2.0 + 2.0
	bounds = bounds.grow(margin)
	var origin := bounds.position.floor()
	# 固定步长分配，避免相机的亚像素移动让纹理尺寸来回变化。
	var size := Vector2i(((bounds.size + Vector2(2, 2)) / 16.0).ceil() * 16.0)
	_coverage.size = size
	_coverage.canvas_transform = Transform2D(0.0, -origin) * get_viewport().get_canvas_transform()
	var uv := PackedVector2Array()
	for point in points:
		uv.append((point.floor() + Vector2(0.5, 0.5) - origin) / Vector2(size))
	_query_material.set_shader_parameter("sample_uv", uv)
	_query_material.set_shader_parameter("sample_valid", valid)
	_collect_occluders(Global.level)
	if Global.player.is_visible_in_tree():
		_mark_visual(Global.player.player_animation)
	_coverage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_result.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_query_pending = true

func _read_query() -> void:
	if not _query_pending or not _can_check():
		_release_expiry(false)
		return
	# 每帧只回读 5×2 的小纹理；实体覆盖和纹理 Alpha 均在 GPU 中合成。
	var result := _result.get_texture().get_image()
	if result == null or result.is_empty():
		_release_expiry(false)
		return
	_is_exposed = false
	for index in 5:
		if result.get_pixel(index, 0).b > 0.5:
			_is_exposed = true
			break
	_release_expiry(true)

func _release_expiry(resolve: bool) -> void:
	if not _held_expiry:
		return
	_held_expiry = false
	var timer: Timer = SignalSystem.timer
	timer.paused = false
	# 其他输入若已重置 timer，则本次暂存的到期也随之取消。
	if resolve and not _is_exposed and not timer.is_stopped() and timer.time_left <= _held_time_left:
		timer.stop()
		timer.timeout.emit()

## 遮挡只来自实际实体：排除背景画布、雾、投影和选择反馈，包含消失中的残影。
func _collect_occluders(node: Node) -> void:
	if node == self or node is Viewport or node is CanvasLayer:
		return
	if node is CanvasItem and not node.is_visible_in_tree():
		return
	if node is LayerObject:
		_mark_visual(node.visual_root)
		return
	if node is ShadowCutAfterimage:
		_mark_visual(node._visual)
		return
	if node is Polygon2D or node is Sprite2D or node is Line2D:
		_mark_visual(node)
		return
	for child in node.get_children():
		if node is DepthLayer and child == node.haze_plane:
			continue
		_collect_occluders(child)

func _mark_visual(node: CanvasItem) -> void:
	_mark_tree(node)
	var ancestor := node.get_parent()
	while ancestor != null and not ancestor is Viewport:
		if ancestor is CanvasItem:
			_mark(ancestor)
		ancestor = ancestor.get_parent()

func _mark_tree(node: Node) -> void:
	if node is Viewport or node.get_meta(&"selection_outline_visual", false):
		return
	if node is CanvasItem:
		_mark(node)
	for child in node.get_children():
		_mark_tree(child)

func _mark(item: CanvasItem) -> void:
	item.visibility_layer |= OCCLUDER_BIT
	_marked[item.get_instance_id()] = item

func _clear_marks() -> void:
	for item in _marked.values():
		if is_instance_valid(item):
			item.visibility_layer &= ~OCCLUDER_BIT
	_marked.clear()

func _exit_tree() -> void:
	RenderingServer.frame_pre_draw.disconnect(_prepare_query)
	_clear_marks()
	_release_expiry(false)
