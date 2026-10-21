## Real Player and rounded project collision polygon, driven on physics ticks.
extends Node

signal stepped

const ORIGIN := Vector2(10000.0, -2000.0)
const CLOUD := "res://Component/Shadowed_Geometry/CloudBox/CloudBox_01/CloudBox_01.tscn"
var _game: Node
var _player: PlayerController
var _platform: StaticBody2D
var _shape: CollisionPolygon2D
var _failures: int = 0
var _checks: int = 0

func _ready() -> void:
	if not OS.get_user_data_dir().contains("PICTOUR_destination_view_qa"):
		push_error("Run through the isolated regression runner")
		get_tree().quit(2)
		return
	process_physics_priority = 1000
	Input.use_accumulated_input = false
	SceneTransition.fade_in_duration = 0.0
	SceneTransition.fade_out_duration = 0.0
	_run.call_deferred()

func _physics_process(_delta: float) -> void:
	stepped.emit()

func _step(count: int = 1) -> void:
	for index in count:
		await stepped

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures += 1
		push_error("FAIL: " + description)

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	if code == KEY_SHIFT:
		event.location = KEY_LOCATION_LEFT
		event.shift_pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _reset_player() -> void:
	_key(KEY_SPACE, false)
	_key(KEY_D, false)
	_key(KEY_SHIFT, false)
	SignalSystem.set_dialogue_active(false)
	_player.position = ORIGIN + Vector2(0.0, -110.0)
	_player.velocity = Vector2.ZERO
	_player.set_collision_group(2)
	await _step(30)
	_check(_player.is_on_floor(), "fixture: landed on original rounded cloud outline")

func _leave_edge() -> void:
	_key(KEY_D, true)
	for frame in 120:
		await _step()
		if not _player.is_on_floor():
			print("EDGE: frame=", frame, " position=", _player.position - ORIGIN, " velocity=", _player.velocity)
			return
	_check(false, "fixture: player must run off rounded edge")

func _assert_no_jump(description: String) -> void:
	_key(KEY_SPACE, true)
	await _step()
	_check(_player.velocity.y >= 0.0, description)
	_key(KEY_SPACE, false)

func _trace(grace: float, jump_from_floor: bool) -> Array[Vector2]:
	_player.jump_grace_time = grace
	await _reset_player()
	if jump_from_floor:
		_key(KEY_SPACE, true)
	else:
		await _leave_edge()
	var trace: Array[Vector2] = []
	for frame in 15:
		await _step()
		trace.append(_player.position)
		trace.append(_player.velocity)
	return trace

func _same_trace(first: Array[Vector2], second: Array[Vector2]) -> bool:
	for index in first.size():
		if first[index].distance_to(second[index]) > 0.02:
			return false
	return true

func _run() -> void:
	# Use default keys only in the isolated save directory.
	for action in [&"jump", &"move_right", &"look_at_destination"]:
		SaveSystem.set_key_binding(action, SaveSystem._default_key_bindings[action])
	_game = load("res://Interface/Game.tscn").instantiate()
	_game.process_mode = Node.PROCESS_MODE_PAUSABLE
	_game.play_dialogue = false
	add_child(_game)
	await _step(5)
	_player = Global.player
	# Copy the existing resource's polygon verbatim into a stationary fixture.
	# Neither the resource nor the real player's collision is edited.
	var template: Node = load(CLOUD).instantiate()
	_shape = template.get_node("CollisionBox").duplicate() as CollisionPolygon2D
	_platform = StaticBody2D.new()
	_platform.position = ORIGIN
	_platform.collision_layer = 2
	_platform.collision_mask = 2
	_platform.add_child(_shape)
	var visual := Polygon2D.new()
	visual.polygon = _shape.polygon
	visual.color = Color(0.7, 0.75, 0.8)
	_platform.add_child(visual)
	_game.add_child(_platform)
	template.free()
	await _reset_player()
	await _leave_edge()
	await _step(2)
	_check(not _player.is_on_floor(), "jump request arrives after true floor contact was lost")
	_key(KEY_SPACE, true)
	await _step()
	_check(_player.velocity.y < -600.0, "late edge press starts jump")
	_check(is_equal_approx(_player.velocity.y, -_player.jump_speed), "late jump gets full original launch speed")
	_check(is_zero_approx(_player._jump_grace_remaining), "jump consumes grace immediately")
	_key(KEY_SPACE, false)
	await _step()
	var previous_vy := _player.velocity.y
	_key(KEY_SPACE, true)
	await _step()
	_check(_player.velocity.y > previous_vy, "second airborne press cannot double jump")

	var normal_disabled := await _trace(0.0, true)
	var normal_enabled := await _trace(0.10, true)
	_check(_same_trace(normal_disabled, normal_enabled), "normal ground jump trajectory is unchanged")
	var fall_disabled := await _trace(0.0, false)
	var fall_enabled := await _trace(0.10, false)
	_check(_same_trace(fall_disabled, fall_enabled), "run-off trajectory is unchanged: no hovering or delayed gravity")

	await _reset_player()
	await _leave_edge()
	await _step(9)
	await _assert_no_jump("expired grace rejects late press")
	_player.jump_grace_time = 0.0
	await _reset_player()
	await _leave_edge()
	await _step(2)
	await _assert_no_jump("zero grace restores strict ground-only jumping")
	_player.jump_grace_time = 0.10

	# Holding jump does not queue jumps on landing; a new press can jump again.
	await _reset_player()
	_key(KEY_SPACE, true)
	await _step(65)
	_check(_player.is_on_floor(), "held jump does not auto-jump after landing")
	_key(KEY_SPACE, false)
	await _step()
	_key(KEY_SPACE, true)
	await _step()
	_check(_player.velocity.y < -600.0, "landing restores next deliberate jump")
	_key(KEY_SPACE, false)
	await _step()
	previous_vy = _player.velocity.y
	_key(KEY_SPACE, true)
	await _step()
	_check(_player.velocity.y > previous_vy, "normal jump cannot be followed by grace double jump")

	# Pause freezes simulation time, while observation/dialogue discard eligibility.
	await _reset_player()
	await _leave_edge()
	var remaining := _player._jump_grace_remaining
	get_tree().paused = true
	await _step(20)
	_check(is_equal_approx(_player._jump_grace_remaining, remaining), "pause freezes grace with physics")
	get_tree().paused = false
	_key(KEY_SPACE, true)
	await _step()
	_check(_player.velocity.y < -600.0, "resume preserves remaining simulation-time grace")
	await _reset_player()
	await _leave_edge()
	_key(KEY_SHIFT, true)
	await _step()
	_check(SignalSystem.looking_at_destination, "observation lock is active")
	_check(is_zero_approx(_player._jump_grace_remaining), "observation discards grace")
	_key(KEY_SHIFT, false)
	await _step()
	await _assert_no_jump("observation release cannot revive airborne grace")
	await _reset_player()
	await _leave_edge()
	SignalSystem.set_dialogue_active(true)
	await _step()
	_check(is_zero_approx(_player._jump_grace_remaining), "dialogue discards grace")
	SignalSystem.set_dialogue_active(false)
	await _assert_no_jump("dialogue exit cannot revive airborne grace")
	await _reset_player()
	await _leave_edge()
	Global.goal.completed = true
	await _step()
	_check(is_zero_approx(_player._jump_grace_remaining), "completion discards grace")
	await _assert_no_jump("completion still blocks player jumping")
	Global.goal.completed = false

	# The original ground-only UAV rule is not broadened by jump grace.
	await _reset_player()
	await _leave_edge()
	_player.UAV_activate()
	_check(_player.current_state == PlayerController.PlayerState.NORMAL, "grace does not allow airborne UAV entry")
	_key(KEY_SPACE, true)
	await _step()
	_check(_player.velocity.y < -600.0, "failed UAV entry does not consume a valid grace jump")
	await _reset_player()
	_player.UAV_activate()
	await _step(2)
	_check(_player.current_state == PlayerController.PlayerState.UAV, "grounded UAV entry still works")
	_check(is_zero_approx(_player._jump_grace_remaining), "UAV entry discards grace")
	_key(KEY_SPACE, true)
	await _step()
	_check(is_zero_approx(_player.velocity.y), "jump input does not affect UAV flight")
	_key(KEY_SPACE, false)
	# Move only the test body's position to exercise recall into unsupported space.
	_player.player_body.position = ORIGIN + Vector2(500.0, 100.0)
	_player.UAV_activate()
	_check(_player.current_state == PlayerController.PlayerState.RECALLING, "UAV recall still starts")
	await _step(30)
	_check(_player.current_state == PlayerController.PlayerState.NORMAL, "UAV recall restores normal mode")
	await _assert_no_jump("recalling into air cannot carry ground grace")

	await _reset_player()
	var controller := _game.get_node("LayerControllerSystem") as LayerControllerSystem
	_check(controller.cycle(1), "real layer cycle starts")
	await _step()
	_check(not _player.is_on_floor(), "new collision layer has no test platform")
	_check(is_zero_approx(_player._jump_grace_remaining), "layer switch discards old floor grace")
	await _assert_no_jump("layer switch cannot grant an extra airborne jump")
	await _step(15)
	_check(controller.cycle(-1), "layer cycle can return")
	await _step(15)

	# A new player must land before earning grace, including after scene recreation.
	var old_player := _player
	_player = load("res://Component/Player/Player.tscn").instantiate()
	_player.position = ORIGIN + Vector2(500.0, 0.0)
	_player.set_collision_group(2)
	Global.player = _player
	_game.add_child(_player)
	old_player.queue_free()
	await _step()
	await _assert_no_jump("fresh airborne player has no grace")

	# Ceiling collisions remain physical even during a grace jump.
	var ceiling := StaticBody2D.new()
	ceiling.position = ORIGIN
	ceiling.collision_layer = 2
	ceiling.collision_mask = 2
	var ceiling_shape := CollisionPolygon2D.new()
	ceiling_shape.polygon = PackedVector2Array([Vector2(-500, -220), Vector2(500, -220), Vector2(500, -210), Vector2(-500, -210)])
	ceiling.add_child(ceiling_shape)
	_game.add_child(ceiling)
	await _reset_player()
	await _leave_edge()
	_key(KEY_SPACE, true)
	var hit_ceiling := false
	var stayed_below := true
	for frame in 15:
		await _step()
		hit_ceiling = hit_ceiling or _player.is_on_ceiling()
		stayed_below = stayed_below and _player.position.y - ORIGIN.y - 67.466667 >= -210.2
	_check(hit_ceiling and stayed_below, "grace jump respects existing ceiling collision")
	ceiling.queue_free()
	await _step()

	for tick_rate in [30, 120]:
		Engine.physics_ticks_per_second = tick_rate
		await _reset_player()
		await _leave_edge()
		await _step(ceili(0.04 * tick_rate))
		_key(KEY_SPACE, true)
		await _step()
		_check(_player.velocity.y < -600.0, "short grace works at %d physics ticks/s" % tick_rate)
		await _reset_player()
		await _leave_edge()
		await _step(ceili(0.13 * tick_rate))
		await _assert_no_jump("grace expires in seconds at %d physics ticks/s" % tick_rate)
	Engine.physics_ticks_per_second = 60
	var original: Node = load(CLOUD).instantiate()
	_check(_shape.polygon == original.get_node("CollisionBox").polygon, "rounded object polygon is unchanged")
	original.free()
	var original_player: Node = load("res://Component/Player/Player.tscn").instantiate()
	_check(_player.body_collision_box.polygon == original_player.get_node("CollisionBox_Body").polygon,
		"player collision polygon is unchanged")
	original_player.free()
	print("JUMP_GRACE_TEST checks=", _checks, " failures=", _failures)
	get_tree().quit(0 if _failures == 0 else 1)
