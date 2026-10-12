## 玩家在 UAV 状态下留在图层上的本体物体。
## 本身不移动，但可被风扇等外力推动，模拟"身体被风吹走"。

class_name Player_Object
extends LayerObject

## 风力等外力累积的速度，每帧更新位置并衰减。
var _external_velocity: Vector2 = Vector2.ZERO
## 外力衰减系数（每秒衰减比例）
const _external_damping: float = 2.0


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _external_velocity.length() > 0.01:
		position += _external_velocity * delta
		## 外力衰减，避免无限持续
		_external_velocity *= (1.0 - _external_damping * delta)
		if _external_velocity.length() < 1.0:
			_external_velocity = Vector2.ZERO


## 由风扇等外力源调用，施加风力到玩家本体。
## direction: 风力方向（已归一化）
## force: 风力加速度（px/s²）
## max_speed: 风力能达到的最大速度
func apply_wind_force(direction: Vector2, force: float, max_speed: float, delta: float) -> void:
	_external_velocity += direction * force * delta
	if _external_velocity.length() > max_speed:
		_external_velocity = _external_velocity.normalized() * max_speed
