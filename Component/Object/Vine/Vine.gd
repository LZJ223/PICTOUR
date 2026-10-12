## 可换层藤蔓。玩家可抓取后攀爬（W/S）和摆荡（A/D），松开时获得切向惯性速度。
##
## 物理模型：参数化钟摆，不使用 Godot 物理关节。
##   - angle = 0 表示藤蔓垂直向下，正角度向右摆，负角度向左摆。
##   - 玩家位置 = anchor + Vector2(sin(angle), cos(angle)) * length。
##   - 松开时切向速度 = Vector2(cos(angle), -sin(angle)) * angular_velocity * length。
##
## 藤蔓自身不参与实体碰撞（玩家可穿过），仅通过 GrabArea 检测可抓取范围。
## 同图层才能抓取由碰撞层自动保证。

@tool
class_name Vine
extends LayerObject

@export_group("藤蔓参数")
## 藤蔓初始长度（像素），也是往下攀爬的上限。
@export var rope_length: float = 200.0
## 往上攀爬的最短长度（像素）。
@export var min_length: float = 40.0
## 攀爬速度（像素/秒）。
@export var climb_speed: float = 120.0
## A/D 输入施加的角加速度，越大摆得越快。
## 设为较小值，需要多次按 A/D 才能摆到最大幅度，模拟荡秋千的"蓄力"感。
@export var swing_force: float = 2.5
## 摆动阻尼系数，越小摆得越久。
@export var swing_damping: float = 0.5
## 最大摆荡角度（弧度），限制摆幅上限，防止荡到水平以上。
@export var max_swing_angle: float = PI * 0.45
## 钟摆重力加速度，应与玩家保持一致。
@export var gravity: float = 1800.0
## 可抓取检测半径（像素），即绳子两侧的抓取宽度。
@export var grab_radius: float = 22.0
## 松开藤蔓时惯性速度的放大倍数。
@export var release_boost: float = 1.0
## 松手速度的最大幅度（像素/秒），仅作为安全上限。
## 实际速度已由钟摆能量模型限制：v = sqrt(2gL(1-cos(max_angle)))。
@export var max_release_speed: float = 1200.0

## 运行时状态
var _gripped_player: PlayerController = null
var _current_length: float = 0.0
var _angle: float = 0.0
var _angular_velocity: float = 0.0
## 风扇等外力源累积的角加速度，每帧 update_swing 时消耗并重置
var _wind_angular_accel: float = 0.0

@onready var _grab_area: Area2D = $GrabArea
@onready var _grab_shape: CollisionShape2D = $GrabArea/CollisionShape2D
@onready var _line: Line2D = $VisualRoot/Line2D


func _ready() -> void:
	super()
	add_to_group("vines")
	_current_length = rope_length
	## 同步抓取区：胶囊体覆盖整条绳子，宽度为 grab_radius*2
	_sync_grab_shape()
	_update_line_visual()
	if not Engine.is_editor_hint():
		_grab_area.body_entered.connect(_on_body_entered)
		_grab_area.body_exited.connect(_on_body_exited)


## 同步抓取区胶囊体形状，使其覆盖整条绳子
func _sync_grab_shape() -> void:
	if _grab_shape == null:
		return
	var shape = _grab_shape.shape
	if shape is CapsuleShape2D:
		shape.height = rope_length
		shape.radius = grab_radius
	## 胶囊体居中于原点，需向下偏移 rope_length/2 使其覆盖从锚点到末端
	_grab_shape.position = Vector2(0, rope_length * 0.5)


func _validate_property(property: Dictionary) -> void:
	if property.name == "can_transfer":
		property.usage = PROPERTY_USAGE_NO_EDITOR


## 玩家尝试抓取此藤蔓。返回是否成功。
## 同图层由碰撞层保证，此处仅判断是否已被占用及距离。
func try_grab(player: PlayerController) -> bool:
	if _gripped_player != null or player == null:
		return false
	## 检测玩家到绳子线段（锚点到静止末端）的最近距离，
	## 而非到锚点的距离，确保绳子任意位置附近都能抓到。
	var rope_end: Vector2 = global_position + Vector2(0, rope_length)
	var to_player: Vector2 = player.global_position - global_position
	var rope_dir: Vector2 = Vector2(0, rope_length)
	var t: float = clamp(to_player.dot(rope_dir) / rope_length / rope_length, 0.0, 1.0)
	var closest: Vector2 = global_position + rope_dir * t
	var dist_to_rope: float = player.global_position.distance_to(closest)
	if dist_to_rope > grab_radius + 30.0:
		return false
	_gripped_player = player
	## 根据玩家当前相对位置初始化角度和长度
	var rel: Vector2 = player.global_position - global_position
	if rel.length() < 0.01:
		rel = Vector2.DOWN
	_angle = clamp(atan2(rel.x, rel.y), -max_swing_angle, max_swing_angle)
	_current_length = clamp(rel.length(), min_length, rope_length)
	_angular_velocity = 0.0
	return true


## 每帧由攀爬中的玩家调用，更新钟摆并返回玩家应处的全局位置。
## input.x = A/D（左负右正），input.y = W/S（上负下正）。
func update_swing(delta: float, input: Vector2) -> Vector2:
	if _gripped_player == null:
		return global_position
	## 攀爬：W（input.y=-1）缩短绳子往上爬，S（input.y=1）伸长绳子往下爬
	_current_length = clamp(_current_length + input.y * climb_speed * delta, min_length, rope_length)
	## 风力外力（由风扇通过 apply_wind_force 累积），提前取出并从总角速度中分离，
	## 使其不受下方钟摆能量守恒 max_omega 的限制——外部力可以突破重力势能上限。
	var wind_contribution: float = _wind_angular_accel * delta
	_wind_angular_accel = 0.0
	## 钟摆重力恢复力
	var angular_accel: float = -(gravity / max(_current_length, 1.0)) * sin(_angle)
	_angular_velocity += angular_accel * delta
	## A/D 摆荡输入：仅在输入方向与当前角速度同向时施加，
	## 模拟荡秋千"顺势蹬"的感觉。仅在绳子接近最低点且接近静止时
	## 允许从静止启动，避免在最大摆幅处持续按键抵消重力导致卡死。
	if input.x != 0.0:
		var near_bottom: bool = abs(_angle) < 0.4
		var pumping: bool = (
			(near_bottom and abs(_angular_velocity) < 0.3)
			or sign(input.x) == sign(_angular_velocity)
		)
		if pumping:
			_angular_velocity += input.x * swing_force * delta
	## 按钟摆能量守恒限制角速度上限。
	## 物理上，摆到最大角度 max_swing_angle 的钟摆在当前角度 angle 处的
	## 最大角速度为 sqrt(2*g/L * (cos(angle) - cos(max_swing_angle)))。
	## 这样短绳即使摆幅大，切向速度 v = ω*L = sqrt(2gL*(...)) 也会随 sqrt(L) 增长，
	## 避免短绳大摆幅时速度异常大。
	## 仅限制"向外"（远离垂直）的角速度，允许向内的恢复速度不受限，
	## 否则在最大摆幅处角速度会被钳为0导致无法回弹。
	## 注意：风力贡献 wind_contribution 不参与此限制，外部力可突破能量上限。
	var max_omega: float = sqrt(max(0.0, 2.0 * gravity / max(_current_length, 1.0) * (cos(_angle) - cos(max_swing_angle))))
	var outward: bool = (_angle > 0.0 and _angular_velocity > 0.0) or (_angle < 0.0 and _angular_velocity < 0.0)
	if outward:
		_angular_velocity = min(_angular_velocity, max_omega)
	## 加回风力贡献，并单独限制风力本身的最大角速度，防止极端强风导致失控
	_angular_velocity += wind_contribution
	var max_wind_omega: float = 12.0
	_angular_velocity = clamp(_angular_velocity, -max_wind_omega, max_wind_omega)
	## 阻尼
	_angular_velocity *= (1.0 - swing_damping * delta)
	## 积分角度并限制最大摆幅
	_angle += _angular_velocity * delta
	if _angle > max_swing_angle:
		_angle = max_swing_angle
		_angular_velocity = min(_angular_velocity, 0.0)
	elif _angle < -max_swing_angle:
		_angle = -max_swing_angle
		_angular_velocity = max(_angular_velocity, 0.0)
	_update_line_visual()
	return global_position + Vector2(sin(_angle), cos(_angle)) * _current_length


## 由风扇调用，把风力转换为钟摆的角加速度外力。
## 风力的切向分量随角度衰减：切线方向 = (cos(angle), -sin(angle))，
## 风力在切线上的投影 = direction.x * cos(angle) - direction.y * sin(angle)。
## 这样风在藤蔓垂直时效果最强，摆到侧面时效果自然减弱，
## 避免风力在最大角度仍然全力向外推导致藤蔓卡死。
## 投影自带符号：风从一侧吹时，会把藤蔓推向该侧，过了垂直点后推力逐渐减小。
func apply_wind_force(direction: Vector2, force: float, delta: float) -> void:
	if _gripped_player == null:
		return
	var tangent_factor: float = direction.x * cos(_angle) - direction.y * sin(_angle)
	var effective_force: float = force * tangent_factor
	_wind_angular_accel += effective_force / max(_current_length, 1.0)


## 玩家主动松开，返回切向惯性速度（沿藤蔓切线方向）。
## 切向方向 = Vector2(cos(angle), -sin(angle))，即绳子的垂线方向。
## 速度大小 = angular_velocity * current_length * release_boost，并被 max_release_speed 限制。
func release() -> Vector2:
	if _gripped_player == null:
		return Vector2.ZERO
	var tangent: Vector2 = Vector2(cos(_angle), -sin(_angle))
	var release_vel: Vector2 = tangent * _angular_velocity * _current_length * release_boost
	## 限制最大松手速度，避免高速摆荡时像炮弹一样飞出
	if release_vel.length() > max_release_speed:
		release_vel = release_vel.normalized() * max_release_speed
	_reset_runtime_state()
	return release_vel


## 强制松开（换层、死亡等），不返回速度，调用方应自行清零玩家速度。
func force_release() -> void:
	_reset_runtime_state()


func transfer_to(target_layer: DepthLayer, target_transform: Transform2D, target_collision_transform: Transform2D) -> void:
	## 换层前强制松开攀爬中的玩家，避免跨层悬挂。
	force_release()
	super(target_layer, target_transform, target_collision_transform)


func update_layer_slot() -> void:
	super()
	## 同步抓取区碰撞层，确保只有同图层玩家能被检测到。
	if _grab_area != null and owner_layer != null:
		_grab_area.collision_layer = 0
		_grab_area.collision_mask = 0
		_grab_area.set_collision_layer_value(owner_layer.layer_id + 1, true)
		_grab_area.set_collision_mask_value(owner_layer.layer_id + 1, true)


func _reset_runtime_state() -> void:
	_gripped_player = null
	_angle = 0.0
	_angular_velocity = 0.0
	_current_length = rope_length
	_update_line_visual()


## 更新调试用线段，从锚点指向当前末端位置（仅辅助观察，非正式视觉）
func _update_line_visual() -> void:
	if _line == null:
		return
	var end: Vector2 = Vector2(sin(_angle), cos(_angle)) * _current_length
	_line.points = [Vector2.ZERO, end]


func _on_body_entered(body: Node2D) -> void:
	if body is PlayerController:
		body.register_grabable_vine(self)


func _on_body_exited(body: Node2D) -> void:
	if body is PlayerController:
		body.unregister_grabable_vine(self)
