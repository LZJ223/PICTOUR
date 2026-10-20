## 轻量启动入口。Main 以路径异步加载，白色 Logo 动画不依赖关卡资源。
## Main 直接挂到根节点，交接时只销毁本覆盖层，不重新加载菜单或重置背景。
extends Node

signal phase_changed(phase: int)

enum Phase { BOOT, STROKE, FILL, LOADING, REVEAL, BACKGROUND, SKY_UP, SKY, MENU_DOWN, FINISHED }

const MAIN_PATH := "res://Interface/Main.tscn"
const DESIGN_SIZE := Vector2(1920.0, 1080.0)

@export_group("Logo")
@export_range(600.0, 1500.0, 10.0) var logo_width: float = 1296.0
@export_range(1.0, 16.0, 0.5) var stroke_width: float = 8.0
@export_range(0.0, 12.0, 0.5) var fill_wave_height: float = 3.0
@export_range(1.0, 1.3, 0.01) var logo_peak_scale: float = 1.08
@export_range(0.01, 0.5, 0.01) var logo_impulse_duration: float = 0.07
@export_range(0.01, 0.5, 0.01) var logo_settle_duration: float = 0.22

@export_group("镜头与模糊")
@export var background_start_offset: float = 2600.0
@export var opening_camera_y: float = -40.0
@export_range(0.8, 2.0, 0.05) var sky_height_in_screens: float = 1.95
@export_range(0.0, 6.0, 0.1) var background_blur_lod: float = 2.4

@export_group("节奏（秒）")
@export_range(0.01, 2.0, 0.01) var start_duration: float = 0.16
@export_range(0.01, 3.0, 0.01) var stroke_duration: float = 1.2
@export_range(0.01, 2.0, 0.01) var fill_duration: float = 0.65
@export_range(0.01, 2.0, 0.01) var white_hold_duration: float = 0.22
@export_range(0.01, 2.0, 0.01) var logo_reveal_duration: float = 0.45
@export_range(0.01, 1.0, 0.01) var background_reveal_delay: float = 0.2
@export_range(0.01, 2.0, 0.01) var reveal_duration: float = 0.65
@export_range(0.01, 3.0, 0.01) var background_hold_duration: float = 0.8
@export_range(0.01, 3.0, 0.01) var sky_move_duration: float = 0.9
@export_range(0.01, 3.0, 0.01) var sky_hold_duration: float = 1.2
@export_range(0.01, 3.0, 0.01) var menu_move_duration: float = 1.1

@onready var _composite: ColorRect = $Overlay/Composite
@onready var _material: ShaderMaterial = _composite.material
@onready var _logo_texture: Texture2D = _material.get_shader_parameter("logo_texture")
@onready var _godot_logo: TextureRect = $Overlay/GodotLogo

var phase: Phase = Phase.BOOT
var _main: Node2D
var _timeline: Tween
var _stroke: float = 0.0
var _fill: float = 0.0
var _logo_reveal: float = 0.0
var _background_reveal: float = 0.0
var _logo_pulse: float = 1.0
var _camera_progress: float = 0.0
var _blur: float = 0.0
var _skip_requested: bool = false
var _load_failed: bool = false
var _pending_loads: Array[String] = []
## 保持强引用直到交接，MusicPlayer 可直接复用缓存，不在菜单显现时同步读盘。
var _menu_music: AudioStream

func _ready() -> void:
	SceneTransition.begin_opening()
	_godot_logo.add_to_group(&"opening_logos")
	_blur = background_blur_lod
	_sync_frame()
	var error := ResourceLoader.load_threaded_request(MAIN_PATH, "PackedScene")
	if error != OK:
		_show_load_error(error_string(error))
		return
	_pending_loads.append(MAIN_PATH)
	if ResourceLoader.load_threaded_request(MusicPlayer.MENU_TRACK, "AudioStream") == OK:
		_pending_loads.append(MusicPlayer.MENU_TRACK)
	_run.call_deferred()

func _new_tween() -> Tween:
	_timeline = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if _skip_requested:
		_timeline.set_speed_scale(1000.0)
	return _timeline

func _wait(seconds: float) -> void:
	var tween := _new_tween()
	tween.tween_interval(seconds)
	await tween.finished

func _set_phase(value: Phase) -> void:
	phase = value
	_camera_progress = 0.0
	if phase == Phase.REVEAL:
		# 先随背景蒙版揭示屏幕固定的 Back，避免到 Godot 画面才突然出现。
		_main.prepare_opening_back_ui()
	elif phase == Phase.SKY:
		_main.prepare_opening_menu()
	_sync_frame()
	phase_changed.emit(phase)

func _run() -> void:
	await _wait(start_duration)
	_set_phase(Phase.STROKE)
	var tween := _new_tween()
	# 路径进度就是累计弧长，线性推进保持笔触沿轮廓匀速移动。
	tween.tween_property(self, "_stroke", 1.0, stroke_duration)
	await tween.finished
	_set_phase(Phase.FILL)
	tween = _new_tween()
	tween.tween_property(self, "_fill", 1.0, fill_duration).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	await _wait(white_hold_duration)
	_set_phase(Phase.LOADING)
	var packed: PackedScene = await _load_menu()
	if packed == null:
		return
	_main = packed.instantiate() as Node2D
	_main.opening_active = true
	## 偏右取景由背景初始相位承担，不让镜头横移；交接时继续沿用这一滚动进度。
	_main.get_node("Game").initial_scroll = background_start_offset
	get_tree().root.add_child(_main)
	_sync_frame()
	## 场景资源就绪不等于画面就绪。背景必须在遮罩后真正绘制，不能 hide 后当作预热。
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	await get_tree().process_frame
	if _skip_requested:
		_finish()
		return
	_set_phase(Phase.REVEAL)
	tween = _new_tween().set_parallel(true)
	tween.tween_property(self, "_logo_reveal", 1.0, logo_reveal_duration).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_background_reveal", 1.0, reveal_duration).set_delay(
		background_reveal_delay
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_logo_pulse", logo_peak_scale, logo_impulse_duration).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_logo_pulse", 1.0, logo_settle_duration).set_delay(
		logo_impulse_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	if _skip_requested:
		_finish()
		return
	_set_phase(Phase.BACKGROUND)
	await _wait(background_hold_duration)
	_set_phase(Phase.SKY_UP)
	tween = _new_tween()
	tween.tween_property(self, "_camera_progress", 1.0, sky_move_duration).set_trans(
		Tween.TRANS_CUBIC
	).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	_set_phase(Phase.SKY)
	await _wait(sky_hold_duration)
	_set_phase(Phase.MENU_DOWN)
	tween = _new_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "_camera_progress", 1.0, menu_move_duration)
	tween.tween_property(self, "_blur", 0.0, menu_move_duration)
	await tween.finished
	_finish()

func _load_menu() -> PackedScene:
	var packed: PackedScene
	while true:
		if packed == null:
			match ResourceLoader.load_threaded_get_status(MAIN_PATH):
				ResourceLoader.THREAD_LOAD_LOADED:
					packed = ResourceLoader.load_threaded_get(MAIN_PATH) as PackedScene
					_pending_loads.erase(MAIN_PATH)
				ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					_show_load_error("Main resource failed to load")
					return null
		if _pending_loads.has(MusicPlayer.MENU_TRACK):
			match ResourceLoader.load_threaded_get_status(MusicPlayer.MENU_TRACK):
				ResourceLoader.THREAD_LOAD_LOADED:
					_menu_music = ResourceLoader.load_threaded_get(MusicPlayer.MENU_TRACK) as AudioStream
					_pending_loads.erase(MusicPlayer.MENU_TRACK)
				ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					_pending_loads.erase(MusicPlayer.MENU_TRACK)
		if packed != null and not _pending_loads.has(MusicPlayer.MENU_TRACK):
			return packed
		await get_tree().process_frame
	return null

func _process(_delta: float) -> void:
	_sync_frame()

func _sync_frame() -> void:
	var view_size := _composite.get_viewport_rect().size
	var fit: float = minf(view_size.x / DESIGN_SIZE.x, view_size.y / DESIGN_SIZE.y)
	var logo_size := Vector2(logo_width, logo_width * 0.5) * fit
	var logo_center := view_size * 0.5
	if is_instance_valid(_main):
		var camera: Camera2D = _main.menu_camera
		var normal_position: Vector2 = _main.main_camera_position.global_position
		var opening_offset := Vector2(0.0, opening_camera_y)
		var sky_offset := opening_offset + Vector2.UP * view_size.y * sky_height_in_screens / camera.zoom.y
		var offset := opening_offset
		match phase:
			Phase.SKY_UP:
				offset = opening_offset.lerp(sky_offset, _camera_progress)
			Phase.SKY:
				offset = sky_offset
			Phase.MENU_DOWN:
				offset = sky_offset.lerp(Vector2.ZERO, _camera_progress)
			Phase.FINISHED:
				offset = Vector2.ZERO
		_main.set_opening_view(offset)
		var menu_logo: Sprite2D = _main.get_node("Logo/Logo_Back")
		var logo_world := normal_position + opening_offset
		if phase == Phase.MENU_DOWN or phase == Phase.FINISHED:
			var blend: float = 1.0 if phase == Phase.FINISHED else _camera_progress
			logo_world = logo_world.lerp(menu_logo.global_position, blend)
			var menu_size := menu_logo.texture.get_size() * menu_logo.get_global_transform_with_canvas().get_scale().abs()
			logo_size = logo_size.lerp(menu_size, blend)
		var canvas := get_viewport().get_canvas_transform()
		logo_center = canvas * logo_world
		_godot_logo.scale = Vector2.ONE * fit
		_godot_logo.position = canvas * (normal_position + sky_offset) - _godot_logo.size * fit * 0.5
		_godot_logo.visible = phase in [Phase.SKY_UP, Phase.SKY, Phase.MENU_DOWN]
	logo_size *= _logo_pulse
	_material.set_shader_parameter("viewport_size", view_size)
	_material.set_shader_parameter("logo_rect", Vector4(
		(logo_center.x - logo_size.x * 0.5) / view_size.x,
		(logo_center.y - logo_size.y * 0.5) / view_size.y,
		logo_size.x / view_size.x, logo_size.y / view_size.y
	))
	_material.set_shader_parameter("stroke_width_source", stroke_width * _logo_texture.get_width() / logo_width)
	_material.set_shader_parameter("fill_wave_height", fill_wave_height / (logo_width * 0.5))
	_material.set_shader_parameter("stroke_progress", _stroke)
	_material.set_shader_parameter("fill_progress", _fill)
	_material.set_shader_parameter("logo_reveal_progress", _logo_reveal)
	_material.set_shader_parameter("background_reveal_progress", _background_reveal)
	_material.set_shader_parameter("blur_lod", _blur)
	# 抬头后停用完整彩色 Logo 的覆盖绘制，回程显示 Main 中按存档分层的真实标题。
	_material.set_shader_parameter("logo_opacity", 0.0 if phase >= Phase.SKY else 1.0)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("back") or event.physical_keycode in [KEY_ESCAPE, KEY_SPACE] or event.keycode in [KEY_ESCAPE, KEY_SPACE]:
		get_viewport().set_input_as_handled()
		if _load_failed:
			get_tree().quit()
			return
		_skip_requested = true
		if _timeline != null and _timeline.is_valid():
			_timeline.set_speed_scale(1000.0)

func _finish() -> void:
	if phase == Phase.FINISHED:
		return
	_logo_pulse = 1.0
	_stroke = 1.0
	_fill = 1.0
	_logo_reveal = 1.0
	_background_reveal = 1.0
	_blur = 0.0
	# 跳过动画可能没有经过天空阶段，交接前同样保证菜单完整。
	_main.prepare_opening_menu()
	_set_phase(Phase.FINISHED)
	_main.complete_opening()
	get_tree().current_scene = _main
	SceneTransition.finish_opening()
	queue_free()

func _show_load_error(message: String) -> void:
	_load_failed = true
	$Overlay/Status.text = "Unable to load the main menu.\nPress Esc to exit."
	$Overlay/Status.show()
	push_error("Opening: " + message)

func _exit_tree() -> void:
	## 窗口在后台加载期间关闭时，先回收线程任务，避免引擎卸载资源时线程还在写入。
	for path in _pending_loads:
		if ResourceLoader.load_threaded_get_status(path) in [
			ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED
		]:
			ResourceLoader.load_threaded_get(path)
