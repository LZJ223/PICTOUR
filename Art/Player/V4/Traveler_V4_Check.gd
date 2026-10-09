extends Node2D
## 验证图集锚点与实际输入行为；不把数量或骨架正确当作美术验收。

const Traveler = preload("res://Component/Player/V4/Traveler_V4.tscn")
var checks: int = 0
var failures: int = 0
var player: PlayerController
var visual: AnimatedSprite2D
var cloth: Node2D


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("TRAVELER_V4_CHECK: " + message)


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func _run() -> void:
	_make_floor()
	player = Traveler.instantiate() as PlayerController
	player.position = Vector2(200, 500)
	add_child(player)
	visual = player.get_node("Visual_Body/Traveler")
	cloth = player.get_node("Visual_Body/Scarf")
	await _wait(30)
	_check(bool(visual.get("_art_ready")), "位图图集与锚点完成加载")
	if not bool(visual.get("_art_ready")):
		_finish()
		return
	_check(player.is_on_floor(), "角色真实碰撞落地")
	_check(is_equal_approx(player.move_speed, 180.0) and is_equal_approx(player.run_speed, 320.0), "V4独立180/320速度，不改变共享控制器默认值")
	var metadata: Dictionary = visual.call("get_metadata")
	var common_size := Vector2.ZERO
	for action in ["idle", "walk", "run", "rise", "apex", "fall", "land", "brake"]:
		_check(visual.sprite_frames.has_animation(action), "图集含状态：" + action)
		for index in visual.sprite_frames.get_frame_count(action):
			var frame_texture := visual.sprite_frames.get_frame_texture(action, index) as AtlasTexture
			_check(frame_texture != null and frame_texture.atlas.resource_path.contains("/Generated/"), "直接使用AI生成原图区域：" + action + "/" + str(index))
			if frame_texture != null:
				if common_size == Vector2.ZERO:
					common_size = frame_texture.get_size()
				_check(frame_texture.get_size().is_equal_approx(common_size), "所有帧共用虚拟画布与足点")
	var lowest := 0.0
	var startup_height_error := 0.0
	var standing_top: float = _top_y(metadata.animations.idle[0], metadata)
	for item: Dictionary in metadata.animations.walk:
		lowest = maxf(lowest, absf(float(item.lowest_pixel_y)))
		startup_height_error = maxf(startup_height_error, absf(_top_y(item, metadata) - standing_top))
	_check(lowest < 3.0, "步行各帧脚底靠近物理地面，最大误差=" + str(lowest))
	_check(startup_height_error < 4.0, "待机转步行不再突然蹲落，头顶变化=" + str(startup_height_error))
	var run_air := 0
	for item: Dictionary in metadata.animations.run:
		if float(item.lowest_pixel_y) < -1.5:
			run_air += 1
	_check(run_air >= 2, "奔跑至少两帧明确腾空，不把所有帧脚底拉平")
	Input.action_press("move_right")
	await _wait(30)
	_check(visual.animation == &"walk", "实际步行输入触发walk")
	_check(absf(player.velocity.x - 180.0) < 0.01, "实际稳定步速180")
	var before_phase: float = visual.get("stride_phase")
	var before_x: float = player.position.x
	await _wait(12)
	var expected: float = fposmod(before_phase + (player.position.x - before_x) / float(visual.get("walk_stride")), 1.0)
	_check(absf(float(visual.get("stride_phase")) - expected) < 0.001, "步态消耗真实移动距离")
	Input.action_press("sprint")
	await _wait(24)
	_check(visual.animation == &"run" and absf(player.velocity.x - 320.0) < 0.01, "实际奔跑输入触发run320")
	_check(absf(float(cloth.call("get_total_length")) - 74.0) < 0.1, "高速围巾保持长度")
	Input.action_release("move_right")
	Input.action_press("move_left")
	await _wait(1)
	_check(player.velocity.x > 0.0 and int(visual.get("visual_facing")) == 1, "反向输入不提前镜像")
	await _wait(24)
	_check(int(visual.get("visual_facing")) == -1, "速度过零后转身")
	Input.action_release("move_left")
	Input.action_release("sprint")
	await _wait(130)
	var points: PackedVector2Array = cloth.call("get_ribbon_points")
	await _wait(30)
	var settled: PackedVector2Array = cloth.call("get_ribbon_points")
	_check(points[-1].distance_to(settled[-1]) < 4.0, "停步围巾衰减")
	Input.action_press("jump")
	var saw_rise := false
	var saw_fall := false
	var maximum_rise := 0.0
	var floor_y := player.position.y
	for tick in 65:
		await _wait(1)
		maximum_rise = maxf(maximum_rise, floor_y - player.position.y)
		saw_rise = saw_rise or visual.animation == &"rise"
		saw_fall = saw_fall or visual.animation == &"fall"
	Input.action_release("jump")
	_check(saw_rise and saw_fall and player.is_on_floor(), "真实跳起、下落与落地完整")
	_check(maximum_rise > 105.0 and maximum_rise < 112.0, "满跳高度保持，实测=" + str(maximum_rise))
	player.position = Vector2(1364, 500)
	player.reset_motion()
	player.reset_physics_interpolation()
	await _wait(3)
	Input.action_press("move_right")
	await _wait(35)
	var phase_at_wall: float = visual.get("stride_phase")
	await _wait(12)
	_check(player.is_on_wall(), "角色真实受到墙体阻挡")
	_check(is_equal_approx(phase_at_wall, float(visual.get("stride_phase"))), "顶墙不空转走路")
	_finish()


func _finish() -> void:
	for action in ["move_right", "move_left", "sprint", "jump"]:
		Input.action_release(action)
	print("TRAVELER_V4_CHECK: %d checks, %d failures; handpainted bitmap anchors and actual movement." % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _top_y(frame_info: Dictionary, metadata: Dictionary) -> float:
	var sheet: Dictionary = metadata.source_sheets[frame_info.sheet]
	var row: int = int(frame_info.source_frame) / int(sheet.grid[0])
	var row_height: float = float(sheet.height) / float(sheet.grid[1])
	return (float(frame_info.source_bounds[1]) - row * row_height - float(frame_info.source_root[1])) * float(metadata.scale)


func _make_floor() -> void:
	var ground := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(8000, 100)
	shape.shape = rectangle
	ground.position = Vector2(0, 550)
	ground.add_child(shape)
	add_child(ground)
	var wall := StaticBody2D.new()
	var wall_shape := CollisionShape2D.new()
	var wall_rectangle := RectangleShape2D.new()
	wall_rectangle.size = Vector2(30, 250)
	wall_shape.shape = wall_rectangle
	wall.position = Vector2(1400, 400)
	wall.add_child(wall_shape)
	add_child(wall)
