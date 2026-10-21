## --probe 先验证实际物理路线；正常运行以 60fps 导出十段原生 1080p 无 UI 行走。
extends Node

const GAME := preload("res://Interface/Game.tscn")
const WALK_GAME := preload("res://Promo_Renders/20261021_Level_Walk_10x2s_1080p60/Source/Walk_Game.gd")
const OUTPUT := "res://Promo_Renders/20261021_Level_Walk_10x2s_1080p60/"
const FRAMES := "res://.godot/promo_walk_20261021/"
const FPS: int = 60
const SHOT_FRAMES: int = 120
const WARMUP: int = 15
const SPEED: float = 260.0
const TRAVEL: float = SPEED * (SHOT_FRAMES + WARMUP) / FPS

@export var level_ids: Array[int] = []
@export var first_shot_number: int = 1
@export_dir var output_directory: String = OUTPUT
@export_dir var frames_directory: String = FRAMES

var _game: Node2D
var _recording: bool = false
var _frame: int = 0
var _shot: Dictionary
var _shot_finished: bool = false
var _manifest: Array[Dictionary] = []
var _positions: Array[Vector2] = []
var _all_grounded: bool = true
var _minimum_speed: float = INF
var _probe: bool = false

func _ready() -> void:
	_probe = "--probe" in OS.get_cmdline_user_args()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	for index in AudioServer.bus_count:
		AudioServer.set_bus_mute(index, true)
	SceneTransition.begin_opening()
	_run.call_deferred()

func _input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()

func _run() -> void:
	if _probe:
		await _probe_levels()
	else:
		await _render_shots()
	get_tree().quit()

func _spawn(level_id: int) -> void:
	seed(20261021 + level_id)
	Global.next_level_id = level_id
	_game = GAME.instantiate() as Node2D
	_game.set_script(WALK_GAME)
	_game.play_dialogue = false
	add_child(_game)
	# 保持转场处于输入锁定状态，但不暂停真实物理或角色动画。
	SceneTransition._black.hide()
	get_tree().paused = false
	PhysicsServer2D.set_active(true)
	await get_tree().physics_frame
	await get_tree().process_frame

func _clear_game() -> void:
	Input.action_release("move_right")
	Input.action_release("move_left")
	get_tree().paused = true
	PhysicsServer2D.set_active(false)
	if is_instance_valid(_game):
		_game.free()
	_game = null
	await get_tree().process_frame

func _probe_levels() -> void:
	var plans: Array[Dictionary] = []
	var requested_levels: Array = range(1, 13) if level_ids.is_empty() else level_ids
	var shot_count: int = 10 if level_ids.is_empty() else level_ids.size()
	for level_id: int in requested_levels:
		await _spawn(level_id)
		var candidates := _candidates()
		var valid: Dictionary = {}
		for candidate in candidates:
			if not _route_clear(candidate):
				continue
			valid = candidate
			break
		if not valid.is_empty():
			_start_walk(valid)
			var min_y: float = INF
			var max_y: float = -INF
			var grounded: bool = true
			var min_speed: float = INF
			for index in WARMUP + SHOT_FRAMES:
				await get_tree().physics_frame
				await get_tree().process_frame
				if index >= WARMUP:
					min_y = minf(min_y, Global.player.position.y)
					max_y = maxf(max_y, Global.player.position.y)
					grounded = grounded and Global.player.is_on_floor()
					min_speed = minf(min_speed, absf(Global.player.velocity.x))
			valid["grounded"] = grounded
			valid["floor_y_range"] = max_y - min_y
			valid["minimum_speed"] = min_speed
			if grounded and max_y - min_y < 0.5 and min_speed > 250.0:
				plans.append(valid)
		print("WALK_PROBE level=", level_id, " candidates=", candidates.size(), " result=", JSON.stringify(valid))
		await _clear_game()
	# 十段素材不要求十个不同关卡；不足时使用已验证路段的反向镜头，绝不改平地形。
	if level_ids.is_empty() and plans.size() < shot_count and not plans.is_empty():
		var reverse: Dictionary = plans.front().duplicate()
		reverse["start_x"] += TRAVEL
		reverse["direction"] = -1
		plans.append(reverse)
	assert(plans.size() >= shot_count, "Not enough verified flat routes")
	plans.resize(shot_count)
	_write_json("Shot_Plan.json", plans)
	print("WALK_PLAN_COMPLETE ", JSON.stringify(plans))

func _candidates() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var layer := Global.get_layer_at_slot(Global.current_layer_index)
	for object in layer.get_children():
		if not object is LayerObject or object.collision_box == null or object.collision_box.disabled:
			continue
		var box: CollisionPolygon2D = object.collision_box
		var polygon := box.polygon
		for index in polygon.size():
			var start := box.to_global(polygon[index])
			var end := box.to_global(polygon[(index + 1) % polygon.size()])
			if absf(start.y - end.y) > 0.05 or absf(start.x - end.x) < TRAVEL + 140.0:
				continue
			var left: float = minf(start.x, end.x) + 70.0
			var right: float = maxf(start.x, end.x) - TRAVEL - 70.0
			for fraction in [0.5, 0.25, 0.75, 0.0, 1.0]:
				results.append({"level": Global.level.level_id, "start_x": lerpf(left, right, fraction),
					"floor_y": start.y, "surface": String(object.get_path()), "night": Global.level.is_night, "direction": 1})
			for x_index in ceili((right - left) / 64.0):
				results.append({"level": Global.level.level_id, "start_x": left + x_index * 64.0,
					"floor_y": start.y, "surface": String(object.get_path()), "night": Global.level.is_night, "direction": 1})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(a.start_x) < absf(b.start_x)
	)
	return results

func _route_clear(candidate: Dictionary) -> bool:
	var space := Global.player.get_world_2d().direct_space_state
	var excluded: Array[RID] = [Global.player.get_rid()]
	var mask: int = Global.player.collision_mask
	var shape := RectangleShape2D.new()
	shape.size = Vector2(70.0, 112.0)
	for index in range(0, ceili(TRAVEL / 20.0) + 1):
		var x: float = candidate.start_x + minf(index * 20.0, TRAVEL)
		var ray := PhysicsRayQueryParameters2D.create(Vector2(x, candidate.floor_y - 115.0),
			Vector2(x, candidate.floor_y + 8.0), mask, excluded)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or absf(hit.position.y - candidate.floor_y) > 0.1 or hit.normal.y > -0.99:
			return false
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.collision_mask = mask
		query.exclude = excluded
		query.transform = Transform2D(0.0, Vector2(x, candidate.floor_y - 58.0))
		if not space.intersect_shape(query, 1).is_empty():
			return false
	return true

func _start_walk(shot: Dictionary) -> void:
	var player := Global.player
	var direction: int = shot.get("direction", 1)
	player.position = Vector2(shot.start_x, shot.floor_y - 1.0)
	player.velocity = Vector2(SPEED * direction, 0.0)
	player.player_animation.set_facing(direction, true)
	player.player_animation.set_motion(SPEED * direction, true)
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_press("move_left" if direction < 0 else "move_right")
	SignalSystem.timer_reset()
	_game.get_node("LayerControllerSystem")._update_view()

func _render_shots() -> void:
	var plans: Array = JSON.parse_string(FileAccess.get_file_as_string(output_directory.path_join("Shot_Plan.json")))
	RenderingServer.frame_post_draw.connect(_capture_frame)
	for index in plans.size():
		_shot = plans[index].duplicate()
		_shot["shot"] = index + first_shot_number
		await _spawn(_shot.level)
		_start_walk(_shot)
		for warmup in WARMUP:
			await get_tree().physics_frame
			await get_tree().process_frame
		_frame = 0
		_positions.clear()
		_all_grounded = true
		_minimum_speed = INF
		_shot_finished = false
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(frames_directory.path_join("Shot_%02d" % _shot.shot)))
		_recording = true
		while not _shot_finished:
			await get_tree().process_frame
		await _clear_game()
	_write_json("Capture.json", _manifest)
	print("WALK_CAPTURE_COMPLETE ", JSON.stringify(_manifest))

func _capture_frame() -> void:
	if not _recording:
		return
	assert(not _game.get_node("Camera/MenuUI").visible)
	var player := Global.player
	_positions.append(player.global_position)
	_all_grounded = _all_grounded and player.is_on_floor()
	_minimum_speed = minf(_minimum_speed, absf(player.velocity.x))
	var image := get_viewport().get_texture().get_image()
	assert(image.get_size() == Vector2i(1920, 1080))
	var error := image.save_png(frames_directory.path_join("Shot_%02d/frame%08d.png" % [_shot.shot, _frame]))
	assert(error == OK)
	_frame += 1
	if _frame == SHOT_FRAMES:
		_recording = false
		var min_y: float = INF
		var max_y: float = -INF
		for point in _positions:
			min_y = minf(min_y, point.y)
			max_y = maxf(max_y, point.y)
		assert(_all_grounded and max_y - min_y < 0.5 and _minimum_speed > 250.0, "Walking route failed")
		_shot.merge({"frames": _frame, "fps": FPS, "duration_seconds": 2.0,
			"resolution": [1920, 1080], "all_frames_grounded": _all_grounded,
			"floor_y_range": max_y - min_y, "minimum_speed": _minimum_speed,
			"start_position": [_positions.front().x, _positions.front().y],
			"end_position": [_positions.back().x, _positions.back().y]}, true)
		_manifest.append(_shot.duplicate())
		print("WALK_SHOT_COMPLETE ", JSON.stringify(_shot))
		_shot_finished = true

func _write_json(name: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	var file := FileAccess.open(output_directory.path_join(name), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(value, "\t"))
	file.close()
