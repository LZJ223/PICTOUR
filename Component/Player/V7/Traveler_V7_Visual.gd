extends Node2D
## 完整侧视作者化角色。身体/衣页/发束由曲线重绘；仅保留母图的头部细节。
## 物理帧选择姿态并记录历史，显示帧仅插值绘图数据，不写实体或节点变换。

const POSES = preload("res://Component/Player/V7/Page_Poses.gd")
const INK := Color("493743")
const HAIR := Color("483441")
const HAIR_LIGHT := Color("78606a")
const CLOTH := Color("eee4cf")
const CLOTH_EDGE := Color("a39289")
const LINING := Color("99818b")
const LINING_DARK := Color("735b6d")
const SKIN := Color("dcc2ab")
@onready var player: PlayerController = get_parent().get_parent()
var visual_facing := 1
var collar_offset := Vector2(-3, -78)
var stride_phase := 0.0
var cycle_total := 0.0
var measured_distance := 0.0
var gait_blend := 0.0
var activity := 0.0
var state_name := "idle"
var skin_ready := false
var render_shape_failures := 0
var total_render_shape_failures := 0
var render_failure_sources: Dictionary = {}
var pose: Dictionary = {}
var previous_pose: Dictionary = {}
var motion_events := {"start": 0, "land": 0, "stop": 0, "turn": 0, "jump": 0}
var _render: Dictionary = {}
var _last_position := Vector2.ZERO
var _last_intent := 0.0
var _seen_floor := false
var _air := false
var _unsupported_time := 0.0
var _air_mix := 0.0
var _land_time := 1.0
var _step_offset := 0.0
var _clock := 0.0
var _hair_response := 0.0
var _cloth_response := 0.0
var _speed_response := 0.0
var _turn_scale := 1.0
var _floor_tangent := Vector2.RIGHT
var _head: Polygon2D
var _stop_pending := false


func _ready() -> void:
	process_physics_priority = 1
	_last_position = player.global_position
	var fabric := ShaderMaterial.new()
	fabric.shader = preload("res://Component/Player/V7/Page_Ink.gdshader")
	fabric.set_shader_parameter("paper_ink", preload("res://Art/Materials/Dry_Ink_AI.png"))
	material = fabric
	_load_head()
	pose = POSES.idle(0)
	pose["facing"] = 1.0
	previous_pose = pose.duplicate(true)
	_update_collar()
	_render = pose.duplicate(true)
	_update_head()


func _load_head() -> void:
	_head = Polygon2D.new()
	_head.name = "MotherHead"
	_head.texture = preload("res://Art/Player/V6/Generated/Traveler_C_Rig.png")
	_head.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_head.z_index = 10
	_head.uv = PackedVector2Array([Vector2(184, 35), Vector2(460, 35), Vector2(460, 301), Vector2(184, 301)])
	_head.material = null
	add_child(_head)
	skin_ready = true


func _ground_at(world_x: float) -> Dictionary:
	var y := player.global_position.y + _floor_tangent.y / maxf(0.1, _floor_tangent.x) * (world_x - player.global_position.x)
	var ray := PhysicsRayQueryParameters2D.create(Vector2(world_x, y - 30), Vector2(world_x, y + 40), player.collision_mask, [player.get_rid()])
	ray.collide_with_areas = false
	var hit := player.get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and Vector2(hit.normal).dot(Vector2.UP) < 0.67:
		return {}
	return hit


func _physics_process(delta: float) -> void:
	if player.UAV_activated:
		return
	var displacement := player.global_position - _last_position
	if displacement.length() > 100:
		reset_after_restore()
		return
	previous_pose = pose.duplicate(true)
	_clock += delta
	_land_time += delta
	var grounded := player.is_on_floor()
	var was_air := _air
	var intent: float = float(player.get_meta("animation_input_axis", Input.get_axis("move_left", "move_right")))
	if grounded:
		if _seen_floor and _air:
			motion_events.land += 1
			_land_time = 0.0
		_seen_floor = true
		_air = false
		_unsupported_time = 0.0
		var normal := player.get_floor_normal()
		_floor_tangent = Vector2(-normal.y, normal.x).normalized()
		if _floor_tangent.x < 0:
			_floor_tangent = -_floor_tangent
	else:
		_unsupported_time += delta
		if not _seen_floor or player.velocity.y < -150 or _unsupported_time > 0.05:
			_air = true
	if _air and not was_air:
		motion_events.jump += 1
	var supported := grounded or (_seen_floor and not _air)
	measured_distance = absf(displacement.dot(_floor_tangent)) if supported else absf(displacement.x)
	var speed := measured_distance / maxf(delta, 0.001)
	var facing := visual_facing
	if absf(player.velocity.x) > 8:
		facing = int(signf(player.velocity.x))
	elif absf(intent) > 0.1:
		facing = int(signf(intent))
	if facing != visual_facing:
		visual_facing = facing
		motion_events.turn += 1
	_turn_scale = move_toward(_turn_scale, float(visual_facing), delta * 23.0)
	if supported and activity < 0.08 and absf(intent) > 0.1 and absf(_last_intent) < 0.1:
		motion_events.start += 1
		cycle_total = floorf(cycle_total) + 0.13
		_stop_pending = false
	if absf(intent) < 0.1 and absf(_last_intent) > 0.1:
		_stop_pending = true
	if _stop_pending and speed < 3:
		motion_events.stop += 1
		_stop_pending = false
	var running := player.is_running or player.dash_active or speed > 240
	gait_blend = move_toward(gait_blend, 1.0 if running else 0.0, delta / 0.18)
	activity = move_toward(activity, 1.0 if speed > 3 else 0.0, delta / (0.12 if speed > 3 else 0.18))
	if supported and measured_distance > 0.01:
		cycle_total += measured_distance / lerpf(POSES.WALK_STRIDE, POSES.RUN_STRIDE, gait_blend)
	stride_phase = fposmod(cycle_total, 1.0)
	var ease := activity * activity * (3 - 2 * activity)
	pose = POSES.blend_pose(POSES.idle(_clock), POSES.gait(stride_phase, gait_blend), ease)
	_air_mix = move_toward(_air_mix, 1.0 if _air else 0.0, delta / (0.10 if _air else 0.13))
	if _air_mix > 0:
		pose = POSES.blend_pose(pose, POSES.air(player.velocity.y, gait_blend), _air_mix)
	# 短冲用舒展的整人长势，不新增一套急促碎步。
	if player.dash_active:
		pose.neck.x += 3.0
		pose.head.x += 3.0
		pose.tail += 5.0
		pose.hem += 3.0
	_step_offset = move_toward(_step_offset, 0.0, delta * 120.0)
	_step_offset = minf(12.0, _step_offset + float(player.get("step_up_height")))
	var compression := sin(clampf(_land_time / 0.19, 0, 1) * PI) * 3.1
	var upper_keys := ["hip", "neck", "head", "chest", "waist", "near_knee", "far_knee", "near_elbow", "far_elbow", "near_hand", "far_hand"]
	for key in upper_keys:
		pose[key].y += _step_offset * (0.5 if "knee" in key else 1.0) + compression * (0.4 if key == "head" else 1.0)
	if supported and _air_mix < 0.2:
		for side in ["near", "far"]:
			var foot: Vector2 = pose[side + "_ankle"]
			var hit := _ground_at(player.global_position.x + foot.x * visual_facing)
			if not hit.is_empty():
				var floor_y := clampf(Vector2(hit.position).y - player.global_position.y, -24, 24)
				pose[side + "_ankle"].y += floor_y
				pose[side + "_toe"].y += floor_y
	_speed_response = lerpf(_speed_response, clampf(absf(player.velocity.x) / 320.0, 0, 1.4), 1 - exp(-delta * 7))
	_hair_response = lerpf(_hair_response, float(pose.hair) + _speed_response * 9.0, 1 - exp(-delta * 13))
	_cloth_response = lerpf(_cloth_response, float(pose.tail), 1 - exp(-delta * 16))
	pose.hair = _hair_response
	pose.tail = _cloth_response
	pose["facing"] = _turn_scale
	state_name = "air" if _air else ("dash" if player.dash_active else ("idle" if activity < 0.1 else ("run" if gait_blend > 0.5 else "walk")))
	_update_collar()
	_last_position = player.global_position
	_last_intent = intent


func reset_after_restore() -> void:
	visual_facing = player.facing_direction
	_turn_scale = float(visual_facing)
	_last_position = player.global_position
	_last_intent = 0.0
	_seen_floor = player.is_on_floor()
	_air = not _seen_floor
	_unsupported_time = 0.0
	_air_mix = 0.0
	_land_time = 1.0
	_step_offset = 0.0
	_hair_response = 0.0
	_cloth_response = 0.0
	_speed_response = 0.0
	_stop_pending = false
	activity = 0.0
	gait_blend = 0.0
	cycle_total = floorf(cycle_total) + 0.13
	stride_phase = 0.13
	_floor_tangent = Vector2.RIGHT
	pose = POSES.idle(_clock)
	pose["facing"] = float(visual_facing)
	previous_pose = pose.duplicate(true)
	_render = pose.duplicate(true)
	state_name = "idle"
	_update_collar()
	_update_head()
	queue_redraw()


func _update_collar() -> void:
	collar_offset = Vector2(pose.neck.x * float(pose.facing) - 3 * float(pose.facing), pose.neck.y + 1.5)


func _process(_delta: float) -> void:
	if pose.is_empty():
		return
	var fraction := Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0
	_render = POSES.blend_pose(previous_pose, pose, fraction)
	_update_head()
	queue_redraw()


func _v(point: Vector2) -> Vector2:
	# 侧视换面允许翻向，不能在中间帧把整人压成一根纸针。
	var facing: float = float(_render.facing)
	var scale_x := signf(facing) * lerpf(0.86, 1.0, absf(facing))
	if is_zero_approx(scale_x):
		scale_x = visual_facing * 0.86
	return Vector2(point.x * scale_x, point.y)


func _update_head() -> void:
	if _head == null or _render.is_empty():
		return
	var rest := [Vector2(-168, -214), Vector2(108, -214), Vector2(108, 52), Vector2(-168, 52)]
	var points := PackedVector2Array()
	for point: Vector2 in rest:
		points.append(_v(Vector2(_render.head) + (point * 0.077).rotated(float(_render.head_angle))))
	_head.polygon = points


func _bezier(a: Vector2, c1: Vector2, c2: Vector2, b: Vector2, count: int = 10) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		var t := float(i) / count
		points.append(a * pow(1 - t, 3) + c1 * 3 * pow(1 - t, 2) * t + c2 * 3 * (1 - t) * t * t + b * t * t * t)
	points.append(b)
	return points


func _path(start: Vector2, segments: Array) -> PackedVector2Array:
	var points := PackedVector2Array([start])
	var a := start
	for segment: Array in segments:
		var section := _bezier(a, segment[0], segment[1], segment[2], 8)
		for i in range(1, section.size()):
			points.append(section[i])
		a = segment[2]
	return points


func _tapered_strand(points: PackedVector2Array, half_width: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in points.size():
		var tangent := (points[mini(points.size() - 1, i + 1)] - points[maxi(0, i - 1)]).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var t := float(i) / (points.size() - 1)
		var width := lerpf(half_width, 0.14, t * t)
		left.append(points[i] + normal * width)
		right.append(points[i] - normal * width)
	right.reverse()
	left.append_array(right)
	return left


func _shape(points: PackedVector2Array, color: Color, edge := Color.TRANSPARENT, edge_width := 0.5) -> void:
	var mirrored := PackedVector2Array()
	for point in points:
		mirrored.append(_v(point))
	if Geometry2D.triangulate_polygon(mirrored).is_empty():
		render_shape_failures += 1
		total_render_shape_failures += 1
		var source := "%s/%d" % [color.to_html(), points.size()]
		render_failure_sources[source] = int(render_failure_sources.get(source, 0)) + 1
		return
	draw_colored_polygon(mirrored, color)
	if edge.a > 0:
		mirrored.append(mirrored[0])
		draw_polyline(mirrored, edge, edge_width, true)


func _line(points: PackedVector2Array, color: Color, width: float) -> void:
	var mirrored := PackedVector2Array()
	for point in points:
		mirrored.append(_v(point))
	draw_polyline(mirrored, color, width, true)


func _leg(side: String, color: Color) -> void:
	var hip: Vector2 = _render.hip
	var knee: Vector2 = _render[side + "_knee"]
	var ankle: Vector2 = _render[side + "_ankle"]
	var toe: Vector2 = _render[side + "_toe"]
	var tangent := (ankle - hip).normalized()
	var upper := _bezier(hip, hip.lerp(knee, 0.35) + Vector2(-0.8, 0), knee - tangent * 4, knee, 7)
	var lower := _bezier(knee, knee + tangent * 5, ankle.lerp(knee, 0.18), ankle + Vector2(-0.4, -0.3), 9)
	upper.append_array(lower.slice(1))
	var sole := _bezier(upper[-1], ankle + Vector2(-0.2, 0.7), toe - Vector2(1.8, 0.1), toe, 5)
	upper.append_array(sole.slice(1))
	# 一笔连续的墨腿，膝/踝不以硬直角折开；宽度从衣内渐收至足尖。
	for i in range(upper.size() - 1):
		var weight := float(i) / (upper.size() - 1)
		var width := lerpf(1.85 if side == "near" else 1.45, 0.70, weight)
		draw_line(_v(upper[i]), _v(upper[i + 1]), color, width, true)


func _arm(side: String, behind: bool) -> void:
	var chest: Vector2 = _render.chest
	var elbow: Vector2 = _render[side + "_elbow"]
	var hand: Vector2 = _render[side + "_hand"]
	var shoulder := chest + Vector2(-3 if not behind else 1, 0)
	var sleeve := _path(shoulder + Vector2(-2, -2), [[shoulder + Vector2(-4, 4), elbow + Vector2(-3, -1), elbow + Vector2(-2, 2)], [elbow + Vector2(0, 3), elbow + Vector2(2, 3), elbow + Vector2(2, 0)], [elbow + Vector2(2, -6), shoulder + Vector2(4, 1), shoulder + Vector2(2, -2)]])
	_shape(sleeve, CLOTH.darkened(0.09) if behind else CLOTH, CLOTH_EDGE.darkened(0.1), 0.4)
	_line(_bezier(elbow, elbow.lerp(hand, 0.35), hand + Vector2(-1, -3), hand, 8), SKIN.darkened(0.1) if behind else SKIN, 2.1)
	_line(PackedVector2Array([hand, hand + Vector2(0.4, 1.9)]), SKIN, 1.7)


func _hair() -> void:
	var neck: Vector2 = _render.neck
	var flow := float(_render.hair)
	var flutter := float(_render.flutter)
	var curl := float(_render.hair_curl)
	var tip := neck + Vector2(-13 - flow * 1.02 + curl * 0.4, 32 - flow * 0.66 + curl * 1.05)
	var outer := _path(neck + Vector2(-5, -6), [[neck + Vector2(-9, 0), neck + Vector2(-13 - flow * 0.50 + curl * 0.35, 10 + curl * 0.2), neck + Vector2(-16 - flow * 0.60 + curl * 0.5, 19 - flow * 0.38)], [neck + Vector2(-20 - flow * 0.76, 30 - flow * 0.53 + curl), tip + Vector2(-4, 3 + curl * 0.15), tip], [tip + Vector2(5, 1), neck + Vector2(-7 - flow * 0.20 + curl * 0.2, 16), neck + Vector2(-3, -3)]])
	_shape(outer, HAIR, HAIR.darkened(0.14), 0.4)
	# 两束细长发尾有各自的末端曲率与滞后，不将整块发型作袋状平移。
	for i in 2:
		var lag := sin(stride_phase * TAU - i * 0.8) * activity * 1.1
		var end := tip + Vector2(-3 + i * 5 + lag + curl * (0.2 + i * 0.1), -2 + i * 4 + flutter * (0.3 + i * 0.2) - curl * i * 0.3)
		var center := _bezier(neck + Vector2(-9 + i * 2.5, -1), neck + Vector2(-11 - flow * 0.45 + curl * 0.35, 13 - flow * 0.2), end + Vector2(4, -5), end, 20)
		var lock := _tapered_strand(center, 1.5 - i * 0.25)
		_shape(lock, HAIR.lightened(i * 0.035))
	for i in 3:
		var offset := i * 1.4
		var strand := _bezier(neck + Vector2(-8 - offset, -1), neck + Vector2(-11 - offset - flow * 0.4, 12), tip + Vector2(-2 - offset, 3), tip + Vector2(2 - offset, -2), 14)
		_line(strand, HAIR_LIGHT.darkened(i * 0.08), 0.3)
	var wisp := _bezier(neck + Vector2(-9, -3), neck + Vector2(-18 - flow * 0.6, 9), tip + Vector2(-7, -2), tip + Vector2(-3, 2), 14)
	_line(wisp, HAIR_LIGHT, 0.35)


func _clothing() -> void:
	var neck: Vector2 = _render.neck
	var waist: Vector2 = _render.waist
	var tail := float(_render.tail)
	var hem := float(_render.hem)
	var volume := float(_render.volume)
	var fold := float(_render.fold)
	var opening := float(_render.page_open)
	var front := waist + Vector2(14 + volume * 0.6 - maxf(0, opening) * 0.65, 33 - hem * 0.70)
	var rear := waist + Vector2(-16 - tail * 0.82, 26 - tail * 0.60)
	# 后页有自己的弧面与内侧；两条叠页的尖端不随同一个刚体一起摇。
	var rear_page := _path(waist + Vector2(-5, 3), [[waist + Vector2(-13, 9), rear + Vector2(-2, -6), rear + Vector2(-2, -1)], [rear + Vector2(0, 3), rear + Vector2(8, 1), waist + Vector2(-4, 23 - hem * 0.55)], [waist + Vector2(-4, 16), waist + Vector2(-3, 9), waist + Vector2(-5, 3)]])
	_shape(rear_page, LINING, LINING_DARK, 0.5)
	var back_leaf := _path(waist + Vector2(-5, 4), [[waist + Vector2(-13, 8), rear + Vector2(-1, -5 - fold * 0.2), rear + Vector2(0, -2 - fold * 0.2)], [rear + Vector2(2, 0), waist + Vector2(-10, 17), waist + Vector2(-3, 20)], [waist + Vector2(-3, 13), waist + Vector2(-2, 9), waist + Vector2(-5, 4)]])
	_shape(back_leaf, LINING_DARK.lightened(0.10), LINING_DARK, 0.45)
	# 连续的肩腰裙面：前缘因收膝隆起，底边因蹬离上扬，主剪影本身参与表演。
	var main := _path(neck + Vector2(-3.5, 0), [[neck + Vector2(4.4, -0.2), neck + Vector2(7.7, 8), waist + Vector2(6, -2)], [waist + Vector2(11 + volume, 6), front + Vector2(14 + volume * 0.2, -9), front], [front + Vector2(-8, 4), rear + Vector2(13, 9 + fold * 0.08), rear + Vector2(1, 1)], [rear + Vector2(7, -7), waist + Vector2(-7, 8), waist + Vector2(-6, -2)], [waist + Vector2(-6, -13), neck + Vector2(-7, 6), neck + Vector2(-3.5, 0)]])
	_shape(main, CLOTH, CLOTH_EDGE, 0.55)
	# 翻面是独立颜色轮廓，不能靠整件衣服缩放冒充。
	var inner := _path(front + Vector2(-10, 1), [[front + Vector2(-5, 2.0), front + Vector2(-1, 1.5), front], [front + Vector2(-2, -2), front + Vector2(-5, -fold * 0.18), front + Vector2(-10, 1)]])
	_shape(inner, LINING.lightened(0.18))
	var seam := _bezier(waist + Vector2(1, 0), waist + Vector2(3, 8), front + Vector2(-8, -5), front + Vector2(-3, 0), 12)
	_line(seam, CLOTH_EDGE.lightened(0.1), 0.4)
	# 小叶墨纹跟随衣页曲面，而不是贴在屏幕上的刚直图案。
	var stem_start := waist + Vector2(4, 13 - hem * 0.17)
	var stem_end := front + Vector2(-5, -2)
	_line(_bezier(stem_start, stem_start + Vector2(1, 5), stem_end + Vector2(-2, -4), stem_end, 10), Color("8c8b75"), 0.55)
	for i in 3:
		var t := 0.2 + i * 0.23
		var center := stem_start.lerp(stem_end, t)
		var direction := Vector2(-3.3 if i % 2 == 0 else 3.2, -2.7)
		var leaf := _path(center, [[center + direction * 0.35 + Vector2(0, -1), center + direction * 0.8, center + direction], [center + direction * 0.6 + Vector2(0, 1.4), center + direction * 0.2 + Vector2(0, 1), center]])
		_shape(leaf, Color("a0a18b"))


func _draw() -> void:
	if _render.is_empty():
		return
	render_shape_failures = 0
	_leg("far", INK.lightened(0.16))
	_arm("far", true)
	_leg("near", INK)
	_hair()
	_clothing()
	_arm("near", false)
	var neck: Vector2 = _render.neck
	_shape(_path(neck + Vector2(-3, -3), [[neck + Vector2(0, -4), neck + Vector2(2, -3), neck + Vector2(2, 3)], [neck + Vector2(1, 5), neck + Vector2(-3, 4), neck + Vector2(-3, -3)]]), SKIN)
	var collar := _path(neck + Vector2(-5.5, -0.5), [[neck + Vector2(-1, -1.5), neck + Vector2(5, 1), neck + Vector2(5, 3.5)], [neck + Vector2(4, 6), neck + Vector2(-3, 4.2), neck + Vector2(-5.5, 3)], [neck + Vector2(-6.1, 2), neck + Vector2(-6, 0), neck + Vector2(-5.5, -0.5)]])
	_shape(collar, Color("b34237"), Color("8d3d38"), 0.45)
