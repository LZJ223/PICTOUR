extends Node2D
## 有长度与弯曲约束的哑光布条。只在物理帧求解世界质点。
## 无持续正弦摆动；空气阻力、重力与人物加减速共同形成布料响应。

@export var ribbon_length: float = 58.0
@export var particle_count: int = 15
@export var ribbon_width: float = 3.6
@export var ribbon_color := Color("b64637")

@onready var player: PlayerController = get_parent().get_parent() as PlayerController
@onready var traveler: Node2D = get_parent().get_node("Traveler")
var _world := PackedVector2Array()
var _previous_world := PackedVector2Array()
var _current_local := PackedVector2Array()
var _previous_local := PackedVector2Array()
var _last_origin := Vector2.ZERO


func _ready() -> void:
	process_physics_priority = 2
	var fabric := ShaderMaterial.new()
	fabric.shader = load("res://Component/Player/Shared/Scarf_Fabric.gdshader")
	fabric.set_shader_parameter("paper_ink", load("res://Art/Materials/Dry_Ink_AI.png"))
	material = fabric
	reset_cloth()


func _anchor() -> Vector2:
	return player.global_position + Vector2(traveler.get("collar_offset"))


func reset_cloth() -> void:
	var origin := _anchor()
	var facing: int = traveler.get("visual_facing")
	_world.clear()
	_previous_world.clear()
	var initial := Vector2(-facing, 0.35).normalized()
	var point := origin
	for i in particle_count:
		if i > 0:
			var ratio := maxf(0.0, float(i - 2) / float(particle_count - 3))
			point += initial.lerp(Vector2.DOWN, ratio * 0.85).normalized() * ribbon_length / (particle_count - 1)
		_world.append(point)
		_previous_world.append(point)
	_current_local = _local_points()
	_previous_local = _current_local.duplicate()
	_last_origin = player.global_position


func _local_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in _world:
		points.append(point - player.global_position)
	return points


func _physics_process(delta: float) -> void:
	if player.UAV_activated:
		return
	if player.global_position.distance_to(_last_origin) > 100.0:
		reset_cloth()
		return
	_previous_local = _current_local.duplicate()
	var origin := _anchor()
	var facing: int = traveler.get("visual_facing")
	# 静止时下垂，跑动时沿相对气流展开；恒速会收敛成弧线。
	var force := Vector2(-player.velocity.x * 1.2 - facing * 22.0, 440.0 - player.velocity.y * 0.40)
	for i in range(1, particle_count):
		var old := _world[i]
		var inertia := (_world[i] - _previous_world[i]) * pow(0.94, delta * 60.0)
		var tail_weight := pow(float(i) / float(particle_count - 1), 2.0)
		_world[i] += inertia + (force + Vector2(0, 850.0 * tail_weight)) * delta * delta
		_previous_world[i] = old
	var segment := ribbon_length / float(particle_count - 1)
	for iteration in 14:
		_world[0] = origin
		# 二阶约束限制急折：抵抗折成绳圈，同时允许整条围巾弯曲。
		for i in range(2, particle_count):
			var gap := _world[i] - _world[i - 2]
			var gap_length := maxf(gap.length(), 0.001)
			var minimum := segment * 1.88
			if gap_length < minimum:
				var correction := gap * ((gap_length - minimum) / gap_length) * 0.42
				_world[i] -= correction
				if i > 2:
					_world[i - 2] += correction
		for i in range(1, particle_count):
			var gap := _world[i] - _world[i - 1]
			var distance := maxf(gap.length(), 0.001)
			var correction := gap * ((distance - segment) / distance)
			if i == 1:
				_world[i] -= correction
			else:
				_world[i - 1] += correction * 0.5
				_world[i] -= correction * 0.5
		_world[0] = origin
	_unfold_cloth(origin, facing, segment)
	_current_local = _local_points()
	_last_origin = player.global_position
	queue_redraw()


func _unfold_cloth(origin: Vector2, facing: int, segment: float) -> void:
	# 领结出口的两段固定朝背后下方，布条不能从脖子前面喷出。
	var previous_direction := Vector2(-facing, 0.35).normalized()
	for i in range(1, particle_count):
		var old := _world[i]
		var direction := (_world[i] - _world[i - 1]).normalized()
		if i <= 2:
			direction = previous_direction
		else:
			# 邻段限制急折，并强制布条持续离开领口：可形成松弧，不能回卷成颈圈。
			var turn := clampf(previous_direction.angle_to(direction), -0.45, 0.45)
			direction = previous_direction.rotated(turn)
			var radial := (_world[i - 1] - origin).normalized()
			var radial_turn := clampf(radial.angle_to(direction), -0.92, 0.92)
			direction = radial.rotated(radial_turn)
		_world[i] = _world[i - 1] + direction * segment
		# 约束产生的位移不全部变成下一帧速度，避免出布方向切换凭空注入甩动。
		_previous_world[i] += (_world[i] - old) * 0.65
		previous_direction = direction


func _process(_delta: float) -> void:
	# 不写节点变换；仅在显示帧插值布条网格。
	queue_redraw()


func _draw() -> void:
	if _current_local.size() < 2:
		return
	var alpha: float = Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0
	var points := PackedVector2Array()
	for i in particle_count:
		points.append(_previous_local[i].lerp(_current_local[i], alpha))
	var smooth := PackedVector2Array()
	for i in range(points.size() - 1):
		var a := points[maxi(i - 1, 0)]
		var b := points[i]
		var c := points[i + 1]
		var d := points[mini(i + 2, points.size() - 1)]
		for j in 3:
			smooth.append(b.cubic_interpolate(c, a, d, float(j) / 3.0))
	smooth.append(points[-1])
	var upper := PackedVector2Array()
	var lower := PackedVector2Array()
	for i in smooth.size():
		var tangent := (smooth[mini(i + 1, smooth.size() - 1)] - smooth[maxi(i - 1, 0)]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var width: float = ribbon_width * lerpf(0.50, 0.44, float(i) / (smooth.size() - 1))
		upper.append(smooth[i] + normal * width)
		lower.append(smooth[i] - normal * width)
	# 连续法线的三角带不依赖自交多边形三角化；取消圆点关节和亮色中线。
	for i in range(smooth.size() - 1):
		var u0: float = float(i) / float(smooth.size() - 1)
		var u1: float = float(i + 1) / float(smooth.size() - 1)
		draw_primitive(PackedVector2Array([upper[i], upper[i + 1], lower[i]]), PackedColorArray([ribbon_color]), PackedVector2Array([Vector2(u0, 0), Vector2(u1, 0), Vector2(u0, 1)]))
		draw_primitive(PackedVector2Array([lower[i], upper[i + 1], lower[i + 1]]), PackedColorArray([ribbon_color]), PackedVector2Array([Vector2(u0, 1), Vector2(u1, 0), Vector2(u1, 1)]))
	draw_polyline(lower, ribbon_color.darkened(0.13), 0.7, true)
	var last_tangent := (smooth[-1] - smooth[-2]).normalized()
	# 平整织物尾口保留三根短流苏，宽度不收成绳尖。
	for i in 3:
		var start := upper[-1].lerp(lower[-1], (i + 0.5) / 3.0)
		draw_line(start, start + last_tangent * 2.3, ribbon_color, 0.8, true)


func get_ribbon_points() -> PackedVector2Array:
	return _current_local.duplicate()


func get_total_length() -> float:
	var length := 0.0
	for i in range(1, _world.size()):
		length += _world[i].distance_to(_world[i - 1])
	return length
