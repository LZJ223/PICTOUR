## 图层、相机、物件搬运与旧原型无人机的协调器。
class_name SystemController
extends Node

@export var player: PlayerController
@export var camera: Camera2D
@export var level: Level
var layers: Array[DepthLayer] = []
var UAV_activated: bool = false
var camera_fixed: bool = true
const PLAYER_BODY_TYPE = preload("res://Component/Object/Player_Object/Player_Object.tscn")


func _ready() -> void:
	assert(player != null and camera != null and level != null, "System需要Player、Camera与Level！")
	level.write_to_global()
	var used_slots := {}
	var used_ids := {}
	for child in level.get_children():
		if child is DepthLayer:
			assert(child.slot >= 0 and child.slot < Global.layer_count and not used_slots.has(child.slot), "图层槽位须唯一且在范围内！")
			assert(child.layer_id >= 0 and child.layer_id < Global.layer_count and not used_ids.has(child.layer_id), "图层内容ID须唯一且在范围内！")
			used_slots[child.slot] = true
			used_ids[child.layer_id] = true
			layers.append(child)
	assert(layers.size() == Global.layer_count, "图层数量错误！")
	camera.position_smoothing_enabled = false
	## 玩家先完成物理移动，再更新投影，最后由相机提交画布变换。
	process_physics_priority = 1000
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.process_physics_priority = 2000
	camera.enabled = true
	_sync_player_layer()
	reset_view_interpolation()
	Global.layer_cycle.connect(cycle)
	Global.layer_change.connect(transfer)
	Global.UAV_activate.connect(UAV_activate)


func _physics_process(_delta: float) -> void:
	_refresh_camera_and_layers()
	var selected := Global.object_selected
	if not is_instance_valid(selected) or not selected.has_method("set_transfer_preview"):
		return
	var direction := 1 if selected.owner_layer.slot > Global.current_layer_index else -1
	selected.set_transfer_preview(_transfer_rejection(direction, selected).is_empty())


func _refresh_camera_and_layers() -> void:
	if camera_fixed:
		camera.global_position = Vector2(player.global_position.x, level.camera_height if level.lock_camera_y else player.global_position.y)
	for layer in layers:
		layer.apply_slot_state(get_projection_anchor())


## 视觉、真实搬运与预检共用同一锚点。旧场景仍直接使用相机位置。
## 纵向研究场可覆盖此函数，把观察窗口与视差基准解耦。
func get_projection_anchor() -> Vector2:
	return camera.global_position


## 检查点、传送及整体轮换跳变不应从旧画面位置插值过去。
func reset_view_interpolation() -> void:
	_refresh_camera_and_layers()
	player.reset_physics_interpolation()
	camera.reset_physics_interpolation()
	for layer in layers:
		for item in layer.get_children():
			if item is LayerObject or item is LayerDecoration:
				item.reset_physics_interpolation()
	camera.force_update_scroll()


func _sync_player_layer() -> void:
	var current := get_layer_at_slot(Global.current_layer_index)
	assert(current != null)
	player.set_collision_group(current.layer_id + 1)
	player.z_index = (Global.layer_count - Global.current_layer_index) * 100 + 1


func cycle(direction: int) -> void:
	if not level.allow_layer_cycle:
		return
	for layer in layers:
		layer.slot = posmod(layer.slot + direction, Global.layer_count)
	_sync_player_layer()
	reset_view_interpolation()


## 返回值和信号使关卡能够显示失败原因；失败不修改物件。
func transfer(direction: int, object: LayerObject) -> bool:
	var reason := _transfer_rejection(direction, object)
	if not reason.is_empty():
		Global.transfer_result.emit(object if is_instance_valid(object) else null, false, reason)
		return false
	var target := get_layer_at_slot(object.owner_layer.slot - direction)
	var success := object.transfer_to(target, get_projection_anchor())
	Global.transfer_result.emit(object, success, "" if success else "这个物件不能搬运。")
	return success


func _transfer_rejection(direction: int, object: LayerObject) -> String:
	if not level.allow_object_transfer:
		return "这里尚未获得搬运能力。"
	if not is_instance_valid(object) or not object.is_inside_tree() or not object.can_transfer:
		return "这个物件不能搬运。"
	if not is_instance_valid(object.owner_layer) or not layers.has(object.owner_layer):
		return "物件不属于当前关卡。"
	if abs(direction) != 1:
		return "每次只能移动一个图层。"
	var target := get_layer_at_slot(object.owner_layer.slot - direction)
	if target == null:
		return "已经到达最近或最远的图层。"
	## 自然景物可提供真实凹轮廓的凸分块；叶草可以只有点选轮廓。
	if object.has_method("allows_non_solid_transfer") and object.allows_non_solid_transfer():
		return ""
	var parts: Array[Dictionary] = []
	if object.has_method("get_transfer_collision_parts"):
		parts = object.get_transfer_collision_parts(target, get_projection_anchor())
	else:
		parts = _legacy_collision_parts(object, target)
	if parts.is_empty():
		return "物件没有可用的碰撞轮廓。"
	var excluded := _transfer_query_exclusions(object, target)
	for part in parts:
		var shape := part.shape as Shape2D
		var transform: Transform2D = part.transform
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape
		query.transform = _contact_tolerant_transform(shape, transform)
		query.collision_mask = 1 << target.layer_id
		query.exclude = excluded
		query.collide_with_bodies = true
		query.collide_with_areas = false
		if not player.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
			return "目标位置被地形、物件或角色占用；换个站位再试。"
	return ""


## 远离玩家所在景别时，景物可以像绘本叠景一样互相遮盖。
## 预先排除所有获准叠放的景物，查询仍能找到其后任意数量的真实障碍。
## 玩家景别不豁免任何实体；旧物件、地形、角色也从不因叠景而被忽略。
func _transfer_query_exclusions(object: LayerObject, target: DepthLayer) -> Array[RID]:
	var excluded: Array[RID] = [object.get_rid()]
	if not level.allow_scenery_overlap_outside_player_layer or not object is NaturalObject or target.slot == Global.current_layer_index:
		return excluded
	for item in target.get_children():
		if item is NaturalObject:
			excluded.append(item.get_rid())
	return excluded


func _legacy_collision_parts(object: LayerObject, target: DepthLayer) -> Array[Dictionary]:
	var shapes: Array[Shape2D] = []
	if object.collision_box is CollisionShape2D:
		var shape := (object.collision_box as CollisionShape2D).shape
		if shape != null:
			shapes.append(shape)
	elif object.collision_box is CollisionPolygon2D:
		for polygon in Geometry2D.decompose_polygon_in_convex((object.collision_box as CollisionPolygon2D).polygon):
			var shape := ConvexPolygonShape2D.new()
			shape.points = polygon
			shapes.append(shape)
	var transform := object.get_transfer_collision_transform(target, get_projection_anchor())
	var parts: Array[Dictionary] = []
	for shape in shapes:
		parts.append({"shape": shape, "transform": transform})
	return parts


## 向轮廓内部留0.5像素接触容差，容纳物理接触求解产生的微小穿入。
func _contact_tolerant_transform(shape: Shape2D, transform: Transform2D) -> Transform2D:
	var bounds := shape.get_rect()
	var center := transform * bounds.get_center()
	var result := transform
	result.x *= maxf(0.9, 1.0 - 1.0 / maxf(1.0, bounds.size.x * transform.x.length()))
	result.y *= maxf(0.9, 1.0 - 1.0 / maxf(1.0, bounds.size.y * transform.y.length()))
	result.origin = center - result.basis_xform(bounds.get_center())
	return result


func UAV_activate() -> void:
	if not level.allow_uav or not player.UAV_activate(not UAV_activated):
		return
	UAV_activated = not UAV_activated
	Global.uav_active = UAV_activated
	if UAV_activated:
		var current := get_layer_at_slot(Global.current_layer_index)
		player.player_body = PLAYER_BODY_TYPE.instantiate()
		current.add_child(player.player_body)
		player.player_body.global_position = player.global_position
		player.player_body.collision_box.scale = player.scale
		player.player_body.set_collision_group(1, current.layer_id + 1)
		reset_view_interpolation()
	else:
		var body := player.player_body
		if not is_instance_valid(body):
			return
		var body_layer := body.find_owner_layer()
		for step in range(Global.layer_count):
			if body_layer.slot == Global.current_layer_index:
				break
			cycle(1)
		player.global_position = body.global_position
		player.scale = body.collision_box.global_scale
		if Global.object_selected == body:
			Global.clear_selection()
		body.queue_free()
		player.player_body = null
		_sync_player_layer()
		reset_view_interpolation()


func get_layer_at_slot(target_slot: int) -> DepthLayer:
	for layer in layers:
		if layer.slot == target_slot:
			return layer
	return null
