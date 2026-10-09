extends "res://Component/Player/V6/Traveler_V6_Visual.gd"
## 使用同一C款PNG的独立姿态候选。借用V6的UV装载/显示插值，不运行其步态。

const RUN = preload("res://Component/Player/RunStudy/Authored_Run.gd")
@export var preview_phase := -1.0
var run_phase := 0.0
var distance_total := 0.0


func _ready() -> void:
	process_physics_priority = 1
	_previous_position = player.global_position
	_load_skin()
	pose = RUN.sample(0)
	previous_pose = pose.duplicate(true)
	_update_collar()
	# 后衣片不改变PNG，通过露出原有梅灰内侧来阅读翻面。
	for part in _parts:
		if part.definition.name == "rear_coat":
			part.node.modulate = Color(0.90, 0.88, 0.93)


func _physics_process(_delta: float) -> void:
	previous_pose = pose.duplicate(true)
	var dx := player.global_position.x - _previous_position.x
	if absf(dx) < 100:
		distance_total += absf(dx)
	run_phase = fposmod(distance_total / RUN.STRIDE, 1.0) if preview_phase < 0 else preview_phase
	pose = RUN.sample(run_phase)
	stride_phase = run_phase
	state_name = "作者化跑动候选"
	visual_facing = 1
	_update_collar()
	_previous_position = player.global_position


func _render_part(part: Dictionary, render: Dictionary) -> void:
	var name: String = part.definition.name
	if name == "bodice":
		_draw_bodice(part, render)
		return
	if "thigh" in name or "shin" in name:
		_draw_soft_leg(part, render)
		return
	if name in ["front_coat", "rear_coat", "rear_hair", "head"]:
		var vertices := PackedVector2Array()
		var definition: Dictionary = part.definition
		var start: Vector2 = render[definition.attach]
		for p: Vector2 in part.rest:
			var local := Vector2(p.x * float(definition.get("width_scale", 1)), p.y)
			var amount := smoothstep(0, 31, local.y)
			if name == "front_coat":
				# 裙面包住折回的膝，不再只是腰上悬着的静态三角片。
				var arch := sin(clampf(local.y / 34.0, 0, 1) * PI)
				local.x *= 1.0 + 0.30 * amount
				local.x += arch * (6.0 + float(render.volume) * 0.85) - amount * float(render.hem) * 0.25
				local.y = local.y * 1.19 - amount * float(render.front_lift) * 0.24
			elif name == "rear_coat":
				local.x *= 1.0 + 0.22 * amount
				local.x -= amount * (7.0 + float(render.hem) * 1.25)
				local.y = local.y * 1.12 - amount * float(render.rear_lift) * 0.5
			elif name == "rear_hair":
				local.x -= smoothstep(0, 35, local.y) * float(render.hair)
				local.y -= smoothstep(0, 35, local.y) * float(render.hair) * 0.30
			var angle := float(render.head_lean) if name == "head" else float(render.lean)
			vertices.append(start + local.rotated(angle))
		part.node.polygon = vertices
		return
	super._render_part(part, render)


func _draw_soft_leg(part: Dictionary, render: Dictionary) -> void:
	var definition: Dictionary = part.definition
	var side := "near" if "near" in String(definition.name) else "far"
	var hip: Vector2 = render[side + "_hip"]
	var knee: Vector2 = render[side + "_knee"]
	var ankle: Vector2 = render[side + "_ankle"]
	var thigh := "thigh" in String(definition.name)
	var a := hip if thigh else knee
	var b := knee if thigh else ankle
	var knee_tangent := (ankle - hip).normalized()
	var segment := b - a
	var handle := minf(5.0, segment.length() * 0.19)
	var c1 := a + segment.normalized() * handle if thigh else a + knee_tangent * handle
	var c2 := b - knee_tangent * handle if thigh else b - segment.normalized() * handle
	var vertices := PackedVector2Array()
	var rows: Array = definition.centerline
	for p: Vector2 in part.rest:
		var source_y := p.y / float(definition.scale) + float(definition.pivot[1])
		var x: float = float(rows[0][1])
		for row in range(1, rows.size()):
			if source_y <= float(rows[row][0]):
				x = lerpf(float(rows[row - 1][1]), float(rows[row][1]), clampf((source_y - float(rows[row - 1][0])) / (float(rows[row][0]) - float(rows[row - 1][0])), 0, 1))
				break
			x = float(rows[row][1])
		var u := clampf((source_y - float(definition.pivot[1])) / float(definition.axis[1]), 0, 1)
		var line := a * pow(1 - u, 3) + c1 * 3 * pow(1 - u, 2) * u + c2 * 3 * (1 - u) * u * u + b * u * u * u
		var tangent := ((c1 - a) * 3 * pow(1 - u, 2) + (c2 - c1) * 6 * (1 - u) * u + (b - c2) * 3 * u * u).normalized()
		var cross := (p.x + (float(definition.pivot[0]) - x) * float(definition.scale)) * float(definition.get("width_scale", 1))
		vertices.append(line + Vector2(tangent.y, -tangent.x) * cross)
	part.node.polygon = vertices


func show_pose(phase: float) -> void:
	preview_phase = phase
	run_phase = phase
	pose = RUN.sample(phase)
	previous_pose = pose.duplicate(true)
	_update_collar()
	_process(0.0)


func _draw_bodice(part: Dictionary, render: Dictionary) -> void:
	var definition: Dictionary = part.definition
	var a: Vector2 = render.neck
	var b: Vector2 = render.waist
	var c1 := a + Vector2(-1.0 + float(render.spine) * 0.3, 8)
	var c2 := b + Vector2(float(render.spine), -9)
	var axis := Vector2(definition.axis[0], definition.axis[1]).normalized()
	var length := Vector2(definition.axis[0], definition.axis[1]).length() * float(definition.scale)
	var vertices := PackedVector2Array()
	for p: Vector2 in part.rest:
		var u := clampf(p.dot(axis) / length, 0, 1)
		var cross := p.dot(Vector2(axis.y, -axis.x))
		var center := a * pow(1 - u, 3) + c1 * 3 * pow(1 - u, 2) * u + c2 * 3 * (1 - u) * u * u + b * u * u * u
		var tangent := ((c1 - a) * 3 * pow(1 - u, 2) + (c2 - c1) * 6 * (1 - u) * u + (b - c2) * 3 * u * u).normalized()
		vertices.append(center + Vector2(tangent.y, -tangent.x) * cross)
	part.node.polygon = vertices
