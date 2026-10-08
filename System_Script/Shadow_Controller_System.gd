## 此脚本挂载在 ShadowControllerSystem 节点上，负责影子判定、布尔运算与物体替换

class_name ShadowControllerSystem
extends Node
## 布尔运算参数
const MIN_FRAGMENT_AREA: float = 4.0
const BOOLEAN_AREA_EPSILON: float = 0.01
## 布尔运算类
class CutPlan:
	var source: LayerObject
	var pieces: Array[PackedVector2Array]
	func _init(p_source: LayerObject, p_pieces: Array[PackedVector2Array]) -> void:
		source = p_source
		pieces = p_pieces

func _ready() -> void:
	SignalSystem.shadow_boolean.connect(shadow_boolean)

## 影子布尔运算
func shadow_boolean() -> void:
	for slot in range(Global.layer_count - 1, Global.current_layer_index + 1, -1):
		## 影子收集
		var shadows: Array[PackedVector2Array] = []
		var shadow_index: int = slot - Global.current_layer_index - 2
		for caster_slot in range(Global.current_layer_index + 1, slot):
			var caster_layer: DepthLayer = Global.get_layer_at_slot(caster_slot)
			for child in caster_layer.get_children():
				if child is LayerObject:
					if not child.can_leave_shadow:
						continue
					if not child.shadow_active[shadow_index]:
						continue
					var shadow_node: Polygon2D = child.shadow_box[shadow_index]
					shadows.append(_polygon_to_world(shadow_node.polygon, shadow_node.global_transform))
		if shadows.is_empty():
			continue
		## 承影物体收集
		var target_layer: DepthLayer = Global.get_layer_at_slot(slot)
		var plans: Array[CutPlan] = []
		for child in target_layer.get_children().duplicate():
			if child is LayerObject:
				if not child.can_be_shadowed or not child.collision_box is CollisionPolygon2D:
					continue
				var source_polygon: PackedVector2Array = _polygon_to_world((child.collision_box as CollisionPolygon2D).polygon, child.collision_box.global_transform)
				var pieces: Array[PackedVector2Array] = _subtract_shadows(source_polygon, shadows)
				if _polygons_area(pieces) < abs(_polygon_area(source_polygon)) - BOOLEAN_AREA_EPSILON:
					plans.append(CutPlan.new(child, pieces))
		for plan in plans:
			_replace_object_with_fragments(plan.source, plan.pieces)

## 将多个影子依次从物体的全部剩余部分中减去
func _subtract_shadows(source: PackedVector2Array, shadows: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = []
	pieces.append(source)
	for shadow_polygon in shadows:
		var next_pieces: Array[PackedVector2Array] = []
		var shadow_bounds: Rect2 = _polygon_bounds(shadow_polygon)
		var apply_clip: bool = true
		for piece in pieces:
			## 如果影子和物体不相交，直接跳过本次切割
			if not _polygon_bounds(piece).intersects(shadow_bounds):
				next_pieces.append(piece)
				continue
			## 切割进程
			var clipped: Array[PackedVector2Array] = Geometry2D.clip_polygons(piece, shadow_polygon)
			## CollisionPolygon2D 不能表示孔洞，如有孔洞跳过本次切割
			var has_clockwise: bool = false
			var has_counterclockwise: bool = false
			for polygon in clipped:
				if Geometry2D.is_polygon_clockwise(polygon):
					has_clockwise = true
				else:
					has_counterclockwise = true
			if has_clockwise and has_counterclockwise:
				apply_clip = false
			## 除去太小的多边形
			for polygon in clipped:
				if polygon.size() >= 3 and abs(_polygon_area(polygon)) >= MIN_FRAGMENT_AREA:
					next_pieces.append(polygon)
		if apply_clip:
			pieces = next_pieces
		if pieces.is_empty():
			break
	return pieces

## 删除原物体，并将每个连通结果生成为同类型的新物体
func _replace_object_with_fragments(source: LayerObject, world_pieces: Array[PackedVector2Array]) -> void:
	if source.scene_file_path.is_empty():
		push_error("%s 没有可用于生成碎片的场景资源！" % source.name)
		return
	var source_scene: PackedScene = load(source.scene_file_path) as PackedScene
	if source_scene == null:
		push_error("无法加载碎片场景：%s" % source.scene_file_path)
		return
	var target_layer: DepthLayer = source.owner_layer
	var generated_count: int = 0
	for world_polygon in world_pieces:
		var center: Vector2 = _polygon_centroid(world_polygon)
		var polygon: PackedVector2Array = []
		for point in world_polygon:
			polygon.append(point - center)
		## 生成物体
		var fragment: LayerObject = source_scene.instantiate() as LayerObject
		if fragment == null or not _configure_fragment_geometry(fragment, polygon):
			if fragment != null:
				fragment.free()
			continue
		fragment.name = "%s_Fragment" % source.name
		fragment.position = center
		fragment.can_transfer = source.can_transfer
		fragment.can_leave_shadow = source.can_leave_shadow
		fragment.can_be_shadowed = source.can_be_shadowed
		_copy_whitebox_style(source, fragment)
		target_layer.add_child(fragment, true)
		generated_count += 1
	## 场景结构不兼容时保留原物体；完全被切除时 world_pieces 本来就为空
	if not world_pieces.is_empty() and generated_count == 0:
		return
	source.queue_free()

## 在物体进入场景树前同步实体、视觉、点选与投影轮廓
func _configure_fragment_geometry(fragment: LayerObject, polygon: PackedVector2Array) -> bool:
	## 寻找节点
	var collision: CollisionPolygon2D = fragment.get_node_or_null("CollisionBox") as CollisionPolygon2D
	var visual: Polygon2D = fragment.get_node_or_null("VisualRoot/Polygon2D") as Polygon2D
	var selection: Line2D = fragment.get_node_or_null("VisualRoot/Line2D") as Line2D
	var pick_shape: CollisionPolygon2D = fragment.get_node_or_null("VisualRoot/Area2D/CollisionShape2D") as CollisionPolygon2D
	var shadow_template: Polygon2D = fragment.get_node_or_null("Shadow") as Polygon2D
	if collision == null or visual == null or selection == null or pick_shape == null:
		push_error("%s 缺少生成布尔碎片所需的节点！" % fragment.name)
		return false
	## 设置多边形
	collision.polygon = polygon
	visual.polygon = polygon
	selection.points = polygon
	pick_shape.polygon = polygon
	if shadow_template != null:
		shadow_template.polygon = polygon
	return true

## 待完善：白模阶段只复制颜色，贴图与蒙版留给后续的 UV 系统
func _copy_whitebox_style(source: LayerObject, target: LayerObject) -> void:
	var source_visual: Polygon2D = source.get_node_or_null("VisualRoot/Polygon2D") as Polygon2D
	var target_visual: Polygon2D = target.get_node_or_null("VisualRoot/Polygon2D") as Polygon2D
	if source_visual == null or target_visual == null:
		return
	target_visual.color = source_visual.color

func _polygon_to_world(polygon: PackedVector2Array, transform: Transform2D) -> PackedVector2Array:
	var result: PackedVector2Array = []
	for point in polygon:
		result.append(transform * point)
	return result

func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var result: Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for point in polygon:
		result = result.expand(point)
	return result

func _polygon_area(polygon: PackedVector2Array) -> float:
	var area: float = 0.0
	for index in range(polygon.size()):
		area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	return area * 0.5

func _polygons_area(polygons: Array[PackedVector2Array]) -> float:
	var area: float = 0.0
	for polygon in polygons:
		area += abs(_polygon_area(polygon))
	return area

func _polygon_centroid(polygon: PackedVector2Array) -> Vector2:
	var cross_sum: float = 0.0
	var centroid_sum: Vector2 = Vector2.ZERO
	for index in range(polygon.size()):
		var current: Vector2 = polygon[index]
		var next: Vector2 = polygon[(index + 1) % polygon.size()]
		var cross: float = current.cross(next)
		cross_sum += cross
		centroid_sum += (current + next) * cross
	if abs(cross_sum) < 0.0001:
		var average: Vector2 = Vector2.ZERO
		for point in polygon:
			average += point
		return average / max(polygon.size(), 1)
	return centroid_sum / (3.0 * cross_sum)
