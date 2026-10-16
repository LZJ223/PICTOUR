extends Node2D

enum Page { MAIN, LEVEL_SELECTION, GAME_OPTION }

const CAMERA_MOVE_DURATION: float = 0.45
const EXIT_HOLD_DURATION: float = 1.0

@onready var menu_camera: Camera2D = $Camera
@onready var main_camera_position: Marker2D = $CameraPosition01
@onready var secondary_camera_position: Marker2D = $CameraPosition02
@onready var main_menu: Control = $MainMenu
@onready var level_selection: Control = $LevelSelection
@onready var game_option: Control = $GameOption
@onready var back_button: Button = $MenuUI/Back

var _page: Page = Page.MAIN
var _camera_tween: Tween
var _exit_timer: Timer
var _back_held: bool = false

func _ready() -> void:
	SignalSystem.set_gameplay_active(false)
	Global.clear_scene_nodes()
	menu_camera.make_current()
	menu_camera.global_position = main_camera_position.global_position
	main_menu.visible = true
	level_selection.visible = false
	game_option.visible = false
	$MainMenu/LevelSelection.pressed.connect(_show_page.bind(Page.LEVEL_SELECTION))
	$MainMenu/GameOption.pressed.connect(_show_page.bind(Page.GAME_OPTION))
	for child in level_selection.get_children():
		if child is Button:
			var level_id: int = child.get_meta(&"level_id", 0)
			child.pressed.connect(_enter_level.bind(level_id))
	back_button.pressed.connect(_on_back_pressed)
	back_button.button_down.connect(_on_back_down)
	back_button.button_up.connect(_on_back_up)
	_exit_timer = Timer.new()
	_exit_timer.one_shot = true
	_exit_timer.wait_time = EXIT_HOLD_DURATION
	add_child(_exit_timer)
	_exit_timer.timeout.connect(_on_exit_hold_timeout)
	SceneTransition.scene_ready()

func _show_page(page: Page) -> void:
	if SceneTransition.busy:
		return
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_exit_timer.stop()
	_page = page
	main_menu.visible = page == Page.MAIN
	level_selection.visible = page == Page.LEVEL_SELECTION
	game_option.visible = page == Page.GAME_OPTION
	var target: Marker2D = main_camera_position if page == Page.MAIN else secondary_camera_position
	_camera_tween = create_tween()
	_camera_tween.tween_property(
		menu_camera, "global_position", target.global_position, CAMERA_MOVE_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func _on_back_pressed() -> void:
	if _page != Page.MAIN:
		_show_page(Page.MAIN)

func _on_back_down() -> void:
	if SceneTransition.busy:
		return
	_back_held = true
	if _page == Page.MAIN:
		_exit_timer.start()

func _on_back_up() -> void:
	_back_held = false
	_exit_timer.stop()

func _on_exit_hold_timeout() -> void:
	if _page == Page.MAIN and _back_held:
		SceneTransition.quit_game()

func _enter_level(level_id: int) -> void:
	if SceneTransition.busy or (_camera_tween != null and _camera_tween.is_running()):
		return
	SceneTransition.enter_level(level_id)
