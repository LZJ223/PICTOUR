## 在隔离用户目录运行；覆盖旧存档、改键冲突、读写失败、真实玩法和跨进程恢复。
extends Node

const ACTIONS: Array[StringName] = [
	&"move_up", &"move_down", &"move_left", &"move_right", &"jump",
	&"UAV", &"forward", &"backward", &"look_at_destination",
]
const DEFAULT_CODES: Array[Key] = [KEY_W, KEY_S, KEY_A, KEY_D, KEY_SPACE, KEY_F, KEY_Q, KEY_E, KEY_SHIFT]
const CUSTOM_CODES: Array[Key] = [KEY_I, KEY_K, KEY_J, KEY_L, KEY_U, KEY_O, KEY_COMMA, KEY_PERIOD, KEY_SHIFT]

var _checks: int = 0
var _failures: Array[String] = []
var _cycles: Array[int] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("KEY_BINDINGS_TEST: " + message)

func _key(code: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.location = location
	return event

func _send(code: Key, pressed: bool, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var event := _key(code, location)
	event.pressed = pressed
	Input.parse_input_event(event)

func _frames(count: int = 2) -> void:
	for index in count:
		await get_tree().physics_frame
		await get_tree().process_frame

func _write(text: String) -> void:
	var file := FileAccess.open(SaveSystem.SAVE_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _check_bindings(custom: bool) -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.SAVE_PATH))
	_check(saved.key_bindings.size() == 9, "存档包含九项键位")
	for index in ACTIONS.size():
		var action := ACTIONS[index]
		var code := CUSTOM_CODES[index] if custom else DEFAULT_CODES[index]
		var location := KEY_LOCATION_RIGHT if custom else KEY_LOCATION_LEFT
		var binding := SaveSystem.get_key_binding(action)
		_check(binding.physical_keycode == code, "%s 的内存键位正确" % action)
		_check(saved.key_bindings[String(action)].physical_keycode == code, "%s 的磁盘键位正确" % action)
		_check(InputMap.event_is_action(_key(code, location), action), "%s 的 InputMap 已应用键位" % action)
		if index == 8:
			_check(binding.location == location and saved.key_bindings[String(action)].location == location, "左右 Shift 位置可保存恢复")
	_check(InputMap.event_is_action(_key(KEY_ESCAPE), &"back"), "Esc 始终保持全局返回")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	_check(InputMap.event_is_action(mouse, &"select_object"), "鼠标选取不受键盘改键影响")

func _floor(layer: DepthLayer) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1 << layer.layer_id
	body.collision_mask = body.collision_layer
	body.position = Vector2(6000, 40)
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(4000, 80)
	collider.shape = shape
	body.add_child(collider)
	layer.add_child(body)

func _run() -> void:
	if OS.get_cmdline_user_args().has("--verify-persisted"):
		_check_bindings(true)
		_check(SaveSystem.is_level_completed(2) and SaveSystem.skip_dialogue, "新进程同时保留原有进度和偏好")
		_finish()
		return
	_check_bindings(false)
	SaveSystem.complete_level(2)
	SaveSystem.set_preference("skip_dialogue", true)
	var old_save: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveSystem.SAVE_PATH))
	old_save.erase("key_bindings")
	old_save.version = 1
	_write(JSON.stringify(old_save))
	_check(SaveSystem.load_progress() == OK, "未包含键位的旧存档可以迁移")
	_check_bindings(false)
	_check(SaveSystem.is_level_completed(2) and SaveSystem.skip_dialogue, "迁移保留已有进度和偏好")
	_check(SaveSystem.set_key_binding(&"back", _key(KEY_P)) == ERR_INVALID_PARAMETER, "禁止修改 Esc 返回动作")
	_check(SaveSystem.set_key_binding(&"jump", _key(KEY_ESCAPE)) == ERR_INVALID_PARAMETER, "禁止将 Esc 绑定到玩法动作")
	_check(SaveSystem.set_key_binding(&"jump", InputEventKey.new()) == ERR_INVALID_PARAMETER, "忽略无键码事件")
	for index in ACTIONS.size():
		var location := KEY_LOCATION_RIGHT if index == 8 else KEY_LOCATION_UNSPECIFIED
		_check(SaveSystem.set_key_binding(ACTIONS[index], _key(CUSTOM_CODES[index], location)) == OK, "九项键位均可保存修改")
	_check_bindings(true)
	## 让初始窗口和输入状态完成首帧初始化，再发送真实键盘事件。
	await _frames()
	for index in ACTIONS.size():
		var location := KEY_LOCATION_RIGHT if index == 8 else KEY_LOCATION_UNSPECIFIED
		_send(CUSTOM_CODES[index], true, location)
		await _frames(1)
		_check(Input.is_action_pressed(ACTIONS[index]), "新物理按键实际触发 %s" % ACTIONS[index])
		_send(CUSTOM_CODES[index], false, location)
		await _frames(1)
		_check(not Input.is_action_pressed(ACTIONS[index]), "松开新按键结束 %s" % ACTIONS[index])
	_check(not InputMap.event_is_action(_key(KEY_W), &"move_up"), "改键后旧按键失效")
	_check(not InputMap.event_is_action(_key(KEY_SHIFT, KEY_LOCATION_LEFT), &"look_at_destination"), "右 Shift 绑定不接受左 Shift")
	SaveSystem.set_key_binding(&"move_up", _key(KEY_K))
	_check(SaveSystem.get_key_binding(&"move_down").physical_keycode == KEY_I, "冲突时被占用操作得到原按键")
	_check(InputMap.event_is_action(_key(KEY_K), &"move_up") and InputMap.event_is_action(_key(KEY_I), &"move_down"), "交换后的两个键实际生效")
	SaveSystem.set_key_binding(&"move_up", _key(KEY_I))
	SaveSystem.set_key_binding(&"jump", _key(KEY_SHIFT, KEY_LOCATION_LEFT))
	_check(InputMap.event_is_action(_key(KEY_SHIFT, KEY_LOCATION_LEFT), &"jump") and InputMap.event_is_action(_key(KEY_SHIFT, KEY_LOCATION_RIGHT), &"look_at_destination"), "左右修饰键可以绑定不同操作")
	_check(SaveSystem.set_key_binding(&"jump", _key(KEY_SHIFT)) == ERR_INVALID_PARAMETER, "不接受同时覆盖左右两项操作的歧义绑定")
	_check(SaveSystem.get_key_binding(&"jump").location == KEY_LOCATION_LEFT and SaveSystem.get_key_binding(&"look_at_destination").location == KEY_LOCATION_RIGHT, "拒绝歧义绑定时保留原有设置")
	SaveSystem.set_key_binding(&"jump", _key(KEY_U))
	var modifier := _key(KEY_SHIFT, KEY_LOCATION_RIGHT)
	modifier.shift_pressed = true
	SaveSystem.set_key_binding(&"look_at_destination", modifier)
	_check(not SaveSystem.get_key_binding(&"look_at_destination").shift_pressed, "单独 Shift 不保存为组合键")
	Input.action_press(&"move_up")
	SaveSystem.set_key_binding(&"move_up", _key(KEY_P))
	_check(not Input.is_action_pressed(&"move_up"), "改键释放原有长按状态")
	SaveSystem.set_key_binding(&"move_up", _key(KEY_I))
	var original := FileAccess.get_file_as_string(SaveSystem.SAVE_PATH)
	for invalid in ["escape", "fraction", "duplicate", "missing"]:
		var corrupt: Dictionary = JSON.parse_string(original)
		match invalid:
			"escape":
				corrupt.key_bindings.move_up.physical_keycode = KEY_ESCAPE
			"fraction":
				corrupt.key_bindings.move_up.physical_keycode = 73.5
			"duplicate":
				corrupt.key_bindings.move_up = corrupt.key_bindings.move_down.duplicate()
			"missing":
				corrupt.key_bindings.move_up.erase("location")
		_write(JSON.stringify(corrupt))
		_check(SaveSystem.load_progress() == ERR_FILE_CORRUPT, "拒绝损坏的键位：" + invalid)
		_check(SaveSystem.get_key_binding(&"move_up").physical_keycode == KEY_I and InputMap.event_is_action(_key(KEY_I), &"move_up"), "读取失败不部分更新键位")
	_write(original)
	_check(SaveSystem.load_progress() == OK, "完整自定义键位可重新读取")
	## 临时文件被目录占用时，写入必须失败并保持内存、InputMap 和原存档一致。
	var blocked_path := ProjectSettings.globalize_path(SaveSystem.SAVE_PATH + ".tmp")
	_check(DirAccess.make_dir_absolute(blocked_path) == OK, "准备写入失败场景")
	_check(SaveSystem.set_key_binding(&"move_up", _key(KEY_P)) != OK, "写盘失败返回错误")
	_check(SaveSystem.get_key_binding(&"move_up").physical_keycode == KEY_I and InputMap.event_is_action(_key(KEY_I), &"move_up"), "写盘失败保留旧键位")
	_check(FileAccess.get_file_as_string(SaveSystem.SAVE_PATH) == original, "写盘失败保留原存档")
	_check(DirAccess.remove_absolute(blocked_path) == OK, "清理失败场景的空目录")
	_check(SaveSystem.reset_progress() == OK, "可以重置通关记录")
	_check_bindings(true)
	_check(not SaveSystem.is_level_completed(2) and SaveSystem.skip_dialogue, "重置仅清空进度，保留键位和偏好")
	SaveSystem.complete_level(2)
	await _check_gameplay()
	_check_bindings(true)
	_finish()

func _check_gameplay() -> void:
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	var game := load("res://Interface/Game.tscn").instantiate() as Node2D
	game.play_dialogue = false
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	for layer in Global.layers:
		_floor(layer)
	var player := Global.player
	player.position = Vector2(6000, -150)
	player.velocity = Vector2.ZERO
	await _frames(45)
	_check(player.is_on_floor(), "真实玩家在测试平台落地")
	var origin := player.position
	_send(KEY_L, true)
	await _frames(6)
	_send(KEY_L, false)
	_check(player.position.x > origin.x + 2.0, "新右移键驱动真实玩家")
	player.velocity = Vector2.ZERO
	origin = player.position
	_send(KEY_J, true)
	await _frames(6)
	_send(KEY_J, false)
	_check(player.position.x < origin.x - 2.0, "新左移键驱动真实玩家")
	player.velocity = Vector2.ZERO
	_send(KEY_U, true)
	await _frames(2)
	_send(KEY_U, false)
	_check(player.velocity.y < 0.0 and not player.is_on_floor(), "新跳跃键驱动真实玩家起跳")
	await _frames(60)
	SignalSystem.layer_cycle.connect(func(direction: int, _collision: bool) -> void: _cycles.append(direction))
	_send(KEY_COMMA, true)
	_send(KEY_COMMA, false)
	await _frames(35)
	_send(KEY_PERIOD, true)
	_send(KEY_PERIOD, false)
	await _frames(35)
	_check(_cycles == [1, -1], "新图层键通过真实输入触发正反轮换")
	_send(KEY_SHIFT, true, KEY_LOCATION_RIGHT)
	await _frames()
	_check(SignalSystem.looking_at_destination, "自定义右 Shift 启用预览目的地")
	_send(KEY_SHIFT, false, KEY_LOCATION_RIGHT)
	await _frames()
	_check(not SignalSystem.looking_at_destination, "松开预览键解除输入锁")
	_send(KEY_O, true)
	_send(KEY_O, false)
	await _frames()
	_check(player.current_state == PlayerController.PlayerState.UAV, "新无人机按键实际切换玩家状态")
	player.velocity = Vector2.ZERO
	origin = player.position
	_send(KEY_I, true)
	await _frames(6)
	_send(KEY_I, false)
	_check(player.position.y < origin.y - 2.0, "新向上键实际驱动无人机")
	player.velocity = Vector2.ZERO
	origin = player.position
	_send(KEY_K, true)
	await _frames(6)
	_send(KEY_K, false)
	_check(player.position.y > origin.y + 2.0, "新向下键实际驱动无人机")
	game.queue_free()
	await _frames()

func _finish() -> void:
	print("KEY_BINDINGS_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
