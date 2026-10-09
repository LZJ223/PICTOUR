extends Node2D
## 独立惯性丝带。世界点只在物理帧求解；绘制点插值不写节点变换。

@export var ribbon_length: float = 72.0
@export var particle_count: int = 8
@export var ribbon_color := Color("c55547")

@onready var player: PlayerController = get_parent().get_parent() as PlayerController
@onready var traveler: AnimatedSprite2D = get_parent().get_node("Traveler")

var _world: PackedVector2Array = []
var _previous_world: PackedVector2Array = []
var _draw_current: PackedVector2Array = []
var _draw_previous: PackedVector2Array = []
var _last_origin := Vector2.ZERO
var _clock: float = 0.0


func _ready() -> void:
	process_physics_priority = 2
	_reset_ribbon()


func _anchor() -> Vector2:
	var offset: Vector2 = traveler.get("collar_offset")
	return player.global_position + offset


func _reset_ribbon() -> void:
	var origin := _anchor()
	_world.clear()
	_previous_world.clear()
	for i in particle_count:
		var ratio := float(i) / float(particle_count - 1)
		var point := origin + Vector2(-player.facing_direction * ratio * ribbon_length * 0.78, ratio * ribbon_length * 0.6)
		_world.append(point)
		_previous_world.append(point)
	_draw_current = _local_points()
	_draw_previous = _draw_current.duplicate()
	_last_origin = player.global_position


func _local_points() -> PackedVector2Array:
	var local := PackedVector2Array()
	for point in _world:
		local.append(point - player.global_position)
	return local


func _physics_process(delta: float) -> void:
	if player.UAV_activated:
		return
	if player.global_position.distance_to(_last_origin) > 120.0:
		_reset_ribbon()
		return
	_draw_previous = _draw_current.duplicate()
	_clock += delta
	var origin := _anchor()
	var moving: float = clampf(absf(player.velocity.x) / player.run_speed, 0.0, 1.4)
	var wind := Vector2(-player.velocity.x * 11.0 - player.facing_direction * 160.0, 340.0 - moving * 260.0 - player.velocity.y * 0.55)
	_world[0] = origin
	_previous_world[0] = origin
	for i in range(1, particle_count):
		var ratio := float(i) / float(particle_count - 1)
		var old := _world[i]
		var inertial := (_world[i] - _previous_world[i]) * pow(0.9, delta * 60.0)
		var breeze := Vector2(sin(_clock * 2.0 + ratio * 3.0) * 80, sin(_clock * (3.3 + moving * 5.2) - ratio * 7.0) * (90.0 + moving * 1800.0))
		_world[i] += inertial + (wind + breeze) * delta * delta
		_previous_world[i] = old
	var segment_length := ribbon_length / float(particle_count - 1)
	for _iteration in 7:
		_world[0] = origin
		for i in range(1, particle_count):
			var gap := _world[i] - _world[i - 1]
			var length := maxf(gap.length(), 0.001)
			var correction := gap * ((length - segment_length) / length)
			if i == 1:
				_world[i] -= correction
			else:
				_world[i - 1] += correction * 0.5
				_world[i] -= correction * 0.5
	_draw_current = _local_points()
	_last_origin = player.global_position
	queue_redraw()


func _process(_delta: float) -> void:
	# 仅请求重绘中间帧；物理和视觉节点变换完全由物理帧管理。
	queue_redraw()


func _draw() -> void:
	if _draw_current.size() < 2:
		return
	var fraction: float = Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0
	var points := PackedVector2Array()
	for i in _draw_current.size():
		points.append(_draw_previous[i].lerp(_draw_current[i], fraction))
	var edge_a := PackedVector2Array()
	var edge_b := PackedVector2Array()
	for i in points.size():
		var tangent: Vector2 = points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]
		var normal := tangent.normalized().orthogonal()
		var half_width: float = lerpf(3.4, 1.8, float(i) / float(points.size() - 1))
		edge_a.append(points[i] + normal * half_width)
		edge_b.append(points[i] - normal * half_width)
	# 急转身时整条丝带可能自交，逐段绘制凸四边形避免自交轮廓三角化失败。
	for i in range(points.size() - 1):
		var direction: Vector2 = (points[i + 1] - points[i]).normalized()
		var normal := direction.orthogonal()
		var width_a: float = lerpf(3.4, 1.8, float(i) / float(points.size() - 1))
		var width_b: float = lerpf(3.4, 1.8, float(i + 1) / float(points.size() - 1))
		var segment := PackedVector2Array([points[i] + normal * width_a, points[i + 1] + normal * width_b, points[i + 1] - normal * width_b, points[i] - normal * width_a])
		if points[i].distance_squared_to(points[i + 1]) > 0.01:
			draw_colored_polygon(segment, ribbon_color)
		if i > 0:
			draw_circle(points[i], width_a, ribbon_color)
	draw_polyline(edge_a, Color("a64743"), 0.9, true)
	draw_polyline(points, Color(0.89, 0.51, 0.39, 0.58), 1.1, true)


func get_ribbon_points() -> PackedVector2Array:
	return _draw_current.duplicate()
