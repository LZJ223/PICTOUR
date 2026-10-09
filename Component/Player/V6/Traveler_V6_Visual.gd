extends Node2D
## 连续分件位图皮肤：原纹理与固定近/远肢体，物理帧求姿态、显示帧插值网格。

const GAIT = preload("res://Component/Player/V6/Gentle_Gait.gd")
const SKIN_PATH := "res://Art/Player/V6/Skin_Layout.json"
@export var debug_joints := false
@onready var player: PlayerController = get_parent().get_parent()
var visual_facing := 1
var collar_offset := Vector2(-2, -78)
var stride_phase := 0.0
var gait_blend := 0.0
var measured_distance := 0.0
var skin_ready := false
var pose: Dictionary = {}
var previous_pose: Dictionary = {}
var motion_events := {"start": 0, "land": 0, "stop": 0}
var state_name := "idle"
var activity := 0.0
var _gait = GAIT.new()
var _parts: Array[Dictionary] = []
var _previous_position := Vector2.ZERO
var _previous_input := 0.0
var _support_seen := false
var _unsupported_time := 0.0
var _committed_air := false
var _previous_tangent := Vector2.RIGHT
var _step_offset := 0.0
var _center_y := 0.0
var _hair_motion := 0.0
var _hem_motion := 0.0
var _stop_pending := false
var _air_blend := 0.0
var _air_start: Dictionary = {}


func _ready() -> void:
	process_physics_priority = 1
	_previous_position = player.global_position
	_load_skin()
	pose = _gait.sample(player.global_position, 1, 0, 0, false, 0, 0, _ground_at)
	previous_pose = pose.duplicate(true)
	_update_collar()


func _ground_at(world_x: float) -> Dictionary:
	var predicted_y := player.global_position.y + _previous_tangent.y / maxf(0.1, _previous_tangent.x) * (world_x - player.global_position.x)
	var ray := PhysicsRayQueryParameters2D.create(Vector2(world_x, predicted_y - 28), Vector2(world_x, predicted_y + 42), player.collision_mask, [player.get_rid()])
	ray.collide_with_areas = false
	var hit := player.get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and Vector2(hit.normal).dot(Vector2.UP) < 0.68:
		return {}
	return hit


func _physics_process(delta: float) -> void:
	if player.UAV_activated:
		return
	previous_pose = pose.duplicate(true)
	var displacement := player.global_position - _previous_position
	var teleported := displacement.length() > 100.0
	var grounded := player.is_on_floor()
	var was_air := _committed_air
	var intent: float = float(player.get_meta("animation_input_axis", Input.get_axis("move_left", "move_right")))
	if teleported:
		_gait.reset()
		_step_offset = 0.0
		_support_seen = grounded
		_committed_air = not grounded
		_unsupported_time = 0.0
		_previous_input = intent
		activity = 0.0
	if grounded:
		if _support_seen and _committed_air:
			motion_events.land += 1
			_gait.reset()
		_support_seen = true
		_committed_air = false
		_unsupported_time = 0.0
	else:
		_unsupported_time += delta
		if not _support_seen or player.velocity.y < -150.0 or _unsupported_time > 0.05:
			_committed_air = true
	var supported := grounded or (_support_seen and not _committed_air)
	if _committed_air and not was_air:
		_air_start = previous_pose.duplicate(true)
		_air_blend = 0.0
	var tangent := _previous_tangent
	if grounded:
		var normal := player.get_floor_normal()
		tangent = Vector2(-normal.y, normal.x).normalized()
		if tangent.x < 0:
			tangent = -tangent
	measured_distance = 0.0
	if supported and not teleported and absf(displacement.x) > 0.001:
		measured_distance = absf(displacement.dot((_previous_tangent + tangent).normalized()))
	var speed := measured_distance / maxf(delta, 0.001)
	if speed > 12.0 and signf(displacement.x) != visual_facing:
		visual_facing = int(signf(displacement.x))
		_gait.reset()
	elif speed < 3.0 and absf(intent) > 0.1 and int(signf(intent)) != visual_facing:
		visual_facing = int(signf(intent))
		_gait.reset()
	if absf(intent) > 0.1 and absf(_previous_input) <= 0.1 and activity < 0.1 and supported:
		_gait.cycle = floorf(_gait.cycle) + 0.25
		_gait.phase = 0.25
		_gait.reset()
		motion_events.start += 1
		_stop_pending = false
	if absf(intent) < 0.1 and absf(_previous_input) > 0.1:
		_stop_pending = true
	if _stop_pending and speed < 3.0:
		motion_events.stop += 1
		_stop_pending = false
	var running := player.is_running or player.dash_active or speed > 240.0
	gait_blend = move_toward(gait_blend, 1.0 if running else 0.0, delta / 0.16)
	activity = move_toward(activity, 1.0 if measured_distance > 0.025 else 0.0, delta / 0.14)
	if measured_distance > 0.025:
		_gait.advance(measured_distance, gait_blend, tangent)
	stride_phase = _gait.phase
	_step_offset = move_toward(_step_offset, 0.0, delta * 150.0)
	if "step_up_height" in player:
		_step_offset = minf(12.0, _step_offset + float(player.get("step_up_height")))
	var center := _ground_at(player.global_position.x) if supported else {}
	if not center.is_empty():
		_center_y = lerpf(_center_y, clampf(float(center.position.y) - player.global_position.y, -8, 12), 1.0 - exp(-delta * 28.0))
	elif not supported:
		_center_y = move_toward(_center_y, 0.0, delta * 90.0)
	pose = _gait.sample(player.global_position, visual_facing, gait_blend, _gait.smooth01(activity), supported, _center_y, _step_offset, _ground_at, tangent)
	if not supported:
		_air_blend = move_toward(_air_blend, 1.0, delta / 0.14)
		var ascent := clampf((player.velocity.y + 610.0) / 1200.0, 0.0, 1.0)
		for side in ["near", "far"]:
			var target := Vector2((-7.0 + 3.0 * ascent) if side == "near" else (9.0 - 2.0 * ascent), (-6.0 - 2.0 * sin(ascent * PI)) if side == "near" else (-10.0 + 3.0 * ascent))
			target.x *= visual_facing
			var start: Vector2 = _air_start.get(side + "_ankle", target)
			pose[side + "_ankle"] = start.lerp(target, _gait.smooth01(_air_blend))
			pose[side + "_toe"] = pose[side + "_ankle"] + Vector2(4.3 * visual_facing, 1.0)
			pose[side + "_knee"] = _gait.knee(pose.hip, pose[side + "_ankle"], visual_facing)
	else:
		_air_blend = 0.0
	_hair_motion = lerpf(_hair_motion, float(pose.hair), 1.0 - exp(-delta * 7.0))
	_hem_motion = lerpf(_hem_motion, float(pose.hem), 1.0 - exp(-delta * 12.0))
	pose.hair = _hair_motion
	pose.hem = _hem_motion
	state_name = "air" if not supported else ("idle" if activity < 0.1 else ("run" if gait_blend > 0.5 else "walk"))
	_update_collar()
	if teleported:
		previous_pose = pose.duplicate(true)
	_previous_position = player.global_position
	_previous_tangent = tangent
	_previous_input = intent


func reset_after_restore() -> void:
	visual_facing = player.facing_direction
	gait_blend = 1.0 if player.is_running or player.dash_active else 0.0
	_stop_pending = false
	_air_blend = 0.0
	_air_start.clear()
	_hair_motion = 0.0
	_hem_motion = 0.0
	_gait.reset()
	_gait.cycle = 0.25
	_gait.phase = 0.25
	stride_phase = 0.25
	activity = 0.0
	_step_offset = 0.0
	_previous_position = player.global_position
	_previous_input = 0.0
	_unsupported_time = 0.0
	_support_seen = player.is_on_floor()
	_committed_air = not _support_seen
	_previous_tangent = Vector2.RIGHT
	var hit := _ground_at(player.global_position.x)
	_center_y = clampf(float(hit.position.y) - player.global_position.y, -8, 12) if not hit.is_empty() else 0.0
	pose = _gait.sample(player.global_position, visual_facing, gait_blend, 0, _support_seen, _center_y, 0, _ground_at)
	previous_pose = pose.duplicate(true)
	_update_collar()


func _update_collar() -> void:
	if pose.has("neck"):
		collar_offset = Vector2(pose.neck) + Vector2(-3 * visual_facing, 1)


func _load_skin() -> void:
	if not FileAccess.file_exists(SKIN_PATH):
		push_warning("V6等待分件原图与Skin_Layout；未将结构占位图当最终美术。")
		return
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SKIN_PATH))
	for definition: Dictionary in layout.parts:
		var texture: Texture2D = load(definition.path)
		if texture == null:
			push_error("V6分件读取失败：" + str(definition.path))
			return
		var region: Array = definition.region
		var rect := Rect2(region[0], region[1], region[2], region[3])
		var grid: Array = definition.get("grid", [4, 10])
		var polygon := Polygon2D.new()
		polygon.name = definition.name
		polygon.z_index = int(definition.get("z", 0))
		polygon.texture = texture
		polygon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		if definition.has("tint"):
			var tint: Array = definition.tint
			polygon.modulate = Color(tint[0], tint[1], tint[2], tint[3])
		var uv := PackedVector2Array()
		var rest := PackedVector2Array()
		var faces: Array[PackedInt32Array] = []
		var pivot := Vector2(definition.pivot[0], definition.pivot[1])
		var art_scale: float = float(definition.scale)
		for y in int(grid[1]) + 1:
			for x in int(grid[0]) + 1:
				var p := rect.size * Vector2(float(x) / int(grid[0]), float(y) / int(grid[1]))
				uv.append(rect.position + p)
				rest.append((p - pivot) * art_scale)
		for y in int(grid[1]):
			for x in int(grid[0]):
				var i: int = y * (int(grid[0]) + 1) + x
				faces.append(PackedInt32Array([i, i + 1, i + int(grid[0]) + 2, i + int(grid[0]) + 1]))
		polygon.uv = uv
		polygon.polygons = faces
		polygon.polygon = rest
		add_child(polygon)
		_parts.append({"node": polygon, "definition": definition, "rest": rest})
	skin_ready = not _parts.is_empty()


func _process(_delta: float) -> void:
	if pose.is_empty() or previous_pose.is_empty():
		return
	var alpha := Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0
	var render: Dictionary = {}
	for key in pose:
		if pose[key] is Vector2:
			render[key] = Vector2(previous_pose[key]).lerp(pose[key], alpha)
		else:
			render[key] = lerpf(float(previous_pose[key]), float(pose[key]), alpha)
	for part in _parts:
		_render_part(part, render)
	if debug_joints:
		queue_redraw()


func _render_part(part: Dictionary, render: Dictionary) -> void:
	var definition: Dictionary = part.definition
	var start: Vector2 = render[definition.attach]
	var vertices := PackedVector2Array()
	var rest: PackedVector2Array = part.rest
	var stretch := definition.has("end")
	var source_axis := Vector2.DOWN
	var target_axis := Vector2.DOWN
	var target_length := 1.0
	var source_length := 1.0
	if stretch:
		var finish: Vector2 = render[definition.end]
		target_length = maxf(0.01, start.distance_to(finish))
		target_axis = (finish - start).normalized()
		source_axis = Vector2(definition.axis[0], definition.axis[1])
		source_length = source_axis.length() * float(definition.scale)
		source_axis = source_axis.normalized()
	var mode: String = definition.get("deform", "rigid")
	for p: Vector2 in rest:
		var destination: Vector2
		if stretch:
			var along := p.dot(source_axis) / maxf(source_length, 0.01)
			var side := p.dot(Vector2(source_axis.y, -source_axis.x)) * float(definition.get("width_scale", 1.0))
			if definition.has("centerline"):
				var source_y := p.y / float(definition.scale) + float(definition.pivot[1])
				var rows: Array = definition.centerline
				var center_x: float = float(rows[0][1])
				for row in range(1, rows.size()):
					if source_y <= float(rows[row][0]):
						center_x = lerpf(float(rows[row - 1][1]), float(rows[row][1]), clampf((source_y - float(rows[row - 1][0])) / (float(rows[row][0]) - float(rows[row - 1][0])), 0, 1))
						break
					center_x = float(rows[row][1])
				along = (source_y - float(definition.pivot[1])) / float(definition.axis[1])
				side = (p.x + (float(definition.pivot[0]) - center_x) * float(definition.scale)) * float(definition.get("width_scale", 1.0))
			destination = start + target_axis * (along * target_length) + Vector2(target_axis.y, -target_axis.x) * side * visual_facing
		else:
			var local := Vector2(p.x * visual_facing * float(definition.get("width_scale", 1.0)), p.y)
			if mode == "coat":
				var weight := smoothstep(4.0, 32.0, local.y)
				local.x += float(render.hem) * weight * float(definition.get("hem_weight", 1.0))
			elif mode == "hair":
				var weight := smoothstep(0.0, 40.0, local.y)
				local.x -= float(render.hair) * visual_facing * weight
			destination = start + local.rotated(float(render.lean))
		vertices.append(destination)
	(part.node as Polygon2D).polygon = vertices


func _draw() -> void:
	if not debug_joints or pose.is_empty():
		return
	for side in ["far", "near"]:
		var ink := Color("aaa09b") if side == "far" else Color("6c5862")
		draw_polyline(PackedVector2Array([pose[side + "_hip"], pose[side + "_knee"], pose[side + "_ankle"]]), ink, 1, true)
		draw_polyline(PackedVector2Array([pose[side + "_shoulder"], pose[side + "_elbow"], pose[side + "_hand"]]), ink, 1, true)
	draw_circle(pose.head, 6, Color("978890"), false, 1, true)
