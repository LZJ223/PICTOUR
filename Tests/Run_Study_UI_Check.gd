extends Node


func _ready() -> void:
	_run.call_deferred()


func _wait(frames: int) -> void:
	for tick in frames:
		await get_tree().physics_frame
		await get_tree().process_frame


func _key(lab: Control, code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	lab._unhandled_input(event)


func _run() -> void:
	var lab := preload("res://Art/Player/RunStudy/Run_Study_Lab.tscn").instantiate()
	add_child(lab)
	await _wait(70)
	var failures := 0
	for index in 4:
		_key(lab, KEY_1 + index)
		var positions := [lab.players[0].position, lab.players[1].position]
		await _wait(4)
		if lab.players[0].position != positions[0] or lab.players[1].position != positions[1]:
			failures += 1
		var visual: Node2D = lab.players[1].get_node("Visual_Body/Traveler")
		if visual.pose != visual.previous_pose:
			failures += 1
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://Exports/Run_Study/Key_4_Paused.png")
	var old_position: Vector2 = lab.players[1].position
	_key(lab, KEY_0)
	await _wait(10)
	if lab.players[1].position.x <= old_position.x or lab.players[1].get_node("Visual_Body/Traveler").preview_phase >= 0:
		failures += 1
	_key(lab, KEY_SPACE)
	var paused_positions := [lab.players[0].position, lab.players[1].position]
	await _wait(4)
	if lab.players[0].position != paused_positions[0] or lab.players[1].position != paused_positions[1]:
		failures += 1
	_key(lab, KEY_SPACE)
	await _wait(4)
	if lab.players[1].position.x <= paused_positions[1].x:
		failures += 1
	print("RUN_STUDY_UI: four pose keys freeze both roots, immediate pose, 0/Space resume; %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
