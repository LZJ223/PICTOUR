extends Node2D
## 真实 CharacterBody2D 跨步回归；--baseline 保留修复前 4px 卡脚复现。

const TRAVELER = preload("res://Component/Player/V5/Traveler_V5.tscn")
const STEP_CONTROLLER = preload("res://Component/Player/V5/Traveler_Step_Controller.gd")
const BASE_CONTROLLER = preload("res://Component/Player/Player_Controller.gd")
var player: PlayerController
var fixtures: Node2D
var checks := 0
var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TRAVELER_STEP: " + message)


func _wait(frames: int) -> void:
	for tick in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func _rectangle(rect: Rect2, layer := 1) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = layer
	body.position = rect.get_center()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	fixtures.add_child(body)
	var polygon := Polygon2D.new()
	var half := rect.size * 0.5
	polygon.polygon = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)])
	polygon.color = Color("86737d")
	body.add_child(polygon)
	return body


func _reset(start := Vector2(200, 490)) -> void:
	for action in ["move_right", "move_left", "sprint", "jump"]:
		Input.action_release(action)
	if is_instance_valid(fixtures):
		fixtures.queue_free()
		await _wait(2)
	fixtures = Node2D.new()
	add_child(fixtures)
	player.position = start
	player.reset_motion()
	player.reset_physics_interpolation()


func _run() -> void:
	player = TRAVELER.instantiate()
	# 基线显式使用旧脚本；场景切换到新控制器后仍可重现，而不是重新制造缺陷。
	player.set_script(BASE_CONTROLLER if "--baseline" in OS.get_cmdline_user_args() else STEP_CONTROLLER)
	player.move_speed = 180.0
	player.run_speed = 320.0
	player.dash_speed = 560.0
	player.jump_speed = 610.0
	player.acceleration = 2600.0
	player.friction_deceleration = 2800.0
	player.air_acceleration = 1400.0
	player.air_friction_deceleration = 500.0
	player.variable_jump_height = true
	add_child(player)
	if "--story-only" in OS.get_cmdline_user_args():
		await _story_case()
		_finish()
		return
	if "--angular-only" in OS.get_cmdline_user_args():
		await _angular_stone_case()
		_finish()
		return
	await _reset()
	_rectangle(Rect2(0, 500, 900, 200))
	_rectangle(Rect2(300, 496, 240, 4))
	await _wait(30)
	Input.action_press("move_right")
	await _wait(90)
	Input.action_release("move_right")
	print("TRAVELER_STEP_BASELINE: 4px stone, x=%.3f y=%.3f wall=%s grounded=%s" % [player.position.x, player.position.y, player.is_on_wall(), player.is_on_floor()])
	if "--baseline" in OS.get_cmdline_user_args():
		_check(player.position.x < 300, "旧控制器在4px障碍处被阻挡的复现")
		_finish()
		return
	_check(player.position.x > 400, "4px自然跨步可前进")
	for height: float in [4.0, 8.0, 12.0]:
		for direction: float in [-1.0, 1.0]:
			for running: bool in [false, true]:
				await _step_case(height, direction, running)
	await _blocked_case(13.0, 0.0, "高于12px的台阶")
	await _blocked_case(70.0, 0.0, "高墙")
	await _blocked_case(8.0, 6.0, "净空只有6px的8px台阶")
	# 4px台阶在6px头部净空中仍应通过；不能只用一律上抬12px的错误查询。
	await _step_case(4.0, 1.0, false, 6.0)
	player.set("max_step_height", 6.0)
	await _step_case(4.0, 1.0, false)
	await _blocked_case(8.0, 0.0, "非默认6px上限拒绝8px")
	player.set("max_step_height", 12.0)
	await _layer_case()
	await _air_case()
	await _gap_case()
	await _slope_case()
	await _angular_stone_case()
	await _dash_case()
	await _jump_case()
	await _story_case()
	_finish()


func _step_case(height: float, direction: float, running: bool, clearance := 0.0) -> void:
	await _reset(Vector2(200 if direction > 0 else 540, 485))
	_rectangle(Rect2(0, 500, 900, 200))
	_rectangle(Rect2(300, 500 - height, 140, height))
	if clearance > 0:
		_rectangle(Rect2(0, 350, 900, 64 - clearance))
	await _wait(30)
	var before: int = player.get("step_count")
	var action := "move_right" if direction > 0 else "move_left"
	Input.action_press(action)
	if running:
		Input.action_press("sprint")
	var maximum_rise := 0.0
	var up_air_frames := 0
	var was_stepped := false
	var minimum_up_speed := INF
	var beginning := player.position
	for tick in (62 if running else 110):
		await _wait(1)
		if float(player.get("step_up_height")) > 0.0:
			was_stepped = true
			minimum_up_speed = minf(minimum_up_speed, absf(player.velocity.x))
		if was_stepped and player.position.x > 310 and player.position.x < 425 and not player.is_on_floor():
			up_air_frames += 1
		maximum_rise = maxf(maximum_rise, 500.0 - player.position.y)
	Input.action_release(action)
	Input.action_release("sprint")
	var label := "%.0fpx %s %s" % [height, "右" if direction > 0 else "左", "跑" if running else "走"]
	_check((player.position.x > 470 if direction > 0 else player.position.x < 270), label + "越过并走下小石")
	_check(int(player.get("step_count")) > before and was_stepped, label + "触发自然跨步")
	_check(maximum_rise >= height - 0.2 and maximum_rise < height + 0.5, label + "落在真实踏面")
	_check(up_air_frames == 0, label + "跨上后不假离地")
	_check(minimum_up_speed > (300.0 if running else 170.0), label + "跨步不归零横向速度")
	_check(player.is_on_floor(), label + "下台后恢复真实地面")
	print("TRAVELER_STEP_CASE: %s move=%s rise=%.3f steps=%d air=%d speed=%.2f" % [label, str(player.position - beginning), maximum_rise, int(player.get("step_count")) - before, up_air_frames, minimum_up_speed])


func _blocked_case(height: float, clearance: float, label: String) -> void:
	await _reset()
	_rectangle(Rect2(0, 500, 900, 200))
	_rectangle(Rect2(300, 500 - height, 140, height))
	if clearance > 0:
		_rectangle(Rect2(0, 350, 900, 64 - clearance))
	await _wait(30)
	var before: int = player.get("step_count")
	Input.action_press("move_right")
	await _wait(75)
	Input.action_release("move_right")
	_check(player.position.x < 286 and player.position.x > 280, label + "保持墙体碰撞")
	_check(int(player.get("step_count")) == before, label + "不触发跨步")
	_check(player.position.y > 499.5, label + "不爬墙或穿顶棚")


func _layer_case() -> void:
	await _reset()
	_rectangle(Rect2(0, 500, 900, 200), 2)
	_rectangle(Rect2(300, 492, 140, 8), 1)
	player.set_collision_group(2)
	await _wait(30)
	var before: int = player.get("step_count")
	Input.action_press("move_right")
	await _wait(95)
	Input.action_release("move_right")
	_check(player.position.x > 460 and player.is_on_floor(), "非默认图层只使用当前mask地面")
	_check(int(player.get("step_count")) == before and player.position.y > 499.5, "不跨不属于当前层的石块")
	player.set_collision_group(1)


func _air_case() -> void:
	await _reset(Vector2(265, 481))
	_rectangle(Rect2(0, 700, 900, 200))
	_rectangle(Rect2(300, 488, 140, 220))
	await _wait(1)
	var before: int = player.get("step_count")
	_check(not player.is_on_floor(), "空中台沿测试确实未接地")
	Input.action_press("move_right")
	await _wait(13)
	Input.action_release("move_right")
	_check(int(player.get("step_count")) == before, "空中不能踏墙向上")
	_check(player.position.y > 490.0 and player.position.x < 286.0, "空中碰壁保持下坠")


func _gap_case() -> void:
	await _reset(Vector2(250, 490))
	_rectangle(Rect2(0, 500, 300, 200))
	_rectangle(Rect2(460, 500, 400, 200))
	await _wait(30)
	var before: int = player.get("step_count")
	Input.action_press("move_right")
	await _wait(40)
	Input.action_release("move_right")
	_check(int(player.get("step_count")) == before, "断谷没有真实落脚点时不自动跨越")
	_check(not player.is_on_floor() and player.position.y > 540, "离开岸边保留正常坠落")


func _slope_case() -> void:
	await _reset(Vector2(180, 480))
	var body := StaticBody2D.new()
	var collision := CollisionPolygon2D.new()
	# 连续缓坡的交接中含4/8px局部岩唇，既要正常走坡也要跨掉真正的小竖边。
	collision.polygon = PackedVector2Array([Vector2(0, 500), Vector2(250, 500), Vector2(300, 492), Vector2(300, 488), Vector2(420, 480), Vector2(420, 472), Vector2(620, 464), Vector2(900, 464), Vector2(900, 700), Vector2(0, 700)])
	body.add_child(collision)
	fixtures.add_child(body)
	await _wait(30)
	var before: int = player.get("step_count")
	Input.action_press("move_right")
	await _wait(170)
	Input.action_release("move_right")
	_check(player.position.x > 650.0, "缓坡与4/8px岩唇组合可连续通行")
	_check(int(player.get("step_count")) >= before + 2, "仅岩唇触发跨步")
	_check(player.is_on_floor() and player.position.y < 464.2 and player.position.y > 463.5, "坡顶真实站稳")


func _angular_stone_case() -> void:
	await _reset()
	_rectangle(Rect2(0, 500, 900, 200))
	var body := StaticBody2D.new()
	var collision := CollisionPolygon2D.new()
	collision.polygon = PackedVector2Array([Vector2(300, 500), Vector2(304, 492), Vector2(309, 492), Vector2(313, 500)])
	body.add_child(collision)
	fixtures.add_child(body)
	await _wait(30)
	Input.action_press("move_right")
	var air_frames := 0
	var minimum_step_speed := INF
	var maximum_displacement := 0.0
	var maximum_lift := 0.0
	for tick in 75:
		var old_position := player.position
		await _wait(1)
		maximum_displacement = maxf(maximum_displacement, absf(player.position.x - old_position.x))
		maximum_lift = maxf(maximum_lift, 500.0 - player.position.y)
		if not player.is_on_floor():
			air_frames += 1
			if "--angular-only" in OS.get_cmdline_user_args():
				print("ANGULAR_AIR: ", player.position, " velocity=", player.velocity, " settling=", player.get("_step_settle_time"))
		if float(player.get("step_up_height")) > 0.0:
			minimum_step_speed = absf(player.velocity.x)
	Input.action_release("move_right")
	_check(player.position.x > 400, "8px不规则矮石不因陡侧面卡脚")
	_check(player.is_on_floor(), "跨过不规则矮石后正常落地")
	_check(air_frames <= 4 and maximum_lift < 8.3, "不规则石侧棱只短暂越过且不跳高")
	_check(minimum_step_speed > 170.0 and maximum_displacement <= 3.01, "斜侧低石不额外前移或减速")
	print("TRAVELER_STEP_ANGULAR: x=%.3f lift=%.3f air=%d max_dx=%.3f" % [player.position.x, maximum_lift, air_frames, maximum_displacement])


func _jump_case() -> void:
	await _reset()
	_rectangle(Rect2(0, 500, 900, 200))
	await _wait(30)
	var floor_y := player.position.y
	var before: int = player.get("step_count")
	var rise := 0.0
	Input.action_press("jump")
	for tick in 65:
		await _wait(1)
		rise = maxf(rise, floor_y - player.position.y)
	Input.action_release("jump")
	_check(rise > 105.0 and rise < 112.0 and player.is_on_floor(), "满跳保持108.6px，实际%.3f" % rise)
	_check(int(player.get("step_count")) == before, "正常跳跃不会触发自动跨步")


func _dash_case() -> void:
	await _reset(Vector2(220, 490))
	_rectangle(Rect2(0, 500, 900, 200))
	_rectangle(Rect2(300, 488, 140, 12))
	await _wait(30)
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _wait(5)
	Input.action_release("sprint")
	var stepped_during_dash := false
	var minimum_speed := INF
	for tick in 24:
		await _wait(1)
		if float(player.get("step_up_height")) > 0.0:
			stepped_during_dash = player.dash_active
			minimum_speed = absf(player.velocity.x)
	Input.action_release("move_right")
	_check(stepped_during_dash and minimum_speed > 550.0, "短冲经过12px石块不被当墙中断")
	_check(player.position.x > 330.0, "短冲越过低障碍后继续前进")


func _story_case() -> void:
	await _reset()
	player.queue_free()
	fixtures.queue_free()
	await _wait(2)
	var game := (load("res://Story_Garden_Game.tscn") as PackedScene).instantiate()
	var level: Node = game.get_node("Level")
	level.set("enable_bookmarks", false)
	level.set("save_path", "user://Tests/Traveler_Step_Regression_Unused.json")
	add_child(game)
	player = game.get_node("Player") as PlayerController
	await _wait(20)
	player.position = Vector2(2230, 484)
	player.reset_motion()
	game.get_node("System").reset_view_interpolation()
	await _wait(15)
	var before: int = player.get("step_count")
	Input.action_press("move_left")
	Input.action_press("sprint")
	for tick in 90:
		await _wait(1)
		if player.position.x < 2005.0:
			break
	Input.action_release("move_left")
	Input.action_release("sprint")
	# 该根尖看似只有3px，真实轮廓却是通向约80px顶部的63度侧壁。
	# 它不是可自动跨越的微台阶，防止为了此处放宽成自动爬高台。
	_check(player.position.x > 2037 and player.position.x < 2040, "Story余根高侧壁保持平台跳跃边界")
	_check(int(player.get("step_count")) == before, "真实根尖缺少12px内可站踏面时不自动爬高根")
	var root_hit := KinematicCollision2D.new()
	player.test_move(player.global_transform, Vector2(-5.34, 0), root_hit, 0.08)
	_check(root_hit.get_collider() == level.get_node("Mid/ReturnRoot"), "真实阻挡归因于余根实体而非坡面重播")
	print("TRAVELER_STEP_STORY_ROOT: x=%.3f y=%.3f collider=%s contact=%s steps=%d" % [player.position.x, player.position.y, str(root_hit.get_collider()), str(root_hit.get_position()), int(player.get("step_count")) - before])
	# 在同一实际关卡的平岸增加仅供测试的4px石块，检查System当前层与新控制器整合。
	fixtures = Node2D.new()
	game.add_child(fixtures)
	_rectangle(Rect2(2270, 480, 28, 4), player.collision_layer)
	player.position = Vector2(2230, 484)
	player.reset_motion()
	game.get_node("System").reset_view_interpolation()
	await _wait(15)
	before = player.get("step_count")
	Input.action_press("move_right")
	for tick in 35:
		await _wait(1)
	Input.action_release("move_right")
	_check(player.position.x > 2315, "实际Story与System当前层中的4px测试石可步行越过")
	_check(int(player.get("step_count")) > before and player.is_on_floor(), "实际关卡跨小石后保持真实接地")
	print("TRAVELER_STEP_STORY_SMALL: x=%.3f y=%.3f steps=%d" % [player.position.x, player.position.y, int(player.get("step_count")) - before])
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://Exports/Traveler_Step")
		get_viewport().get_texture().get_image().save_png("res://Exports/Traveler_Step/Story_After_Step.png")


func _finish() -> void:
	for action in ["move_right", "move_left", "sprint", "jump"]:
		Input.action_release(action)
	print("TRAVELER_STEP: %d checks, %d failures." % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
