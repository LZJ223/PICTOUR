## 计时、取景和真实 GPU 星空回归；不修改保存的关卡布置。
extends Node

const BACKGROUND := preload("res://Component/Background/Night_Background.tscn")
const OUTPUT := "res://.godot/night_background_qa/"
var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("NIGHT_BACKGROUND_TEST: " + message)

func _frames(count: int = 3) -> void:
	for index in count:
		await get_tree().process_frame

func _capture(viewport: Viewport, name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(OUTPUT + name + ".png")
	return image

func _check_color(background: CanvasLayer, fraction: float, message: String) -> void:
	background._sync_color(background.color_reset_duration)
	var color: Color = background.get_node("SkyColor").color
	_check(color.is_equal_approx(Color.BLACK.lerp(background.active_color, fraction)), message)

func _check_activity_timeline(background: CanvasLayer) -> void:
	var animation := Global.player.player_animation
	SignalSystem.timer_reset()
	await _frames()
	_check(animation._expression_index == 0 and animation._bob_amplitude > 0.0, "重置后恢复活动表情与待机浮动")
	await get_tree().create_timer(2.1).timeout
	_check(not SignalSystem.timer.is_stopped() and animation._expression_index == 0 and animation._bob_amplitude > 0.0, "超过原来的 2 秒仍保持活动，不提前休息")
	_check(is_equal_approx(background._color_progress, SignalSystem.timer.time_left / SignalSystem.timer.wait_time), "恢复后仍严格按计时比例线性变暗")
	await get_tree().create_timer(SignalSystem.timer.time_left - animation.expression_middle_time + 0.04).timeout
	await _frames(1)
	_check(animation._expression_index == 1 and animation._bob_amplitude > 0.0, "最后 0.35 秒进入过渡表情，仍未休息")
	await SignalSystem.timer.timeout
	await _frames()
	_check(animation._expression_index == 2 and is_zero_approx(animation._bob_amplitude), "5 秒到期才进入休息表情并停止浮动")
	_check(SignalSystem.is_physics_resting() and background.get_node("SkyColor").color == Color.BLACK, "夜间到期同步休眠且背景达到纯黑")
	SignalSystem.timer_reset()
	await get_tree().create_timer(background.color_reset_duration + 0.05).timeout
	await _frames()
	_check(animation._expression_index == 0 and animation._bob_amplitude > 0.0, "休息后重新操作正常唤醒角色动画")

func _star_stats(image: Image) -> Dictionary:
	var pixels: Dictionary = {}
	var bytes := image.get_data()
	for index in range(3, bytes.size(), 4):
		if bytes[index] > 38:
			var pixel: int = index / 4
			pixels[Vector2i(pixel % image.get_width(), pixel / image.get_width())] = true
	var lit_pixels: int = pixels.size()
	var stars: int = 0
	var largest: int = 0
	while not pixels.is_empty():
		stars += 1
		var pending: Array[Vector2i] = [pixels.keys()[0]]
		var area: int = 0
		pixels.erase(pending[0])
		while not pending.is_empty():
			var at: Vector2i = pending.pop_back()
			area += 1
			for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next: Vector2i = at + offset
				if pixels.erase(next):
					pending.append(next)
		largest = maxi(largest, area)
	return {"stars": stars, "pixels": lit_pixels, "largest": largest}

func _run() -> void:
	var activity_timeout := SignalSystem.timer.wait_time
	_check(is_equal_approx(activity_timeout, 5.0), "全局活动倒计时默认为 5 秒")
	SceneTransition.fade_in_duration = 0.01
	SceneTransition.fade_out_duration = 0.01
	for level_id in [9, 10, 11, 12]:
		Global.next_level_id = level_id
		var game := load("res://Interface/Game.tscn").instantiate() as Node2D
		game.play_dialogue = false
		get_tree().root.add_child(game)
		get_tree().current_scene = game
		if SceneTransition.busy:
			await SceneTransition.transition_finished
		Global.player.set_physics_process(false)
		SignalSystem.set_process(false)
		SignalSystem.set_physics_process(false)
		var background := Global.level.get_node("Background") as CanvasLayer
		var sprite := background.get_node("Frame/Sprite") as Sprite2D
		var sky := background.get_node("SkyColor") as ColorRect
		var frame := sprite.get_parent() as Control
		_check(background.get_script().resource_path.ends_with("Night_Background.gd"), "夜间关卡 %d 使用独立背景" % level_id)
		_check(background.is_in_group(&"level_backgrounds") and background.layer == -100, "复用背景分组与渲染层")
		_check(sprite.texture.get_size() == Vector2(2, 2), "星空只需要微型占位纹理")
		_check(sky.get_index() < frame.get_index() and sky.mouse_filter == Control.MOUSE_FILTER_IGNORE, "纯色底位于星点后，不阻挡鼠标输入")
		_check(background.active_color.b > background.active_color.r and background.active_color.get_luminance() < Color("#202020").get_luminance(), "活动色更暗且略偏蓝")
		SignalSystem.timer.start(activity_timeout)
		_check_color(background, 1.0, "计时开始为深蓝灰色")
		SignalSystem.timer.start(activity_timeout * 0.5)
		SignalSystem.timer.wait_time = activity_timeout
		_check_color(background, 0.5, "计时中点为颜色的线性中间值")
		SignalSystem.timer.stop()
		_check_color(background, 0.0, "计时结束为纯黑色")
		SignalSystem.timer_reset()
		background._sync_color()
		_check(sky.color == Color.BLACK, "重置计时器不会立即跳变背景颜色")
		background._sync_color(background.color_reset_duration * 0.5)
		_check(sky.color.is_equal_approx(Color.BLACK.lerp(background.active_color, 0.5)), "恢复进行一半时颜色连续经过中间值")
		background._sync_color(background.color_reset_duration * 0.5)
		_check(sky.color.is_equal_approx(background.active_color) and SignalSystem.timer.time_left > 4.9, "短时恢复到活动色，不篡改真正的倒计时")
		SignalSystem.timer.stop()
		_check_color(background, 0.0, "测试持续重置前恢复纯黑")
		for index in 12:
			SignalSystem.timer_reset()
			await _frames(1)
		_check(background._color_progress > 0.95, "每帧重置计时器仍能快速恢复，不反复重启动画")
		if level_id == 9:
			await _check_activity_timeline(background)
			SignalSystem.timer.stop()
			_check_color(background, 0.0, "暂停测试前恢复纯黑")
			SignalSystem.timer_reset()
			background._sync_color(background.color_reset_duration * 0.5)
			get_tree().paused = true
			var remaining := SignalSystem.timer.time_left
			var color := sky.color
			await _frames(5)
			_check(is_equal_approx(SignalSystem.timer.time_left, remaining) and sky.color == color, "真正暂停时计时与背景颜色同步停止")
			for window_size in [Vector2i(2560, 720), Vector2i(1280, 1000), Vector2i(1280, 720)]:
				get_tree().root.size = window_size
				await _frames(4)
				_check(sky.get_global_rect().is_equal_approx(get_viewport().get_visible_rect()), "暂停时窗口变化，纯色底仍铺满视口")
			get_tree().paused = false
			var controller := game.get_node("LayerControllerSystem") as LayerControllerSystem
			var anchor := sprite.texture.get_size() * 0.5 + Vector2(0, 360)
			controller.set_dialogue_view(true)
			var maximum_error: float = 0.0
			for index in 30:
				await _frames(1)
				var screen_anchor: Vector2 = sprite.get_global_transform_with_canvas() * (anchor - sprite.region_rect.position)
				var player_screen: Vector2 = get_viewport().get_canvas_transform() * Global.player.global_position
				maximum_error = maxf(maximum_error, screen_anchor.distance_to(player_screen))
			_check(maximum_error < 0.05, "对话 Tween 全程星空取景与角色环境保持同步")
			_check(sky.scale == Vector2.ONE and sky.get_global_rect().size == get_viewport().get_visible_rect().size, "对话只缩放星点，不缩放纯色底")
			_check((sprite.material as ShaderMaterial).get_shader_parameter("region_origin").is_equal_approx(sprite.region_rect.position), "着色器使用当前真实取景原点")
			controller.complete_dialogue_view(false)
			if DisplayServer.get_name() != "headless":
				DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
				await _capture(get_viewport(), "01_level09")
		game.queue_free()
		await _frames(3)
		SignalSystem.timer.wait_time = activity_timeout

	if DisplayServer.get_name() != "headless":
		await _render_stars()
	print("NIGHT_BACKGROUND_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)

func _render_stars() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var background := BACKGROUND.instantiate() as CanvasLayer
	viewport.add_child(background)
	SignalSystem.timer.start(60.0)
	await _frames(5)
	var sky := background.get_node("SkyColor") as ColorRect
	var sprite := background.get_node("Frame/Sprite") as Sprite2D
	var material := sprite.material as ShaderMaterial
	var composed := await _capture(viewport, "02_night_sky")
	_check(composed.get_pixel(0, 0).a > 0.99, "实际绘制的纯色底完全不透明")
	sky.hide()
	await _frames()
	var core := await _capture(viewport, "03_transparent_stars")
	var stats := _star_stats(core)
	_check(stats.stars > 100 and stats.stars < 1000, "实际生成数百颗稀疏星点")
	_check(stats.pixels < 10000 and stats.largest < 40, "星点是小圆点，没有云团、月亮或边缘长条")
	_check(stats.pixels > 500, "星点不是不可见的单像素噪点")
	await _frames(5)
	var still := await _capture(viewport, "04_static")
	_check(core.get_data() == still.get_data(), "不依赖时间，星星不会闪烁或逐帧重排")
	viewport.size = Vector2i(2560, 720)
	await _frames(5)
	var wide := await _capture(viewport, "05_wide")
	var wide_stats := _star_stats(wide)
	_check(wide_stats.stars > stats.stars * 1.7, "超宽窗口继续生成星点，不拉伸边缘")
	var center := wide.get_region(Rect2i(640, 0, 1280, 720))
	var difference: float = 0.0
	var a := center.get_data()
	var b := core.get_data()
	for index in range(3, a.size(), 4):
		difference += absf(float(a[index]) - float(b[index]))
	_check(difference / (a.size() / 4) < 0.05, "窗口变宽时中心区域的星星位置保持一致")
	viewport.size = Vector2i(1280, 720)
	await _frames()
	background.set_camera_framing(Vector2.ONE * 1.5, Vector2(0, 72))
	await _frames()
	var zoomed := await _capture(viewport, "06_zoomed")
	var zoom_stats := _star_stats(zoomed)
	_check(zoom_stats.stars < stats.stars * 0.65 and zoom_stats.largest > stats.largest, "对话镜头放大星点，同时显示更小范围的夜空")
	material.set_shader_parameter("density", 0.0)
	await _frames()
	var empty := await _capture(viewport, "07_empty")
	_check(empty.get_used_rect() == Rect2i(), "星点以外完全透明，没有隐藏的底色")
	var other := BACKGROUND.instantiate() as CanvasLayer
	viewport.add_child(other)
	_check(other.get_node("Frame/Sprite").material != material, "每个夜间背景使用独立材质，不互相修改星空参数")
	other.queue_free()
	viewport.queue_free()
	await _frames()
