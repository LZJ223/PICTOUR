extends Node
## 连续真实按键穿过Story缓坡，检查动画相位，不以接地连续冒充动作连续。

const GAME := preload("res://Story_Garden_Game.tscn")
var game: Node2D
var player: PlayerController
var visual: AnimatedSprite2D
var checks := 0
var failures := 0
var trace: FileAccess
var label: Label
var capture := false


func _ready() -> void:
	call_deferred("_run")


func _wait(count: int) -> void:
	for tick in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	print("SLOPE_GAIT %s: %s" % ["PASS" if condition else "FAIL", message])
	if not condition:
		failures += 1


func _run() -> void:
	capture = "--gait-capture" in OS.get_cmdline_user_args()
	var suffix := "before" if "--baseline" in OS.get_cmdline_user_args() else "after"
	DirAccess.make_dir_recursive_absolute("res://Exports/Slope_Gait")
	trace = FileAccess.open("res://Exports/Slope_Gait/%s.csv" % suffix, FileAccess.WRITE)
	trace.store_csv_line(PackedStringArray(["route","tick","x","y","vx","dx","floor","animation","frame","phase","transition","transition_left","phase_error"]))
	game = GAME.instantiate()
	game.get_node("Level").set("enable_bookmarks", false)
	add_child(game)
	player = game.get_node("Player")
	visual = player.get_node("Visual_Body/Traveler")
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	label = Label.new()
	label.position = Vector2(30, 75)
	label.add_theme_color_override("font_color", Color("592f3f"))
	label.add_theme_font_size_override("font_size", 17)
	canvas.add_child(label)
	add_child(canvas)
	await _wait(20)
	await _route("walk_right", Vector2(310, 580), 1.0, false, 705.0)
	await _route("walk_left", Vector2(705, 550), -1.0, false, 310.0)
	await _route("run_right", Vector2(310, 580), 1.0, true, 705.0)
	await _route("run_left", Vector2(705, 550), -1.0, true, 310.0)
	await _route("court_walk", Vector2(1030, 520), 1.0, false, 1300.0)
	await _route("court_run", Vector2(1300, 480), -1.0, true, 1030.0)
	await _route("far_walk", Vector2(1985, 520), 1.0, false, 2230.0)
	await _route("far_run", Vector2(2230, 484), -1.0, true, 2050.0)
	await _route("contact_blink", Vector2(310, 580), 1.0, false, 705.0, true)
	await _semantic_actions()
	_release()
	trace.close()
	print("SLOPE_GAIT: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _route(title: String, start: Vector2, direction: float, running: bool, goal: float, contact_blink := false) -> void:
	_release()
	player.position = start + Vector2(0, -2)
	player.reset_motion()
	game.get_node("System").reset_view_interpolation()
	await _wait(20)
	Input.action_press("move_right" if direction > 0.0 else "move_left")
	if running:
		Input.action_press("sprint")
	var interruptions := 0
	var phase_jumps := 0
	var zero_velocity_moves := 0
	var lost_floor := 0
	var observed: Dictionary = {}
	var cycles := 0
	var completed := false
	var wrong_action := 0
	var expected_action := &"run" if running else &"walk"
	for tick in 260:
		var ground: StaticBody2D = game.get_node("Level/Mid/GroveBank")
		var old_layer := ground.collision_layer
		var blink_now: bool = contact_blink and tick in [24, 49, 74]
		if blink_now:
			# 明确的受控故障注入；不声称原关卡必然发生一帧碰撞层丢失。
			ground.collision_layer = 0
		var previous: float = visual.get("stride_phase")
		var old_position := player.position
		await _wait(1)
		if blink_now:
			ground.collision_layer = old_layer
		var delta_position := player.position - old_position
		var distance: float = visual.get("measured_distance")
		var blend: float = visual.get("gait_blend")
		var length := lerpf(float(visual.get("walk_stride")), float(visual.get("run_stride")), blend)
		var expected := fposmod(previous + distance / length, 1.0)
		var actual: float = visual.get("stride_phase")
		var error := absf(wrapf(actual - expected, -0.5, 0.5))
		var transition: StringName = visual.get("_transition")
		var left: float = visual.get("_transition_left")
		if tick > 12:
			if error > 0.005:
				phase_jumps += 1
			if left > 0.0:
				interruptions += 1
			if not player.is_on_floor():
				lost_floor += 1
			if absf(player.velocity.x) < 3.0 and absf(delta_position.x) > 0.2:
				zero_velocity_moves += 1
			if visual.animation != expected_action:
				wrong_action += 1
			else:
				observed[visual.frame] = true
			if actual < previous and error < 0.005:
				cycles += 1
		trace.store_csv_line(PackedStringArray([title, str(tick), str(player.position.x), str(player.position.y), str(player.velocity.x), str(delta_position.x), str(player.is_on_floor()), str(visual.animation), str(visual.frame), str(actual), str(transition), str(left), str(error)]))
		label.text = "%s   %s:%02d   phase %.3f   vx %.1f / dx %.2f   %s %.3f" % [title, visual.animation, visual.frame, actual, player.velocity.x, delta_position.x, transition, left]
		if capture and tick == 60:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://Exports/Slope_Gait/%s.png" % title)
		if (player.position.x - goal) * direction >= 0.0:
			completed = true
			break
	_check(completed, title + "持续真实输入通过真实缓坡")
	_check(phase_jumps == 0, title + "相位不重启，异常次数=" + str(phase_jumps))
	_check(interruptions == 0 and wrong_action == 0, title + "不被起停/落地打断，transition=%d wrong_action=%d" % [interruptions, wrong_action])
	_check(observed.size() >= 14 and cycles >= 1, title + "实际播放完整循环，独立帧=%d cycles=%d" % [observed.size(), cycles])
	print("SLOPE_GAIT_METRIC: %s floor_loss=%d zero_velocity_despite_motion=%d" % [title, lost_floor, zero_velocity_moves])
	_release()
	await _wait(8)


func _semantic_actions() -> void:
	_release()
	player.position = Vector2(310, 578)
	player.reset_motion()
	game.get_node("System").reset_view_interpolation()
	await _wait(30)
	var old_events: Dictionary = visual.get("motion_events").duplicate()
	for cycle in 2:
		Input.action_press("move_right")
		await _wait(25)
		_release()
		await _wait(20)
	var events: Dictionary = visual.get("motion_events")
	_check(int(events.start) - int(old_events.start) == 2, "两次真正按键起步仅触发两次start")
	_check(int(events.brake) - int(old_events.brake) == 2, "两次松键减速到停仅触发两次brake")
	var land_before: int = int(events.land)
	Input.action_press("jump")
	await _wait(65)
	Input.action_release("jump")
	_check(int(visual.get("motion_events").land) - land_before == 1, "真正跳跃落地仅触发一次land")
	player.position = Vector2(2230, 482)
	player.reset_motion()
	game.get_node("System").reset_view_interpolation()
	await _wait(25)
	Input.action_press("move_left")
	Input.action_press("sprint")
	await _wait(70)
	var old_phase: float = visual.get("stride_phase")
	old_events = visual.get("motion_events").duplicate()
	await _wait(35)
	_check(player.is_on_wall() and absf(player.velocity.x) < 0.01, "真实ReturnRoot高侧壁保持实体阻挡")
	_check(is_equal_approx(old_phase, float(visual.get("stride_phase"))) and visual.animation == &"idle", "持续顶住真实侧壁时相位停止，稳定待机")
	_check(old_events == visual.get("motion_events"), "持续顶墙不反复start/brake/land")
	_release()


func _release() -> void:
	for action in ["move_left", "move_right", "sprint", "jump"]:
		Input.action_release(action)
