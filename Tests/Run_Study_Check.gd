extends Node2D
## 此检查只看接触与循环连续的底线，不能判定优雅或美术质量。

const RUN = preload("res://Component/Player/RunStudy/Authored_Run.gd")
const PLAYER = preload("res://Component/Player/RunStudy/Traveler_Run_Study.tscn")
var failures := 0


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("RUN_STUDY_CHECK: " + message)


func _ready() -> void:
	_run.call_deferred()


func _wait() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame


func _run() -> void:
	var seam_error := 0.0
	var p0: Dictionary = RUN.sample(0)
	var p1: Dictionary = RUN.sample(1.0 - 0.00001)
	for key in p0:
		if p0[key] is Vector2:
			seam_error = maxf(seam_error, Vector2(p0[key]).distance_to(p1[key]))
	_check(seam_error < 0.01, "循环位置首尾连续")
	var maximum_speed_jump := 0.0
	for t: float in RUN.TIMES:
		var before: Dictionary = RUN.sample(t - 0.0001)
		var center: Dictionary = RUN.sample(t)
		var after: Dictionary = RUN.sample(t + 0.0001)
		for key in ["hip", "neck", "near_knee", "far_knee"]:
			var incoming := (Vector2(center[key]) - Vector2(before[key])) / 0.0001
			var outgoing := (Vector2(after[key]) - Vector2(center[key])) / 0.0001
			maximum_speed_jump = maxf(maximum_speed_jump, incoming.distance_to(outgoing))
	_check(maximum_speed_jump < 1.0, "不等相段插值速度连续")
	var ground := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(5000, 100)
	collision.shape = rectangle
	collision.position.y = 50
	ground.add_child(collision)
	add_child(ground)
	var player := PLAYER.instantiate() as PlayerController
	player.position.y = -0.1
	add_child(player)
	player.set_collision_group(1)
	var visual := player.get_node("Visual_Body/Traveler")
	Input.action_press("move_right")
	Input.action_press("sprint")
	var contact_points: Array = [null, null]
	var contact_cycle := [-999, -999]
	var max_slide := 0.0
	var max_heel_lift := 0.0
	for frame in 150:
		await _wait()
		for leg in 2:
			var shifted: float = float(visual.distance_total) / RUN.STRIDE + leg * 0.5
			var phase := fposmod(shifted, 1.0)
			var side := "near" if leg == 0 else "far"
			var foot: Vector2 = player.global_position + Vector2(visual.pose[side + "_ankle"])
			if phase < RUN.STANCE:
				if contact_cycle[leg] == int(floor(shifted)):
					max_slide = maxf(max_slide, foot.distance_to(contact_points[leg]))
				else:
					contact_cycle[leg] = int(floor(shifted))
					contact_points[leg] = foot
			max_heel_lift = maxf(max_heel_lift, -float(visual.pose[side + "_ankle"].y))
	_check(absf(player.velocity.x - 320) < 0.001, "真实速度320")
	_check(max_slide < 0.01, "支撑脚世界位置稳定")
	_check(max_heel_lift > 25, "明确后跟收回，非低扫地")
	print("RUN_STUDY_CHECK: seam=%.6f derivative_delta=%.4f contact_slide=%.6f heel_lift=%.2f; %d failures" % [seam_error, maximum_speed_jump, max_slide, max_heel_lift, failures])
	Input.action_release("move_right")
	Input.action_release("sprint")
	get_tree().quit(0 if failures == 0 else 1)
