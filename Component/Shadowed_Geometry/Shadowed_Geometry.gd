class_name ShadowedGeometry
extends LayerObject
const SHADOW_CLIP_SHADER := preload("res://Shader/Shadow_Receiver_Clip.gdshader")
@onready var shadow: Polygon2D = $Shadow

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
