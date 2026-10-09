@tool
class_name LayerDecoration
extends Node2D

## 没有碰撞和点选的装饰，与所在真实图层共用投影和插值历史。
@export var texture: Texture2D:
	set(value):
		texture = value
		_refresh_sprite()
@export var display_size: Vector2 = Vector2(600, 400):
	set(value):
		display_size = value
		_refresh_sprite()
@export var tint: Color = Color(1, 1, 1, 0.7):
	set(value):
		tint = value
		_refresh_sprite()
var _sprite: Sprite2D
var _layer: DepthLayer

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "DecorationSprite"
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)
	_layer = get_parent() as DepthLayer
	_refresh_sprite()

func _refresh_sprite() -> void:
	if not is_instance_valid(_sprite):
		return
	_sprite.texture = texture
	_sprite.modulate = tint
	if texture != null:
		_sprite.scale = display_size / texture.get_size()

func apply_visual_transfer(anchor_position: Vector2) -> void:
	if not is_instance_valid(_sprite) or not is_instance_valid(_layer):
		return
	var multiplier: float = Global.layer_scales[_layer.slot]
	_sprite.global_position = anchor_position + (global_position - anchor_position) * multiplier
	_sprite.global_scale = display_size / texture.get_size() * multiplier if texture != null else Vector2.ONE
	_sprite.z_index = (Global.layer_count - _layer.slot) * 100 - 1
