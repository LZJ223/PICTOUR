extends Node2D
## 风险验证：真实物理跳高、输入响应、围巾动态、PNG 动画和脚底锚。

const PLAYER := preload("res://Component/Player/Traveler_Large.tscn")
var player: PlayerController
var visual: AnimatedSprite2D
var scarf: Node2D
var failures: Array[String] = []
var checks: int = 0
var report: Dictionary = {"animations": {}, "captures": [], "metrics": {}}


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("f1e9d8"))
	var ground := StaticBody2D.new()
	ground.position = Vector2(1500, 550)
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(6000, 100)
	shape_node.shape = shape
	ground.add_child(shape_node)
	add_child(ground)
	player = PLAYER.instantiate()
	player.position = Vector2(300, 500)
	add_child(player)
	visual = player.get_node("Visual_Body/Traveler")
	scarf = player.get_node("Visual_Body/Scarf")
	call_deferred("_run")


func _run() -> void:
	await _tick(20)
	_check(player.is_on_floor(), "人物落地且脚底为根节点")
	_check((player.body_collision_box.shape as RectangleShape2D).size == Vector2(30, 86), "碰撞 30×86")
	_check(player.variable_jump_height, "新场景可变跳高开启")
	_test_frames()
	await _capture("idle")
	var idle_points: PackedVector2Array = scarf.get_ribbon_points()
	Input.action_press("move_right")
	await _tick(7)
	_check(player.velocity.x >= 249, "步行在七个物理帧内达到250")
	_check(visual.animation == &"walk", "步行动作")
	await _capture("walk")
	Input.action_press("sprint")
	await _tick(1)
	_check(player.is_running and player.velocity.x > 250, "Shift 按下首帧立即加速")
	await _tick(18)
	_check(is_equal_approx(player.velocity.x, 400), "长按400奔跑")
	_check(visual.animation == &"run", "奔跑动作")
	var running_points: PackedVector2Array = scarf.get_ribbon_points()
	_check(running_points[-1].x < -50, "奔跑时围巾尾部伸展到身后")
	_check(running_points[-1].distance_to(idle_points[-1]) > 15, "围巾跑动与待机姿态明显不同")
	await _capture("run")
	var tail_y_min: float = 999
	var tail_y_max: float = -999
	for i in 24:
		await _tick(1)
		var current: PackedVector2Array = scarf.get_ribbon_points()
		tail_y_min = minf(tail_y_min, current[-1].y)
		tail_y_max = maxf(tail_y_max, current[-1].y)
	report.metrics.running_scarf_tail_sway = tail_y_max - tail_y_min
	_check(tail_y_max - tail_y_min > 3.0, "持续匀速跑动时围巾仍有明显波动")
	Input.action_release("move_right")
	Input.action_press("move_left")
	await _tick(1)
	_check(visual.flip_h, "转身立即朝左")
	_check(visual.animation == &"turn", "快速转身具有明确关键姿态")
	var turning_points: PackedVector2Array = scarf.get_ribbon_points()
	_check(turning_points[-1].x < 0, "转身首帧保留围巾原方向惯性")
	await _capture("turn")
	await _tick(35)
	_check(scarf.get_ribbon_points()[-1].x > 45, "左跑后丝带自然换向")
	Input.action_release("move_left")
	Input.action_release("sprint")
	await _tick(1)
	_check(not player.dash_active, "长按释放不附加冲刺")
	_check(visual.animation == &"brake", "急刹有姿态过渡")
	await _capture("brake")
	await _reset()
	var full_height: float = await _jump_height(false)
	var short_height: float = await _jump_height(true)
	report.metrics.full_jump_height = full_height
	report.metrics.short_jump_height = short_height
	_check(full_height > 105 and full_height < 112, "满跳约108像素=90px身高的1.2倍")
	_check(short_height > 30 and short_height < full_height * 0.65, "短按Space降低跳高")
	await _reset()
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _tick(3)
	Input.action_release("sprint")
	await _tick(1)
	_check(player.dash_active and is_equal_approx(player.velocity.x, 560), "短按Shift释放触发560冲刺")
	await _capture("dash")
	Input.action_release("move_right")
	await _tick(25)
	_check(not player.dash_active and absf(player.velocity.x) < 1, "冲刺结束能及时停稳")
	await _reset()
	var original_shape: PackedVector2Array = scarf.get_ribbon_points()
	player.global_position = Vector2(800, 500)
	player.reset_motion()
	player.reset_physics_interpolation()
	await _tick(1)
	var restored_shape: PackedVector2Array = scarf.get_ribbon_points()
	_check(restored_shape[-1].length() < 140 and restored_shape[0].distance_to(original_shape[0]) < 10, "传送自动重置丝带，不拖出巨大尾迹")
	var enabled := player.UAV_activate(true)
	_check(enabled and not visual.is_visible_in_tree() and not scarf.is_visible_in_tree(), "无人机接口兼容并隐藏整个人物")
	player.UAV_activate(false)
	await _tick(2)
	_check(visual.is_visible_in_tree(), "回到人物恢复外观")
	_release()
	report["checks"] = checks
	report["failures"] = failures
	var file := FileAccess.open("res://Exports/Traveler_V2_Check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("TRAVELER_V2_CHECK: %d checks, %d failures; full_jump=%.3f short_jump=%.3f" % [checks, failures.size(), full_height, short_height])
	for failure in failures:
		push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_frames() -> void:
	for action in visual.sprite_frames.get_animation_names():
		var unique: Dictionary = {}
		var bounds: Array = []
		var grounded: bool = action in [&"idle", &"walk", &"run", &"land", &"brake", &"turn", &"dash"]
		var count: int = visual.sprite_frames.get_frame_count(action)
		var foot_min: int = 999
		var foot_max: int = -1
		for index in count:
			var atlas := visual.sprite_frames.get_frame_texture(action, index) as AtlasTexture
			var image: Image = atlas.atlas.get_image().get_region(Rect2i(atlas.region))
			var rect := image.get_used_rect()
			var digest := HashingContext.new()
			digest.start(HashingContext.HASH_SHA256)
			digest.update(image.get_data())
			unique[digest.finish().hex_encode()] = true
			foot_min = mini(foot_min, rect.end.y)
			foot_max = maxi(foot_max, rect.end.y)
			bounds.append([rect.position.y, rect.end.y])
		_check(unique.size() == count, "%s %d帧均有独立姿态" % [action, count])
		if grounded:
			_check(foot_min == 236 and foot_max == 236, "%s所有帧脚底锚定236" % action)
		report.animations[action] = {"frames": count, "unique": unique.size(), "bounds_y": bounds}
	_check(visual.sprite_frames.get_frame_count(&"walk") == 16 and visual.sprite_frames.get_frame_count(&"run") == 16, "走跑各16帧")


func _jump_height(short_jump: bool) -> float:
	await _reset()
	var start: float = player.global_position.y
	var highest: float = start
	Input.action_press("jump")
	await _tick(1)
	if short_jump:
		Input.action_release("jump")
	for i in 45:
		await _tick(1)
		highest = minf(highest, player.global_position.y)
		if not short_jump and i == 6:
			await _capture("rise")
		if not short_jump and i == 26:
			await _capture("fall")
	Input.action_release("jump")
	return start - highest


func _reset() -> void:
	_release()
	player.global_position = Vector2(300, 500)
	player.reset_motion()
	player.reset_physics_interpolation()
	await _tick(5)


func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("res://Exports/Traveler_V2_%s.png" % name)
	report.captures.append(name)


func _tick(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.0).timeout


func _release() -> void:
	for action in ["move_left", "move_right", "sprint", "jump"]:
		Input.action_release(action)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
