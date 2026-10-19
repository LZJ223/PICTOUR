## 不修改关卡资源；在内存中注入台词，覆盖真实 Game 的开场和暂停流程。
extends Node

const DialogueLine = preload("res://Interface/Dialogue/Dialogue_Line.gd")
const DialogueSystem = preload("res://Interface/Dialogue/Dialogue_System.gd")

var _game: Node2D
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("DIALOGUE_TEST: " + message)

func _frames(count: int = 2) -> void:
	for index in count:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _wait_until(predicate: Callable) -> void:
	for frame in 240:
		if predicate.call():
			return
		await get_tree().process_frame
	_check(false, "等待演出状态超时")

func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	## 隐藏窗口测试也提交一次离屏绘制，不依赖可见窗口的绘制事件。
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/dialogue_qa"))
	get_viewport().get_texture().get_image().save_png("res://.godot/dialogue_qa/" + filename + ".png")

func _line(speaker: DialogueLine.Speaker, text: String) -> DialogueLine:
	var line := DialogueLine.new()
	line.speaker = speaker
	line.text = text
	return line

func _create_game(lines: Array[DialogueLine]) -> void:
	_game = load("res://Interface/Game.tscn").instantiate() as Node2D
	_game.child_entered_tree.connect(func(child: Node) -> void:
		if child is Level:
			child.dialogue = lines
	)
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game

func _dialogue() -> DialogueSystem:
	return _game.get_node("DialogueSystem") as DialogueSystem

func _click(at := Vector2(50, 250)) -> void:
	at = get_viewport().get_final_transform() * at
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.global_position = at
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	Input.parse_input_event(event)

func _only_current_box() -> bool:
	var count: int = 0
	for box in _dialogue()._boxes:
		if box.visible:
			count += 1
	return count <= 1

func _finish_all() -> void:
	for index in 30:
		if not SignalSystem.dialogue_active:
			return
		_dialogue().advance()
		_check(_only_current_box(), "连续点击时同屏最多一个对话框")
		await _frames(1)
	_check(false, "有限次点击后应结束对话")

func _run() -> void:
	SceneTransition.fade_in_duration = 0.02
	SceneTransition.fade_out_duration = 0.02
	var lines: Array[DialogueLine] = [
		_line(DialogueLine.Speaker.VOICEOVER, "旁白测试：点击完成动画，再次点击才切换台词。"),
		_line(DialogueLine.Speaker.BOOK_SPIRIT, "书灵第一次出现，并在后续台词中保持浮动。"),
		_line(DialogueLine.Speaker.PLAYER, "玩家测试：这是一段用于检查暂停恢复的较长台词。".repeat(3)),
		_line(DialogueLine.Speaker.BOOK_SPIRIT, "同一书灵第二次对话，不重复播放出现动画。"),
	]
	SaveSystem.set_preference("skip_dialogue", true)
	_create_game(lines)
	await _frames()
	_check(not _game.play_dialogue and not SignalSystem.dialogue_active and _dialogue()._state == DialogueSystem.State.IDLE,
		"勾选跳过对话后，有台词的关卡也不启动开场对话")
	SaveSystem.set_preference("skip_dialogue", false)
	await _frames()
	_check(not SignalSystem.dialogue_active, "更改偏好仅在下次进入关卡时生效")
	_game.queue_free()
	await _frames()
	_create_game(lines)
	_check(SignalSystem.dialogue_active, "Game 初始化时已经锁定输入")
	await _wait(0.08)
	var dialogue := _dialogue()
	var controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	var origin := Global.player.global_position
	var camera_origin := Global.camera.global_position
	## 首次镜头 Tween 尚未结束；鼠标只完成当前句，不推进索引。
	_click()
	await _frames()
	_check(dialogue._index == 0 and dialogue._state == DialogueSystem.State.WAITING, "首个点击完成镜头和当前句，不换句")
	_check(dialogue._box._text.visible_characters == -1, "跳过动画后全文可见")
	await _capture("01_voiceover")
	_check(Global.camera.zoom.is_equal_approx(Vector2.ONE * controller.dialogue_zoom), "对话镜头使用 zoom 放大")
	_check(Global.camera.global_position.is_equal_approx(camera_origin), "对话构图不修改相机位置")
	_check(not controller.cycle(1, false), "对话锁定整层轮换")
	Global.player.UAV_activate()
	_check(Global.player.current_state == PlayerController.PlayerState.NORMAL, "对话锁定 UAV")
	Global.goal._on_body_entered(Global.player)
	_check(not Global.goal.completed, "对话期间不触发结算")
	Input.action_press("move_right")
	Input.action_press("jump")
	Input.action_press("look_at_destination")
	await _wait(SignalSystem.timer.wait_time + 0.15)
	_check(Global.player.global_position.is_equal_approx(origin), "长按移动和跳跃时玩家仍不移动")
	_check(not SignalSystem.looking_at_destination, "对话锁定 Shift 观察")
	_check(not SignalSystem.timer.is_stopped(), "长时间阅读不会触发休眠")
	_check(Global.object_selected == null, "继续对话不会选中场景物体")
	Input.action_release("move_right")
	Input.action_release("jump")
	Input.action_release("look_at_destination")
	_click()
	await _wait_until(func() -> bool: return dialogue._index == 1)
	_check(dialogue._index == 1 and dialogue._spirit_shown and not dialogue._boxes[0].visible, "旧框先退场，然后首次书灵出场")
	_click()
	await _frames()
	_check(dialogue._state == DialogueSystem.State.WAITING and dialogue._index == 1, "点击完成书灵和第二句，不额外换句")
	_check(dialogue._spirit.visible and dialogue._spirit_shown, "书灵可见")
	_check(_only_current_box(), "书灵出现后只有当前框可见")
	await _capture("02_book_spirit")
	_click()
	await _wait_until(func() -> bool:
		return dialogue._index == 2 and dialogue._state == DialogueSystem.State.PRESENTING and dialogue._box._text.visible_characters > 1
	)
	_check(dialogue._index == 2 and dialogue._state == DialogueSystem.State.PRESENTING, "第三句自然进入打字状态")
	var pause := _game.get_node("Camera/MenuUI/Screen/Pause") as Control
	pause.open()
	await _frames()
	var visible_count: int = dialogue._box._text.visible_characters
	var spirit_y: float = dialogue._spirit_visual.position.y
	await _wait(0.3)
	_check(dialogue._box._text.visible_characters == visible_count, "暂停冻结打字")
	_check(is_equal_approx(dialogue._spirit_visual.position.y, spirit_y), "暂停冻结书灵浮动")
	_click((pause.get_node("Continue") as Button).get_global_rect().get_center())
	await _frames()
	_check(not get_tree().paused, "Continue 可以解除暂停")
	_check(dialogue._index == 2 and dialogue._state == DialogueSystem.State.PRESENTING, "Continue 点击不穿透并跳过打字")
	await _wait(0.12)
	_check(dialogue._box._text.visible_characters > visible_count, "继续后恢复打字")
	await _capture("03_player")
	get_tree().root.size = Vector2i(1100, 900)
	await _frames(4)
	_check(Global.camera.global_position.is_equal_approx(camera_origin), "窗口变化时仍不移动对话镜头位置")
	if dialogue._state == DialogueSystem.State.PRESENTING:
		dialogue.advance()
	dialogue.advance()
	dialogue.advance()
	_check(dialogue._index == 3 and dialogue._state == DialogueSystem.State.PRESENTING,
		"第二次书灵发言直接呈现台词，不重复召唤")
	await _finish_all()
	_check(not SignalSystem.dialogue_active and not dialogue._spirit.visible, "结束后解除锁定并隐藏书灵")
	_check(Global.camera.zoom.is_equal_approx(Vector2.ONE), "结束后恢复原 zoom")
	_check(is_zero_approx(controller._dialogue_blend), "结束后恢复正常构图")
	_check(not SignalSystem.timer.is_stopped(), "结束后重新开始休息计时")
	## 再次播放，用真实 Pause Restart 调用检查 bool 传递与旧演出清理。
	dialogue.start(lines, controller)
	await _wait(1.8)
	_check(dialogue._state == DialogueSystem.State.WAITING and dialogue._index == 0, "不点击时镜头、入场和逐字动画也能自然完成")
	_check(not dialogue._spirit_shown, "旁白阶段不提前召唤书灵")
	pause.open()
	pause._begin_hold(pause.HoldAction.RESTART)
	pause._on_hold_timeout()
	await SceneTransition.transition_finished
	await _frames(4)
	_game = get_tree().current_scene as Node2D
	_check(not _game.play_dialogue, "Restart 显式传入不播放开场对话")
	_check(not SignalSystem.dialogue_active, "对话中重开不残留输入锁")
	_check(_dialogue()._state == DialogueSystem.State.IDLE, "新 Game 不启动演出")
	_check(Global.camera.zoom.is_equal_approx(Vector2.ONE), "重开不残留旧镜头缩放")
	_check(await SceneTransition.enter_main_menu() == OK, "可返回主菜单")
	await _frames()
	_check(not SignalSystem.dialogue_active and Global.player == null, "离场清理对话锁与玩家引用")
	_check(await SceneTransition.enter_level(1) == OK, "可以重新进入真实第一关")
	_game = get_tree().current_scene as Node2D
	_check(_game.play_dialogue and SignalSystem.dialogue_active, "取消跳过对话后，第一关正常播放实际剧情")
	_check(SceneTransition.consume_dialogue_request(), "重开参数不会污染后续启动请求")
	_game.queue_free()
	await _frames()
	_create_game([])
	_check(not SignalSystem.dialogue_active and _dialogue()._state == DialogueSystem.State.IDLE, "空数组跳过对话")
	print("DIALOGUE_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
