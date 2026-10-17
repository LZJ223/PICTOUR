## 核心取景、原生 clamp 与对话镜头的真实场景回归，不改动保存的关卡素材。
extends Node

const BACKGROUND := preload("res://Component/Background/Background.tscn")
var _game: Node2D
var _background: CanvasLayer
var _sprite: Sprite2D
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("BACKGROUND_TEST: " + message)

func _frames(count: int = 3) -> void:
	for index in count:
		await get_tree().process_frame

func _check_cover(message: String) -> void:
	var bounds: Rect2 = _sprite.get_global_transform_with_canvas() * _sprite.get_rect()
	_check(bounds.grow(0.01).encloses(get_viewport().get_visible_rect()), message)
	_check(_sprite.transform.is_equal_approx(Transform2D.IDENTITY), "Sprite 的局部变换保持不变")

func _source_to_screen(point: Vector2) -> Vector2:
	return _sprite.get_global_transform_with_canvas() * (point - _sprite.region_rect.position)

func _capture(filename: String) -> Image:
	RenderingServer.force_draw(false)
	var result := get_viewport().get_texture().get_image()
	result.save_png("res://.godot/background_qa/" + filename + ".png")
	return result

func _check_pixel(image: Image, uv: Vector2, color: Color, message: String) -> void:
	var at := (uv * Vector2(image.get_size())).clamp(Vector2.ZERO, Vector2(image.get_size() - Vector2i.ONE))
	var actual := image.get_pixel(int(at.x), int(at.y))
	_check(absf(actual.r - color.r) + absf(actual.g - color.g) + absf(actual.b - color.b) < 0.03, message)

func _image_difference(a: Image, b: Image) -> float:
	var difference: float = 0.0
	var count: int = 0
	for y in range(0, a.get_height(), 16):
		for x in range(0, a.get_width(), 16):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			difference += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 1
	return difference / maxf(count, 1)

func _probe_texture() -> ImageTexture:
	var image := Image.create(3840, 1440, false, Image.FORMAT_RGBA8)
	image.fill(Color.BLUE)
	image.fill_rect(Rect2i(0, 0, 640, 1440), Color.RED)
	image.fill_rect(Rect2i(3200, 0, 640, 1440), Color.GREEN)
	image.fill_rect(Rect2i(0, 0, 3840, 8), Color.WHITE)
	image.fill_rect(Rect2i(0, 1432, 3840, 8), Color.MAGENTA)
	return ImageTexture.create_from_image(image)

func _run() -> void:
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	get_tree().root.size = Vector2i(1280, 720)
	Global.next_level_id = 1
	_game = load("res://Interface/Game.tscn").instantiate() as Node2D
	_game.play_dialogue = false
	get_tree().root.add_child(_game)
	get_tree().current_scene = _game
	if SceneTransition.busy:
		await SceneTransition.transition_finished
	Global.player.set_physics_process(false)
	await _frames(5)
	_background = Global.level.get_node("Background") as CanvasLayer
	_sprite = _background.get_node("Frame/Sprite") as Sprite2D
	var frame := _sprite.get_parent() as Control
	var controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	_check(_sprite.texture.resource_path == "res://Texture/Background/Forest.png", "保留用户替换的贴图")
	_check(_sprite.texture.get_size() == Vector2(3840, 1440), "贴图尺寸为 3840×1440")
	_check(frame.material == null and _sprite.material == null, "没有额外模糊材质")
	_check(_sprite.texture_repeat == CanvasItem.TEXTURE_REPEAT_DISABLED, "使用原生边缘 clamp，不重复")
	_check(_sprite.region_rect.is_equal_approx(Rect2(640, 0, 2560, 1440)), "16:9 精确显示中间核心区域")
	_check(frame.scale.is_equal_approx(Vector2.ONE * 0.5), "原图和设计窗口使用 2:1 像素比例")
	_check_cover("核心区域铺满设计窗口")
	var normal_region := _sprite.region_rect
	Global.player.position += Vector2(500, -100)
	await _frames()
	_check(_sprite.region_rect.is_equal_approx(normal_region), "普通移动仍锁定背景")

	# 与正常画面中玩家脚部重合的背景点，应在整个对话 Tween 中保持重合。
	var landmark := _sprite.texture.get_size() * 0.5 + Vector2(0, 360)
	var player_screen: Vector2 = get_viewport().get_canvas_transform() * Global.player.global_position
	_check(_source_to_screen(landmark).distance_to(player_screen) < 0.05, "正常镜头的背景锚点与环境对齐")
	controller.set_dialogue_view(true)
	var maximum_error: float = 0.0
	for index in 50:
		await _frames(1)
		player_screen = get_viewport().get_canvas_transform() * Global.player.global_position
		maximum_error = maxf(maximum_error, _source_to_screen(landmark).distance_to(player_screen))
	_check(maximum_error < 0.05, "对话全程同时跟随 zoom 和 offset，没有相对滑动")
	controller.complete_dialogue_view(true)
	_check(frame.scale.is_equal_approx(Vector2.ONE * 0.75), "对话 1.5 倍镜头使背景同比放大")
	_check_cover("对话缩放后仍完整覆盖窗口")
	controller.complete_dialogue_view(false)
	_check(_sprite.region_rect.is_equal_approx(normal_region), "对话结束精确恢复核心取景")
	Global.camera.zoom = Vector2.ONE * 0.8
	controller._update_view()
	controller.set_dialogue_view(true)
	await get_tree().create_timer(0.5).timeout
	player_screen = get_viewport().get_canvas_transform() * Global.player.global_position
	_check(_source_to_screen(landmark).distance_to(player_screen) < 0.05, "非 1 倍基础相机也按相对 zoom 锁定")
	controller.complete_dialogue_view(false)
	Global.camera.zoom = Vector2.ONE
	controller._update_view()
	controller._on_destination_view_changed(true)
	await get_tree().create_timer(0.5).timeout
	_check(_sprite.region_rect.is_equal_approx(normal_region), "普通目标观察移动不拖动背景")
	controller._on_destination_view_changed(false)
	await get_tree().create_timer(0.5).timeout

	get_tree().paused = true
	for window_size in [Vector2i(1920, 720), Vector2i(2560, 720), Vector2i(1280, 1000), Vector2i(1280, 720)]:
		get_tree().root.size = window_size
		await _frames(5)
		_check_cover("暂停时窗口变为 %s 仍铺满" % window_size)
		if window_size == Vector2i(1920, 720):
			_check(_sprite.region_rect.is_equal_approx(Rect2(0, 0, 3840, 1440)), "宽屏露出完整两侧冗余")
		elif window_size == Vector2i(2560, 720):
			_check(_sprite.region_rect.position.x < 0, "超宽区域交由边缘采样延展")
		elif window_size == Vector2i(1280, 1000):
			_check(_sprite.region_rect.position.y < 0, "偏高窗口上下区域交由边缘采样延展")
	get_tree().paused = false

	Global.level.position = Vector2(120, -80)
	Global.level.scale = Vector2.ONE * 0.75
	await _frames()
	_check(_sprite.region_rect.is_equal_approx(normal_region), "Level 的世界变换不改变背景取景")
	Global.level.position = Vector2.ZERO
	Global.level.scale = Vector2.ONE
	var other := BACKGROUND.instantiate() as CanvasLayer
	_game.add_child(other)
	other.core_size = Vector2(1280, 720)
	_check(_sprite.region_rect.is_equal_approx(normal_region), "其他背景实例的核心配置不会串改当前实例")
	other.free()

	if DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/background_qa"))
		_capture("10_level_core")
		for child in Global.level.get_children():
			if child is CanvasItem:
				child.hide()
		Global.player.hide()
		_game.get_node("Camera/MenuUI").hide()
		var core_image := _capture("11_core")
		await controller.set_dialogue_view(true).finished
		await _frames()
		var dialogue_image := _capture("12_dialogue")
		_check(_image_difference(core_image, dialogue_image) > 0.01, "实际渲染的背景随对话镜头推进")
		controller.complete_dialogue_view(false)
		await _frames()
		var source := _sprite.texture
		_sprite.texture = _probe_texture()
		for window_size in [Vector2i(1280, 720), Vector2i(1920, 720), Vector2i(2560, 720), Vector2i(1280, 1000)]:
			get_tree().root.size = window_size
			await _frames(5)
			var image := _capture("13_clamp_%s" % window_size.x + "x%s" % window_size.y)
			_check_pixel(image, Vector2(0.5, 0.5), Color.BLUE, "核心图像始终居中")
			if window_size == Vector2i(1280, 720):
				_check_pixel(image, Vector2(0.01, 0.5), Color.BLUE, "16:9 不显示左侧冗余")
				_check_pixel(image, Vector2(0.99, 0.5), Color.BLUE, "16:9 不显示右侧冗余")
			elif window_size.x > 1280:
				_check_pixel(image, Vector2(0.01, 0.5), Color.RED, "宽屏左侧冗余或越界 clamp 正确")
				_check_pixel(image, Vector2(0.99, 0.5), Color.GREEN, "宽屏右侧冗余或越界 clamp 正确")
			else:
				_check_pixel(image, Vector2(0.5, 0.01), Color.WHITE, "偏高窗口顶部 clamp 正确")
				_check_pixel(image, Vector2(0.5, 0.99), Color.MAGENTA, "偏高窗口底部 clamp 正确")
		_sprite.texture = source

	_check(await SceneTransition.enter_level(2, false, false) == OK, "可以正常切换关卡")
	_check(not is_instance_valid(_background), "旧背景随 Level 清理")
	_check(await SceneTransition.enter_level(1, false, false) == OK, "可以重新进入关卡 01")
	_background = Global.level.get_node("Background") as CanvasLayer
	_check(_background.core_size == Vector2(2560, 1440), "重新进入恢复默认核心区域")
	_check(await SceneTransition.enter_main_menu() == OK, "可以正常返回主菜单")
	_check(not is_instance_valid(_background), "主菜单没有遗留背景")
	print("BACKGROUND_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
