## 开屏、同实例交接、跳过、返回菜单与实际 GPU 画面回归；不写入游戏设置或通关状态。
extends Node

const Intro = preload("res://Opening/Opening.gd")
const OUTPUT := "res://.godot/opening_qa/"
var _checks: int = 0
var _failures: Array[String] = []
var _phases: Array[int] = []
var _opening: Node
var _menu: Node2D
var _background_id: int = 0
var _scroll_before_finish: float = 0.0
var _peak_scale: float = 1.0
var _previous_scroll: float = -INF
var _phase_start_scroll: float = 0.0
var _scroll_continuous: bool = true
var _camera_vertical: bool = true
var _return_downward: bool = true
var _return_y: float = -INF
var _logo_first: bool = false
var _back_screen_fixed: bool = true
var _back_screen_offset := Vector2.ZERO
var _back_screen_size := Vector2.ZERO

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("OPENING_TEST: " + message)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _frames(count: int = 3) -> void:
	for frame in count:
		await get_tree().process_frame

func _process(_delta: float) -> void:
	if is_instance_valid(_opening):
		_peak_scale = maxf(_peak_scale, _opening._logo_pulse)
		if is_instance_valid(_menu) and _opening._main == _menu:
			var back_rect: Rect2 = _menu.back_button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _menu.back_button.size)
			var right_edge := Vector2(get_viewport().get_visible_rect().size.x, 0.0)
			_back_screen_fixed = _back_screen_fixed and (back_rect.position - right_edge).is_equal_approx(_back_screen_offset) and back_rect.size.is_equal_approx(_back_screen_size)
			var scroll: float = _menu.get_node("Game")._scroll
			_scroll_continuous = _scroll_continuous and scroll >= _previous_scroll
			_previous_scroll = scroll
			_camera_vertical = _camera_vertical and is_equal_approx(
				_menu.menu_camera.global_position.x, _menu.main_camera_position.global_position.x
			)
			if _opening.phase == Intro.Phase.MENU_DOWN:
				var camera_y: float = _menu.menu_camera.global_position.y
				_return_downward = _return_downward and camera_y >= _return_y - 0.001
				_return_y = camera_y

func _run() -> void:
	SceneTransition.fade_in_duration = 0.03
	SceneTransition.fade_out_duration = 0.03
	_check(ProjectSettings.get_setting("application/run/main_scene") == "res://Opening/Opening.tscn", "项目启动入口为轻量开屏")
	_check(not ProjectSettings.get_setting("application/boot_splash/show_image"), "原生启动不显示默认 Godot Logo")
	_opening = load("res://Opening/Opening.tscn").instantiate()
	_opening.phase_changed.connect(_on_phase)
	get_tree().root.add_child(_opening)
	get_tree().current_scene = _opening
	_check(_opening._main == null, "开屏首帧不需要实例化主菜单或背景")
	_check(is_equal_approx(_opening.logo_width, 1080.0 * 1.2), "开屏游戏 Logo 放大到原来的 1.2 倍")
	_check(_opening._godot_logo.size.is_equal_approx(Vector2(1440.0, 810.0) * 1.2), "开屏 Godot Logo 放大到原来的 1.2 倍")
	_check(_opening._logo_texture.resource_path == "res://Texture/Logo/Logo.png", "游戏 Logo 使用迁移后的资源路径")
	_check(_opening._godot_logo.texture.resource_path == "res://Texture/Logo/Godot.png", "天空展示重绘的 Godot Logo")
	_check(not _opening.has_node("Overlay/GodotPlaceholder") and _opening._godot_logo.get_child_count() == 0, "旧占位文字与重复标题已移除")
	_check(SceneTransition.busy and not SceneTransition._black.visible, "开屏保持输入锁但不被转场黑幕遮挡")
	while is_instance_valid(_opening):
		await get_tree().process_frame
	_menu = get_tree().current_scene as Node2D
	_check_prepared_menu("交接首帧")
	_check(_back_screen_fixed, "Back 从背景揭示到镜头回正始终固定在屏幕同一位置，尺寸不变")
	var back_rect: Rect2 = _menu.back_button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _menu.back_button.size)
	_check((back_rect.position - Vector2(get_viewport().get_visible_rect().size.x, 0.0)).is_equal_approx(_back_screen_offset), "Back 交回正常菜单后没有位置跳变")
	await _wait(0.4)
	_menu = get_tree().current_scene as Node2D
	_check(_phases == [1, 2, 3, 4, 5, 6, 7, 8, 9], "完整阶段顺序：描边、涨水填白、加载、圆形揭示、停留、上移、天空、下移、交接")
	_check(_logo_first, "Logo 圆形蒙版先扩张，背景稍后独立展开")
	_check(_peak_scale > 1.04 and _peak_scale <= 1.081, "Logo 快速放大再回落")
	_check(_menu.scene_file_path == "res://Interface/Main.tscn" and not _menu.opening_active, "结束后主菜单成为当前场景")
	_check(_menu.get_node("Game").get_instance_id() == _background_id, "交接沿用同一份动态背景实例")
	_check(_menu.get_node("Game")._scroll > _scroll_before_finish, "背景滚动持续，没有回零")
	_check(_scroll_continuous, "开屏各帧背景滚动不倒退或重置")
	_check(_camera_vertical and _return_downward, "镜头全程无横移，回正时只向正下方移动")
	_check(_menu.get_node("Logo").visible and _menu.get_node("Game/Player").visible and _menu.get_node("MenuUI").visible, "菜单 Logo、玩家与 UI 正常恢复")
	_check(_menu.menu_camera.global_position.is_equal_approx(_menu.main_camera_position.global_position), "镜头精确到达主菜单锚点")
	_check(not SceneTransition.busy and not get_tree().paused and not SceneTransition._opening_active, "交接后解除暂停与输入锁")
	_check(MusicPlayer._current_key == "menu", "主菜单音乐在交接后启动")
	_check(not _menu.get_node("MainMenu/LevelSelection").disabled, "主菜单按钮在交接后可操作")
	await _snapshot("11_menu")
	var phase_count := _phases.size()
	var error: Error = await SceneTransition.enter_level(1, false, false)
	_check(error == OK and get_tree().current_scene.scene_file_path == "res://Interface/Game.tscn", "主菜单进入关卡正常")
	await _frames()
	error = await SceneTransition.enter_main_menu()
	await _wait(0.35)
	_menu = get_tree().current_scene as Node2D
	_check(error == OK and _menu.scene_file_path == "res://Interface/Main.tscn", "关卡返回主菜单正常")
	_check(not _menu.opening_active and _phases.size() == phase_count, "返回主菜单不再次播放开屏")
	_check(get_tree().get_nodes_in_group(&"opening_logos").is_empty(), "开屏 Godot Logo 节点没有残留")
	_menu.queue_free()
	await _frames()
	## 独立验证在尚未挂载 Main 时跳过：仍等待资源，但不留下中间动画或黑幕。
	_opening = load("res://Opening/Opening.tscn").instantiate()
	get_tree().root.add_child(_opening)
	get_tree().current_scene = _opening
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	while is_instance_valid(_opening):
		await get_tree().process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await _frames()
	_menu = get_tree().current_scene as Node2D
	_check(_menu != null and _menu.scene_file_path == "res://Interface/Main.tscn" and not _menu.opening_active, "加载期间按空格可安全跳过")
	_check(not SceneTransition.busy and not get_tree().paused, "跳过后没有残留输入锁")
	_check_prepared_menu("跳过开屏后")
	_menu.queue_free()
	await _frames()
	print("OPENING_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _on_phase(value: int) -> void:
	_phases.append(value)
	if value >= Intro.Phase.BACKGROUND:
		var scroll: float = _menu.get_node("Game")._scroll
		_check(scroll > _phase_start_scroll, "开屏阶段 %d 背景持续运动" % (value - 1))
		_phase_start_scroll = scroll
	match value:
		Intro.Phase.STROKE:
			_check(is_zero_approx(_opening._fill), "描边期间尚未填白")
			_capture_after(_opening.stroke_duration * 0.5, value, "01_stroke")
		Intro.Phase.FILL:
			_check(is_equal_approx(_opening._stroke, 1.0) and is_zero_approx(_opening._fill), "完整描边形成后才开始涨水填白")
			_capture_after(0.0, value, "02_outline")
			_capture_after(_opening.fill_duration * 0.5, value, "03_fill")
			_check_fill_render()
		Intro.Phase.LOADING:
			_check(is_equal_approx(_opening._fill, 1.0), "白色剪影完全填满后才进入后续流程")
			_capture_after(0.0, value, "04_white")
		Intro.Phase.REVEAL:
			_menu = _opening._main
			_background_id = _menu.get_node("Game").get_instance_id()
			_phase_start_scroll = _menu.get_node("Game")._scroll
			var back_rect: Rect2 = _menu.back_button.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _menu.back_button.size)
			_back_screen_offset = back_rect.position - Vector2(get_viewport().get_visible_rect().size.x, 0.0)
			_back_screen_size = back_rect.size
			_check(_phase_start_scroll >= _opening.background_start_offset, "偏右取景使用背景初始相位而非横移镜头")
			_check(not _menu.get_node("Game/Player").visible and not _menu.get_node("Logo").visible, "开屏背景不提前显示 Player 或重复 Logo")
			_check(_menu.get_node("MenuUI").visible, "Back 提前随背景蒙版揭示，天空阶段不再突然显示")
			_check(SceneTransition.busy and MusicPlayer._current_key.is_empty(), "揭示背景时仍锁定菜单，音乐没有提前开始")
			_check(_opening._menu_music != null, "菜单音乐已异步缓存，交接时不再同步读盘")
			_check_reveal_order()
			_capture_after(_opening.background_reveal_delay * 0.5, value, "05_logo_circle")
			_capture_after(_opening.background_reveal_delay + 0.12, value, "06_background_circle")
		Intro.Phase.BACKGROUND:
			_check(is_equal_approx(_opening._logo_reveal, 1.0) and is_equal_approx(_opening._background_reveal, 1.0), "Logo 和背景完整出现后才进入停留阶段")
			_capture_after(0.08, value, "07_background")
		Intro.Phase.SKY:
			_check(_menu._opening_offset.y < -get_viewport().get_visible_rect().size.y, "镜头已真正上移至天空")
			_check(_opening._godot_logo.visible, "天空中显示重绘的 Godot Logo")
			_check(_opening._godot_logo.position.y >= 0.0, "Godot Logo 进入可见画面")
			_check(_menu.get_node("Logo/Logo_Back").texture.resource_path == "res://Texture/Logo/Logo_Back.png", "主菜单使用拆分后的 Logo 背景")
			_check_prepared_menu("展示 Godot Logo 时")
			_check(is_zero_approx(_opening._material.get_shader_parameter("logo_opacity")), "天空阶段停用完整彩色 Logo 覆盖层")
			_menu._show_page(_menu.Page.LEVEL_SELECTION)
			_check(_menu._page == _menu.Page.MAIN and SceneTransition.busy and get_tree().paused, "菜单提前展示后仍保持开屏输入锁")
			_capture_after(0.1, value, "08_sky")
			_check_resize()
		Intro.Phase.MENU_DOWN:
			_check_prepared_menu("镜头开始下移时")
			_capture_after(_opening.menu_move_duration * 0.8, value, "10_return")
			_check_return_render()
		Intro.Phase.FINISHED:
			_scroll_before_finish = _menu.get_node("Game")._scroll
			_check(is_zero_approx(_opening._blur), "下移结束时额外背景模糊已清除")
			_check(_menu._opening_offset.is_zero_approx(), "最终偏移精确回零")
			_check(_menu.get_node("Game").get_instance_id() == _background_id, "镜头往返没有重新生成背景")
			var rect: Vector4 = _opening._material.get_shader_parameter("logo_rect")
			var view := get_viewport().get_visible_rect().size
			var logo: Sprite2D = _menu.get_node("Logo/Logo_Back")
			var target := logo.get_global_transform_with_canvas() * logo.get_rect()
			_check((Vector2(rect.x, rect.y) * view).distance_to(target.position) < 0.01, "开屏 Logo 交接位置与主菜单精确重合")
			_check((Vector2(rect.z, rect.w) * view).distance_to(target.size) < 0.01, "开屏 Logo 交接尺寸与主菜单精确重合")

func _check_prepared_menu(stage: String) -> void:
	_check(_menu.get_node("Logo").visible and _menu.get_node("Game/Player").visible and _menu.get_node("MenuUI").visible, stage + "标题、机器人及菜单已显示")
	_check(is_equal_approx(_menu.get_node("Game/Player").modulate.a, 1.0) and is_equal_approx(_menu.get_node("MenuUI/Screen").modulate.a, 1.0), stage + "机器人和菜单不再等待淡入")
	for character: String in SaveSystem.COLLECTION_CHARACTERS:
		_check(_menu.get_node("Logo/Logo_" + character).visible == SaveSystem.is_character_collected(character), stage + "标题读取收集状态：" + character)
	for button in _menu.main_menu.get_children():
		_check(is_equal_approx(button._presentation_scale, 1.0), stage + "主菜单按钮已完整呈现")

func _check_return_render() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _wait(_opening.menu_move_duration * 0.8)
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_opening) or _opening.phase != Intro.Phase.MENU_DOWN:
		_check(false, "回程画面检查没有错过镜头下移阶段")
		return
	var image := get_viewport().get_texture().get_image()
	var screen_scale := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	for character: String in SaveSystem.COLLECTION_CHARACTERS:
		var sprite: Sprite2D = _menu.get_node("Logo/Logo_" + character)
		var source := sprite.texture.get_image()
		var total: int = 0
		var green: int = 0
		for y in range(0, source.get_height(), 16):
			for x in range(0, source.get_width(), 16):
				var original := source.get_pixel(x, y)
				if original.a < 0.99 or original.g < original.r + 0.25 or original.g < original.b + 0.15:
					continue
				var screen: Vector2 = (sprite.get_global_transform_with_canvas() * (sprite.get_rect().position + Vector2(x, y))) * screen_scale
				if not Rect2(Vector2.ZERO, Vector2(image.get_size())).has_point(screen):
					continue
				var color := image.get_pixelv(Vector2i(screen))
				total += 1
				green += int(color.g > color.r + 0.12 and color.g > color.b + 0.08)
		var collected := SaveSystem.is_character_collected(character)
		_check(total > 20 and (green > total * 0.65 if collected else green < total * 0.2),
			"回程真实画面已显示 %s 的%s收集颜色（绿 %d / %d）" % [character, "已" if collected else "未", green, total])

func _check_reveal_order() -> void:
	await _wait(_opening.background_reveal_delay * 0.5)
	_logo_first = _opening._logo_reveal > 0.0 and is_zero_approx(_opening._background_reveal)
	_check(is_zero_approx(_opening._material.get_shader_parameter("background_reveal_progress")), "Logo 显色时背景蒙版仍关闭")

func _check_fill_render() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _wait(_opening.fill_duration * 0.5)
	await RenderingServer.frame_post_draw
	if not is_instance_valid(_opening) or _opening.phase != Intro.Phase.FILL:
		_check(false, "涨水填色渲染检查没有错过阶段")
		return
	var image := get_viewport().get_texture().get_image()
	var logo := (_opening._material.get_shader_parameter("logo_texture") as Texture2D).get_image()
	var data := (_opening._material.get_shader_parameter("stroke_texture") as Texture2D).get_image()
	var rect: Vector4 = _opening._material.get_shader_parameter("logo_rect")
	# 截图使用实际像素，而非 canvas_items 拉伸前的逻辑视口尺寸。
	var view := Vector2(image.get_size())
	var width: float = _opening._material.get_shader_parameter("stroke_width_source")
	var upper_gray: int = 0
	var upper_white: int = 0
	var lower_white: int = 0
	for y in range(0, logo.get_height(), 12):
		for x in range(0, logo.get_width(), 12):
			if logo.get_pixel(x, y).a < 0.99 or data.get_pixel(x, y).b * 64.0 < width + 3.0:
				continue
			var uv := (Vector2(x, y) + Vector2.ONE * 0.5) / Vector2(logo.get_size())
			var screen := (Vector2(rect.x, rect.y) + uv * Vector2(rect.z, rect.w)) * view
			var color := image.get_pixelv(Vector2i(screen))
			if uv.y < 0.35:
				upper_white += int(color.r > 0.9)
				upper_gray += int(color.r < 0.5)
			elif uv.y > 0.75:
				lower_white += int(color.r > 0.9)
	_check(upper_gray > 20 and upper_white == 0 and lower_white > 20,
		"真实画面中下半部已填白，上半部内部仍为深灰（上灰 %d，上白 %d，下白 %d，填色 %.3f）"
		% [upper_gray, upper_white, lower_white, _opening._fill])

func _check_resize() -> void:
	await _wait(0.25)
	var original_size := get_window().size
	get_window().size = Vector2i(1280, 960)
	await _frames()
	var rect: Vector4 = _opening._material.get_shader_parameter("logo_rect")
	var size: Vector2 = _opening._material.get_shader_parameter("viewport_size")
	_check(is_equal_approx(rect.z * size.x / (rect.w * size.y), 2.0), "4:3 窗口中 Logo 仍保持 2:1 比例")
	_check(size.is_equal_approx(get_viewport().get_visible_rect().size), "窗口改变时蒙版使用实时像素尺寸")
	var godot_rect: Rect2 = _opening._godot_logo.get_global_rect()
	_check((godot_rect.get_center() - size * 0.5).length() < 0.01 and godot_rect.size.x <= size.x and godot_rect.size.y <= size.y, "4:3 窗口中 Godot Logo 居中且不越界")
	await _snapshot("09_sky_4x3")
	get_window().size = original_size
	await _frames()

func _capture_after(seconds: float, expected_phase: int, name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if seconds > 0.0:
		await _wait(seconds)
	await RenderingServer.frame_post_draw
	if is_instance_valid(_opening) and _opening.phase == expected_phase:
		await _snapshot(name)

func _snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	get_viewport().get_texture().get_image().save_png(OUTPUT + name + ".png")
