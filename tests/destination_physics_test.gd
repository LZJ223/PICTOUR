## 真实 Game 的 Shift 输入锁：不停止玩家、无人机或世界的自动物理更新。
extends Node

var _game: Node2D
var _player: PlayerController
var _controller: LayerControllerSystem
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("DESTINATION_PHYSICS_TEST: " + message)

func _frames(count: int) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	if code == KEY_SHIFT:
		event.location = KEY_LOCATION_LEFT
	Input.parse_input_event(event)

func _action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func _floor(layer: DepthLayer) -> void:
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1 << layer.layer_id
	floor_body.collision_mask = floor_body.collision_layer
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4000, 80)
	collider.shape = shape
	floor_body.position = Vector2(6000, 40)
	floor_body.add_child(collider)
	layer.add_child(floor_body)

func _falling_body() -> RigidBody2D:
	var body := RigidBody2D.new()
	body.collision_layer = _player.collision_layer
	body.collision_mask = _player.collision_mask
	body.position = Vector2(6200, -300)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 12)
	collider.shape = shape
	body.add_child(collider)
	_game.add_child(body)
	return body

func _run() -> void:
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	_game = load("res://Interface/Game.tscn").instantiate() as Node2D
	_game.play_dialogue = false
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	_player = Global.player
	_controller = _game.get_node("LayerControllerSystem") as LayerControllerSystem
	for layer in Global.layers:
		_floor(layer)
	_player.global_position = Vector2(6000, -250)
	_player.velocity = Vector2.ZERO
	var falling := _falling_body()
	_key(KEY_SHIFT, true)
	_action(&"move_right", true)
	_action(&"jump", true)
	await _frames(8)
	_check(SignalSystem.looking_at_destination, "真实 Shift 输入进入观察状态")
	_check(_player.position.y > -245.0 and _player.velocity.y > 0.0, "观察时半空玩家仍受重力下落")
	_check(absf(_player.position.x - 6000.0) < 0.1 and is_zero_approx(_player.velocity.x), "观察时不接受水平移动输入")
	_check(falling.position.y > -295.0 and falling.linear_velocity.y > 0.0, "普通刚体仍正常下落，全局物理没有被冻结")
	_check(_player.player_animation.process_mode != Node.PROCESS_MODE_DISABLED, "观察不禁用角色动画更新")
	_check(not _controller.cycle(1), "观察时仍不能主动轮换图层")
	_action(&"UAV", true)
	await _frames(2)
	_action(&"UAV", false)
	_check(_player.current_state == PlayerController.PlayerState.NORMAL, "观察时不能激活无人机")
	await _frames(45)
	_check(_player.is_on_floor() and absf(_player.position.y) < 1.0, "观察期间正常碰撞并落在地面")
	_check(absf(_player.position.x - 6000.0) < 0.1, "持续按住移动键也不会穿透输入锁")
	_action(&"jump", false)
	_action(&"jump", true)
	await _frames(4)
	_check(_player.is_on_floor(), "落地后新的跳跃输入也被阻止")
	_action(&"jump", false)
	_action(&"move_right", false)
	Global.level.is_night = true
	await get_tree().create_timer(2.2).timeout
	_check(SignalSystem.looking_at_destination and not SignalSystem.timer.is_stopped(), "夜间长按 Shift 不触发休眠冻结")
	falling = _falling_body()
	await _frames(8)
	_check(falling.position.y > -295.0, "超过休眠时限后世界物理仍运行")

	# 暂停仍可使用，Shift 在暂停期间松开也不会残留输入锁。
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	_check(get_tree().paused, "观察时仍能使用 Esc 打开暂停菜单")
	var position_before := _player.position
	_key(KEY_SHIFT, false)
	await _frames(5)
	_check(_player.position == position_before, "真正暂停菜单仍正常暂停游戏")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(3)
	_check(not get_tree().paused and not SignalSystem.looking_at_destination, "暂停期间松开 Shift，恢复后正确解除观察")
	_action(&"move_right", true)
	await _frames(5)
	_action(&"move_right", false)
	_check(_player.position.x > position_before.x + 3.0, "退出观察后恢复移动输入")
	await _frames(8)
	_player.UAV_activate()
	await _frames(3)
	_check(_player.current_state == PlayerController.PlayerState.UAV, "正常进入无人机模式")
	_player.velocity = Vector2(160, -80)
	position_before = _player.position
	_key(KEY_SHIFT, true)
	_action(&"move_right", true)
	_action(&"move_up", true)
	await _frames(7)
	_check(_player.position.distance_to(position_before) > 1.0 and _player.velocity.length() < 100.0, "无人机观察时保留惯性与减速，不悬停冻结")
	_player.velocity = Vector2.ZERO
	position_before = _player.position
	await _frames(5)
	_check(_player.position.distance_to(position_before) < 0.1, "无人机静止后不接受方向输入")
	_action(&"move_right", false)
	_action(&"move_up", false)
	var body: LayerObject = _player.player_body
	body.position.y = -200.0
	await _frames(8)
	_check(body.position.y > -195.0, "观察无人机时留在场景中的身体仍受重力影响")
	_action(&"UAV", true)
	await _frames(2)
	_action(&"UAV", false)
	_check(_player.current_state == PlayerController.PlayerState.UAV, "观察中不能主动发起无人机收回")
	_key(KEY_SHIFT, false)
	await _frames(3)
	# 把身体移至需要轮换两次才能收回的图层，中途再进入观察。
	var body_transform := body.global_transform
	body_transform.origin = Vector2(6000, 0)
	var recall_slot: int = posmod(Global.current_layer_index - 2, Global.layer_count)
	body.transfer_to(Global.get_layer_at_slot(recall_slot), body_transform, body.collision_box.transform)
	await _frames(3)
	_player.UAV_activate()
	await _frames(2)
	_check(_controller.is_cycling() and body.owner_layer.slot != Global.current_layer_index, "收回需要连续完成至少两次自动轮换")
	_key(KEY_SHIFT, true)
	await _frames(2)
	_check(_player.current_state == PlayerController.PlayerState.RECALLING and _player._recall_tween.is_running(), "观察不暂停已开始的无人机位置收回 Tween")
	await _frames(35)
	_check(SignalSystem.looking_at_destination and _player.current_state == PlayerController.PlayerState.NORMAL, "按住 Shift 时自动轮换和位置收回仍能完整结束")
	_check(_player.player_body == null and not _player.body_collision_box.disabled, "收回正常清理身体并恢复玩家碰撞箱")
	_check(not _controller.cycle(1, false), "收回结束后不会放行其他观察期间的主动轮换")
	_key(KEY_SHIFT, false)
	await _frames(25)
	_check(Global.camera.global_position.distance_to(_player.global_position) < 0.1, "松开后相机平滑回到玩家当前真实位置")
	# 夜间已经休眠时，观察也应唤醒物理，而非保留之前的冻结。
	falling = _falling_body()
	SignalSystem.timer.stop()
	SignalSystem._timer_trigger()
	await _frames(4)
	var frozen_y: float = falling.position.y
	await _frames(4)
	_check(is_equal_approx(falling.position.y, frozen_y), "夜间普通休眠仍可冻结物理")
	_key(KEY_SHIFT, true)
	await _frames(10)
	_check(falling.position.y > frozen_y + 5.0 and not SignalSystem.timer.is_stopped(), "从夜间休眠进入观察会正常唤醒物理")
	_key(KEY_SHIFT, false)
	await _frames(2)
	_game.queue_free()
	await _frames(3)
	print("DESTINATION_PHYSICS_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
