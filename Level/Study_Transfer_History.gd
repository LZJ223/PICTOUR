class_name StudyTransferHistory
extends Node
## 纵向试验的内存操作历史：一次换层撤回整套摆位、玩家和投影基准。
## 不读取或写入 BookmarkManager、用户存档、墨水和永久奖励。

signal history_changed(count: int)
signal message_changed(message: String)

@export_range(1, 256) var history_limit: int = 64
const MOTION_FIELDS := ["velocity", "gait", "dash_active", "is_running", "facing_direction", "activated", "_sprint_held_time", "_sprint_pressed", "_dash_time", "_dash_cooldown_time", "_dash_direction", "_jump_buffer_time", "_coyote_time", "_air_speed_limit", "_was_on_floor", "step_up_height", "_step_settle_time", "_step_direction", "_last_floor_y"]

var system: SystemController
var last_error: String = ""
var _entries: Array[Dictionary] = []
var _initial: Dictionary = {}
var _objects: Dictionary = {}
var _layers: Dictionary = {}


func configure(target: SystemController) -> void:
	system = target
	for layer in system.layers:
		_layers[layer.layer_id] = layer
		for object in layer.get_children():
			if not object is LayerObject:
				continue
			var key := str(object.get_meta("persistent_id", object.name))
			assert(not key.is_empty() and not _objects.has(key), "Study物件稳定ID不可重复：" + key)
			_objects[key] = object
	_initial = capture_state()
	history_changed.emit(0)


func get_history_count() -> int:
	return _entries.size()


func capture_state() -> Dictionary:
	var objects: Array[Dictionary] = []
	for key in _objects:
		var object := _objects[key] as LayerObject
		if not is_instance_valid(object) or not is_instance_valid(object.owner_layer):
			return {}
		var source_parts: Array[Dictionary] = object.get_transfer_collision_parts(object.owner_layer, system.get_projection_anchor()) if object.has_method("get_transfer_collision_parts") else system._legacy_collision_parts(object, object.owner_layer)
		var parts: Array[Dictionary] = []
		for part in source_parts:
			parts.append({"shape": (part.shape as Shape2D).duplicate(), "transform": part.transform})
		objects.append({"id": key, "instance": object.get_instance_id(), "layer_id": object.owner_layer.layer_id, "pose": object.global_transform, "collision_pose": object.collision_box.transform, "parts": parts})
	var motion: Dictionary = {}
	var available: Dictionary = {}
	for property in system.player.get_property_list():
		available[property.name] = true
	for key in MOTION_FIELDS:
		if available.has(key):
			motion[key] = system.player.get(key)
	return {"objects": objects, "player_pose": system.player.global_transform, "player_collision_pose": system.player.body_collision_box.transform, "player_mask": system.player.collision_mask, "player_shape": system.player.body_collision_box.shape.duplicate(), "player_shape_pose": system.player.body_collision_box.global_transform, "motion": motion, "on_floor": system.player.is_on_floor(), "camera_pose": system.camera.global_transform, "camera_fixed": system.camera_fixed, "anchor": system.get_projection_anchor()}


func record_success(previous: Dictionary) -> void:
	assert(not previous.is_empty(), "不能记录不完整的换层历史。")
	_entries.append(previous)
	while _entries.size() > history_limit:
		_entries.pop_front()
	history_changed.emit(_entries.size())


func undo() -> bool:
	if _entries.is_empty():
		last_error = "还没有可以撤回的换层。"
		message_changed.emit(last_error)
		return false
	if not restore_state(_entries.back()):
		message_changed.emit(last_error)
		return false
	_entries.pop_back()
	history_changed.emit(_entries.size())
	message_changed.emit("已撤回上一次换层，同时回到当时的站位。")
	return true


func reset_initial() -> bool:
	if not restore_state(_initial):
		message_changed.emit(last_error)
		return false
	_entries.clear()
	history_changed.emit(0)
	message_changed.emit("回到本庭院的起始摆位。")
	return true


func restore_state(state: Dictionary) -> bool:
	last_error = _validate(state)
	if not last_error.is_empty():
		return false
	# 先验证全部身份、形状与目标占用，再在一个物理调用里恢复；中途无await。
	Global.clear_selection()
	for saved: Dictionary in state.objects:
		var object := _objects[saved.id] as LayerObject
		var layer := _layers[int(saved.layer_id)] as DepthLayer
		if object.get_parent() != layer:
			object.reparent(layer, false)
		object.owner_layer = layer
		object.global_transform = saved.pose
		object.collision_box.transform = saved.collision_pose
		object.set_collision_group(1, layer.layer_id + 1)
		object.set_pick_condition(false)
		# PaperStage/Vertical多段实体在此同步直属PhysicsBody的额外轮廓，
		# 必须早于刷新人物接触缓存，不能只恢复主CollisionBox的尺度。
		object.apply_visual_transfer(state.anchor)
	var player := system.player
	player.global_transform = state.player_pose
	player.body_collision_box.transform = state.player_collision_pose
	player.reset_motion()
	# 原生接触缓存不能直接赋值；先清除来自撤回前位置的墙/地面缓存。
	# 这次零运动仅刷新接触，真实根位保持快照，不偷走或添加移动距离。
	var saved_snap := player.floor_snap_length
	player.floor_snap_length = 0.0
	player.move_and_slide()
	player.global_transform = state.player_pose
	player.floor_snap_length = saved_snap
	if state.on_floor:
		player.apply_floor_snap()
		player.global_transform = state.player_pose
	for key in state.motion:
		player.set(key, state.motion[key])
	system.camera.global_transform = state.camera_pose
	system.camera_fixed = state.camera_fixed
	system.set("projection_anchor_y", Vector2(state.anchor).y)
	system.reset_restored_view_interpolation()
	# 消除小距离撤回被视觉误记为一步路程；围巾从新位置展开。
	var visual := player.get_node_or_null("Visual_Body/Traveler")
	if visual != null and visual.has_method("reset_after_restore"):
		visual.reset_after_restore()
	elif visual != null and visual.get("_previous_position") != null:
		visual.set("_previous_position", player.global_position)
	var scarf := player.get_node_or_null("Visual_Body/Scarf")
	if scarf != null and scarf.has_method("reset_cloth"):
		scarf.reset_cloth()
	return true


func _validate(state: Dictionary) -> String:
	if state.is_empty() or not state.get("objects") is Array or state.objects.size() != _objects.size():
		return "这条历史缺少完整的庭院摆位，未执行撤回。"
	for key in ["player_pose", "player_collision_pose", "player_shape_pose", "camera_pose"]:
		if not state.get(key) is Transform2D or not _finite_transform(state[key]):
			return "历史位置无效，未执行撤回。"
	if not state.get("anchor") is Vector2 or not Vector2(state.anchor).is_finite() or not state.get("motion") is Dictionary:
		return "历史投影或人物状态无效，未执行撤回。"
	if not state.get("on_floor") is bool or not state.get("camera_fixed") is bool or not state.motion.get("velocity") is Vector2:
		return "历史人物或镜头状态不完整，未执行撤回。"
	if not _same_transform(state.player_shape_pose, state.player_pose * state.player_collision_pose) or not is_equal_approx(Vector2(state.anchor).x, Transform2D(state.player_pose).origin.x):
		return "历史人物位置与投影基准不一致，未执行撤回。"
	for key in state.motion:
		var value: Variant = state.motion[key]
		if key not in MOTION_FIELDS or (value is float and not is_finite(value)) or (value is Vector2 and not value.is_finite()):
			return "历史运动状态无效，未执行撤回。"
	if int(state.get("player_mask", 0)) != system.player.collision_mask or not state.get("player_shape") is Shape2D:
		return "人物图层已变化，未执行不适用的撤回。"
	var current_count := 0
	for layer in system.layers:
		for child in layer.get_children():
			if child is LayerObject:
				current_count += 1
	if current_count != _objects.size():
		return "庭院物件集合已变化，未执行部分撤回。"
	var seen: Dictionary = {}
	var excluded: Array[RID] = [system.player.get_rid()]
	for saved in state.objects:
		if not saved is Dictionary or not _objects.has(saved.get("id")) or seen.has(saved.id):
			return "历史物件身份无效，未执行部分撤回。"
		var object := _objects[saved.id] as LayerObject
		if not is_instance_valid(object) or int(saved.get("instance", 0)) != object.get_instance_id() or not saved.get("layer_id") is int or not is_instance_valid(_layers.get(saved.layer_id)):
			return "历史物件已缺失，未执行部分撤回。"
		if not saved.get("pose") is Transform2D or not saved.get("collision_pose") is Transform2D or not _finite_transform(saved.pose) or not _finite_transform(saved.collision_pose) or not saved.get("parts") is Array:
			return "历史物件形状无效，未执行部分撤回。"
		for part in saved.parts:
			if not part is Dictionary or not part.get("shape") is Shape2D or not part.get("transform") is Transform2D or not _finite_transform(part.transform):
				return "历史碰撞形状无效，未执行部分撤回。"
			if not _same_transform(part.transform, saved.pose * saved.collision_pose):
				return "历史实体与根位置不一致，未执行部分撤回。"
		seen[saved.id] = true
		excluded.append(object.get_rid())
	# 忽略物件当前摆位，查询已保存的整套形状；固定地形仍按真实空间检查。
	var bodies: Array[Dictionary] = []
	for saved: Dictionary in state.objects:
		bodies.append({"id": saved.id, "mask": 1 << int(saved.layer_id), "parts": saved.parts})
	bodies.append({"id": "player", "mask": int(state.player_mask), "parts": [{"shape": state.player_shape, "transform": state.player_shape_pose}]})
	var space := system.player.get_world_2d().direct_space_state
	for index in bodies.size():
		var body: Dictionary = bodies[index]
		for part in body.parts:
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = part.shape
			query.transform = system._contact_tolerant_transform(part.shape, part.transform)
			query.collision_mask = body.mask
			query.exclude = excluded
			if not space.intersect_shape(query, 1).is_empty():
				return "历史落点被新的固定地形占用，未执行撤回。"
			for other_index in range(index + 1, bodies.size()):
				var other: Dictionary = bodies[other_index]
				if body.mask != other.mask:
					continue
				for other_part in other.parts:
					if (part.shape as Shape2D).collide(query.transform, other_part.shape, system._contact_tolerant_transform(other_part.shape, other_part.transform)):
						return "历史摆位包含实体重叠，未执行部分撤回。"
	return ""


func _finite_transform(value: Transform2D) -> bool:
	return value.origin.is_finite() and value.x.is_finite() and value.y.is_finite() and value.determinant() > 0.000001


func _same_transform(a: Transform2D, b: Transform2D) -> bool:
	return a.origin.distance_to(b.origin) < 0.001 and a.x.distance_to(b.x) < 0.001 and a.y.distance_to(b.y) < 0.001
