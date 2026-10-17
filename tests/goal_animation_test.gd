## 独立检查 Goal 指示物，不加载或修改关卡布置。
extends Node

const GOAL := preload("res://Component/Goal/Goal.tscn")
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("GOAL_ANIMATION_TEST: " + message)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _run() -> void:
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.scene_ready()
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	var level := Level.new()
	level.process_mode = Node.PROCESS_MODE_PAUSABLE
	var goal := GOAL.instantiate() as LevelGoal
	var indicator := goal.get_node("Goal") as Sprite2D
	var original_scale := indicator.scale
	var original_position := indicator.position
	var original_shape: Shape2D = (goal.get_node("DetectArea") as CollisionShape2D).shape
	level.add_child(goal)
	add_child(level)
	## Godot 会把 Node2D 的零缩放限制为极小值，避免奇异变换矩阵。
	_check(not indicator.visible and indicator.scale.length() < 0.0001, "初始隐藏并从零缩放开始")
	SignalSystem.destination_view_changed.emit(true)
	_check(indicator.visible and indicator.scale.length() < 0.0001, "观察目标时先显示，再开始放大")
	await _wait(0.04)
	_check(indicator.scale.length() > 0.0, "出现动画逐渐放大")
	await _wait(0.2)
	_check(indicator.scale.is_equal_approx(original_scale), "最终精确恢复场景中的原始缩放")
	_check(indicator.position.y < original_position.y, "缩放动画保留上下浮动")
	var floating := goal._float_tween
	var before := indicator.position
	SignalSystem.destination_view_changed.emit(false)
	_check(indicator.visible and indicator.position == before, "松开时不立即隐藏或跳回初始位置")
	_check(goal._float_tween == floating, "消失过程中继续原来的浮动")
	await _wait(0.04)
	_check(indicator.scale.length() < original_scale.length() and indicator.scale.length() > 0.0, "消失动画逐渐缩小")
	await _wait(0.15)
	_check(not indicator.visible and indicator.scale.length() < 0.0001, "缩小到零之后才隐藏")
	_check(indicator.position == original_position and goal._float_tween == null, "完全隐藏后停止浮动并复位")

	SignalSystem.destination_view_changed.emit(true)
	await _wait(0.04)
	var current_scale := indicator.scale
	SignalSystem.destination_view_changed.emit(false)
	_check(indicator.scale == current_scale, "出现途中松开，从当前缩放平滑转为消失")
	await _wait(0.04)
	current_scale = indicator.scale
	before = indicator.position
	SignalSystem.destination_view_changed.emit(true)
	_check(indicator.scale == current_scale and indicator.position == before, "消失途中重新按住，不重置缩放或位置")
	await _wait(0.25)
	_check(indicator.visible and indicator.scale.is_equal_approx(original_scale), "重新出现后不会被旧动画的回调隐藏")

	for index in 5:
		SignalSystem.destination_view_changed.emit(false)
		await get_tree().process_frame
		SignalSystem.destination_view_changed.emit(true)
		await get_tree().process_frame
	await _wait(0.25)
	_check(indicator.visible and indicator.scale.is_equal_approx(original_scale), "反复快速切换不会累积缩放")
	SignalSystem.destination_view_changed.emit(false)
	await _wait(0.2)
	_check(not indicator.visible and goal._float_tween == null, "最终松开仍可正常清理动画")

	SignalSystem.destination_view_changed.emit(true)
	await _wait(0.03)
	get_tree().paused = true
	current_scale = indicator.scale
	before = indicator.position
	await _wait(0.1)
	_check(indicator.scale == current_scale and indicator.position == before, "暂停时缩放和浮动一同暂停")
	get_tree().paused = false
	await _wait(0.25)
	_check(indicator.scale.is_equal_approx(original_scale), "解除暂停后继续完成出现动画")
	_check((goal.get_node("DetectArea") as CollisionShape2D).shape == original_shape and goal.scale == Vector2.ONE, "动画仅改变 Sprite，不影响触发区域")

	var other := GOAL.instantiate() as LevelGoal
	var other_indicator := other.get_node("Goal") as Sprite2D
	other_indicator.scale = Vector2(0.45, 0.2)
	level.add_child(other)
	other._set_preview(true)
	await _wait(0.25)
	_check(other_indicator.scale.is_equal_approx(Vector2(0.45, 0.2)), "支持用户自定义及非等比缩放")
	_check(indicator.scale.is_equal_approx(original_scale), "不同实例不会共享原始缩放")
	other._set_preview(false)
	other.queue_free()
	await _wait(0.2)
	_check(not is_instance_valid(other), "消失过程中释放实例会安全清理 Tween")
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("GOAL_ANIMATION_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
