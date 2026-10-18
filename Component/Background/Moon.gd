## 初始位置使用关卡局部坐标；只更新位置，保留精灵本身的缩放。
extends Sprite2D

@export var initial_position: Vector2 = Vector2.ZERO
## 相机跟随玩家时的相对位移比例，越接近 0 表示越远。
@export_range(0.0, 1.0, 0.001) var parallax_ratio: float = 0.02

var _player_origin: Vector2
var _has_player_origin: bool = false

func _ready() -> void:
	position = initial_position

func _process(_delta: float) -> void:
	if not is_instance_valid(Global.player):
		return
	var player_position: Vector2 = (get_parent() as Node2D).to_local(Global.player.global_position)
	if not _has_player_origin:
		_player_origin = player_position
		_has_player_origin = true
	position = initial_position + (player_position - _player_origin) * (1.0 - parallax_ratio)
