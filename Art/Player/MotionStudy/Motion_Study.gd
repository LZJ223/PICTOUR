extends Node2D
## 八秒独立动作结构实验；不进入主场景、不替换角色美术、不读写存档。

const ACTOR = preload("res://Component/Player/MotionStudy/Contact_Gait.gd")
var actors: Array[Node2D] = []
var readouts: Array[Label] = []
var ticks := 0
var capture := false


func _ready() -> void:
	# 子角色先完成当前物理帧，读数再采样同一份姿态，避免HUD滞后一帧。
	process_physics_priority = 2
	capture = "--study-capture" in OS.get_cmdline_user_args()
	RenderingServer.set_default_clear_color(Color("f3eee4"))
	_label("步态灰稿实验 · 动作结构，非最终美术", Vector2(32, 22), 27)
	_label("近腿深色 / 远腿浅色　绿色圆点：世界锁定的支撑脚　空心橙点：沿弧线摆动的脚", Vector2(32, 67), 17)
	_label("保留清楚的脚部承重与腿身份；原C款角色、美术素材和F5入口均未改动。", Vector2(32, 96), 15)
	for index in 2:
		var title := "步行 180 px/s · 双支撑交接" if index == 0 else "奔跑 320 px/s · 短暂双脚离地"
		_label(title, Vector2(36 + index * 640, 164), 22)
		var actor := Node2D.new()
		actor.set_script(ACTOR)
		actor.set("running", index == 1)
		actor.set("speed", 180.0 if index == 0 else 320.0)
		actor.position = Vector2(320 + index * 640, 578)
		actor.scale = Vector2.ONE * 3.4
		add_child(actor)
		actors.append(actor)
		readouts.append(_label("", Vector2(36 + index * 640, 614), 17))
	_label("60Hz 更新动作结构；显示帧连续插值。支撑段固定世界足点，摆动段使用端点连续曲线。", Vector2(32, 687), 15)
	if capture:
		DirAccess.make_dir_recursive_absolute("res://Exports/MotionStudy")


func _physics_process(_delta: float) -> void:
	ticks += 1
	for index in actors.size():
		var actor := actors[index]
		var pose: Dictionary = actor.get("current_pose")
		var contact := "双脚离地" if not pose.nearcontact and not pose.farcontact else ("双脚交接" if pose.nearcontact and pose.farcontact else "单脚支撑")
		readouts[index].text = "%s　相位 %.3f\n支撑脚滑动 %.4f px　循环接缝 %.4f px" % [contact, fposmod(float(actor.get("distance")) / float(actor.get("stride")), 1.0), float(actor.get("max_support_error")), float(actor.get("seam_error"))]
	if capture and ticks in [100, 175, 239]:
		_screenshot.call_deferred(ticks)
	if capture and ticks == 480:
		_finish.call_deferred()


func _finish() -> void:
	var success := true
	for index in actors.size():
		var actor := actors[index]
		var correct: bool = float(actor.get("max_support_error")) < 0.001 and float(actor.get("seam_error")) < 0.001
		if index == 1:
			correct = correct and bool(actor.get("saw_flight"))
		success = success and correct
		print("MOTION_STUDY: %s support_error=%.6f seam_error=%.6f flight=%s samples=%d" % ["walk" if index == 0 else "run", actor.get("max_support_error"), actor.get("seam_error"), str(actor.get("saw_flight")), int(actor.get("samples"))])
	get_tree().quit(0 if success else 1)


func _screenshot(frame: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://Exports/MotionStudy/frame_%03d.png" % frame)


func _label(text: String, position: Vector2, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("594d52"))
	add_child(label)
	return label
