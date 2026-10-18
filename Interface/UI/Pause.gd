extends Control

enum HoldAction { NONE, RESTART, QUIT }

@export_range(0.1, 3.0, 0.1, "or_greater") var hold_duration: float = 1.0

@onready var _hold_timer: Timer = $HoldTimer
var _hold_action: HoldAction = HoldAction.NONE

func _ready() -> void:
	hide()
	SignalSystem.back_pressed.connect(toggle)
	$Continue.pressed.connect(resume)
	$Options.pressed.connect(_open_options)
	$Restart.button_down.connect(_begin_hold.bind(HoldAction.RESTART))
	$Quit.button_down.connect(_begin_hold.bind(HoldAction.QUIT))
	for button: Button in [$Restart, $Quit]:
		button.button_up.connect(_cancel_hold)
		button.mouse_exited.connect(_cancel_hold)
	_hold_timer.timeout.connect(_on_hold_timeout)
	get_window().focus_exited.connect(_cancel_hold)

func toggle() -> void:
	if SceneTransition.busy:
		return
	if $OptionsMenu.visible:
		_close_options()
	elif visible:
		resume()
	else:
		open()

func open() -> void:
	if visible or SceneTransition.busy:
		return
	show()
	get_tree().paused = true
	$Continue.grab_focus()

func _open_options() -> void:
	if not visible or SceneTransition.busy:
		return
	_cancel_hold()
	_set_buttons_visible(false)
	$OptionsMenu.show()
	$OptionsMenu/SideBar/Game.grab_focus()

func _close_options() -> void:
	$OptionsMenu.hide()
	_set_buttons_visible(true)
	$Options.grab_focus()

func _set_buttons_visible(active: bool) -> void:
	for button: Button in [$Continue, $Options, $Restart, $Quit]:
		button.visible = active

func resume() -> void:
	if not visible or SceneTransition.busy:
		return
	_cancel_hold()
	$OptionsMenu.hide()
	_set_buttons_visible(true)
	hide()
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	get_tree().paused = false
	## 仅保留夜间影子关卡的物理冻结，白天 Player 休息时世界仍继续运行。
	PhysicsServer2D.set_active(not SignalSystem.is_physics_resting())

func _begin_hold(action: HoldAction) -> void:
	if not visible or SceneTransition.busy:
		return
	_cancel_hold()
	_hold_action = action
	_hold_timer.start(hold_duration)
	var button: Button = $Restart if action == HoldAction.RESTART else $Quit
	button.start_hold(_hold_timer)

func _cancel_hold() -> void:
	_hold_timer.stop()
	_hold_action = HoldAction.NONE
	for button: Button in [$Restart, $Quit]:
		button.stop_hold()

func _on_hold_timeout() -> void:
	if not visible or SceneTransition.busy or _hold_action == HoldAction.NONE:
		return
	var action: HoldAction = _hold_action
	_cancel_hold()
	if action == HoldAction.RESTART:
		SceneTransition.enter_level(Global.level.level_id, false, false)
	else:
		SceneTransition.enter_main_menu()

func _exit_tree() -> void:
	if visible and not SceneTransition.busy:
		get_tree().paused = false
