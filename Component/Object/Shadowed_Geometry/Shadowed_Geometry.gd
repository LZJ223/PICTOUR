class_name ShadowedGeometry
extends LayerObject
## 节点信息
@onready var selected_box = $VisualRoot/Line2D
@onready var shadow: Polygon2D = $Shadow
var shadow_box: Array[Polygon2D] = []
var shadow_visual: Array[Polygon2D] = []

## 准备时生成影子
func _ready() -> void:
	super()
	if owner_layer.slot > Global.current_layer_index:
		var shadow_temp: Polygon2D
		for i in range(owner_layer.slot + 1, Global.layer_count):
			shadow_temp = shadow.duplicate()
			self.add_child(shadow_temp)
			shadow_temp.z_index = (Global.layer_count - i) * 100 + 50
			shadow_temp.visible = false
			shadow_box.append(shadow_temp)
			shadow_temp = shadow.duplicate()
			self.add_child(shadow_temp)
			shadow_temp.z_index = (Global.layer_count - i) * 100 + 50
			shadow_temp.visible = true
			shadow_visual.append(shadow_temp)

## 每帧更新影子状态
func apply_visual_transfer(anchor_position: Vector2) -> void:
	super(anchor_position)
	if owner_layer.slot > Global.current_layer_index:
		for i in range(Global.layer_count - owner_layer.slot - 1):
			var scaling: float = Global.layer_scales[owner_layer.slot + i + 1]
			var differ: float = owner_layer.slot - Global.current_layer_index
			shadow_box[i].position = (position - anchor_position) * (i + 1) / differ
			shadow_box[i].scale = collision_box.scale * (differ + i + 1) / differ
			shadow_visual[i].position = (anchor_position - position) * (1 - scaling) + shadow_box[i].position * scaling
			shadow_visual[i].scale = shadow_box[i].scale * scaling

## 更新选取状态
func set_pick_condition(condition: bool = false) -> void:
	selected_box.visible = condition
