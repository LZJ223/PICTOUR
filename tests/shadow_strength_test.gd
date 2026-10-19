## 复用真实图层与可控投影，验证计时强度在清晰、模糊与透明边缘上的合成。
extends "res://tests/shadow_blur_test.gd"

func _transition(lod: float, label: String) -> float:
	var width := await super._transition(lod, label)
	if label not in ["01_sharp", "02_default", "03_strong"]:
		return width
	var timer: Timer = SignalSystem.timer
	var duration: float = timer.wait_time
	timer.paused = true
	# 比较完整图像中的边界，覆盖联合采样和遮罩恒定两条着色器分支。
	var full := _capture(label + "_strength_100")
	_show_shadow = false
	await _frames()
	var clear := _capture(label + "_strength_clear")
	_show_shadow = true
	for remaining in [1.0, 0.5, 0.0]:
		if remaining > 0.0:
			timer.start(duration * remaining)
			timer.wait_time = duration
		else:
			timer.stop()
		await _frames()
		var strength: float = lerpf(1.0, 0.7, remaining)
		var image := _capture(label + "_strength_%d" % roundi(strength * 100.0))
		var error := _blend_error(image, clear, full, strength)
		_metrics[label + "_strength_%d_error" % roundi(strength * 100.0)] = error
		_check(error < 0.012, label + " 覆盖强度 %.0f%% 与合成参考一致" % (strength * 100.0))
		var empty := Vector2(_center().x, _center().y - 220)
		_check(_screen_color(image, empty).is_equal_approx(_screen_color(clear, empty)), label + " 强度变化不改变透明区域")
	# 检查实体 Alpha 仍只参与一次合成，不因降低影子强度而改变轮廓。
	_receiver.visual_root.modulate.a = 0.4
	await _frames()
	var translucent_full := _capture(label + "_translucent_100")
	_show_shadow = false
	await _frames()
	var translucent_clear := _capture(label + "_translucent_clear")
	_show_shadow = true
	SignalSystem.timer_reset()
	PhysicsServer2D.set_active(false)
	await _frames()
	var reset := _capture(label + "_translucent_reset")
	_check(_blend_error(reset, translucent_clear, translucent_full, 0.7) < 0.012, label + " 重置立即回到 70%，保留半透明边缘")
	_receiver.visual_root.modulate.a = 1.0
	if label == "01_sharp":
		timer.start(duration * 0.5)
		timer.wait_time = duration
		get_tree().paused = true
		timer.paused = false
		await _frames()
		var before := _capture("strength_pause_before")
		var time_left: float = timer.time_left
		await get_tree().create_timer(0.2, true).timeout
		await _frames()
		var after := _capture("strength_pause_after")
		_check(is_equal_approx(timer.time_left, time_left), "暂停保持计时进度")
		_check(_blend_error(after, before, before, 1.0) < 0.001, "暂停保持影子覆盖强度")
		get_tree().paused = false
	timer.stop()
	timer.paused = false
	await _frames()
	return width

func _blend_error(actual: Image, clear: Image, full: Image, strength: float) -> float:
	var error := 0.0
	for y in range(roundi(_center().y) - 15, roundi(_center().y) + 16):
		for x in range(roundi(_edge) - 30, roundi(_edge) + 31):
			var point := Vector2(x, y)
			var expected := _screen_color(clear, point).lerp(_screen_color(full, point), strength)
			var value := _screen_color(actual, point)
			error = maxf(error, maxf(absf(value.r - expected.r), maxf(absf(value.g - expected.g), absf(value.b - expected.b))))
	return error
