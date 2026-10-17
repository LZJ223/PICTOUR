## 在内存中搭建巡逻场地，并验证真实 Game 的对话、观察目标及换层接入。
extends Node

const BOT := preload("res://Component/Bot/Bot.tscn")
const LAYER := preload("res://Component/Layer/Depth_Layer.tscn")
var _stage: Level
var _layers: Array[DepthLayer] = []
var _bot: Bot
var _checks: int = 0
var _failures: Array[String] = []
var _shadow_events: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("BOT_TEST: " + message)

func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _solid(parent: Node, rect: Rect2, layer_id: int = 0) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.collision_layer = 1 << layer_id
	body.collision_mask = 1 << layer_id
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = rect.get_center()
	body.add_child(collider)
	parent.add_child(body)
	return body

func _new_stage(floor_rect: Rect2, spawn: Vector2, initial_direction: int = 1, speed: float = 80.0) -> void:
	SignalSystem.set_gameplay_active(false)
	SignalSystem.timer.start(120.0)
	_stage = Level.new()
	_stage.process_mode = Node.PROCESS_MODE_PAUSABLE
	_stage.layer_count = 2
	_stage.current_layer_index = 0
	Global.level = _stage
	_layers.clear()
	for index in 2:
		var layer := LAYER.instantiate() as DepthLayer
		layer.layer_id = index
		layer.slot = index
		_stage.add_child(layer)
		_layers.append(layer)
	_solid(_layers[0], floor_rect)
	_bot = BOT.instantiate() as Bot
	_bot.position = spawn
	_bot.initial_direction = initial_direction
	_bot.move_speed = speed
	## 巡逻场地使用固定碰撞尺寸，不随用户调整贴图及场景碰撞箱而改变测试基准。
	(_bot.get_node("CollisionBox") as CollisionPolygon2D).polygon = PackedVector2Array([
		Vector2(40, 28), Vector2(40, -24), Vector2(-40, -24), Vector2(-40, 28),
	])
	_layers[0].add_child(_bot)
	add_child(_stage)
	for layer in _layers:
		layer.cancel_cycle()

func _clear_stage() -> void:
	Global.level = null
	_stage.queue_free()
	await _frames(3)
	_bot = null

func _run() -> void:
	SignalSystem.shadow_boolean.connect(func() -> void: _shadow_events += 1)
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	SceneTransition.scene_ready()
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	_new_stage(Rect2(-800, 100, 1600, 80), Vector2(0, 72))
	await _frames(12)
	_check(_bot is LayerObject and _bot.get_node(".") is RigidBody2D, "保留 RigidBody2D 根节点并继承 LayerObject")
	_check(_bot._body.lock_rotation and not _bot._body.can_sleep, "禁止旋转和刚体自动休眠")
	_check(_bot.owner_layer == _layers[0] and _bot.collision_mask == 1, "完成基类图层注册")
	_check(_bot.position.x > 5.0 and absf(_bot.position.y - 72.0) < 1.0, "在平地向右移动且不改变站立高度")
	_check(_bot._poses[2].visible and not _bot._poses[0].visible and not _bot._poses[1].visible, "常态仅显示正确朝向")
	var maximum_bob: float = 0.0
	for index in 15:
		await _frames(1)
		maximum_bob = maxf(maximum_bob, absf(_bot._sprite.position.y - _bot._sprite_origin.y))
	_check(maximum_bob > 0.1 and maximum_bob <= _bot.bob_amplitude + 0.01, "运动时有小幅震动且不累积位移")
	_check(_bot.collision_box.position == Vector2.ZERO, "行走动画不移动碰撞箱")
	_check(is_equal_approx(_bot.bob_frequency, 6.0), "默认震动频率降至 6Hz")
	var origin := _bot.position
	get_tree().paused = true
	await _frames(2)
	origin = _bot.position
	await _frames(8)
	_check(_bot.position.is_equal_approx(origin), "暂停菜单冻结巡逻")
	get_tree().paused = false
	SignalSystem.timer.start(0.05)
	origin = _bot.position
	await _frames(12)
	_check(SignalSystem.timer.is_stopped() and not SignalSystem.is_physics_resting(), "白天计时正常结束，但不进入物理休眠")
	_check(_shadow_events == 0 and _bot.position.x > origin.x + 5.0, "白天计时结束后不触发影子布尔，Bot 继续巡逻")
	# 同一套计时器在夜间仍需冻结物理，不能提前启动或改变 Player 的休息判定。
	_stage.is_night = true
	SignalSystem.timer.start(0.05)
	await _frames(8)
	_check(SignalSystem.timer.is_stopped() and SignalSystem.is_physics_resting() and _shadow_events == 1, "夜间计时结束后触发一次影子布尔并进入物理休眠")
	await _frames(2)
	origin = _bot.position
	var resting_sprite := _bot._sprite.position
	await _frames(8)
	_check(_bot.position.is_equal_approx(origin) and _bot._sprite.position == resting_sprite, "精神滤镜休眠冻结巡逻和震动")
	PhysicsServer2D.set_active(true)
	SignalSystem.timer.start(120.0)
	await _frames(8)
	_check(_bot.position.x > origin.x + 3.0, "唤醒后恢复巡逻")
	await _clear_stage()

	# 墙体、低矮台阶和悬空障碍都必须在碰撞之前转向。
	for obstacle in [Rect2(160, -100, 40, 200), Rect2(160, 97, 40, 3), Rect2(160, 50, 40, 10)]:
		_new_stage(Rect2(-800, 100, 1600, 80), Vector2(95, 72))
		_solid(_layers[0], obstacle)
		var saw_middle: bool = false
		var furthest_x: float = _bot.position.x
		for index in 45:
			await _frames(1)
			saw_middle = saw_middle or _bot._poses[1].visible
			furthest_x = maxf(furthest_x, _bot.position.x)
		_check(saw_middle and _bot._direction == -1 and _bot._poses[0].visible, "遇到障碍经过中间帧转向：%s" % obstacle)
		_check(furthest_x + 40.0 < obstacle.position.x + 0.5 and _bot.position.x < 95.0, "遇障碍提前停止，不穿透或向前推动")
		await _clear_stage()

	_new_stage(Rect2(-800, 100, 1600, 80), Vector2(112, 72))
	_stage.is_night = true
	_solid(_layers[0], Rect2(160, -100, 40, 200))
	for index in 20:
		if _bot._state == Bot.PatrolState.TURNING:
			break
		await _frames(1)
	SignalSystem.timer.start(0.01)
	await _frames(12)
	_check(_bot._state == Bot.PatrolState.TURNING and _bot._poses[1].visible, "休眠期间暂停正在进行的转向 Tween")
	SignalSystem.timer.start(120.0)
	PhysicsServer2D.set_active(true)
	await _frames(12)
	_check(_bot._poses[0].visible and _bot._moving, "唤醒后继续完成转向并巡逻")
	await _clear_stage()

	_new_stage(Rect2(-500, 100, 660, 80), Vector2(95, 72))
	await _frames(45)
	_check(_bot._direction == -1 and _bot.position.x < 95.0 and absf(_bot.position.y - 72.0) < 1.0, "悬崖前转向且不跌落")
	await _clear_stage()

	_new_stage(Rect2(-160, 100, 660, 80), Vector2(-95, 72), -1)
	await _frames(45)
	_check(_bot._direction == 1 and _bot.position.x > -95.0, "向左巡逻时也能检测悬崖并转向")
	await _clear_stage()

	_new_stage(Rect2(-500, 100, 660, 80), Vector2(95, 72))
	_solid(_layers[0], Rect2(160, 103, 500, 80))
	await _frames(40)
	_check(_bot._direction == -1 and _bot.position.x < 95.0, "有地面但高度下降的台阶也会阻止前进")
	await _clear_stage()

	_new_stage(Rect2(-500, 100, 660, 80), Vector2(95, 72))
	var ramp := StaticBody2D.new()
	var ramp_collision := CollisionPolygon2D.new()
	ramp_collision.polygon = PackedVector2Array([Vector2(160, 100), Vector2(380, 140), Vector2(380, 180), Vector2(160, 180)])
	ramp.add_child(ramp_collision)
	_layers[0].add_child(ramp)
	await _frames(40)
	_check(_bot._direction == -1 and _bot.position.x < 95.0, "倾斜地面不能作为平地继续前进")
	await _clear_stage()

	_new_stage(Rect2(-400, 100, 800, 80), Vector2(0, 72), 1, 1800.0)
	var stayed_on_platform: bool = true
	for index in 35:
		await _frames(1)
		stayed_on_platform = stayed_on_platform and absf(_bot.position.x) + 40.0 <= 400.0 and absf(_bot.position.y - 72.0) < 1.0
	_check(stayed_on_platform, "高速巡逻时检测距离包含下一物理帧移动量，不越过悬崖")
	await _clear_stage()

	for size_ratio in [0.5, 2.0]:
		_new_stage(Rect2(-800, 100, 1600, 80), Vector2(120 - 40 * size_ratio, 100 - 28 * size_ratio))
		_bot.collision_box.scale = Vector2.ONE * size_ratio
		_solid(_layers[0], Rect2(160, -100, 40, 200))
		await _frames(50)
		_check(_bot._direction == -1 and absf(_bot.position.y + 28 * size_ratio - 100) < 1.0, "按实际碰撞箱缩放检测障碍：%s 倍" % size_ratio)
		await _clear_stage()

	_new_stage(Rect2(-50, 100, 100, 80), Vector2(0, 72))
	_solid(_layers[0], Rect2(-65, 30, 20, 70))
	var right_wall := _solid(_layers[0], Rect2(45, 30, 20, 70))
	await _frames(20)
	_check(_bot._state == Bot.PatrolState.WAITING and _bot._poses[2].visible, "两侧堵住时等待，不反复转向")
	right_wall.queue_free()
	_solid(_layers[0], Rect2(50, 100, 400, 80))
	await _frames(15)
	_check(_bot.position.x > 5.0, "道路恢复后自动继续巡逻")
	await _clear_stage()

	_new_stage(Rect2(-800, 100, 1600, 80), Vector2(0, -100))
	await _frames(8)
	_check(absf(_bot.position.x) < 0.01 and _bot.position.y > -100, "悬空时停止水平运动并自然下落")
	await _frames(50)
	_check(_bot.position.x > 5.0 and absf(_bot.position.y - 72.0) < 1.0, "落地后重新开始巡逻")
	await _clear_stage()

	_new_stage(Rect2(-800, 100, 1600, 80), Vector2(0, 72))
	# 其他图层的墙不能影响当前图层的巡逻。
	_solid(_layers[1], Rect2(50, -100, 40, 200), 1)
	await _frames(35)
	_check(_bot._direction == 1 and _bot.position.x > 40.0, "忽略其他图层的障碍")
	# 换层时缩放碰撞箱；新层没有地面，必须停止水平运动。
	var collision_transform := _bot.collision_box.transform.scaled(Vector2.ONE * 0.5)
	var target_transform := _bot.global_transform
	target_transform.origin = Vector2(-200, 0)
	_bot.transfer_to(_layers[1], target_transform, collision_transform)
	await _frames(10)
	_check(_bot.owner_layer == _layers[1] and _bot.collision_mask == 2, "换层更新所有巡逻查询的碰撞层")
	_check(absf(_bot.position.x + 200.0) < 0.1 and _bot.position.y > 0, "换层到空中后停止水平运动并下落")
	await _clear_stage()

	# 使用真正的 Game，验证输入锁与长按 Shift 不会误冻结 Bot。
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	SignalSystem.timer.wait_time = 2.0
	var game := load("res://Interface/Game.tscn").instantiate() as Node2D
	game.play_dialogue = false
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	Global.player.set_physics_process(false)
	var layer: DepthLayer = Global.get_layer_at_slot(1)
	_solid(layer, Rect2(-1500, -500, 3000, 80), layer.layer_id)
	_bot = BOT.instantiate() as Bot
	_bot.position = Vector2(0, -528)
	layer.add_child(_bot)
	await _frames(5)
	SignalSystem.set_dialogue_active(true)
	origin = _bot.position
	await get_tree().create_timer(2.2).timeout
	_check(_bot.position.x > origin.x + 100.0 and not SignalSystem.timer.is_stopped(), "对话超过休眠时限仍持续巡逻")
	SignalSystem.set_dialogue_active(false)
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	shift.keycode = KEY_SHIFT
	shift.location = KEY_LOCATION_LEFT
	shift.pressed = true
	Input.parse_input_event(shift)
	await _frames(4)
	_check(SignalSystem.looking_at_destination, "真实 Shift 输入进入观察目标")
	origin = _bot.position
	await get_tree().create_timer(2.2).timeout
	_check(_bot.position.x > origin.x + 100.0 and not SignalSystem.timer.is_stopped(), "长按观察目标超过休眠时限仍持续巡逻")
	shift = InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	shift.keycode = KEY_SHIFT
	shift.location = KEY_LOCATION_LEFT
	shift.pressed = false
	Input.parse_input_event(shift)
	await _frames(4)
	_check(not SignalSystem.looking_at_destination, "松开 Shift 正常退出观察目标")
	var controller := game.get_node("LayerControllerSystem") as LayerControllerSystem
	var target_layer: DepthLayer = Global.get_layer_at_slot(2)
	var ratio: float = Global.layer_scales[1] / Global.layer_scales[2]
	var next_position: Vector2 = Global.camera.global_position + (_bot.global_position - Global.camera.global_position) * ratio
	var next_bottom: float = next_position.y + _bot.collision_box.polygon[0].y * ratio
	_solid(target_layer, Rect2(-1500, next_bottom + 0.5, 3000, 80), target_layer.layer_id)
	await _frames(2)
	var previous_selection_distance: float = Global.max_selection_distance
	Global.max_selection_distance = 5000.0
	_bot.set_pick_condition(true)
	Global.object_selected = _bot
	_check(controller.transfer(-1, _bot), "现有图层控制器可直接转换 Bot 图层")
	_check(_bot.owner_layer == target_layer and _bot._transfer_visual_tween != null, "复用物体换层成功动画")
	await _frames(20)
	_check(_bot.collision_box.scale.is_equal_approx(Vector2.ONE * ratio) and _bot._moving, "换层后使用新碰撞箱尺寸继续巡逻")
	var visible_outlines: int = 0
	for entry in _bot._selection_outlines:
		if entry.outline.visible:
			visible_outlines += 1
	_check(visible_outlines == 1, "选中 Bot 时只有当前朝向显示描边")
	origin = _bot.position
	var collision_scale := _bot.collision_box.scale
	_check(controller.cycle(1, false), "现有图层轮换系统可正常调用")
	await _frames(18)
	_check(_bot.position.x > origin.x + 10.0 and _bot.collision_box.scale == collision_scale, "图层轮换期间继续巡逻且不改变物理尺寸")
	_check(_bot.visual_root.scale.is_equal_approx(collision_scale * _bot.owner_layer.visual_scale), "巡逻局部动画不覆盖图层视差变换")
	Global.max_selection_distance = previous_selection_distance
	_bot.set_pick_condition(false)
	Global.object_selected = null
	var shadow_events_before: int = _shadow_events
	SignalSystem.timer.start(0.05)
	await _frames(10)
	_check(SignalSystem.timer.is_stopped() and Global.player.player_animation._expression_index == 2, "白天计时结束时 Player 仍正常显示休息表情")
	_check(is_zero_approx(Global.player.player_animation._bob_amplitude), "Player 休息时停止浮动，不受 Bot 巡逻影响")
	_check(_shadow_events == shadow_events_before, "真实白天关卡不执行影子布尔")
	var pause := game.get_node("Camera/MenuUI/Screen/Pause") as Control
	pause.open()
	await _frames(2)
	origin = _bot.position
	await _frames(6)
	_check(_bot.position.is_equal_approx(origin), "白天休息后仍可正常暂停巡逻")
	pause.resume()
	await _frames(10)
	_check(SignalSystem.timer.is_stopped() and _bot.position.x > origin.x + 5.0, "白天恢复暂停不重启计时器，也不冻结 Bot")
	origin = _bot.position
	SceneTransition._finish(false)
	await _frames(8)
	_check(SignalSystem.timer.is_stopped() and _bot.position.x > origin.x + 3.0, "白天转场恢复不把 Player 休息误判为物理冻结")
	# 只切换内存中的模式，不改动用户关卡或加入 Shadowed_Geometry。
	Global.level.is_night = true
	SignalSystem.timer.start(0.05)
	await _frames(10)
	_check(_shadow_events == shadow_events_before + 1 and SignalSystem.is_physics_resting(), "真实 Game 夜间模式仍触发影子布尔")
	origin = _bot.position
	pause.open()
	await _frames(3)
	pause.resume()
	await _frames(8)
	_check(SignalSystem.timer.is_stopped() and _bot.position.is_equal_approx(origin), "夜间恢复暂停继续保留悬空物体的物理冻结")
	SceneTransition._finish(false)
	await _frames(8)
	_check(_bot.position.is_equal_approx(origin), "夜间转场恢复继续保留物理冻结")
	SignalSystem.timer.wait_time = 2.0
	SignalSystem.timer_reset()
	await _frames(8)
	_check(_bot.position.x > origin.x + 3.0, "夜间重新操作后仍能正常唤醒物理世界")
	game.queue_free()
	await _frames(3)
	print("BOT_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
