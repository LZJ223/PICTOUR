## 真实 Main 背景：巡逻、碰撞、缩放、循环回收及淡入期间的持续运动。
extends Node

var _menu: Node2D
var _background: Node2D
var _bots: Array[Bot] = []
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("MENU_BOT_TEST: " + message)

func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _collect(node: Node) -> void:
	if node is Bot:
		_bots.append(node)
	for child in node.get_children():
		_collect(child)

func _positions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for bot in _bots:
		result.append(bot.position)
	return result

func _check_grounded(message: String) -> void:
	for bot in _bots:
		_check(absf(bot.position.y - 500.0) < 1.0, message + "：" + str(bot.get_path()))

func _run() -> void:
	SceneTransition.fade_in_duration = 0.5
	_menu = load("res://Interface/Main.tscn").instantiate() as Node2D
	get_tree().root.add_child(_menu)
	get_tree().current_scene = _menu
	_background = _menu.get_node("Game") as Node2D
	await _frames(3)
	_collect(_background)
	_check(_bots.size() >= 4, "原始场景与背景拷贝都包含 Bot")
	var before := _positions()
	await _frames(12)
	_check(SceneTransition.busy, "检查时仍处于菜单淡入阶段")
	for index in _bots.size():
		var bot := _bots[index]
		_check(bot.position.x > before[index].x + 5.0, "淡入期间 Bot 已相对地面巡逻")
		_check(bot._background_motion and bot._body.freeze, "受控运动不会与刚体模拟争用位置")
		_check(bot.collision_mask == 1 << bot.owner_layer.layer_id, "保留 Bot 所属图层的物理检测")
		var area := bot.get_node("VisualRoot/Area2D") as Area2D
		_check(not area.input_pickable and area.collision_layer == 0 and not area.monitoring, "选择与交互仍保持关闭")
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	_check(Global.level == null and Global.player == null and SignalSystem.timer.is_stopped(), "菜单不注册关卡或启动游戏计时器")
	before = _positions()
	var previous_scroll: float = _background._scroll
	await _frames(30)
	_check(_background._scroll > previous_scroll + 80.0, "背景继续正常向左滚动")
	for index in _bots.size():
		_check(_bots[index].position.x > before[index].x + 20.0, "滚动时 Bot 仍向自己的朝向移动，不被反向拖动")
	_check_grounded("没有逐帧下沉或悬空漂移")
	for bot in _bots:
		var anchor: Vector2 = bot.to_local(_background.get_node("Player").global_position)
		_check(bot.visual_root.position.is_equal_approx(anchor * (1.0 - bot.owner_layer.visual_scale)), "巡逻与背景视差同帧更新，不产生一帧偏移")
	var primary := _bots[0]
	var phase: float = primary._bob_phase
	await _frames(5)
	_check(not is_equal_approx(primary._bob_phase, phase), "菜单 Bot 持续播放行走震动")

	_background.scale = Vector2.ONE * 0.75
	_menu._update_layout()
	await _frames(5)
	before = _positions()
	await _frames(15)
	for index in _bots.size():
		_check(absf(_bots[index].position.x - before[index].x) > 10.0, "0.75 倍背景保持本地巡逻速度")
		_check(_bots[index].scale.is_equal_approx(Vector2.ONE), "父级缩放不改变 Bot 自身的物理变换")
	_check_grounded("缩放后仍稳定站在地面")

	# 整个图层瞬移回收时，Bot 应与地面一起移动，不改变自身的局部巡逻位置。
	before = _positions()
	_background._scroll += _background.loop_length
	_background._update_background()
	for index in _bots.size():
		_check(_bots[index].position.is_equal_approx(before[index]), "循环回收不重置或偏移 Bot 局部位置")
	_background.scroll_speed = 20000.0
	await _frames(100)
	_check_grounded("多次循环回收后不漂移或掉落")
	for bot in _bots:
		_check(bot._state != Bot.PatrolState.AIRBORNE, "多次回收后仍能检测所属图层地面")
	_background.scroll_speed = 260.0

	# 将一个测试 Bot 放到场景内的独立平台，检查菜单模式同样使用避障和转向逻辑。
	var platform := StaticBody2D.new()
	platform.collision_layer = primary.collision_mask
	platform.collision_mask = primary.collision_mask
	platform.position = Vector2(0, -200)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(200, 40)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	platform.add_child(collision)
	primary.owner_layer.add_child(platform)
	primary.position = Vector2(50, -240)
	primary._background_velocity = Vector2.ZERO
	primary._direction = 1
	primary._state = Bot.PatrolState.WAITING
	var saw_middle: bool = false
	for index in 30:
		await _frames(1)
		saw_middle = saw_middle or primary._poses[1].visible
	_check(saw_middle and primary._direction == -1 and primary._poses[0].visible, "菜单模式到达悬崖后通过中间帧转身")
	_check(absf(primary.position.y + 240.0) < 1.0, "转向时没有跌落平台")

	_menu.queue_free()
	await _frames(3)
	print("MENU_BOT_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
