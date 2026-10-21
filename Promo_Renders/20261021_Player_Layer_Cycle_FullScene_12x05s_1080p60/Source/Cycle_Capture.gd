## 人物换层宣传素材：调用真实 cycle()，保留完整场景、碰撞判定与轮换动画。
extends "res://Promo_Renders/20261021_Object_Transfer_FullScene_12x05s_1080p60/Source/Transfer_Capture.gd"

var _slots_before: Dictionary = {}
var _cycle_seen: bool = false
var _wrap_seen: bool = false
var _intermediate_depth_seen: bool = false
var _grounded_frames: int = 0
var _player_y_min: float = INF
var _player_y_max: float = -INF

func _probe_levels() -> void:
	var plans: Array[Dictionary] = []
	var walks := _walk_plans()
	for level_id in range(1, 13):
		await _spawn(level_id)
		var walk: Dictionary = walks[level_id - 1]
		var standpoints: Array[Vector2] = [Vector2(walk.start_x, walk.floor_y - 1.0)]
		for candidate in _candidates():
			if standpoints.size() >= 48:
				break
			if _route_clear(candidate):
				var point := Vector2(candidate.start_x, candidate.floor_y - 1.0)
				if not point in standpoints:
					standpoints.append(point)
		var plan: Dictionary = {}
		for require_floor in [true, false]:
			for standpoint in standpoints:
				await _pose_player(standpoint)
				if not Global.player.is_on_floor():
					continue
				var preferred: int = 1 if level_id % 2 == 1 else -1
				for direction in [preferred, -preferred]:
					if not _cycle_possible(direction, require_floor):
						continue
					var target := Global.get_layer_at_slot(posmod(Global.current_layer_index - direction, Global.layer_count))
					plan = {"level": level_id, "shot": level_id, "type": "Player",
						"player_spawn": [standpoint.x, standpoint.y], "direction": direction,
						"motion": "forward" if direction > 0 else "backward",
						"source_layer_id": Global.get_layer_at_slot(Global.current_layer_index).layer_id,
						"target_layer_id": target.layer_id, "layer_count": Global.layers.size(),
						"target_floor_supported": require_floor, "night": Global.level.is_night}
					_shot = plan.duplicate(true)
					_perform_cycle()
					var cycled: bool = false
					for index in CLIP_FRAMES:
						await get_tree().physics_frame
						await get_tree().process_frame
						cycled = cycled or (_game.get_node("LayerControllerSystem") as LayerControllerSystem).is_cycling()
					assert(cycled and not (_game.get_node("LayerControllerSystem") as LayerControllerSystem).is_cycling())
					assert(Global.get_layer_at_slot(Global.current_layer_index).layer_id == target.layer_id)
					plan["audio"] = _shot.audio
					break
				if not plan.is_empty():
					break
			if not plan.is_empty():
				break
		assert(not plan.is_empty(), "No valid player layer cycle in level %d" % level_id)
		plans.append(plan)
		print("PLAYER_CYCLE_PLAN ", JSON.stringify(plan))
		await _clear_game()
	_write_json("Shot_Plan.json", plans)
	print("PLAYER_CYCLE_PLAN_COMPLETE shots=", plans.size())

func _cycle_possible(direction: int, require_floor: bool) -> bool:
	var target := Global.get_layer_at_slot(posmod(Global.current_layer_index - direction, Global.layer_count))
	var box := Global.player.body_collision_box
	var controller: LayerControllerSystem = _game.get_node("LayerControllerSystem")
	if controller._has_collision(Global.player, box, target, box.global_transform):
		return false
	if not require_floor:
		return true
	var space := Global.player.get_world_2d().direct_space_state
	var excluded: Array[RID] = [Global.player.get_rid()]
	for offset in [-20.0, 0.0, 20.0]:
		var foot := Global.player.global_position + Vector2(offset, 0.0)
		var ray := PhysicsRayQueryParameters2D.create(foot + Vector2.UP * 3.0,
			foot + Vector2.DOWN * 3.0, 1 << target.layer_id, excluded)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or absf(hit.position.y - foot.y) > 1.5 or hit.normal.y > -0.95:
			return false
	return true

func _perform_cycle() -> void:
	var cursor := SoundPlayer._cursor
	var controller: LayerControllerSystem = _game.get_node("LayerControllerSystem")
	assert(controller.cycle(int(_shot.direction), true), "Actual player cycle was blocked")
	assert(SoundPlayer._cursor != cursor)
	var sound: AudioStreamPlayer = SoundPlayer._players[posmod(SoundPlayer._cursor - 1, SoundPlayer.POOL_SIZE)]
	assert(sound.stream != null and sound.stream.resource_path == SoundPlayer.CUES["layer_cycle"])
	_shot["audio"] = {"source": sound.stream.resource_path, "start_frame": ACTION_FRAME, "volume_db": sound.volume_db}
	_triggered = true

func _process(_delta: float) -> void:
	if _recording and _frame == ACTION_FRAME and not _triggered:
		_perform_cycle()

func _render_shots() -> void:
	var plans: Array = JSON.parse_string(FileAccess.get_file_as_string(output_directory.path_join("Shot_Plan.json")))
	assert(plans.size() == 12)
	RenderingServer.frame_post_draw.connect(_capture_frame)
	for plan: Dictionary in plans:
		_shot = plan.duplicate(true)
		await _spawn(int(plan.level))
		await _pose_player(Vector2(plan.player_spawn[0], plan.player_spawn[1]))
		assert(_cycle_possible(int(plan.direction), bool(plan.target_floor_supported)))
		_layers_before.assign(Global.layers)
		_slots_before.clear()
		for layer in Global.layers:
			_slots_before[layer.layer_id] = layer.slot
		for index in 3:
			await get_tree().process_frame
		_frame = 0
		_triggered = false
		_cycle_seen = false
		_wrap_seen = false
		_intermediate_depth_seen = false
		_grounded_frames = 0
		_player_y_min = INF
		_player_y_max = -INF
		_shot_finished = false
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_directory.path_join("Shot_%02d" % int(plan.shot))))
		_recording = true
		while not _shot_finished:
			await get_tree().process_frame
		await _clear_game()
	_write_json("Capture.json", _manifest)
	print("PLAYER_CYCLE_CAPTURE_COMPLETE shots=", _manifest.size())

func _capture_frame() -> void:
	if not _recording:
		return
	assert(not _game.get_node("Camera/MenuUI").visible)
	assert(Global.player.is_visible_in_tree() and Global.player.is_physics_processing())
	assert(Global.camera.zoom.is_equal_approx(Vector2.ONE) and Global.camera_fixed)
	assert(Global.layers.size() == _layers_before.size())
	var controller: LayerControllerSystem = _game.get_node("LayerControllerSystem")
	_cycle_seen = _cycle_seen or controller.is_cycling()
	for layer in _layers_before:
		assert(is_instance_valid(layer) and layer.is_visible_in_tree())
		_wrap_seen = _wrap_seen or layer.cycle_opacity < 0.95
		_intermediate_depth_seen = _intermediate_depth_seen or posmod(layer.z_index, 100) != 0
	_grounded_frames += int(Global.player.is_on_floor())
	_player_y_min = minf(_player_y_min, Global.player.position.y)
	_player_y_max = maxf(_player_y_max, Global.player.position.y)
	var image := get_viewport().get_texture().get_image()
	assert(image.get_size() == Vector2i(1920, 1080))
	var error := image.save_png(frames_directory.path_join("Shot_%02d/frame%08d.png" % [int(_shot.shot), _frame]))
	assert(error == OK)
	_frame += 1
	if _frame == CLIP_FRAMES:
		_recording = false
		assert(_triggered and _cycle_seen and _wrap_seen and _intermediate_depth_seen and not controller.is_cycling())
		assert(Global.get_layer_at_slot(Global.current_layer_index).layer_id == int(_shot.target_layer_id))
		assert(Global.player.get_collision_mask_value(int(_shot.target_layer_id) + 1))
		for layer in Global.layers:
			assert(layer.slot == posmod(int(_slots_before[layer.layer_id]) + int(_shot.direction), Global.layer_count))
			assert(is_equal_approx(layer.cycle_opacity, 1.0))
		if bool(_shot.target_floor_supported):
			assert(_grounded_frames == CLIP_FRAMES and _player_y_max - _player_y_min < 1.5)
		_shot.merge({"frames": CLIP_FRAMES, "fps": FPS, "duration_seconds": 0.5,
			"resolution": [1920, 1080], "cycle_frame": ACTION_FRAME, "cycle_succeeded": true,
			"cycle_animation_seen": _cycle_seen, "wrap_fade_seen": _wrap_seen,
			"intermediate_depth_seen": _intermediate_depth_seen, "grounded_frames": _grounded_frames,
			"player_y_range": _player_y_max - _player_y_min, "music": false, "ui": false,
			"player_visible": true, "all_layers_visible": true, "camera_zoom": 1.0}, true)
		_manifest.append(_shot.duplicate(true))
		print("PLAYER_CYCLE_SHOT_COMPLETE ", JSON.stringify(_shot))
		_shot_finished = true
