## 真实影子布尔入口与删除流程，覆盖第十二关保护半径及其他关卡回归。
extends Node

const SHAPE := preload("res://Component/Shadowed_Geometry/Shadowed_Geometry.tscn")
const LAYER := preload("res://Component/Layer/Depth_Layer.tscn")
const PLAYER := preload("res://Component/Player/Player.tscn")
var _stage: Level
var _controller: ShadowControllerSystem
var _receiver: DepthLayer
var _caster: ShadowedGeometry
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("SHADOW_CUT_DISTANCE_TEST: " + message)

func _frames(count: int = 3) -> void:
	for index in count:
		await get_tree().process_frame

func _target(position: Vector2, collision_offset := Vector2.ZERO) -> ShadowedGeometry:
	var object := SHAPE.instantiate() as ShadowedGeometry
	object.can_leave_shadow = false
	object.can_be_shadowed = true
	object.freeze = true
	object.position = position
	(object.get_node("CollisionBox") as CollisionPolygon2D).position = collision_offset
	_receiver.add_child(object)
	return object

func _case(level_id: int, offset: Vector2, protected: bool) -> void:
	_stage.level_id = level_id
	var object := _target(Global.player.position + offset)
	_controller.shadow_boolean()
	await _frames()
	_check(is_instance_valid(object) == protected, "关卡 %d、距离 %.3fpx：%s" % [level_id, offset.length(), "保留物体" if protected else "正常切割"])
	if is_instance_valid(object):
		object.queue_free()
		await _frames(1)

func _run() -> void:
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.scene_ready()
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	SignalSystem.set_gameplay_active(false)
	_stage = Level.new()
	_stage.level_id = 12
	_stage.is_night = true
	_stage.current_layer_index = 1
	_stage.write_to_global()
	Global.level = _stage
	add_child(_stage)
	for slot in 4:
		var layer := LAYER.instantiate() as DepthLayer
		layer.layer_id = slot
		layer.slot = slot
		_stage.add_child(layer)
		Global.layers.append(layer)
		layer.cancel_cycle()
	_receiver = Global.get_layer_at_slot(3)
	Global.player = PLAYER.instantiate() as PlayerController
	_stage.add_child(Global.player)
	Global.player.set_physics_process(false)
	_controller = ShadowControllerSystem.new()
	_controller.cut_afterimage_duration = 0.0
	_stage.add_child(_controller)
	_caster = SHAPE.instantiate() as ShadowedGeometry
	_caster.freeze = true
	_caster.can_leave_shadow = true
	_caster.can_be_shadowed = false
	Global.get_layer_at_slot(2).add_child(_caster)
	_caster.shadow_box[0].polygon = PackedVector2Array([
		Vector2(-2000, -2000), Vector2(2000, -2000), Vector2(2000, 2000), Vector2(-2000, 2000),
	])
	for distance: float in [0.0, 50.0, 199.99, 200.0, 200.01, 201.0, 500.0, 1199.99, 1200.0, 1200.01]:
		await _case(12, Vector2(distance, 0), distance <= 200.0 or distance >= 1200.0)
	for offset: Vector2 in [Vector2(-199, 0), Vector2(0, -200), Vector2(120, 160), Vector2(-201, 0), Vector2(0, 201), Vector2(121, 160)]:
		await _case(12, offset, offset.length_squared() <= 200.0 * 200.0)
	for level_id in range(1, 12):
		await _case(level_id, Vector2.ZERO, false)
		await _case(level_id, Vector2(199, 0), false)
		await _case(level_id, Vector2(200, 0), false)
		await _case(level_id, Vector2(1200, 0), true)
	_stage.level_id = 12
	var near := _target(Vector2(600, 0), Vector2(-500, 0))
	near.visual_root.position = Vector2(5000, -4000)
	near.visual_root.scale = Vector2(0.3, 2.0)
	var far := _target(Vector2(50, 0), Vector2(300, 0))
	_controller.shadow_boolean()
	await _frames()
	_check(is_instance_valid(near) and not is_instance_valid(far), "距离沿用碰撞箱物理锚点，不读取物体根节点或视差后的 VisualRoot")
	near.queue_free()
	await _frames()
	_stage.position = Vector2(3000, 400)
	Global.player.position = Vector2(35, 80)
	await _case(12, Vector2(199, 0), true)
	await _case(12, Vector2(201, 0), false)
	var camera := Camera2D.new()
	camera.zoom = Vector2(2.0, 1.5)
	_stage.add_child(camera)
	Global.camera = camera
	await _case(12, Vector2(199, 0), true)
	await _case(12, Vector2(201, 0), false)
	near = _target(Global.player.position + Vector2(199, 0))
	far = _target(Global.player.position + Vector2(201, 0))
	var polygon := near.collision_box.polygon
	var shadow_polygon := _caster.shadow_box[0].polygon
	SignalSystem.timer.start(0.05)
	await SignalSystem.timer.timeout
	await _frames()
	_check(is_instance_valid(near) and not is_instance_valid(far), "真实 timer 到期经 shadow_boolean 同样只保护 200px 内物体")
	_check(SignalSystem.is_physics_resting() and SignalSystem.timer.is_stopped(), "距离保护不重置倒计时或改变夜间休眠逻辑")
	_check(near.collision_box.polygon == polygon and _caster.shadow_box[0].polygon == shadow_polygon and _caster.shadow_visual[0].visible, "保护对象几何和原有影子状态均保持不变")
	SignalSystem.timer.wait_time = 5.0
	SignalSystem.set_gameplay_active(false)
	Global.clear_scene_nodes()
	_stage.queue_free()
	await _frames()
	print("SHADOW_CUT_DISTANCE_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
