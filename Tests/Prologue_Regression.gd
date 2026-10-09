## 序章核心行为回归：使用独立小场景与真实2D物理，不依赖白模关卡的节点摆放。
## 运行：Godot --headless --path . res://Tests/Prologue_Regression.tscn
## 使用普通场景加载，使Global自动挂载先初始化，再解析依赖它的公共组件。
extends Node

const PLAYER_SCENE = preload("res://Component/Player/Player.tscn")
const GROUND_SCENE = preload("res://Component/Object/Ground/Ground.tscn")
const TRANSFER_PLATFORM_SCENE = preload("res://Component/Object/Transfer_Platform/Transfer_Platform.tscn")
const PROLOGUE_GAME_SCENE = preload("res://Prologue_Test_Game.tscn")

var _global: Node
var _failures: Array[String] = []
var _checks: int = 0
var _last_transfer: Dictionary = {}


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_global = get_tree().root.get_node("Global")
	_global.transfer_result.connect(_on_transfer_result)
	_test_input_map()
	await _test_default_layers()
	await _test_uav_compatibility()
	await _test_prologue_restrictions()
	await _test_physics_view_updates()
	await _test_platform_depth_style()
	await _test_mouse_selection()
	await _test_transfer_geometry()
	await _test_transfer_collision()
	await _test_freed_selection()
	await _test_movement()
	await _test_diagnostic_camera_controls()
	_release_inputs()
	print("PROLOGUE_REGRESSION: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures:
		push_error(failure)
	get_tree().quit(0 if _checks > 0 and _failures.is_empty() else 1)


func _test_input_map() -> void:
	_check(_key_event(KEY_A).is_action_pressed("move_left"), "实际A键事件映射到左移")
	_check(_key_event(KEY_D).is_action_pressed("move_right"), "实际D键事件映射到右移")
	_check(_key_event(KEY_SPACE).is_action_pressed("jump"), "实际Space键事件映射到跳跃")
	_check(_key_event(KEY_W).is_action_pressed("transfer_forward"), "实际W键事件映射到移近物件")
	_check(_key_event(KEY_S).is_action_pressed("transfer_backward"), "实际S键事件映射到移远物件")
	_check(_key_event(KEY_SHIFT).is_action_pressed("sprint"), "实际Shift键事件映射到冲刺/奔跑")
	_check(_key_event(KEY_PAGEUP).is_action_pressed("UAV"), "实际Page Up键事件映射到无人机")
	_check(not _key_event(KEY_PAGEDOWN).is_action_pressed("UAV"), "Page Down不会错误映射为无人机键")


func _test_default_layers() -> void:
	var fixture: Dictionary = await _make_fixture(4, 1, true)
	var system: SystemController = fixture.system
	var player: PlayerController = fixture.player
	_check(_global.layer_scales.size() == 4, "默认配置生成四个倍率")
	_check(is_equal_approx(_global.layer_scales[0], 1.25), "默认前景倍率为1.25")
	_check(is_equal_approx(_global.layer_scales[3], 0.64), "默认远景倍率为0.64")
	_check_collision_bits(fixture)
	var original_slots: Array[int] = _slots(fixture)
	_global.clear_selection()
	_send_action("transfer_forward")
	await _tick(2)
	_check(_slots(fixture) == original_slots, "允许轮换的原型中，空选W也不会轮换图层")
	for index in range(4):
		system.cycle(1)
		var active: DepthLayer = system.get_layer_at_slot(1)
		_check(player.collision_mask == 1 << active.layer_id, "正向轮换%d次后玩家只碰当前内容层" % (index + 1))
	_check(_slots(fixture) == original_slots, "四层完整正向轮换返回原槽位")
	for index in range(4):
		system.cycle(-1)
		var active: DepthLayer = system.get_layer_at_slot(1)
		_check(player.collision_mask == 1 << active.layer_id, "反向轮换%d次后玩家只碰当前内容层" % (index + 1))
	_check(_slots(fixture) == original_slots, "四层完整反向轮换返回原槽位")
	await _destroy_fixture(fixture)


func _test_uav_compatibility() -> void:
	var fixture: Dictionary = await _make_fixture(4, 1, true)
	var system: SystemController = fixture.system
	var player: PlayerController = fixture.player
	var current: DepthLayer = system.get_layer_at_slot(1)
	player.scale = Vector2(1.25, 1.25)
	player.set_physics_process(true)
	await _tick(4)
	_check(player.is_on_floor(), "四层旧原型的缩放角色通过真实物理接地")
	var original_scale: Vector2 = player.scale
	var original_position: Vector2 = player.global_position
	_global._unhandled_input(_key_event(KEY_PAGEUP))
	await _tick(3)
	var body: Player_Object = player.player_body
	_check(system.UAV_activated and player.UAV_activated and is_instance_valid(body), "接地Page Up激活无人机并生成角色身体")
	if not is_instance_valid(body):
		await _destroy_fixture(fixture)
		return
	_check(body.global_position.distance_to(original_position) < 1.0, "无人机身体保持角色原有位置")
	_check(body.collision_box.global_scale.is_equal_approx(original_scale), "无人机身体继承已经缩放的角色实体尺寸")
	_check(body.owner_layer == current and body.collision_layer == 1 << current.layer_id and body.collision_mask == 1 << current.layer_id, "无人机身体具有当前内容层的唯一碰撞身份")
	_check(player.body_collision_box.disabled and not player.UAV_collision_box.disabled, "无人机启用时只使用无人机碰撞轮廓")
	_global.select_object(body)
	_global._unhandled_input(_key_event(KEY_PAGEUP))
	await _tick(4)
	_check(not system.UAV_activated and not player.UAV_activated and not is_instance_valid(player.player_body), "Page Up退出无人机并清理身体引用")
	_check(not is_instance_valid(body) and not is_instance_valid(_global.object_selected), "选中身体后退出会释放身体并安全清理选择")
	_check(player.scale.is_equal_approx(original_scale) and player.is_on_floor(), "退出无人机后恢复缩放尺寸并能在原地接地")
	_check(not player.body_collision_box.disabled and player.UAV_collision_box.disabled, "无人机退出时恢复角色碰撞轮廓")
	_global._unhandled_input(_key_event(KEY_PAGEUP))
	await _tick(3)
	body = player.player_body
	_check(system.UAV_activated and is_instance_valid(body), "退出后可以重复激活无人机")
	if not is_instance_valid(body):
		await _destroy_fixture(fixture)
		return
	_check(body.collision_box.global_scale.is_equal_approx(original_scale), "重复激活仍继承正确尺寸，不重置或累计缩放")
	## 冻结这一次身体，隔离跨层瞬间几何；目标背景没有地面，不验证其落地。
	body.set("freeze", true)
	await _tick(1)
	var visual_before: PackedVector2Array = _visual_corners(body, "VisualRoot/Visual_Body")
	_global.select_object(body)
	_last_transfer = {}
	_send_action("transfer_backward")
	await _tick(2)
	_check(body.owner_layer == current and _last_transfer.is_empty(), "无人机飞行中S保留移动用途，不搬运选中的身体")
	_send_action("transfer_forward")
	await _tick(2)
	_check(body.owner_layer == current and _last_transfer.is_empty(), "无人机飞行中W保留移动用途，不搬运选中的身体")
	await _transfer(body, -1, true)
	_check(body.owner_layer == system.get_layer_at_slot(2), "旧原型角色身体仍可作为物件送入背景")
	_check(_corners_equal(visual_before, _visual_corners(body, "VisualRoot/Visual_Body")), "角色身体换层保持画面位置与大小连续")
	_check(body.collision_layer == 1 << body.owner_layer.layer_id and body.collision_mask == 1 << body.owner_layer.layer_id, "角色身体换层后只碰目标内容层")
	await _transfer(body, 1, true)
	_check(body.owner_layer == current and body.collision_box.global_scale.is_equal_approx(original_scale), "角色身体返回原层后恢复原来的实体尺寸")
	_global._unhandled_input(_key_event(KEY_PAGEUP))
	await _tick(4)
	_check(player.scale.is_equal_approx(original_scale) and not is_instance_valid(_global.object_selected), "身体跨层往返后退出仍保留角色尺寸并清理选择")
	Input.action_press("jump")
	await _tick(1)
	Input.action_release("jump")
	await _tick(2)
	_check(not player.is_on_floor(), "空中拒绝测试确实从真实跳跃进入空中")
	_global._unhandled_input(_key_event(KEY_PAGEUP))
	await _tick(2)
	_check(not system.UAV_activated and not player.UAV_activated and not is_instance_valid(player.player_body), "空中Page Up不能召唤无人机或遗留身体")
	await _destroy_fixture(fixture)


func _test_prologue_restrictions() -> void:
	## 固定内容ID与槽位反序，避免错误地把slot当作碰撞ID。
	var fixture: Dictionary = await _make_fixture(2, 0, false, true)
	var system: SystemController = fixture.system
	var player: PlayerController = fixture.player
	_check_collision_bits(fixture)
	_check(_global.layer_scales == [1.0, 0.8], "两层配置生成玩家层与背景倍率")
	var original_slots: Array[int] = _slots(fixture)
	system.cycle(1)
	system.UAV_activate()
	_check(not system.UAV_activated and not player.UAV_activated, "序章禁止启用无人机")
	_global.clear_selection()
	_send_action("transfer_forward")
	_send_action("transfer_backward")
	_send_action("forward")
	_send_action("backward")
	await _tick(3)
	_check(_slots(fixture) == original_slots, "序章禁止轮换，空选W/S与旧Q/E也不会轮换")
	var active: DepthLayer = system.get_layer_at_slot(0)
	_check(player.collision_mask == 1 << active.layer_id, "两层序章玩家碰撞跟随固定内容ID")
	await _destroy_fixture(fixture)


func _test_transfer_geometry() -> void:
	var fixture: Dictionary = await _make_fixture(2, 0)
	var system: SystemController = fixture.system
	var background: DepthLayer = system.get_layer_at_slot(1)
	var object: LayerObject = _make_rectangle(background, "Movable", Vector2(350, -100), Vector2(100, 50), true)
	await _tick(2)
	var original_position: Vector2 = object.global_position
	var original_size: Vector2 = object.collision_box.scale
	var visual_before: PackedVector2Array = _visual_corners(object)
	await _transfer(object, 1)
	_check(object.owner_layer == system.get_layer_at_slot(0), "W将背景物件搬入玩家层")
	_check(_last_transfer.get("success", false), "成功搬入返回成功反馈")
	_check(_corners_equal(visual_before, _visual_corners(object)), "搬入保留可见轮廓的全局位置与大小")
	_check(object.collision_layer == 1 << object.owner_layer.layer_id, "搬入后实体仅在目标内容层碰撞")
	var landed_position: Vector2 = object.global_position
	await _tick(30)
	_check(object.global_position.is_equal_approx(landed_position), "静态搬运平台悬停，不受重力影响")
	var fixture_player: PlayerController = fixture.player
	fixture_player.global_position.x += 80.0
	await _tick(2)
	_check(object.global_position.is_equal_approx(landed_position), "玩家改变站位后，已搬入的平台位置固定")
	fixture_player.global_position.x -= 80.0
	await _tick(2)
	await _transfer(object, -1)
	_check(object.owner_layer == background, "S将物件送回背景")
	_check(object.global_position.is_equal_approx(original_position), "固定锚点的跨层往返恢复真实位置")
	_check(object.collision_box.scale.is_equal_approx(original_size), "固定倍率往返不会持续放大物件")
	_check(_corners_equal(visual_before, _visual_corners(object)), "跨层往返仍保持可见轮廓连续")
	await _transfer(object, -1)
	_check(object.owner_layer == background and not _last_transfer.get("success", true), "最远层拒绝继续后移，不循环到前景")
	await _destroy_fixture(fixture)


func _test_physics_view_updates() -> void:
	var fixture: Dictionary = await _make_fixture(2, 0)
	var system: SystemController = fixture.system
	var player: PlayerController = fixture.player
	var camera: Camera2D = fixture.camera
	_check(ProjectSettings.get_setting("physics/common/physics_interpolation", false), "项目全局启用物理插值")
	_check(system.process_physics_priority > player.process_physics_priority, "图层与相机协调在玩家物理移动之后执行")
	_check(camera.process_callback == Camera2D.CAMERA2D_PROCESS_PHYSICS, "相机使用物理更新回调")
	_check(camera.process_physics_priority > system.process_physics_priority, "相机画布提交在图层投影更新之后执行")
	var background: DepthLayer = system.get_layer_at_slot(1)
	var object: LayerObject = _make_rectangle(background, "PhysicsProjection", Vector2(400, -100), Vector2(40, 40), true)
	await _tick(2)
	var projected_before: Vector2 = object.visual_root.global_position
	var camera_before: Vector2 = camera.global_position
	system.set_physics_process(false)
	player.global_position.x = 160.0
	await _tick(2)
	_check(object.visual_root.global_position.is_equal_approx(projected_before) and camera.global_position.is_equal_approx(camera_before), "停止物理投影更新后，idle帧不会另行修改相机与背景位置")
	system.set_physics_process(true)
	await _physics_tick()
	_check(absf(camera.global_position.x - player.global_position.x) < 0.1, "恢复物理更新后同一tick同步相机位置")
	_check(absf(object.visual_root.global_position.x - projected_before.x - 32.0) < 0.1, "背景0.8倍率在物理tick中正确产生站位视差")
	var original_entity_position: Vector2 = object.global_position
	player.global_position.x = -200.0
	system.reset_view_interpolation()
	_check(absf(camera.global_position.x + 200.0) < 0.1 and absf(object.visual_root.global_position.x - 280.0) < 0.1, "恢复视图立即应用传送后的相机与背景投影位置")
	_check(object.global_position.is_equal_approx(original_entity_position), "视差与插值恢复不改动背景物件实体位置")
	await _destroy_fixture(fixture)


func _test_platform_depth_style() -> void:
	## 前后内容ID反序；层名、填色与边缘必须依据视觉slot，而不是固定layer_id。
	var fixture: Dictionary = await _make_fixture(2, 0, true, true)
	var system: SystemController = fixture.system
	var background: DepthLayer = system.get_layer_at_slot(1)
	var platform: TransferPlatform = TRANSFER_PLATFORM_SCENE.instantiate() as TransferPlatform
	platform.name = "StyledPlatform"
	platform.dimensions = Vector2(100, 60)
	platform.color = Color(0.9, 0.62, 0.3, 1.0)
	platform.caption = "测试平台"
	platform.position = Vector2(350, -100)
	background.add_child(platform)
	await _tick(2)
	var polygon: Polygon2D = platform.get_node("VisualRoot/Polygon2D") as Polygon2D
	var top_edge: Line2D = platform.get_node("VisualRoot/TopEdge") as Line2D
	var caption: Label = platform.get_node("VisualRoot/Caption") as Label
	var selection: Line2D = platform.get_node("VisualRoot/Selection") as Line2D
	var background_fill: Color = polygon.color
	var background_edge_width: float = top_edge.width
	_check(background.layer_id == 0 and caption.text.contains("背景"), "背景物件显示当前背景层名，不把固定ID0当作玩家层")
	_check(background_fill != platform.color and is_equal_approx(background_fill.a, platform.color.a), "背景使用不同填色降低对比，同时保留填色alpha")
	_global.select_object(platform)
	await _tick(1)
	_check(selection.is_visible_in_tree() and is_equal_approx(selection.default_color.a * _effective_item_alpha(selection), 1.0), "背景选中轮廓独立清晰，不随整体alpha变淡")
	var visual_before: PackedVector2Array = _visual_corners(platform)
	await _transfer(platform, 1)
	_check(platform.owner_layer == system.get_layer_at_slot(0) and caption.text.contains("玩家层") and not caption.text.contains("背景"), "搬入后平台标签立即更新为玩家层")
	_check(polygon.color == platform.color and top_edge.width > background_edge_width, "搬入后恢复实体色与清晰顶边")
	_check(_corners_equal(visual_before, _visual_corners(platform)), "图层风格更新不破坏搬运画面几何连续性")
	_check(selection.is_visible_in_tree() and is_equal_approx(selection.default_color.a * _effective_item_alpha(selection), 1.0), "搬层后仍保留完整的选中轮廓")
	await _transfer(platform, -1)
	_check(caption.text.contains("背景") and polygon.color == background_fill, "送回背景后恢复背景标签与填色")
	var fixed_id: int = platform.owner_layer.layer_id
	system.cycle(1)
	_check(platform.owner_layer.layer_id == fixed_id and platform.owner_layer.slot == 0, "整体轮换只改变平台视觉槽位，保留内容身份")
	_check(caption.text.contains("玩家层") and polygon.color == platform.color and top_edge.width > background_edge_width, "整体轮换后标签与外观随slot更新")
	await _destroy_fixture(fixture)


func _test_mouse_selection() -> void:
	var fixture: Dictionary = await _make_fixture(2, 0)
	var system: SystemController = fixture.system
	var front: LayerObject = _make_rectangle(system.get_layer_at_slot(0), "FrontPick", Vector2(300, -100), Vector2(80, 40), true)
	var back: LayerObject = _make_rectangle(system.get_layer_at_slot(1), "BackPick", Vector2(375, -125), Vector2(100, 50), true)
	await _tick(3)
	_click_world(Vector2(300, -100))
	await _tick(3)
	_check(_global.object_selected == front, "左键对重叠视觉代理执行真实查询，选中有效z更高的玩家层物件")
	_click_world(Vector2(300, -100))
	await _tick(3)
	_check(not is_instance_valid(_global.object_selected), "重复左键选中物件取消选择")
	front.queue_free()
	await _tick(2)
	_click_world(Vector2(300, -100))
	await _tick(3)
	_check(_global.object_selected == back, "前层物件释放后能够选中其后的背景物件")
	_click_world(Vector2(-500, -100))
	await _tick(3)
	_check(not is_instance_valid(_global.object_selected), "左键空白区域取消选择")
	await _destroy_fixture(fixture)


func _test_transfer_collision() -> void:
	var fixture: Dictionary = await _make_fixture(2, 0)
	var system: SystemController = fixture.system
	var active: DepthLayer = system.get_layer_at_slot(0)
	var background: DepthLayer = system.get_layer_at_slot(1)
	var object: LayerObject = _make_rectangle(background, "Movable", Vector2(375, -125), Vector2(100, 50), true)
	await _tick(2)
	var target_center: Vector2 = object.visual_root.global_position
	var wall: LayerObject = _make_rectangle(active, "BlockingWall", target_center, Vector2(100, 100), false)
	await _tick(2)
	var original_position: Vector2 = object.global_position
	var original_scale: Vector2 = object.collision_box.scale
	var original_mask: int = object.collision_mask
	await _transfer(object, 1)
	_check(not _last_transfer.get("success", true), "目标墙体占用时拒绝搬入")
	_check(object.owner_layer == background and object.get_parent() == background, "拒绝搬入后保留原所属层与父节点")
	_check(object.global_position.is_equal_approx(original_position) and object.collision_box.scale.is_equal_approx(original_scale), "拒绝搬入后保留真实位置与尺寸")
	_check(object.collision_mask == original_mask, "拒绝搬入后保留碰撞归属")
	_check(not str(_last_transfer.get("reason", "")).is_empty(), "拒绝搬入提供原因")
	wall.queue_free()
	await _tick(2)
	var player: PlayerController = fixture.player
	## 相机横向跟随角色，角色站到背景物件的真实x处时，投影x才与角色相同。
	player.global_position = Vector2(object.global_position.x, target_center.y + 20.0)
	await _tick(2)
	await _transfer(object, 1)
	_check(not _last_transfer.get("success", true) and object.owner_layer == background, "目标与玩家实体重叠时拒绝搬入")
	player.global_position = Vector2.ZERO
	object.global_position = Vector2(375, -23.5)
	await _tick(2)
	await _transfer(object, 1)
	_check(not _last_transfer.get("success", true) and object.owner_layer == background, "超出接触容差的地面穿入仍拒绝搬运")
	object.global_position = Vector2(375, -25)
	await _tick(2)
	await _transfer(object, 1)
	_check(_last_transfer.get("success", false) and object.owner_layer == active, "平台底边与地面顶边正常接缝允许搬入")
	var front_position: Vector2 = object.global_position
	await _transfer(object, 1)
	_check(not _last_transfer.get("success", true) and object.global_position.is_equal_approx(front_position), "最近层拒绝继续前移")
	await _destroy_fixture(fixture)


func _test_freed_selection() -> void:
	var fixture: Dictionary = await _make_fixture(2, 0)
	var layer: DepthLayer = fixture.system.get_layer_at_slot(1)
	var object: LayerObject = _make_rectangle(layer, "TemporarySelection", Vector2(300, -100), Vector2(40, 40), true)
	await _tick(2)
	_global.select_object(object)
	_check(_global.object_selected == object, "可选物件能够成为当前选中对象")
	object.queue_free()
	await _tick(2)
	_global.clear_selection()
	_send_action("transfer_forward")
	await _tick(2)
	_check(not is_instance_valid(_global.object_selected), "选中对象释放后安全清空，随后W不会访问已释放对象")
	await _destroy_fixture(fixture)


func _test_movement() -> void:
	var fixture: Dictionary = await _make_fixture(2, 0)
	var player: PlayerController = fixture.player
	player.set_physics_process(true)
	await _tick(4)
	_check(player.is_on_floor(), "角色通过真实物理站在测试地面")
	Input.action_press("move_right")
	await _tick(20)
	var walking_speed: float = player.velocity.x
	_check(walking_speed > 200.0 and walking_speed <= player.move_speed + 1.0, "D正常行走达到步行速度")
	Input.action_press("sprint")
	await _physics_tick()
	_check(player.is_running and not player.dash_active and player.velocity.x > walking_speed, "Shift按下的第一个物理tick立即奔跑加速，无0.18秒等待")
	await _tick(1)
	Input.action_release("sprint")
	await _tick(1)
	_check(player.dash_active and player.velocity.x > walking_speed * 1.5, "短按Shift释放后产生短冲刺")
	await _tick(12)
	_check(not player.dash_active, "短冲刺会按持续时间结束")
	await _tick(20)
	Input.action_press("sprint")
	await _tick(20)
	var running_speed: float = player.velocity.x
	_check(player.is_running and not player.dash_active and running_speed > walking_speed * 1.2, "长按Shift进入持续奔跑")
	player.reset_motion()
	await _tick(20)
	_check(player.is_running and not player.dash_active and player.velocity.x > walking_speed * 1.2, "恢复清空运动状态后，仍按住Shift能够继续奔跑")
	Input.action_release("sprint")
	await _tick(1)
	_check(not player.is_running and not player.dash_active, "长按Shift释放后停止奔跑，不额外触发冲刺")
	var camera: Camera2D = fixture.camera
	_check(absf(camera.global_position.x - player.global_position.x) < 0.1, "相机横向持续跟随角色")
	await _destroy_fixture(fixture)
	var walking_jump: float = await _measure_jump(false)
	var running_jump: float = await _measure_jump(true)
	_check(running_jump > walking_jump * 1.2, "跑跳在相同地面与跳跃参数下比走跳更远")
	await _test_dash_wall()


func _measure_jump(running: bool) -> float:
	var fixture: Dictionary = await _make_fixture(2, 0)
	var player: PlayerController = fixture.player
	player.set_physics_process(true)
	await _tick(4)
	Input.action_press("move_right")
	if running:
		Input.action_press("sprint")
	await _tick(25)
	var start_x: float = player.global_position.x
	Input.action_press("jump")
	await _tick(1)
	Input.action_release("jump")
	var airborne: bool = not player.is_on_floor()
	var highest_y: float = player.global_position.y
	var locked_camera: bool = true
	for index in range(90):
		await _tick(1)
		highest_y = minf(highest_y, player.global_position.y)
		locked_camera = locked_camera and absf(fixture.camera.global_position.y) < 0.1
		if player.is_on_floor() and airborne:
			break
		airborne = airborne or not player.is_on_floor()
	var distance: float = player.global_position.x - start_x
	_check(airborne and highest_y < -50.0 and player.is_on_floor(), "%sSpace触发跳跃并成功落地" % ("跑动时" if running else "行走时"))
	_check(locked_camera, "%s跳跃过程中相机高度锁定" % ("跑动" if running else "行走"))
	await _destroy_fixture(fixture)
	return distance


func _test_dash_wall() -> void:
	var fixture: Dictionary = await _make_fixture(2, 0)
	var player: PlayerController = fixture.player
	var active: DepthLayer = fixture.system.get_layer_at_slot(0)
	_make_rectangle(active, "Wall", Vector2(150, -50), Vector2(40, 100), false)
	player.set_physics_process(true)
	await _tick(4)
	Input.action_press("move_right")
	await _tick(10)
	Input.action_press("sprint")
	await _tick(2)
	Input.action_release("sprint")
	await _tick(20)
	_check(player.is_on_wall() and player.global_position.x <= 120.5, "冲刺由真实墙体阻挡，不穿透墙面")
	_check(not player.dash_active, "撞墙结束冲刺")
	_release_inputs()
	Input.action_press("move_left")
	await _tick(15)
	_check(player.velocity.x < -200.0 and player.global_position.x < 100.0, "A能够离开墙面向左行走")
	await _destroy_fixture(fixture)


func _test_diagnostic_camera_controls() -> void:
	## 使用完整白模与实际视口按键，验证诊断模式不会冻结人物或遗留固定镜头。
	_release_inputs()
	_global.clear_selection()
	var game := PROLOGUE_GAME_SCENE.instantiate() as Node2D
	add_child(game)
	var level := game.get_node("Level") as PrologueTestLevel
	var player := game.get_node("Player") as PlayerController
	var camera := game.get_node("Camera") as Camera2D
	var system := game.get_node("System") as SystemController
	await _tick(6)
	get_viewport().push_input(_key_event(KEY_F7), true)
	var fixed_position := camera.global_position
	var background_box := level.get_node("BackgroundLayer/StepBox") as LayerObject
	var fixed_background_position := background_box.visual_root.global_position
	var player_start_x := player.global_position.x
	Input.action_press("move_right")
	await _tick(15)
	_check(not system.camera_fixed and camera.global_position.is_equal_approx(fixed_position) and background_box.visual_root.global_position.is_equal_approx(fixed_background_position) and player.global_position.x > player_start_x + 30.0, "F7固定镜头后，背景视图固定且人物继续通过真实物理移动")
	get_viewport().push_input(_key_event(KEY_F4), true)
	_check(system.camera_fixed and absf(camera.global_position.x - player.global_position.x) < 0.1 and absf(camera.get_screen_center_position().x - player.global_position.x) < 0.1, "F4关闭诊断立即恢复跟随并清空固定镜头的插值历史")
	await _tick(5)
	_check(absf(camera.global_position.x - player.global_position.x) < 0.1 and camera.global_position.x > fixed_position.x + 30.0, "关闭诊断后，镜头在后续物理tick继续跟随移动人物")
	get_viewport().push_input(_key_event(KEY_F7), true)
	await _tick(5)
	_release_inputs()
	get_viewport().push_input(_key_event(KEY_R), true)
	_check(system.camera_fixed and player.global_position.distance_to(level.checkpoint_position) < 0.1 and absf(camera.get_screen_center_position().x - level.checkpoint_position.x) < 0.1, "固定镜头期间按R恢复出生点与跟随，画面不会停在诊断位置")
	get_viewport().push_input(_key_event(KEY_F7), true)
	get_viewport().push_input(_key_event(KEY_F3), true)
	_check(system.camera_fixed and level.current_section == 2 and absf(camera.get_screen_center_position().x - player.global_position.x) < 0.1, "固定镜头期间F3切段立即恢复跟随与新片段画面")
	get_viewport().push_input(_key_event(KEY_F4), true)
	_global.clear_selection()
	game.queue_free()
	await _tick(2)


func _make_fixture(count: int, current: int, advanced: bool = false, reverse_ids: bool = false) -> Dictionary:
	_release_inputs()
	_global.clear_selection()
	var world := Node2D.new()
	world.name = "RegressionFixture"
	var level := Level.new()
	level.name = "Level"
	level.layer_count = count
	level.current_layer_index = current
	level.layer_scale = 0.8
	level.set("allow_layer_cycle", advanced)
	level.set("allow_uav", advanced)
	level.set("allow_object_transfer", true)
	level.set("lock_camera_y", true)
	level.set("camera_height", 0.0)
	world.add_child(level)
	var layers: Array[DepthLayer] = []
	for slot in range(count):
		var layer := DepthLayer.new()
		layer.name = "Layer%d" % slot
		layer.slot = slot
		layer.layer_id = count - slot - 1 if reverse_ids else slot
		level.add_child(layer)
		layers.append(layer)
	var floor_object: LayerObject = _make_rectangle(layers[current], "Floor", Vector2(0, 50), Vector2(4000, 100), false)
	var player: PlayerController = PLAYER_SCENE.instantiate() as PlayerController
	player.name = "Player"
	player.set_physics_process(false)
	world.add_child(player)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	world.add_child(camera)
	var system := SystemController.new()
	system.name = "System"
	system.player = player
	system.camera = camera
	system.level = level
	world.add_child(system)
	get_tree().root.add_child(world)
	player.set_physics_process(false)
	await _tick(3)
	return {"world": world, "level": level, "layers": layers, "player": player, "camera": camera, "system": system, "floor": floor_object}


func _make_rectangle(layer: DepthLayer, object_name: String, center: Vector2, dimensions: Vector2, transferable: bool) -> LayerObject:
	var body: LayerObject = GROUND_SCENE.instantiate() as LayerObject
	body.name = object_name
	body.position = center
	body.can_transfer = transferable
	var half: Vector2 = dimensions * 0.5
	var points := PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	(body.get_node("CollisionBox") as CollisionPolygon2D).polygon = points
	(body.get_node("VisualRoot/Polygon2D") as Polygon2D).polygon = points
	if transferable:
		var area := Area2D.new()
		area.name = "PickArea"
		area.monitoring = false
		area.monitorable = false
		area.input_pickable = true
		var pick_shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = dimensions
		pick_shape.shape = rectangle
		area.add_child(pick_shape)
		body.get_node("VisualRoot").add_child(area)
	layer.add_child(body)
	return body


func _check_collision_bits(fixture: Dictionary) -> void:
	for object in get_tree().get_nodes_in_group("layer_objects"):
		var expected: int = 1 << object.owner_layer.layer_id
		_check(object.collision_layer == expected and object.collision_mask == expected, "%s实体初始化只有所属内容层碰撞位" % object.name)
	var active: DepthLayer = fixture.system.get_layer_at_slot(fixture.level.current_layer_index)
	_check(fixture.player.collision_layer == 1 << active.layer_id and fixture.player.collision_mask == 1 << active.layer_id, "玩家初始化只有当前内容层碰撞位")


func _visual_corners(object: LayerObject, polygon_path: String = "VisualRoot/Polygon2D") -> PackedVector2Array:
	var result := PackedVector2Array()
	var polygon: Polygon2D = object.get_node(polygon_path) as Polygon2D
	for point in polygon.polygon:
		result.append(polygon.global_transform * point)
	return result


func _corners_equal(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	if first.size() != second.size():
		return false
	for index in range(first.size()):
		if first[index].distance_to(second[index]) > 0.1:
			return false
	return true


func _effective_item_alpha(item: CanvasItem) -> float:
	## self_modulate只影响节点自己的绘制，祖先modulate则会影响其所有子节点。
	var result: float = item.self_modulate.a
	var ancestor: CanvasItem = item
	while ancestor != null:
		result *= ancestor.modulate.a
		ancestor = ancestor.get_parent() as CanvasItem
	return result


func _slots(fixture: Dictionary) -> Array[int]:
	var result: Array[int] = []
	for layer in fixture.layers:
		result.append(layer.slot)
	return result


func _transfer(object: LayerObject, direction: int, legacy: bool = false) -> void:
	_last_transfer = {}
	_global.select_object(object)
	if legacy:
		_send_action("forward" if direction > 0 else "backward")
	else:
		_send_action("transfer_forward" if direction > 0 else "transfer_backward")
	await _tick(3)
	_check(not _last_transfer.is_empty(), "物件输入在物理更新中执行并返回结果")


func _send_action(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	_global._unhandled_input(event)


func _key_event(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _click_world(world_position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.pressed = true
	event.position = get_tree().root.get_canvas_transform() * world_position
	event.global_position = event.position
	_global._unhandled_input(event)


func _on_transfer_result(_object: LayerObject, success: bool, reason: String) -> void:
	_last_transfer = {"success": success, "reason": reason}


func _physics_tick() -> void:
	await get_tree().physics_frame
	## 物理timer在本tick的全部节点更新后发出，避免把idle期间的多tick算成首tick。
	await get_tree().create_timer(0.0, true, true).timeout


func _tick(frames: int) -> void:
	for index in range(frames):
		await get_tree().physics_frame
	await get_tree().process_frame
	## process_frame在节点_process之前发出，零时长timer在节点更新后发出。
	await get_tree().create_timer(0.0).timeout


func _destroy_fixture(fixture: Dictionary) -> void:
	_release_inputs()
	_global.clear_selection()
	fixture.world.queue_free()
	await _tick(2)


func _release_inputs() -> void:
	for action in ["move_left", "move_right", "jump", "sprint"]:
		if InputMap.has_action(action):
			Input.action_release(action)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(description)
		print("FAIL: ", description)
