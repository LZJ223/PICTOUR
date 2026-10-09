extends Control
## 动作观察场：真实实体移动与独立物理世界，地面刻度揭示脚底打滑。
## 四格包含真实正负坡面；全局 Shift 保持按住，步行格使用步行速度。
## 正常 F6 循环观察；命令行 -- --lab-capture 在八秒后自动退出。

const PLAYER_PATH := "res://Component/Player/V5/Traveler_V5.tscn"
const INK := Color("51454b")
var _players: Array[PlayerController] = []
var _worlds: Array[Node2D] = []
var _cameras: Array[Camera2D] = []
var _readouts: Array[Label] = []
var _visuals: Array[AnimatedSprite2D] = []
var _elapsed: float = 0.0
var _frames: int = 0
var _playing: bool = true
var _capture: bool = false
var _zoom: float = 1.8
var _status: Label


class FloorMarks extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-100000, 0, 200000, 180), Color("e8dfd0"))
		draw_line(Vector2(-100000, 0), Vector2(100000, 0), Color("92857e"), 0.8)
		for x in range(-20000, 20001, 24):
			var length: float = 9.0 if x % 120 == 0 else 4.0
			draw_line(Vector2(x, 0), Vector2(x, length), Color("b5a99b"), 0.6)


class RootMark extends Node2D:
	func _draw() -> void:
		draw_line(Vector2(-5, 0), Vector2(5, 0), Color("a56543"), 1.0)
		draw_line(Vector2(0, -3), Vector2(0, 3), Color("a56543"), 0.6)


func _ready() -> void:
	process_physics_priority = -50
	_capture = "--lab-capture" in OS.get_cmdline_user_args()
	RenderingServer.set_default_clear_color(Color("f5eee0"))
	Global.clear_selection()
	Global.allow_layer_cycle = false
	Global.allow_object_transfer = false
	Global.allow_uav = false
	var background := ColorRect.new()
	background.color = Color("f5eee0")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_add_label("叠页旅人 · 十六帧与坡面观察场", Vector2(32, 20), 26)
	_status = _add_label("Space 暂停 / 继续　R 重播　1 原尺寸　2 放大　地面细线每 24px", Vector2(34, 58), 16)
	var player_scene := load(PLAYER_PATH) as PackedScene
	if player_scene == null:
		push_error("V5角色资源尚未就绪：" + PLAYER_PATH)
		get_tree().quit(1)
		return
	var titles: Array[String] = ["平地 · 步行 / 十六帧", "平地 · 奔跑 / 十六帧", "上坡 18° · 走跑交接", "下坡 28° · 转身 / 停步"]
	for index in 4:
		_create_lane(index, titles[index], player_scene)
	Input.action_press("sprint")
	if _capture:
		DirAccess.make_dir_recursive_absolute("res://Exports/Traveler_V5_Lab")
	print("TRAVELER_V5_LAB: 四个独立物理世界；步行/跑步对照，空格暂停，R重播。")


func _create_lane(index: int, title: String, player_scene: PackedScene) -> void:
	var origin := Vector2(24 + (index % 2) * 628, 99 + (index / 2) * 302)
	var backdrop := ColorRect.new()
	backdrop.position = origin
	backdrop.size = Vector2(604, 286)
	backdrop.color = Color("ded5c6")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var container := SubViewportContainer.new()
	container.position = origin + Vector2(1, 42)
	container.size = Vector2(602, 243)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(602, 243)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.world_2d = World2D.new()
	container.add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	_worlds.append(world)
	var slope: float = -tan(deg_to_rad(18.0)) if index == 2 else (tan(deg_to_rad(28.0)) if index == 3 else 0.0)
	var floor_art := FloorMarks.new()
	floor_art.rotation = atan(slope)
	world.add_child(floor_art)
	var ground := StaticBody2D.new()
	var collision := CollisionPolygon2D.new()
	collision.polygon = PackedVector2Array([Vector2(-100000, -100000 * slope), Vector2(100000, 100000 * slope), Vector2(100000, 100000 * slope + 600), Vector2(-100000, -100000 * slope + 600)])
	ground.add_child(collision)
	world.add_child(ground)
	var player := player_scene.instantiate() as PlayerController
	player.position = Vector2(0, -12.0)
	if index == 0:
		player.run_speed = player.move_speed
	world.add_child(player)
	player.add_child(RootMark.new())
	player.set_physics_process(false)
	player.set_collision_group(1)
	_players.append(player)
	_visuals.append(player.get_node("Visual_Body/Traveler") as AnimatedSprite2D)
	var camera := Camera2D.new()
	camera.position = Vector2(0, -54)
	camera.zoom = Vector2.ONE * _zoom
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.process_physics_priority = 2000
	world.add_child(camera)
	_cameras.append(camera)
	_add_label(title, origin + Vector2(14, 8), 18)
	var readout := _add_label("", origin + Vector2(360, 12), 13)
	_readouts.append(readout)


func _physics_process(delta: float) -> void:
	if not _playing or _players.is_empty():
		return
	_elapsed += delta
	_frames += 1
	for index in _players.size():
		var player := _players[index]
		var direction: float = 0.0
		if index in [0, 1, 2]:
			direction = 1.0
		elif index == 3:
			var phase: float = fmod(_elapsed, 5.0)
			if phase >= 0.5 and phase < 1.8:
				direction = 1.0
			elif phase >= 2.25 and phase < 3.35:
				direction = -1.0
			elif phase >= 3.35 and phase < 4.4:
				direction = 1.0
		# 全局Input仅保持一次Shift，分屏不可反复释放，避免污染其他角色。
		var walking: bool = index == 0 or (index == 2 and fmod(_elapsed, 4.0) < 2.0)
		player.run_speed = player.move_speed if walking else 320.0
		player.set_meta("animation_input_axis", direction)
		_set_direction(direction)
		player._physics_process(delta)
		if walking:
			player.is_running = false
		_cameras[index].position = Vector2(player.position.x, player.position.y - 54)
		var phase: float = float(_visuals[index].get("stride_phase"))
		_readouts[index].text = "%3.0f · %s:%d · φ%.2f" % [player.velocity.x, _visuals[index].animation, _visuals[index].frame, phase]
	_set_direction(0)
	if _capture:
		if _frames in [90, 165, 213, 260]:
			_capture_frame.call_deferred(_frames)
		if _frames == 480:
			_finish_capture.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_SPACE:
			_playing = not _playing
			for world in _worlds:
				world.process_mode = Node.PROCESS_MODE_INHERIT if _playing else Node.PROCESS_MODE_DISABLED
			_status.text = "Space 暂停 / 继续　R 重播　1 原尺寸　2 放大　" + ("播放中" if _playing else "已暂停，可检查脚掌与围巾轮廓")
		KEY_R:
			_elapsed = 0.0
			for index in _players.size():
				_players[index].position = Vector2(0, -0.1)
				_players[index].reset_motion()
				_players[index].reset_physics_interpolation()
				_cameras[index].position = Vector2(0, -54)
				_cameras[index].reset_physics_interpolation()
		KEY_1, KEY_2:
			_zoom = 1.0 if event.physical_keycode == KEY_1 else 1.8
			for camera in _cameras:
				camera.zoom = Vector2.ONE * _zoom
				camera.reset_physics_interpolation()


func _add_label(text: String, position: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _set_direction(direction: float) -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	if direction > 0:
		Input.action_press("move_right")
	elif direction < 0:
		Input.action_press("move_left")


func _capture_frame(frame: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://Exports/Traveler_V5_Lab/frame_%03d.png" % frame)


func _finish_capture() -> void:
	_release()
	print("TRAVELER_V5_LAB: 480个物理帧动作观察完成；截图在Exports/Traveler_V5_Lab。")
	get_tree().quit(0)


func _exit_tree() -> void:
	_release()


func _release() -> void:
	for action in ["move_left", "move_right", "sprint", "jump"]:
		Input.action_release(action)
