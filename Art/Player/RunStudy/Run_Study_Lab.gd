extends Control
## 同速度、同尺寸、同纸底对照。底部关键姿态来自同一候选皮肤。

const CANDIDATE = preload("res://Component/Player/RunStudy/Traveler_Run_Study.tscn")
const OLD = preload("res://Component/Player/V6/Traveler_V6.tscn")
var players: Array[PlayerController] = []
var cameras: Array[Camera2D] = []
var worlds: Array[Node2D] = []
var frame := 0
var capture := false
var paused := false


class FloorMarks extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(-10000, 0, 20000, 250), Color("e8dfd0"))
		draw_line(Vector2(-10000, 0), Vector2(10000, 0), Color("b2a694"), 0.5)
		for x in range(-10000, 10000, 40):
			draw_line(Vector2(x, 0), Vector2(x, 5), Color("c4b9a8"), 0.5)


func _ready() -> void:
	process_physics_priority = 100
	capture = "--study-capture" in OS.get_cmdline_user_args()
	Global.allow_uav = false
	Global.allow_layer_cycle = false
	Global.allow_object_transfer = false
	RenderingServer.set_default_clear_color(Color("f5eee0"))
	var paper := ColorRect.new()
	paper.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	paper.color = Color("f5eee0")
	add_child(paper)
	_label("从脚步公式到关键姿态 · C款纸墨皮肤对照", Vector2(30, 16), 26)
	_label("真实移动速度同为320px/s · 同尺寸 · Space暂停　1–4查看候选四个阶段　0继续", Vector2(32, 54), 16)
	for index in 2:
		_lane(index)
	var phases := [0.0, 0.08, 0.20, 0.35]
	var captions := ["接触 · 长腿准备承重", "承重 · 轻缓压低", "蹬离 · 后摆上扬", "收膝 · 后跟进入衣内"]
	for index in 4:
		_pose(index, float(phases[index]), captions[index])
	Input.action_press("move_right")
	Input.action_press("sprint")
	if capture:
		DirAccess.make_dir_recursive_absolute("res://Exports/Run_Study")


func _lane(index: int) -> void:
	var origin := Vector2(24 + index * 628, 96)
	_label("现有V6 · 0.388s/周期" if index == 0 else "姿态候选 · 0.64s/周期", origin + Vector2(8, 0), 21)
	var container := SubViewportContainer.new()
	container.position = origin + Vector2(0, 35)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(604, 350)
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var world := Node2D.new()
	viewport.add_child(world)
	worlds.append(world)
	world.add_child(FloorMarks.new())
	var ground := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20000, 300)
	collision.shape = rectangle
	collision.position.y = 150
	ground.add_child(collision)
	world.add_child(ground)
	var player: PlayerController = (OLD if index == 0 else CANDIDATE).instantiate()
	player.position = Vector2(0, -0.1)
	world.add_child(player)
	player.set_collision_group(1)
	players.append(player)
	var camera := Camera2D.new()
	camera.position = Vector2(0, -43)
	camera.zoom = Vector2.ONE * 2.3
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.process_physics_priority = 200
	world.add_child(camera)
	cameras.append(camera)


func _pose(index: int, phase: float, caption: String) -> void:
	var player := CANDIDATE.instantiate() as PlayerController
	player.position = Vector2(180 + index * 305, 673)
	player.scale = Vector2.ONE * 1.45
	player.z_index = 10
	player.get_node("Visual_Body/Traveler").preview_phase = phase
	add_child(player)
	player.set_physics_process(false)
	player.collision_layer = 0
	player.collision_mask = 0
	_label(caption, Vector2(55 + index * 305, 687), 15)


func _physics_process(_delta: float) -> void:
	if paused:
		return
	frame += 1
	for index in 2:
		cameras[index].position = Vector2(players[index].position.x, -43)
	if capture and frame in [75, 120, 150]:
		_capture.call_deferred(frame)
	if capture and frame == 240:
		_finish.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_SPACE:
		_set_pause(not paused)
	elif event.physical_keycode in [KEY_1, KEY_2, KEY_3, KEY_4]:
		_set_pause(true)
		var index: int = event.physical_keycode - KEY_1
		players[1].get_node("Visual_Body/Traveler").show_pose([0.0, 0.08, 0.20, 0.35][index])
		players[1].get_node("Visual_Body/Scarf").align_to_pose()
	elif event.physical_keycode == KEY_0:
		_set_pause(false)


func _set_pause(value: bool) -> void:
	paused = value
	if not paused:
		players[1].get_node("Visual_Body/Traveler").preview_phase = -1.0
	for world in worlds:
		world.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT


func _label(text: String, where: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = where
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("51454b"))
	add_child(label)


func _capture(number: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://Exports/Run_Study/frame_%03d.png" % number)


func _finish() -> void:
	print("RUN_STUDY: 240 physics frames at 60Hz; two real players 320px/s.")
	get_tree().quit()


func _exit_tree() -> void:
	Input.action_release("move_right")
	Input.action_release("sprint")
