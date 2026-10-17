extends Control

enum HoldAction { NONE, RESTART, QUIT }

@export_range(0.1, 3.0, 0.1, "or_greater") var hold_duration: float = 1.0

@onready var _hold_timer: Timer = $HoldTimer
var _hold_action: HoldAction = HoldAction.NONE

func _ready() -> void:
	hide()
	$Continue.pressed.connect(resume)
	$Restart.button_down.connect(_begin_hold.bind(HoldAction.RESTART))
	$Quit.button_down.connect(_begin_hold.bind(HoldAction.QUIT))
	for button: Button in [$Restart, $Quit]:
		button.button_up.connect(_cancel_hold)
		button.mouse_exited.connect(_cancel_hold)
	_hold_timer.timeout.connect(_on_hold_timeout)
	get_window().focus_exited.connect(_cancel_hold)

func _input(event: InputEvent) -> void:
	if SceneTransition.busy or event.is_echo() or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if visible:
		resume()
	else:
		open()

func open() -> void:
	if visible or SceneTransition.busy:
		return
	show()
	get_tree().paused = true
	$Continue.grab_focus()

func resume() -> void:
	if not visible or SceneTransition.busy:
		return
	_cancel_hold()
	hide()
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	get_tree().paused = false
	## 解除场景树暂停会唤醒物理服务器；保留精神滤镜原有的休息状态。
	PhysicsServer2D.set_active(not SignalSystem.timer.is_stopped())

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
