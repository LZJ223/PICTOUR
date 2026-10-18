## 切割后仅保留消失区域的画面；局部纹理绘制一次，随后只衰减透明度。
class_name ShadowCutAfterimage
extends Node2D

const FADE_SHADER := preload("res://Shader/Shadow_Cut_Afterimage.gdshader")
const MAX_CAPTURE_SIZE: float = 1024.0

var owner_layer: DepthLayer
var front: bool = false
var _collision_scale: Vector2
var _visual: Node2D
var _fade_material: ShaderMaterial
var _duration: float
var _capture_visuals: Array[Node2D] = []
var _captures: Array[SubViewport] = []

static func create(source: LayerObject, fragments: Array[LayerObject], duration: float) -> ShadowCutAfterimage:
	if duration <= 0.0 or not source.is_visible_in_tree() or not source.visual_root.is_visible_in_tree():
		return null
	var image := ShadowCutAfterimage.new()
	image.name = "%s_Afterimage" % source.name
	image.owner_layer = source.owner_layer
	image.front = source.front
	image.transform = source.transform
	image._collision_scale = source.collision_box.scale
	image._duration = duration
	var old_visual := _copy_visual(source.visual_root)
	if old_visual == null:
		image.free()
		return null
	old_visual.transform = Transform2D.IDENTITY
	old_visual.modulate *= source.modulate
	var bounds := _visual_bounds(old_visual)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		old_visual.free()
		image.free()
		return null
	var screen := source.visual_root.get_global_transform_with_canvas()
	var density := Vector2(screen.x.length(), screen.y.length()).max(Vector2(0.01, 0.01))
	bounds = bounds.grow(2.0 / minf(density.x, density.y))
	var pixels := bounds.size * density
	pixels *= minf(1.0, MAX_CAPTURE_SIZE / maxf(pixels.x, pixels.y))
	var size := Vector2i(pixels.ceil()).max(Vector2i(2, 2))
	var old_capture := image._make_capture("OldAppearance", bounds, size)
	image.add_child(old_capture)
	old_capture.add_child(old_visual)
	image._capture_visuals.append(old_visual)
	var retained_capture := image._make_capture("RetainedAppearance", bounds, size)
	# 纹理依赖明确为 新碎片覆盖 → 旧外观 → 主视口，首帧即得到有效遮罩。
	old_capture.add_child(retained_capture)
	var retained := Node2D.new()
	retained_capture.add_child(retained)
	image._capture_visuals.append(retained)
	var inverse := source.visual_root.global_transform.affine_inverse()
	for fragment in fragments:
		var copy := _copy_visual(fragment.visual_root)
		if copy != null:
			copy.transform = inverse * fragment.visual_root.global_transform
			copy.modulate *= fragment.modulate
			retained.add_child(copy)
	image._visual = Node2D.new()
	image._visual.transform = source.visual_root.transform
	image.add_child(image._visual)
	image._fade_material = ShaderMaterial.new()
	image._fade_material.shader = FADE_SHADER
	image._fade_material.set_shader_parameter("retained_appearance", retained_capture.get_texture())
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.position = bounds.position
	sprite.scale = bounds.size / Vector2(size)
	sprite.texture = old_capture.get_texture()
	sprite.material = image._fade_material
	image._visual.add_child(sprite)
	return image

func _ready() -> void:
	# 不参与承影覆盖、角色遮挡、点选或物理；只在所属图层的主画面中绘制。
	visibility_layer = 1
	RenderingServer.frame_post_draw.connect(_start_fade, CONNECT_ONE_SHOT)

func _start_fade() -> void:
	for capture in _captures:
		capture.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_captures.clear()
	for visual in _capture_visuals:
		visual.queue_free()
	_capture_visuals.clear()
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tween.tween_method(_set_progress, 0.0, 1.0, _duration)
	tween.tween_callback(queue_free)

func _set_progress(progress: float) -> void:
	_fade_material.set_shader_parameter("progress", progress)

func apply_visual_transfer(anchor_position: Vector2, camera_zoom: Vector2) -> void:
	var scaling: float = owner_layer.visual_scale
	var pixels: Vector2 = owner_layer.blocked_shake_offset
	var world_offset := Vector2(pixels.x / maxf(camera_zoom.x, 0.0001), pixels.y / maxf(camera_zoom.y, 0.0001))
	_visual.scale = _collision_scale * scaling
	_visual.position = to_local(anchor_position) * (1.0 - scaling) + global_transform.affine_inverse().basis_xform(world_offset)

func _make_capture(capture_name: String, bounds: Rect2, size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = capture_name
	viewport.world_2d = World2D.new()
	viewport.size = size
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var density := Vector2(size) / bounds.size
	var canvas := Transform2D(Vector2(density.x, 0), Vector2(0, density.y), -bounds.position * density)
	viewport.ready.connect(func(): viewport.canvas_transform = canvas, CONNECT_ONE_SHOT)
	_captures.append(viewport)
	return viewport

## 复制可绘制节点及其材质参数，剔除脚本、信号、Area2D 和选择反馈。
static func _copy_visual(source: Node2D) -> Node2D:
	if source.get_meta(&"selection_outline_visual", false):
		return null
	if not (source is Polygon2D or source is Line2D or source is Sprite2D or source.get_class() == "Node2D"):
		return null
	var copy := source.duplicate(0) as Node2D
	for child in copy.get_children():
		copy.remove_child(child)
		child.free()
	copy.visibility_layer = 1
	if source.material != null:
		copy.material = source.material.duplicate() as Material
	for child in source.get_children():
		if child is Node2D:
			var visual := _copy_visual(child)
			if visual != null:
				copy.add_child(visual)
	return copy

static func _visual_bounds(node: Node2D, parent_transform: Transform2D = Transform2D.IDENTITY) -> Rect2:
	if not node.visible:
		return Rect2()
	var transform := parent_transform * node.transform
	var points := PackedVector2Array()
	var margin: float = 0.0
	if node is Polygon2D:
		for point in node.polygon:
			points.append(transform * (point + node.offset))
	elif node is Line2D:
		points = transform * node.points
		var curve_scale: float = node.width_curve.max_value if node.width_curve != null else 1.0
		margin = node.width * curve_scale * maxf(node.sharp_limit, 2.0) * maxf(transform.x.length(), transform.y.length())
	elif node is Sprite2D:
		var rect: Rect2 = node.get_rect()
		points = transform * PackedVector2Array([rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)])
	var bounds := Rect2()
	if not points.is_empty():
		bounds = Rect2(points[0], Vector2.ZERO)
		for point in points:
			bounds = bounds.expand(point)
		bounds = bounds.grow(margin)
	for child in node.get_children():
		if child is Node2D:
			var child_bounds := _visual_bounds(child, transform)
			if child_bounds.has_area():
				bounds = bounds.merge(child_bounds) if bounds.has_area() else child_bounds
	return bounds
