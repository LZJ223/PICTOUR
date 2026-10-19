class_name ShadowedGeometry
extends LayerObject
const SHADOW_CLIP_SHADER := preload("res://Shader/Shadow_Receiver_Clip.gdshader")
@onready var shadow: Polygon2D = $Shadow

## 黑描边外缘仅在形状/样式改变时重建；白色选中线在屏幕坐标中保持等宽。
## 使用闭合线而非填满的放大多边形，保留凹口，避免把物体内部整块填白。
class SelectionContour extends Node2D:
	var _geometry_key: Array = []
	var _contours: Array[PackedVector2Array] = []
	var _screen_contours: Array[PackedVector2Array] = []
	var _screen_basis := Transform2D.IDENTITY
	var _width: float = -1.0

	func sync(source: Polygon2D, border: Line2D) -> void:
		var has_border := border != null and border.visible and border.closed and border.width > 0.0
		var geometry_key: Array = [source.polygon, source.offset]
		if has_border:
			geometry_key.append_array([
				border.points, border.width, border.joint_mode,
				source.transform.affine_inverse() * border.transform,
			])
		var rebuild := geometry_key != _geometry_key
		if rebuild:
			_geometry_key = geometry_key
			_contours.clear()
			var boundary := source.polygon
			for index in boundary.size():
				boundary[index] += source.offset
			var border_to_source := Transform2D.IDENTITY
			if has_border:
				border_to_source = source.transform.affine_inverse() * border.transform
				## 装饰用 Polygon2D 也由父类收集，不能套用主体的黑描边。
				has_border = _same_boundary(boundary, border_to_source * border.points)
			if has_border:
				var joint := Geometry2D.JOIN_MITER
				if border.joint_mode == Line2D.LINE_JOINT_ROUND:
					joint = Geometry2D.JOIN_ROUND
				elif border.joint_mode == Line2D.LINE_JOINT_BEVEL:
					joint = Geometry2D.JOIN_SQUARE
				for contour in Geometry2D.offset_polygon(border.points, border.width * 0.5, joint):
					_contours.append(border_to_source * contour)
			else:
				_contours.append(boundary)
		var screen_transform := source.get_global_transform_with_canvas()
		var basis := Transform2D(screen_transform.x, screen_transform.y, Vector2.ZERO)
		if absf(basis.determinant()) < 0.000001:
			return
		## 抵消物体/图层/相机的缩放与旋转，线宽和抗锯齿边带保持屏幕像素大小。
		transform = source.transform * basis.affine_inverse()
		var update_points := rebuild or not basis.is_equal_approx(_screen_basis)
		if update_points:
			_screen_contours.clear()
			for contour in _contours:
				if contour.size() < 3:
					continue
				var points := basis * contour
				if not points[0].is_equal_approx(points[points.size() - 1]):
					points.append(points[0])
				_screen_contours.append(points)
		## 线以黑描边外缘为中心，内半边由原物体遮住，外半边就是选中宽度。
		var width := Renderer.selection_outline_width * 2.0
		if update_points or not is_equal_approx(_width, width):
			_width = width
			queue_redraw()
		_screen_basis = basis

	func _draw() -> void:
		if _width <= 0.0:
			return
		for points in _screen_contours:
			## draw_polyline 实际生成渐变 Alpha 边带；选中材质必须保留 COLOR.a。
			draw_polyline(points, Color.WHITE, _width, true)

	## 闭合边界允许起点不同、绕序相反，以及显式重复最后一个顶点。
	func _same_boundary(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		var count_a := a.size()
		var count_b := b.size()
		if count_a > 1 and a[0].is_equal_approx(a[count_a - 1]):
			count_a -= 1
		if count_b > 1 and b[0].is_equal_approx(b[count_b - 1]):
			count_b -= 1
		if count_a < 3 or count_a != count_b:
			return false
		for start in count_b:
			if not a[0].is_equal_approx(b[start]):
				continue
			var forward := true
			var backward := true
			for index in count_a:
				forward = forward and a[index].is_equal_approx(b[(start + index) % count_b])
				backward = backward and a[index].is_equal_approx(b[posmod(start - index, count_b)])
			return forward or backward
		return false


## 复用父类的选中、显隐、材质和图层管理，只替换 Polygon2D 的轮廓几何。
func _create_outline_visual(source: Node2D) -> Node2D:
	if not source is Polygon2D:
		return super(source)
	var outline := SelectionContour.new()
	outline.name = "%s_SelectionOutline" % source.name
	outline.show_behind_parent = true
	outline.z_as_relative = false
	outline.visible = false
	return outline


func _sync_outline_geometry(source: Node2D, outline: Node2D, outline_material: ShaderMaterial) -> void:
	if outline is SelectionContour:
		outline_material.set_shader_parameter("prepared_geometry", true)
	else:
		super(source, outline, outline_material)


func _sync_selection_outlines(sync_geometry: bool = false) -> void:
	super(sync_geometry)
	if not is_inside_tree() or not is_instance_valid(owner_layer) or (not _selected and not sync_geometry):
		return
	for entry in _selection_outlines:
		if not is_instance_valid(entry.source) or not is_instance_valid(entry.outline):
			continue
		if entry.outline is SelectionContour:
			var source := entry.source as Polygon2D
			var border := source.get_parent().get_node_or_null("Outline") as Line2D
			(entry.outline as SelectionContour).sync(source, border)


## 准备时生成影子
func _ready() -> void:
	add_to_group("layer_objects")
	owner_layer = find_owner_layer()
	assert(owner_layer != null, "%s 必须位于 DepthLayer/Objects 下！" % name)
	_setup_selection_outlines()
	if can_leave_shadow:
		var shadow_temp: Polygon2D
		for shadow_layer in range(Global.current_layer_index + 2, Global.layer_count):
			shadow_active.append(false)
			shadow_temp = shadow.duplicate()
			shadow_temp.name = "ShadowBox_%d" % shadow_layer
			add_child(shadow_temp)
			## 影子仍按投射目标层独立排序，不被投影物体所在的 CanvasGroup 改写深度。
			shadow_temp.z_as_relative = false
			shadow_temp.z_index = (
				(Global.current_layer_index - shadow_layer) * DepthLayer.Z_INDEX_STEP
				+ DepthLayer.Z_INDEX_STEP / 2
			)
			shadow_temp.visible = false
			shadow_box.append(shadow_temp)
			shadow_temp = shadow.duplicate()
			shadow_temp.name = "ShadowVisual_%d" % shadow_layer
			var clip_material := ShaderMaterial.new()
			clip_material.shader = SHADOW_CLIP_SHADER
			shadow_temp.material = clip_material
			add_child(shadow_temp)
			shadow_temp.z_as_relative = false
			shadow_temp.z_index = (
				(Global.current_layer_index - shadow_layer) * DepthLayer.Z_INDEX_STEP
				+ DepthLayer.Z_INDEX_STEP / 2
			)
			shadow_temp.visible = false
			shadow_visual.append(shadow_temp)
	update_layer_slot()

## 每帧更新影子状态
func apply_visual_transfer(anchor_position: Vector2, camera_zoom: Vector2) -> void:
	super(anchor_position, camera_zoom)
	if can_leave_shadow:
		for shadow_layer in range(Global.current_layer_index + 2, Global.layer_count):
			var index: int = shadow_layer - Global.current_layer_index - 2
			if shadow_active[index]:
				var target_layer: DepthLayer = Global.get_layer_at_slot(shadow_layer)
				(shadow_visual[index].material as ShaderMaterial).set_shader_parameter("receiver_layer_id", target_layer.layer_id)
				var owner_scale: float = owner_layer.visual_scale
				var shadow_scale: float = target_layer.visual_scale
				var opacity: float = (
					owner_layer.cycle_opacity * target_layer.cycle_opacity
					* clampf((1.0 - owner_scale) * 5.0, 0.0, 1.0)
					* clampf((1.0 - shadow_scale) * 5.0, 0.0, 1.0)
				)
				shadow_visual[index].visible = opacity > 0.0
				if opacity <= 0.0:
					continue
				## 靠近玩家平面时限制投影倍率，避免分母趋近于零。
				owner_scale = minf(owner_scale, 0.95)
				shadow_scale = minf(shadow_scale, 0.95)
				var shadow_box_scale: float = (owner_scale * (1 - shadow_scale)) / (shadow_scale * (1 - owner_scale))
				shadow_box[index].position = (position - anchor_position) * (shadow_box_scale - 1)
				shadow_box[index].scale = collision_box.scale * shadow_box_scale
				shadow_visual[index].position = (anchor_position - position) * (1 - shadow_scale * shadow_box_scale)
				shadow_visual[index].scale = shadow_box[index].scale * shadow_scale
				shadow_visual[index].z_index = target_layer.z_index + DepthLayer.Z_INDEX_STEP / 2
				shadow_visual[index].modulate.a = opacity

## 图层改变时更新影子激活状态
func update_layer_slot() -> void:
	super()
	if can_leave_shadow:
		for shadow_layer in range(Global.current_layer_index + 2, Global.layer_count):
			var index: int = shadow_layer - Global.current_layer_index - 2
			var active: bool = owner_layer.slot > Global.current_layer_index and owner_layer.slot < shadow_layer
			shadow_active[index] = active
			shadow_visual[index].visible = active
