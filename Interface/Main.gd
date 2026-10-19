extends Node2D

enum Page { MAIN, LEVEL_SELECTION, GAME_OPTION }

const LevelsMenu = preload("res://Interface/UI/Levels.gd")
const CAMERA_MOVE_DURATION: float = 0.45
const EXIT_HOLD_DURATION: float = 1.0
const DESIGN_SIZE := Vector2(1280.0, 720.0)

@onready var menu_camera: Camera2D = $Camera
@onready var main_camera_position: Marker2D = $CameraPosition01
@onready var secondary_camera_position: Marker2D = $CameraPosition02
@onready var main_menu: Control = $MainMenu
@onready var level_selection: LevelsMenu = $LevelSelection
@onready var game_option: Control = $GameOption
@onready var back_button: Button = $MenuUI/Screen/Back
@onready var _page_controls: Array[Control] = [main_menu, level_selection, game_option]

var _page: Page = Page.MAIN
var _camera_tween: Tween
var _exit_timer: Timer
var _back_held: bool = false
var _back_key_held: bool = false
var _page_blend: float = 0.0
var _main_origin: Vector2
var _secondary_offset: Vector2
var _logo_offset: Vector2
var _background_offset: Vector2
var _background_player_offset: Vector2
var _control_offsets: Array[Vector2] = []

func _ready() -> void:
	SignalSystem.set_gameplay_active(false)
	Global.clear_scene_nodes()
	menu_camera.make_current()
	## 场景中的坐标仍是 1280×720 的布局参考，只缓存一次，避免累计缩放。
	_main_origin = main_camera_position.position
	_secondary_offset = (secondary_camera_position.position - _main_origin) / DESIGN_SIZE
	_logo_offset = ($Logo.position - _main_origin) / DESIGN_SIZE
	var player_position := to_local($Game/Player.global_position)
	_background_offset = (player_position - _main_origin) / DESIGN_SIZE
	_background_player_offset = player_position - $Game.position
	for index in _page_controls.size():
		var anchor := main_camera_position if index == 0 else secondary_camera_position
		var control := _page_controls[index]
		_control_offsets.append((control.position + control.size * 0.5 - anchor.position) / DESIGN_SIZE)
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	main_menu.visible = true
	level_selection.visible = false
	game_option.visible = false
	$MainMenu/LevelSelection.pressed.connect(_show_page.bind(Page.LEVEL_SELECTION))
	$MainMenu/GameOption.pressed.connect(_show_page.bind(Page.GAME_OPTION))
	level_selection.level_selected.connect(_enter_level)
	back_button.pressed.connect(_on_back_pressed)
	back_button.button_down.connect(_on_back_down)
	back_button.button_up.connect(_on_back_up)
	back_button.mouse_exited.connect(_on_back_up)
	get_window().focus_exited.connect(_cancel_back_hold)
	_exit_timer = Timer.new()
	_exit_timer.one_shot = true
	_exit_timer.wait_time = EXIT_HOLD_DURATION
	add_child(_exit_timer)
	_exit_timer.timeout.connect(_on_exit_hold_timeout)
	SignalSystem.back_pressed.connect(_on_back_key_pressed)
	SignalSystem.back_released.connect(_on_back_key_released)
	_set_main_buttons_presented(false, true)
	if SceneTransition.busy:
		SceneTransition.transition_finished.connect(_set_main_buttons_presented.bind(true), CONNECT_ONE_SHOT)
	else:
		_set_main_buttons_presented(true)
	SceneTransition.scene_ready()

func _set_main_buttons_presented(presented: bool, instant: bool = false) -> void:
	for button in main_menu.get_children():
		button.set_presented(presented, instant)

func _show_page(page: Page) -> void:
	if SceneTransition.busy:
		return
	if _camera_tween != null and _camera_tween.is_valid():
		_camera_tween.kill()
	_cancel_back_hold()
	_page = page
	## 离场动画完成前保留容器，缩放只影响 Icon，不参与布局。
	main_menu.show()
	_set_main_buttons_presented(page == Page.MAIN)
	level_selection.visible = page == Page.LEVEL_SELECTION
	game_option.visible = page == Page.GAME_OPTION
	_camera_tween = create_tween()
	_camera_tween.tween_method(
		_set_page_blend, _page_blend, 0.0 if page == Page.MAIN else 1.0, CAMERA_MOVE_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if page != Page.MAIN:
		_camera_tween.tween_callback(main_menu.hide)

func _update_layout() -> void:
	var view_size := get_viewport_rect().size / menu_camera.zoom.abs()
	secondary_camera_position.position = _main_origin + _secondary_offset * view_size
	$Logo.position = _main_origin + _logo_offset * view_size
	$Game.position = _main_origin + _background_offset * view_size - _background_player_offset
	for index in _page_controls.size():
		var anchor := main_camera_position if index == 0 else secondary_camera_position
		var control := _page_controls[index]
		control.position = anchor.position + _control_offsets[index] * view_size - control.size * 0.5
	_set_page_blend(_page_blend)

func _set_page_blend(value: float) -> void:
	_page_blend = value
	menu_camera.global_position = main_camera_position.global_position.lerp(
		secondary_camera_position.global_position, _page_blend
	)
	menu_camera.force_update_scroll()
	## 尺寸变化和 Tween 也可能发生在暂停时，直接刷新而不等待下一帧。
	$Game.refresh_view()

func _on_back_pressed() -> void:
	if _page != Page.MAIN:
		_show_page(Page.MAIN)

func _on_back_down() -> void:
	if SceneTransition.busy:
		return
	_back_held = true
	_update_exit_hold()

func _on_back_up() -> void:
	_back_held = false
	_update_exit_hold()

## Esc 直接响应全局输入信号，不模拟按钮按下或点击。
func _on_back_key_pressed() -> void:
	if SceneTransition.busy:
		return
	if _page != Page.MAIN:
		_show_page(Page.MAIN)
		return
	_back_key_held = true
	_update_exit_hold()

func _on_back_key_released() -> void:
	_back_key_held = false
	_update_exit_hold()

func _cancel_back_hold() -> void:
	_back_held = false
	_back_key_held = false
	_update_exit_hold()

func _update_exit_hold() -> void:
	var holding := _page == Page.MAIN and not SceneTransition.busy and (_back_held or _back_key_held)
	if not holding:
		_exit_timer.stop()
		back_button.stop_hold()
	elif _exit_timer.is_stopped():
		_exit_timer.start()
		# 只复用进度环与抖动表现；计时和是否退出由菜单自身管理。
		back_button.start_hold(_exit_timer)

func _on_exit_hold_timeout() -> void:
	if _page == Page.MAIN and not SceneTransition.busy and (_back_held or _back_key_held):
		if _back_key_held and not _back_held:
			SoundPlayer.play(&"ui_press")
		_cancel_back_hold()
		_set_main_buttons_presented(false)
		SceneTransition.quit_game()

func _enter_level(level_id: int) -> void:
	if SceneTransition.busy or (_camera_tween != null and _camera_tween.is_running()):
		return
	SceneTransition.enter_level(level_id)
