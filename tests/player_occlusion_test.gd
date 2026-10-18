## 真实 GPU 像素回归：只修改内存中的关卡，不写回用户场景。
extends Node

const OBJECT_SCRIPT := preload("res://Component/Object/Layer_Object.gd")
const BODY := preload("res://Component/Object/Others/Player_Object.tscn")
const OUTPUT := "res://.godot/player_occlusion_qa/"
var _game: Node2D
var _system: Node
var _probe: SubViewport
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("PLAYER_OCCLUSION_TEST: " + message)

func _frames(count: int = 3) -> void:
	for index in count:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _view() -> void:
	Global.camera.force_update_scroll()
	for layer in Global.layers:
		layer.apply_slot_state(Global.camera.global_position, Global.camera.zoom)
		layer.haze_plane.hide()
	_probe.size = Vector2i(get_viewport().get_visible_rect().size)
	(_probe.get_child(0) as ColorRect).size = Vector2(_probe.size)

func _block(layer: DepthLayer, bounds := Rect2(-400, -300, 800, 600)) -> LayerObject:
	var body: Node2D = StaticBody2D.new()
	body.set_script(OBJECT_SCRIPT)
	var polygon := PackedVector2Array([
		bounds.position, bounds.position + Vector2(bounds.size.x, 0),
		bounds.end, bounds.position + Vector2(0, bounds.size.y),
	])
	var collision := CollisionPolygon2D.new()
	collision.name = "CollisionBox"
	collision.polygon = polygon
	body.add_child(collision)
	var visual := Node2D.new()
	visual.name = "VisualRoot"
	body.add_child(visual)
	var shape := Polygon2D.new()
	shape.polygon = polygon
	shape.color = Color(0.7, 0.12, 0.08)
	visual.add_child(shape)
	layer.add_child(body)
	_view()
	return body as LayerObject

func _mask(pass_name: StringName) -> Image:
	return _system._captures[pass_name].get_texture().get_image()

func _coverage() -> Image:
	return _probe.get_texture().get_image()

func _peak(image: Image) -> float:
	var peak: float = 0.0
	var bytes := image.get_data()
	for index in range(3, bytes.size(), 4):
		peak = maxf(peak, bytes[index] / 255.0)
	return peak

func _verify_player_mask(message: String) -> void:
	var target := _mask(&"player_mask")
	var front := _mask(&"player_front")
	var coverage := _coverage()
	var maximum_error: float = 0.0
	var lit: int = 0
	for y in target.get_height():
		for x in target.get_width():
			var expected: float = target.get_pixel(x, y).a * front.get_pixel(x, y).a * _system.xray_color.a
			var actual := coverage.get_pixel(x, y).a
			maximum_error = maxf(maximum_error, absf(expected - actual))
			if actual > 0.1:
				lit += 1
	_check(maximum_error < 0.012 and lit > 200, message)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("人物透视像素回归需要真实 GPU")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	Global.next_level_id = 10 if OS.get_cmdline_user_args().has("--night") else 1
	_game = load("res://Interface/Game.tscn").instantiate() as Node2D
	_game.play_dialogue = false
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	_system = _game.get_node("PlayerOcclusionSystem")
	Global.player.set_physics_process(false)
	Global.player.player_animation.set_process(false)
	Global.player.position = Vector2(0, 40)
	Global.camera_fixed = false
	(_game.get_node("LayerControllerSystem") as Node).set_process(false)
	Global.camera.position = Vector2.ZERO
	Global.camera.offset = Vector2.ZERO
	Global.camera.zoom = Vector2.ONE
	SignalSystem.set_process(false)
	SignalSystem.timer.start(120.0)
	# 用户可调整关卡初始槽位；测试固定为前景、关卡层、两层后景。
	Global.current_layer_index = 1
	Global.level.current_layer_index = 1
	for layer in Global.layers:
		layer.cancel_cycle()
		for child in layer.get_children():
			if child is LayerObject:
				child.hide()
	_probe = SubViewport.new()
	_probe.world_2d = World2D.new()
	_probe.transparent_bg = true
	_probe.disable_3d = true
	_probe.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_probe)
	var quad := ColorRect.new()
	quad.material = _system._material
	_probe.add_child(quad)
	_view()
	await _frames()
	_check(_peak(_coverage()) < 0.005, "无物体遮挡时不显示蓝色")
	var front := Global.get_layer_at_slot(0)
	var current := Global.get_layer_at_slot(Global.current_layer_index)
	var rear := Global.get_layer_at_slot(2)
	var blocker := _block(front)
	await _frames()
	_check(_system._overlay.z_index > front.z_index and _system._overlay.get_canvas() == Global.player.get_canvas(), "剪影在世界前景之上，但不提升到 UI 画布")
	_check(_system._captures[&"player_mask"].canvas_transform == get_viewport().get_canvas_transform(), "捕获与主视口使用相同相机变换")
	_verify_player_mask("完全遮挡只显示贴图真实轮廓，没有矩形色块")
	var with_xray := get_viewport().get_texture().get_image()
	with_xray.save_png(OUTPUT + "01_player_covered.png")
	_system.enabled = false
	await _frames()
	var without := get_viewport().get_texture().get_image()
	var mask := _mask(&"player_mask")
	var changed: int = 0
	var leaked: int = 0
	for y in mask.get_height():
		for x in mask.get_width():
			var difference := with_xray.get_pixel(x, y) - without.get_pixel(x, y)
			if maxf(absf(difference.r), maxf(absf(difference.g), absf(difference.b))) > 0.02:
				changed += 1
				if mask.get_pixel(x, y).a < 0.001:
					leaked += 1
	_check(changed > 200 and leaked == 0, "最终画面确实透出蓝色，且只改变角色轮廓内的像素")
	_check(_system._captures.values().all(func(viewport: SubViewport) -> bool: return viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED), "关闭功能停止全部离屏捕获")
	_system.enabled = true
	var polygon := blocker.visual_root.get_child(0) as Polygon2D
	polygon.polygon = PackedVector2Array([Vector2(-400, -300), Vector2(0, -300), Vector2(0, 300), Vector2(-400, 300)])
	await _frames()
	_verify_player_mask("半遮挡只显示被覆盖的半侧")
	_coverage().save_png(OUTPUT + "02_partial_mask.png")
	blocker.transfer_to(rear, Transform2D.IDENTITY, Transform2D.IDENTITY)
	_view()
	await _frames()
	_check(_peak(_coverage()) < 0.005, "移到人物后方的物体不造成透视")
	blocker.transfer_to(front, Transform2D.IDENTITY, Transform2D.IDENTITY)
	polygon.polygon = PackedVector2Array([Vector2(-400, -300), Vector2(400, -300), Vector2(400, 300), Vector2(-400, 300)])
	blocker.modulate.a = 0.4
	_view()
	await _frames()
	_check(absf(_peak(_coverage()) - 0.4 * _system.xray_color.a) < 0.015, "半透明遮挡物对应较弱蓝色")
	var second := _block(front)
	second.modulate.a = 0.5
	await _frames()
	_check(absf(_peak(_coverage()) - 0.7 * _system.xray_color.a) < 0.015, "多个半透明遮挡物以 Alpha 合成，不直接相加")
	second.hide()
	front.z_index = -150
	await _frames()
	_check(_peak(_coverage()) < 0.005 and front.slot == 0, "判断实际渲染 Z，而非逻辑 slot")
	front.z_index = 100
	blocker.modulate.a = 1.0
	for zoom in [Vector2.ONE * 1.5, Vector2.ONE * 0.8]:
		Global.camera.zoom = zoom
		Global.camera.position = Vector2(13, -17)
		Global.camera.offset = Vector2(8, -20)
		_view()
		await _frames()
		_verify_player_mask("相机缩放及偏移后仍逐像素对齐")
	Global.camera.zoom = Vector2.ONE
	Global.camera.position = Vector2.ZERO
	Global.camera.offset = Vector2.ZERO
	Global.player.player_animation.set_display_mode(PlayerAnimation.DisplayMode.HEAD_ONLY)
	Global.player.current_state = PlayerController.PlayerState.UAV
	var body := BODY.instantiate() as LayerObject
	body.freeze = true
	body.position = Vector2(140, 40)
	current.add_child(body)
	(body.visual_root.get_node("PlayerSprite") as PlayerAnimation).set_process(false)
	Global.player.player_body = body
	_view()
	await _frames()
	_check(_peak(_mask(&"body_mask")) > 0.99 and _system._material.get_shader_parameter("body_active"), "无人机状态同时捕获独立身体")
	get_viewport().get_texture().get_image().save_png(OUTPUT + "03_uav_and_body.png")
	blocker.hide()
	var same := _block(current)
	same.front = true
	current.update_object_draw_order()
	await _frames()
	_check(_system._material.get_shader_parameter("has_same_layer") and _peak(_mask(&"body_same_layer")) > 0.99, "同层 front 物体会遮挡 PlayerObject")
	_check(_peak(_coverage()) > 0.5, "同层遮挡的身体也能透视")
	body.front = true
	same.front = false
	current.update_object_draw_order()
	await _frames()
	_check(not _system._material.get_shader_parameter("has_same_layer") and _peak(_coverage()) < 0.005, "同层物体改到身体后方后不再透视，也不把身体自身当遮挡物")
	body.front = false
	same.front = true
	current.update_object_draw_order()
	current.cycle_opacity = 0.5
	(current.material as ShaderMaterial).set_shader_parameter("cycle_opacity", 0.5)
	await _frames()
	_check(absf(_peak(_coverage()) - 0.5 * _system.xray_color.a) < 0.015, "同层共同淡出只应用一次透明度，不平方")
	current.cancel_cycle()
	same.hide()
	blocker.show()
	body.set_pick_condition(true)
	Global.object_selected = body
	await _frames()
	_check(_peak(_mask(&"body_mask")) > 0.99, "身体选中描边不会替代或污染目标轮廓")
	Global.object_selected = null
	body.set_pick_condition(false)
	var body_transform := body.global_transform
	body.transfer_to(rear, body_transform, body.collision_box.transform)
	_view()
	await _frames()
	_check(body.owner_layer == rear and _peak(_mask(&"body_mask")) > 0.9, "身体换层后目标捕获跟随新祖先与视差")
	var controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	_check(controller.cycle(1, false), "真实图层轮换可以正常开始")
	var aligned: bool = true
	var sort_matches: bool = true
	var torso := body.visual_root.get_node("PlayerSprite/Right/BodyRig/PlayerBodyRight") as Sprite2D
	for index in 24:
		await _frames(1)
		var point: Vector2 = get_viewport().get_canvas_transform() * torso.global_position
		var image := _mask(&"body_mask")
		if body.owner_layer.cycle_opacity > 0.1 and Rect2(Vector2.ZERO, Vector2(image.get_size())).has_point(point):
			aligned = aligned and image.get_pixel(roundi(point.x), roundi(point.y)).a > 0.05
		sort_matches = sort_matches and _system._captures[&"player_front"].canvas_cull_mask == _system._front_layers(Global.player)
	_check(aligned and sort_matches and not controller.is_cycling(), "Tween 全程按实时 Z 筛选前景，身体轮廓没有一帧视差延迟")
	for window_size in [Vector2i(1920, 720), Vector2i(1280, 900), Vector2i(1280, 720)]:
		get_tree().root.size = window_size
		await _frames(1)
		_view()
		await _frames()
		_check(_system._captures[&"player_mask"].size == Vector2i(get_viewport().get_visible_rect().size), "窗口比例变化同步更新遮罩尺寸")
	var transforms := [Global.player.transform, body.transform, body.collision_box.transform]
	get_tree().paused = true
	await _frames(4)
	_check(transforms == [Global.player.transform, body.transform, body.collision_box.transform], "暂停与透视不会改变任何物理变换")
	get_tree().paused = false
	Global.player.UAV_activate()
	for index in 90:
		if Global.player.current_state == PlayerController.PlayerState.NORMAL:
			break
		await _frames(1)
	await _frames()
	_check(Global.player.current_state == PlayerController.PlayerState.NORMAL and Global.player.player_body == null, "真实无人机收回完成多次轮换、位移和身体释放")
	_check(not _system._material.get_shader_parameter("has_body") and _system._captures[&"body_mask"].render_target_update_mode == SubViewport.UPDATE_DISABLED, "无人机收回后清除身体目标并停止捕获")
	# 选中身体时用真实暂停菜单重开，覆盖旧场景的清理顺序。
	body = BODY.instantiate() as LayerObject
	body.freeze = true
	Global.get_layer_at_slot(Global.current_layer_index).add_child(body)
	body.position = Global.player.position
	Global.player.player_body = body
	Global.player.current_state = PlayerController.PlayerState.UAV
	Global.object_selected = body
	body.set_pick_condition(true)
	await _frames()
	var old_system: WeakRef = weakref(_system)
	_probe.queue_free()
	await _frames()
	var pause := _game.get_node("Camera/MenuUI/Screen/Pause") as Control
	pause.open()
	pause._begin_hold(pause.HoldAction.RESTART)
	pause._on_hold_timeout()
	await SceneTransition.transition_finished
	await _frames()
	_game = get_tree().current_scene as Node2D
	_check(old_system.get_ref() == null and Global.object_selected == null, "选中身体时重开关卡，旧透视与选择引用均被安全清理")
	_check(_game.get_node("PlayerOcclusionSystem") != null and Global.player.player_body == null, "重开后建立全新透视系统，无残留身体")
	_game.queue_free()
	await _frames()
	_check(Global.player == null, "离场安全清理人物引用")
	print("PLAYER_OCCLUSION_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
