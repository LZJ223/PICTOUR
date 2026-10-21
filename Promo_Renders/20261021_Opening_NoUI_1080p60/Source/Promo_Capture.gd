## --fixed-fps 60 逐帧保存实际 1080p 窗口纹理，避免 Movie Maker 锁定项目的 720p。
extends Node

const Intro = preload("res://Opening/Opening.gd")
const FPS: int = 60
const TAIL_FRAMES: int = 10 * FPS
const OUTPUT := "res://Promo_Renders/20261021_Opening_NoUI_1080p60/"
const FRAMES := "res://.godot/promo_opening_20261021/Frames1080p/"
const PIANO := "res://Audio/SFX/opening_piano.wav"
const PIANO_BUS := &"PromoLogo"

@onready var _opening: Node = $Opening
var _menu: Node2D
var _return_frame: int = -1
var _piano_frame: int = -1
var _phases: Array[Dictionary] = []
var _done: bool = false
var _checks: int = 0
var _frame_count: int = 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	seed(20261021)
	# 所有游戏声音总线静音，仅允许本次 Logo 音效进入独立总线。
	for index in AudioServer.bus_count:
		AudioServer.set_bus_mute(index, index != 0)
	AudioServer.set_bus_volume_db(0, 0.0)
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, PIANO_BUS)
	AudioServer.set_bus_send(index, &"Master")
	AudioServer.set_bus_volume_db(index, 0.0)
	_opening.phase_changed.connect(_on_phase)
	RenderingServer.frame_post_draw.connect(_write_frame)
	print("PROMO_CAPTURE_START 1920x1080 60fps; Logo sound only; no UI")

func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()

func _on_phase(value: int) -> void:
	var frame := _frame_count
	_phases.append({"phase": Intro.Phase.keys()[value], "frame": frame})
	if value == Intro.Phase.REVEAL:
		_menu = _opening._main
		for player: AudioStreamPlayer in SoundPlayer._players:
			if player.playing and player.stream != null and player.stream.resource_path == PIANO:
				player.bus = PIANO_BUS
				player.volume_db = 0.0
				_piano_frame = frame
		assert(_piano_frame >= 0, "Logo piano was not played")
	elif value == Intro.Phase.FINISHED:
		_return_frame = frame
		assert(_menu.menu_camera.global_position.is_equal_approx(_menu.main_camera_position.global_position))
		print("PROMO_CAMERA_RETURN frame=", frame, "; record 600 more frames")
	print("PROMO_PHASE ", Intro.Phase.keys()[value], " frame=", frame)

func _process(_delta: float) -> void:
	if is_instance_valid(_menu):
		for path in ["Logo", "MainMenu", "LevelSelection", "GameOption", "MenuUI"]:
			assert(not _menu.get_node(path).visible, "UI was shown: " + path)
		_checks += 1

func _write_frame() -> void:
	if _done:
		return
	var image := get_viewport().get_texture().get_image()
	assert(image.get_size() == Vector2i(1920, 1080), "Capture must be native 1920x1080")
	var error := image.save_png(FRAMES + "frame%08d.png" % _frame_count)
	assert(error == OK, "Could not save frame")
	_frame_count += 1
	if _frame_count % 180 == 0:
		print("PROMO_FRAMES_WRITTEN ", _frame_count)
	if _return_frame >= 0 and _frame_count >= _return_frame + TAIL_FRAMES:
		_done = true
		var data := {
			"resolution": [1920, 1080], "fps": FPS,
			"camera_return_frame": _return_frame, "piano_start_frame": _piano_frame,
			"tail_frames": TAIL_FRAMES, "tail_seconds": 10.0,
			"frame_count": _frame_count, "duration_seconds": float(_frame_count) / FPS,
			"ui_hidden_checks": _checks,
			"phases": _phases, "music": false, "audio_source": PIANO,
		}
		var file := FileAccess.open(OUTPUT + "Capture.json", FileAccess.WRITE)
		assert(file != null, "Could not write capture metadata")
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("PROMO_CAPTURE_COMPLETE ", JSON.stringify(data))
		get_tree().quit()
