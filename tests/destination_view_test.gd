## Run with an isolated user directory; exercises real Game, camera, input and transitions.
extends Node

var _failures: int = 0
var _changes: Array[bool] = []
var _game: Node

func _ready() -> void:
	if not OS.get_user_data_dir().contains("PICTOUR_destination_view_qa"):
		push_error("Use a QA project with custom_user_dir_name=PICTOUR_destination_view_qa")
		get_tree().quit(2)
		return
	Input.use_accumulated_input = false
	SceneTransition.fade_in_duration = 0.0
	SceneTransition.fade_out_duration = 0.0
	SignalSystem.destination_view_changed.connect(func(active: bool): _changes.append(active))
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)

func _key(code: Key, pressed: bool, location: KeyLocation = KEY_LOCATION_UNSPECIFIED,
		physical: bool = true, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code if physical else KEY_NONE
	event.location = location
	event.pressed = pressed
	event.echo = echo
	event.shift_pressed = pressed and code == KEY_SHIFT
	event.ctrl_pressed = pressed and code == KEY_CTRL
	event.alt_pressed = pressed and code == KEY_ALT
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _settle() -> void:
	await get_tree().create_timer(0.45).timeout

func _view(active: bool, description: String) -> void:
	await _settle()
	var target := Global.goal.global_position if active else Global.player.global_position
	_check(SignalSystem.looking_at_destination == active, description + ": input state")
	_check(Global.camera.global_position.distance_to(target) < 1.0, description + ": camera target")
	if active:
		_check(SoundPlayer._channel_cue.get(&"destination") == &"destination_in", description + ": sound triggered")
	else:
		_check(not SoundPlayer._channel_cue.has(&"destination"), description + ": sound stopped")

func _binding(code: Key, location: KeyLocation = KEY_LOCATION_UNSPECIFIED) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.location = location
	_check(SaveSystem.set_key_binding(&"look_at_destination", event) == OK, "rebind destination")

func _run() -> void:
	_binding(KEY_SHIFT, KEY_LOCATION_LEFT)
	Global.next_level_id = 1
	_game = load("res://Interface/Game.tscn").instantiate()
	_game.play_dialogue = false
	add_child(_game)
	await _settle()
	await _view(false, "initial entry")
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	await _view(true, "normal hold")
	var changes := _changes.size()
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT, true, true)
	await _settle()
	_check(_changes.size() == changes, "key repeat does not restart observation")
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)
	await _view(false, "normal release")
	for index in 3:
		_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
		await get_tree().create_timer(0.05).timeout
		_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)
		await get_tree().create_timer(0.05).timeout
	await _view(false, "rapid presses during camera tween")
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	_key(KEY_A, false)
	await _view(true, "unrelated key-up keeps observation")
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)

	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	await _view(true, "hold before incomplete release")
	_key(KEY_SHIFT, false, KEY_LOCATION_UNSPECIFIED, false)
	_check(Input.is_action_pressed("look_at_destination") and Input.is_physical_key_pressed(KEY_SHIFT),
		"reproduction leaves both engine caches pressed")
	await _view(false, "logical-only release")
	_game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Global.next_level_id = 1
	_game = load("res://Interface/Game.tscn").instantiate()
	_game.play_dialogue = false
	add_child(_game)
	await _view(false, "restart with stale engine caches")
	_game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)

	# Real menu/re-entry/next-level transitions run from a persistent test runner.
	get_tree().current_scene = null
	await SceneTransition.enter_main_menu()
	await SceneTransition.enter_level(1, false, false)
	_game = get_tree().current_scene
	await _view(false, "menu then re-entry")
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	_key(KEY_SHIFT, false, KEY_LOCATION_UNSPECIFIED, false)
	await SceneTransition.enter_level(2, false, false)
	_game = get_tree().current_scene
	await _view(false, "next level with stale engine caches")
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)

	_key(KEY_SHIFT, true, KEY_LOCATION_RIGHT)
	await _view(false, "opposite Shift alone")
	_key(KEY_SHIFT, false, KEY_LOCATION_RIGHT)
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	_key(KEY_SHIFT, true, KEY_LOCATION_RIGHT)
	_key(KEY_SHIFT, false, KEY_LOCATION_UNSPECIFIED)
	_key(KEY_SHIFT, true, KEY_LOCATION_RIGHT, true, true)
	await _view(false, "ambiguous release and opposite Shift repeat")
	_key(KEY_SHIFT, false, KEY_LOCATION_RIGHT)
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	_key(KEY_SHIFT, false, KEY_LOCATION_RIGHT)
	await _view(false, "mismatched-side release clears held record")
	_key(KEY_SHIFT, true, KEY_LOCATION_RIGHT)
	await _view(false, "opposite Shift cannot revive stale action")
	_key(KEY_SHIFT, false, KEY_LOCATION_RIGHT)
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)

	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	await _view(true, "hold before focus loss")
	get_window().focus_exited.emit()
	await _view(false, "focus loss without key-up")
	get_window().focus_entered.emit()
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT, true, true)
	await _view(false, "focus return and repeat cannot relatch")
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)

	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	await _view(true, "hold before pause")
	_game.get_node("Camera/MenuUI/Screen/Pause").open()
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)
	_game.get_node("Camera/MenuUI/Screen/Pause").resume()
	await _view(false, "release while paused")
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	await _view(true, "hold before settings capture")
	var pause: Control = _game.get_node("Camera/MenuUI/Screen/Pause")
	pause.open()
	pause._open_options()
	var options: Control = pause.get_node("OptionsMenu")
	options._select_page(2)
	options._listen_for_key(options._binding_buttons[&"look_at_destination"])
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)
	options._cancel_listening()
	pause.resume()
	await _view(false, "settings consumes key-up before gameplay input")

	SignalSystem.set_dialogue_active(true)
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	await _view(false, "dialogue blocks observation")
	SignalSystem.set_dialogue_active(false)
	await _view(true, "held key after dialogue")
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)
	await _view(false, "release after dialogue")

	for spec in [[KEY_SHIFT, KEY_LOCATION_RIGHT], [KEY_CTRL, KEY_LOCATION_LEFT],
			[KEY_ALT, KEY_LOCATION_RIGHT], [KEY_G, KEY_LOCATION_UNSPECIFIED]]:
		_binding(spec[0], spec[1])
		_key(spec[0], true, spec[1])
		await _view(true, "custom key hold %s" % [spec])
		_key(spec[0], false, spec[1])
		await _view(false, "custom key release %s" % [spec])
	_key(KEY_G, true)
	await _view(true, "hold before rebinding")
	_binding(KEY_SHIFT, KEY_LOCATION_LEFT)
	await _view(false, "rebind cancels previous hold")
	_key(KEY_G, false)

	# Observe does not mutate player state or layer assignments; movement resumes.
	await SceneTransition.enter_level(1, false, false)
	_game = get_tree().current_scene
	await _settle()
	var slots: Array = Global.layers.map(func(layer: DepthLayer): return layer.slot)
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	_key(KEY_D, true)
	_key(KEY_Q, true)
	_key(KEY_F, true)
	await _settle()
	_check(Global.layers.map(func(layer: DepthLayer): return layer.slot) == slots, "layer input blocked during observation")
	_check(Global.player.current_state == PlayerController.PlayerState.NORMAL, "UAV input blocked during observation")
	_check(is_zero_approx(Global.player.velocity.x), "movement blocked during observation")
	_key(KEY_Q, false)
	_key(KEY_F, false)
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)
	await _settle()
	_check(Global.player.velocity.x > 0.0, "movement resumes after release")
	_key(KEY_D, false)
	await _view(false, "camera follows moving player after release")
	await SceneTransition.enter_level(9, false, false)
	_game = get_tree().current_scene
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	await _view(true, "night level hold")
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)
	await _view(false, "night level release")
	print("DESTINATION_VIEW_TEST failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
