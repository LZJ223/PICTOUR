class_name ShadowedGeometry
extends LayerObject

@onready var shadow: Polygon2D = $Shadow

func _ready() -> void:
	super()
	shadow.hide()

## 连续景深决定投影关系；slot 不作为目标图层的身份。
func can_project_on(receiver: DepthLayer) -> bool:
	return (
		can_leave_shadow and is_visible_in_tree() and receiver != owner_layer
		and owner_layer.visual_scale < 0.999
		and receiver.visual_scale < owner_layer.visual_scale - 0.001
		and owner_layer.cycle_opacity > 0.001 and receiver.cycle_opacity > 0.001
	)

## GPU 与实体切割共用此仿射变换。这里不逐帧裁切多边形。
func get_projection_transform(receiver: DepthLayer, light_position: Vector2) -> Transform2D:
	var caster_scale: float = minf(owner_layer.visual_scale, 0.95)
	var receiver_scale: float = maxf(receiver.visual_scale, 0.0001)
	var ratio: float = caster_scale * (1.0 - receiver_scale) / (
		receiver_scale * (1.0 - caster_scale)
	)
	var projected: Transform2D = collision_box.global_transform
	projected.x *= ratio
	projected.y *= ratio
	projected.origin = light_position + (projected.origin - light_position) * ratio
	return projected

## 只在静止后的实体切割事件中展开世界坐标轮廓。
func get_projection_polygon(receiver: DepthLayer, light_position: Vector2) -> PackedVector2Array:
	return get_projection_transform(receiver, light_position) * shadow.polygon
