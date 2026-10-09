extends Node2D
## 作者化织物弧线：整条宽面、翻边、松弧和延迟。视觉美感优先，不宣称定长物理布模拟。

@onready var player: PlayerController = get_parent().get_parent()
@onready var traveler: Node2D = get_parent().get_node("Traveler")
var _points := PackedVector2Array()
var _previous_points := PackedVector2Array()
var _tail := Vector2(-7, 47)
var _wind := 0.0
var _clock := 0.0
var _last_origin := Vector2.ZERO


func _ready() -> void:
	process_physics_priority = 2
	var fabric := ShaderMaterial.new()
	fabric.shader = preload("res://Component/Player/V7/Page_Ink.gdshader")
	fabric.set_shader_parameter("paper_ink", preload("res://Art/Materials/Dry_Ink_AI.png"))
	material = fabric
	reset_cloth()


func reset_cloth() -> void:
	_wind = 0.0
	_tail = Vector2(-7 * int(traveler.visual_facing), 47)
	_clock = 0.0
	_last_origin = player.global_position
	_solve_points()
	_previous_points = _points.duplicate()
	queue_redraw()


func _physics_process(delta: float) -> void:
	if player.UAV_activated:
		return
	if player.global_position.distance_to(_last_origin) > 100:
		reset_cloth()
		return
	_previous_points = _points.duplicate()
	_clock += delta
	_wind = lerpf(_wind, player.velocity.x / 320, 1 - exp(-delta * 7.0))
	var intensity := clampf(absf(_wind), 0, 1.5)
	var flow := Vector2(-signf(_wind) * lerpf(7, 56, clampf(intensity, 0, 1)), lerpf(47, 9, clampf(intensity, 0, 1)))
	if intensity < 0.02:
		flow.x = -int(traveler.visual_facing) * 7
	flow.y += float(traveler.pose.flutter) * intensity * 1.3 - clampf(player.velocity.y / 100, -5, 5)
	_tail = _tail.lerp(flow, 1 - exp(-delta * 10))
	_solve_points()
	_last_origin = player.global_position
	queue_redraw()


func _solve_points() -> void:
	var anchor: Vector2 = traveler.collar_offset
	var direction: int = traveler.visual_facing
	var intensity := minf(1.0, absf(_wind))
	var middle := anchor + _tail * 0.50 + Vector2(0, intensity * 6.5)
	_points.clear()
	for i in 25:
		var t := float(i) / 24
		var u := t * 2 if t < 0.5 else (t - 0.5) * 2
		var a := anchor if t < 0.5 else middle
		var b := middle if t < 0.5 else anchor + _tail
		var c1 := anchor + Vector2(-direction * 12, -intensity * 3.4) if t < 0.5 else middle + _tail * 0.17 + Vector2(0, -intensity * 3.0)
		var c2 := middle - _tail * 0.17 + Vector2(0, intensity * 3.0) if t < 0.5 else b - _tail * 0.19 + Vector2(0, -intensity * 9.0)
		var point := a * pow(1 - u, 3) + c1 * 3 * pow(1 - u, 2) * u + c2 * 3 * (1 - u) * u * u + b * u * u * u
		point.y += sin(t * PI * 2.0 - _clock * 6.0) * sin(t * PI) * intensity * 1.3
		_points.append(point)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _points.size() != _previous_points.size() or _points.size() < 2:
		return
	var fraction := Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0
	var points := PackedVector2Array()
	for i in _points.size():
		points.append(_previous_points[i].lerp(_points[i], fraction))
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var t := float(i) / (points.size() - 1)
		var half_width := lerpf(2.1, 2.55, sin(t * PI * 0.8)) - sin(t * PI * 2 - _clock * 4.0) * t * minf(1.0, absf(_wind)) * 0.28
		top.append(points[i] + normal * half_width)
		bottom.append(points[i] - normal * half_width)
	for i in range(points.size() - 1):
		var shade := Color("b44237").lerp(Color("a83b39"), float(i) / points.size())
		draw_primitive(PackedVector2Array([top[i], top[i + 1], bottom[i]]), PackedColorArray([shade]), PackedVector2Array())
		draw_primitive(PackedVector2Array([bottom[i], top[i + 1], bottom[i + 1]]), PackedColorArray([shade]), PackedVector2Array())
	draw_polyline(bottom, Color("8b3938"), 0.55, true)
	var edge := PackedVector2Array()
	for i in points.size():
		edge.append(top[i].lerp(bottom[i], 0.18))
	draw_polyline(edge, Color("ca6552"), 0.45, true)
	var direction := (points[-1] - points[-2]).normalized()
	for i in 4:
		var start := top[-1].lerp(bottom[-1], (i + 0.5) / 4.0)
		draw_line(start, start + direction * 1.7, Color("a83b39"), 0.5, true)


func get_ribbon_points() -> PackedVector2Array:
	return _points.duplicate()
