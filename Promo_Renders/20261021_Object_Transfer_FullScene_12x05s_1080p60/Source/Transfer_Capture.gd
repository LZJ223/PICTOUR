## 完整游戏视角：保留人物、所有图层和游戏系统，仅关闭 UI、音乐及存档触发器。
extends "res://Promo_Renders/20261021_Level_Walk_10x2s_1080p60/Source/Walk_Capture.gd"

const CLIP_FRAMES: int = 30
const ACTION_FRAME: int = 6
const DESIGN_VIEW := Vector2(1280.0, 720.0)
const DIRECTIONS: Array[int] = [1, -1, 1, 1, 1, -1, -1, -1, 1, -1, 1, -1]

var _object: LayerObject
var _triggered: bool = false
var _peak_scale: float = 1.0
var _min_scale: float = 1.0
var _layers_before: Array[DepthLayer] = []

func _ready() -> void:
	_probe = "--probe" in OS.get_cmdline_user_args()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)
	SceneTransition.begin_opening()
	_run.call_deferred()

func _walk_plans() -> Array:
	var first: Array = JSON.parse_string(FileAccess.get_file_as_string("res://Promo_Renders/20261021_Level_Walk_10x2s_1080p60/Shot_Plan.json"))
	var last: Array = JSON.parse_string(FileAccess.get_file_as_string("res://Promo_Renders/20261021_Level_Walk_11_12_2x2s_1080p60/Shot_Plan.json"))
	first.append_array(last)
	return first

func _pose_player(position: Vector2) -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Global.camera_fixed = true
	Global.camera.zoom = Vector2.ONE
	Global.player.position = position
	Global.player.velocity = Vector2.ZERO
	Global.player.player_animation.set_facing(1, true)
	Global.player.player_animation.set_motion(0.0, true)
	SignalSystem.timer_reset()
	for index in 20:
		await get_tree().physics_frame
		await get_tree().process_frame
	_game.get_node("LayerControllerSystem")._update_view()

func _probe_levels() -> void:
	var plans: Array[Dictionary] = []
	var walks := _walk_plans()
	for level_id in range(1, 13):
		await _spawn(level_id)
		var walk: Dictionary = walks[level_id - 1]
		var standpoints: Array[Vector2] = [Vector2(walk.start_x, walk.floor_y - 1.0)]
		for candidate in _candidates():
			if standpoints.size() >= 24:
				break
			if _route_clear(candidate):
				var point := Vector2(candidate.start_x, candidate.floor_y - 1.0)
				if not point in standpoints:
					standpoints.append(point)
		var plan: Dictionary = {}
		for standpoint in standpoints:
			await _pose_player(standpoint)
			if not Global.player.is_on_floor():
				continue
			var candidates := _visible_candidates()
			for direction in [DIRECTIONS[level_id - 1], -DIRECTIONS[level_id - 1]]:
				for candidate in candidates:
					if not _can_transfer(candidate, direction):
						continue
					_object = candidate
					plan = {"level": level_id, "shot": level_id,
						"player_spawn": [standpoint.x, standpoint.y],
						"object_path": str(_game.get_path_to(candidate)), "object_scene": candidate.scene_file_path,
						"type": _sound_type(candidate), "direction": direction,
						"motion": "outward" if direction > 0 else "inward",
						"source_slot": candidate.owner_layer.slot, "target_slot": candidate.owner_layer.slot - direction,
						"layer_count": Global.layers.size(), "night": Global.level.is_night}
					_shot = plan.duplicate(true)
					_perform_transfer()
					var peak: float = 1.0
					var minimum: float = 1.0
					for index in CLIP_FRAMES:
						await get_tree().physics_frame
						await get_tree().process_frame
						peak = maxf(peak, candidate._transfer_visual_scale)
						minimum = minf(minimum, candidate._transfer_visual_scale)
					assert(candidate.owner_layer.slot == plan.target_slot)
					assert(is_equal_approx(candidate._transfer_visual_scale, 1.0))
					assert(peak > 1.02 if direction > 0 else minimum < 0.98)
					plan.merge({"verified_peak_scale": peak, "verified_min_scale": minimum, "audio": _shot.audio})
					break
				if not plan.is_empty():
					break
			if not plan.is_empty():
				break
		assert(not plan.is_empty(), "No visible transfer with a grounded player in level %d" % level_id)
		plans.append(plan)
		print("FULL_TRANSFER_PLAN ", JSON.stringify(plan))
		await _clear_game()
	_write_json("Shot_Plan.json", plans)
	print("FULL_TRANSFER_PLAN_COMPLETE shots=", plans.size())

func _sound_type(object: LayerObject) -> String:
	for type in ["CloudBox", "Tree", "Bush", "Cloud", "Box"]:
		if object.scene_file_path.contains(type):
			return type
	return ""

func _object_bounds(object: LayerObject) -> Rect2:
	var bounds := Rect2()
	var first: bool = true
	for entry in object._selection_outlines:
		var source: Node2D = entry.source
		if not source.is_visible_in_tree():
			continue
		var local_bounds := Rect2()
		if source is Sprite2D:
			local_bounds = source.get_rect()
		elif source is Polygon2D:
			local_bounds = object._polygon_bounds(source.polygon)
		var world_bounds := source.global_transform * local_bounds
		bounds = world_bounds if first else bounds.merge(world_bounds)
		first = false
	return bounds

func _visible_candidates() -> Array[LayerObject]:
	var result: Array[LayerObject] = []
	var center := Global.camera.global_position + Vector2(0.0, -180.0)
	var view := Rect2(center - DESIGN_VIEW * 0.5, DESIGN_VIEW)
	for node in get_tree().get_nodes_in_group(&"layer_objects"):
		var object := node as LayerObject
		if object == null or not _game.is_ancestor_of(object) or not object.can_transfer or object.collision_box == null:
			continue
		if _sound_type(object).is_empty() or object.global_position.distance_to(Global.player.global_position) > Global.max_selection_distance * 0.9:
			continue
		var bounds := _object_bounds(object)
		if not bounds.has_area() or bounds.size.x < 45.0 or bounds.size.y < 35.0:
			continue
		if bounds.intersection(view.grow(-20.0)).get_area() < bounds.get_area() * 0.85:
			continue
		result.append(object)
	result.sort_custom(func(a: LayerObject, b: LayerObject) -> bool: return _candidate_score(a) < _candidate_score(b))
	return result

func _candidate_score(object: LayerObject) -> float:
	var bounds := _object_bounds(object)
	var covered: float = 0.0
	for other in get_tree().get_nodes_in_group(&"layer_objects"):
		if other == object or not _game.is_ancestor_of(other) or other.front or other.owner_layer.slot >= object.owner_layer.slot:
			continue
		var overlap := bounds.intersection(_object_bounds(other))
		if overlap.has_area():
			covered += overlap.get_area() / bounds.get_area()
	var focal_point := Global.player.global_position + Vector2(220.0, -140.0)
	return covered * 4000.0 + bounds.get_center().distance_to(focal_point) - minf(bounds.get_area() * 0.0005, 80.0)

func _can_transfer(object: LayerObject, direction: int) -> bool:
	var source_slot := object.owner_layer.slot
	var target_slot := source_slot - direction
	if target_slot < 0 or target_slot >= Global.layer_count or object.collision_box.disabled:
		return false
	var ratio: float = Global.layer_scales[source_slot] / Global.layer_scales[target_slot]
	var transform := object.global_transform
	transform.origin = Global.camera.global_position + (object.global_position - Global.camera.global_position) * ratio
	var collision := object.collision_box.transform
	collision.x *= ratio
	collision.y *= ratio
	var controller: LayerControllerSystem = _game.get_node("LayerControllerSystem")
	return not controller._has_collision(object, object.collision_box, Global.get_layer_at_slot(target_slot), transform * collision)

func _perform_transfer() -> void:
	var cursor := SoundPlayer._cursor
	var controller: LayerControllerSystem = _game.get_node("LayerControllerSystem")
	assert(controller.transfer(int(_shot.direction), _object), "Actual transfer was blocked")
	assert(SoundPlayer._cursor != cursor)
	var sound: AudioStreamPlayer = SoundPlayer._players[posmod(SoundPlayer._cursor - 1, SoundPlayer.POOL_SIZE)]
	assert(sound.stream != null and sound.stream.resource_path.begins_with("res://Audio/SFX/"))
	_shot["audio"] = {"source": sound.stream.resource_path, "start_frame": ACTION_FRAME, "volume_db": sound.volume_db}
	_triggered = true

func _process(_delta: float) -> void:
	if _recording and _frame == ACTION_FRAME and not _triggered:
		_perform_transfer()

func _render_shots() -> void:
	var plans: Array = JSON.parse_string(FileAccess.get_file_as_string(output_directory.path_join("Shot_Plan.json")))
	assert(plans.size() == 12)
	RenderingServer.frame_post_draw.connect(_capture_frame)
	for plan: Dictionary in plans:
		_shot = plan.duplicate(true)
		await _spawn(int(plan.level))
		await _pose_player(Vector2(plan.player_spawn[0], plan.player_spawn[1]))
		_object = _game.get_node(plan.object_path) as LayerObject
		assert(_object != null and _can_transfer(_object, int(plan.direction)))
		Global.object_selected = _object
		_object.set_pick_condition(true)
		_layers_before.assign(Global.layers)
		for index in 3:
			await get_tree().process_frame
		_frame = 0
		_peak_scale = 1.0
		_min_scale = 1.0
		_triggered = false
		_shot_finished = false
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_directory.path_join("Shot_%02d" % int(plan.shot))))
		_recording = true
		while not _shot_finished:
			await get_tree().process_frame
		await _clear_game()
	_write_json("Capture.json", _manifest)
	print("FULL_TRANSFER_CAPTURE_COMPLETE shots=", _manifest.size())

func _capture_frame() -> void:
	if not _recording:
		return
	assert(not _game.get_node("Camera/MenuUI").visible)
	assert(Global.player.is_visible_in_tree() and Global.player.is_physics_processing() and Global.player.is_on_floor())
	assert(Global.camera.zoom.is_equal_approx(Vector2.ONE) and Global.camera_fixed)
	assert(Global.layers.size() == _layers_before.size())
	for layer in _layers_before:
		assert(is_instance_valid(layer) and layer.is_visible_in_tree())
	_peak_scale = maxf(_peak_scale, _object._transfer_visual_scale)
	_min_scale = minf(_min_scale, _object._transfer_visual_scale)
	var image := get_viewport().get_texture().get_image()
	assert(image.get_size() == Vector2i(1920, 1080))
	var error := image.save_png(frames_directory.path_join("Shot_%02d/frame%08d.png" % [int(_shot.shot), _frame]))
	assert(error == OK)
	_frame += 1
	if _frame == CLIP_FRAMES:
		_recording = false
		assert(_triggered and _object.owner_layer.slot == int(_shot.target_slot))
		assert(is_equal_approx(_object._transfer_visual_scale, 1.0))
		assert(_peak_scale > 1.02 if int(_shot.direction) > 0 else _min_scale < 0.98)
		_shot.merge({"frames": CLIP_FRAMES, "fps": FPS, "duration_seconds": 0.5,
			"resolution": [1920, 1080], "transfer_frame": ACTION_FRAME,
			"peak_scale": _peak_scale, "min_scale": _min_scale, "transfer_succeeded": true,
			"music": false, "ui": false, "player_visible": true, "all_layers_visible": true,
			"camera_zoom": 1.0, "player_position": [Global.player.position.x, Global.player.position.y]}, true)
		_manifest.append(_shot.duplicate(true))
		print("FULL_TRANSFER_SHOT_COMPLETE ", JSON.stringify(_shot))
		_shot_finished = true
