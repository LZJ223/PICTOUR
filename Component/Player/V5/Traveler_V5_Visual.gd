extends AnimatedSprite2D
## 16张候选图片（动作连续性尚不合格）+ 坡面脚点适配。
## 原AnimatedSprite负责状态接口，子网格渲染原图并只在下腿做有限贴地变形。

const FRAMES_PATH := "res://Art/Player/V5/Traveler_V5_Frames.tres"
const METADATA_PATH := "res://Art/Player/V5/Traveler_V5_Metadata.json"
const TERRAIN_SHADER = preload("res://Component/Player/V5/Terrain_Pose.gdshader")
const GRID_X := 14
const GRID_Y := 30

@export var walk_stride: float = 108.0
@export var run_stride: float = 152.0
@onready var player: PlayerController = get_parent().get_parent() as PlayerController
var visual_facing: int = 1
var collar_offset := Vector2(-4.0, -73.0)
var stride_phase: float = 0.0
var measured_distance: float = 0.0
var floor_angle: float = 0.0
var foot_grounded := [false, false]
var foot_targets := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var gait_blend: float = 0.0
var _clock: float = 0.0
var _previous_position := Vector2.ZERO
var _previous_speed: float = 0.0
var _previous_velocity_x: float = 0.0
var _previous_grounded: bool = false
var _previous_tangent := Vector2.RIGHT
var _transition: StringName = &""
var _transition_left: float = 0.0
var _transition_duration: float = 0.0
var _metadata: Dictionary = {}
var _art_ready: bool = false
var _mesh: Polygon2D
var _terrain_material: ShaderMaterial
var _frame_meta: Dictionary = {}
var _mesh_key := ""
var _mesh_cache: Dictionary = {}
var _shape := Vector4.ZERO
var _previous_shape := Vector4.ZERO
var _foot_positions := PackedVector2Array([Vector2(-12, 0), Vector2(12, 0)])
var _gait_action: StringName = &"walk"
var _pending_gait_time: float = 0.0
var _previous_input: float = 0.0
var _stop_pending: bool = false
var _support_seen: bool = false
var _unsupported_time: float = 0.0
var _airborne_committed: bool = false
var _signed_surface_speed: float = 0.0
var _previous_surface_speed: float = 0.0
var _step_visual_offset: float = 0.0
var _step_impulse: float = 0.0
var motion_events: Dictionary = {"start": 0, "brake": 0, "land": 0}
const CONTACT_GRACE := 0.05


func _ready() -> void:
	process_physics_priority = 1
	_previous_position = player.global_position
	stop()
	# 只隐藏原AnimatedSprite自己的矩形；子Polygon保留原图和颜色。
	self_modulate.a = 0.0
	_mesh = Polygon2D.new()
	_mesh.name = "PaintedBody"
	_mesh.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_mesh)
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = TERRAIN_SHADER
	_mesh.material = _terrain_material
	if not ResourceLoader.exists(FRAMES_PATH) or not FileAccess.file_exists(METADATA_PATH):
		push_warning("TRAVELER_V5: 等待16帧母图与锚点导入。")
		return
	sprite_frames = load(FRAMES_PATH)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(METADATA_PATH))
	if not parsed is Dictionary:
		push_error("TRAVELER_V5: 锚点元数据无效。")
		return
	_metadata = parsed
	walk_stride = float(_metadata.get("walk_stride", walk_stride))
	run_stride = float(_metadata.get("run_stride", run_stride))
	_art_ready = true
	_apply_pose(&"idle", 0.0)
	_update_collar()


func _begin(action: StringName, duration: float) -> void:
	if motion_events.has(str(action)):
		motion_events[str(action)] += 1
	_transition = action
	_transition_left = duration
	_transition_duration = duration


func _physics_process(delta: float) -> void:
	if not _art_ready or not is_instance_valid(player) or player.UAV_activated:
		return
	_clock += delta
	var displacement := player.global_position - _previous_position
	var teleported: bool = displacement.length() > 100.0
	var grounded: bool = player.is_on_floor()
	# 正常游戏使用实际按键；四分屏观察场为每个角色记录本帧真实输入。
	var intent: float = float(player.get_meta("animation_input_axis", Input.get_axis("move_left", "move_right")))
	if teleported:
		_transition_left = 0.0
		_transition = &""
		_shape = Vector4.ZERO
		_previous_shape = _shape
		_unsupported_time = 0.0
		_airborne_committed = not grounded
		_support_seen = grounded
		_previous_input = intent
		_previous_speed = 0.0
		_stop_pending = false
		_step_visual_offset = 0.0
	var landed := false
	if grounded:
		landed = _airborne_committed and _support_seen
		_support_seen = true
		_unsupported_time = 0.0
		_airborne_committed = false
	else:
		_unsupported_time += delta
		# 主动起跳立即进空中；接缝一两帧失地不插播fall/land。
		if not _support_seen or player.velocity.y < -150.0 or _unsupported_time > CONTACT_GRACE:
			_airborne_committed = true
	var supported: bool = grounded or (_support_seen and not _airborne_committed)
	var tangent := _previous_tangent if supported else Vector2.RIGHT
	if grounded:
		var normal := player.get_floor_normal()
		tangent = Vector2(-normal.y, normal.x).normalized()
		if tangent.x < 0.0:
			tangent = -tangent
	floor_angle = tangent.angle() if supported else 0.0
	measured_distance = 0.0
	var signed_distance := 0.0
	if not teleported and supported and absf(displacement.x) > 0.001:
		var travel_tangent := (_previous_tangent + tangent).normalized()
		signed_distance = displacement.dot(travel_tangent)
		measured_distance = absf(signed_distance)
	var speed: float = measured_distance / maxf(delta, 0.001)
	var signed_speed: float = signed_distance / maxf(delta, 0.001)
	_signed_surface_speed = lerpf(_signed_surface_speed, signed_speed, 1.0 - exp(-delta * 18.0))
	var started: bool = absf(intent) > 0.1 and absf(_previous_input) <= 0.1 and _previous_speed < 12.0 and supported
	if started:
		stride_phase = 0.25
		motion_events["start"] += 1
		_stop_pending = false
	elif absf(intent) <= 0.1 and absf(_previous_input) > 0.1:
		_stop_pending = true
	if absf(intent) > 0.1:
		_stop_pending = false
	var new_facing := visual_facing
	if speed > 12.0 and (absf(intent) <= 0.1 or signf(signed_speed) == signf(intent)):
		new_facing = int(signf(signed_speed))
	elif speed < 3.0 and absf(intent) > 0.1:
		new_facing = int(signf(intent))
	if landed:
		_begin(&"land", 0.075)
	elif supported and new_facing != visual_facing:
		_begin(&"brake", 0.045)
	elif supported and _stop_pending and speed < 12.0:
		_begin(&"brake", 0.07)
		_stop_pending = false
	visual_facing = new_facing
	flip_h = visual_facing < 0
	_transition_left = maxf(0.0, _transition_left - delta)
	if _transition_left <= 0.0:
		_transition = &""
	var running: bool = player.is_running or player.dash_active or speed > 240.0
	gait_blend = move_toward(gait_blend, 1.0 if running else 0.0, delta / 0.12)
	var desired_gait: StringName = &"run" if gait_blend > 0.5 else &"walk"
	if desired_gait != _gait_action:
		_pending_gait_time += delta
		var half_phase := fposmod(stride_phase, 0.5)
		if half_phase < 0.08 or absf(half_phase - 0.25) < 0.06 or _pending_gait_time > 0.10:
			_gait_action = desired_gait
			_pending_gait_time = 0.0
	else:
		_pending_gait_time = 0.0
	# 距离推进独立于pose过渡。碰撞返回velocity.x=0不再等同玩家刹车。
	if measured_distance > 0.02:
		stride_phase = fposmod(stride_phase + measured_distance / lerpf(walk_stride, run_stride, gait_blend), 1.0)
	var action: StringName = &"idle"
	var phase: float = fposmod(_clock * 0.5, 1.0)
	if not supported:
		action = &"rise" if player.velocity.y < -55.0 else (&"apex" if player.velocity.y < 100.0 else &"fall")
	elif _transition_left > 0.0 and speed < 70.0:
		action = _transition
		phase = 1.0 - _transition_left / _transition_duration
	elif measured_distance > 0.02:
		action = _gait_action
		phase = stride_phase
	_apply_pose(action, phase)
	_step_visual_offset = move_toward(_step_visual_offset, 0.0, delta * 150.0)
	_step_impulse = 0.0
	if "step_up_height" in player:
		_step_impulse = minf(12.0 - _step_visual_offset, float(player.get("step_up_height")))
		_step_visual_offset += _step_impulse
	if grounded or not supported:
		_update_terrain(delta, grounded, teleported)
	else:
		# 一帧接触丢失期间保持贴地形变，不把脚和重心弹回平面。
		_previous_shape = _shape
		_terrain_material.set_shader_parameter("previous_shape", _shape)
		_terrain_material.set_shader_parameter("current_shape", _shape)
	_update_collar()
	_previous_grounded = grounded
	_previous_speed = speed
	_previous_velocity_x = player.velocity.x
	_previous_surface_speed = _signed_surface_speed
	_previous_input = intent
	_previous_position = player.global_position
	_previous_tangent = tangent


func _apply_pose(action: StringName, phase: float) -> void:
	if not sprite_frames.has_animation(action):
		action = &"idle"
	animation = action
	var count := sprite_frames.get_frame_count(action)
	var frame_position: float = clampf(phase, 0.0, 0.99999) * count
	set_frame_and_progress(mini(int(frame_position), count - 1), fposmod(frame_position, 1.0))
	var animation_meta: Array = _metadata.get("animations", {}).get(str(action), [])
	if frame >= animation_meta.size():
		return
	_frame_meta = animation_meta[frame]
	var key := "%s/%d" % [action, frame]
	if key != _mesh_key:
		_install_mesh(key)
	var feet: Array = _frame_meta.get("feet", [[-12, 0], [12, 0]])
	var a := Vector2(float(feet[0][0]) * visual_facing, float(feet[0][1]))
	var b := Vector2(float(feet[1][0]) * visual_facing, float(feet[1][1]))
	_foot_positions = PackedVector2Array([a, b]) if a.x < b.x else PackedVector2Array([b, a])
	_terrain_material.set_shader_parameter("facing", float(visual_facing))
	_terrain_material.set_shader_parameter("foot_x", Vector2(_foot_positions[0].x, _foot_positions[1].x))


func _install_mesh(key: String) -> void:
	if not _mesh_cache.has(key):
		var texture_atlas := sprite_frames.get_frame_texture(animation, frame) as AtlasTexture
		var info := _frame_meta
		var sheet: Dictionary = _metadata.source_sheets[info.sheet]
		var cell_size := Vector2(sheet.cell_size[0], sheet.cell_size[1])
		var source_index: int = int(info.source_frame)
		var cell_origin := Vector2(source_index % int(sheet.grid[0]), source_index / int(sheet.grid[0])) * cell_size
		var root := Vector2(info.source_root[0], info.source_root[1])
		var art_scale: float = float(info.scale)
		var rect := texture_atlas.region
		var vertices := PackedVector2Array()
		var uv := PackedVector2Array()
		var faces: Array[PackedInt32Array] = []
		for y in GRID_Y + 1:
			for x in GRID_X + 1:
				var point := rect.position + rect.size * Vector2(float(x) / GRID_X, float(y) / GRID_Y)
				uv.append(point)
				vertices.append((point - cell_origin - root) * art_scale)
		for y in GRID_Y:
			for x in GRID_X:
				var index: int = y * (GRID_X + 1) + x
				faces.append(PackedInt32Array([index, index + 1, index + GRID_X + 2, index + GRID_X + 1]))
		_mesh_cache[key] = {"vertices": vertices, "uv": uv, "faces": faces, "texture": texture_atlas.atlas}
	var cached: Dictionary = _mesh_cache[key]
	_mesh.polygon = cached.vertices
	_mesh.uv = cached.uv
	_mesh.polygons = cached.faces
	_mesh.texture = cached.texture
	_mesh_key = key


func _ground_at(local_x: float) -> Dictionary:
	var ray := PhysicsRayQueryParameters2D.create(player.global_position + Vector2(local_x, -24), player.global_position + Vector2(local_x, 32), player.collision_mask, [player.get_rid()])
	ray.collide_with_areas = false
	var hit := player.get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and Vector2(hit.normal).dot(Vector2.UP) < 0.68:
		return {}
	return hit


func _update_terrain(delta: float, grounded: bool, teleported: bool) -> void:
	_previous_shape = _shape
	var target := Vector4.ZERO
	foot_grounded = [false, false]
	var center_hit: Dictionary = _ground_at(0.0) if grounded else {}
	if not center_hit.is_empty():
		# 矩形碰撞在坡上由较高角支撑，视觉重心落到中心地面。
		target.z = clampf(float(center_hit.position.y) - player.global_position.y, -8.0, 12.0) + _step_visual_offset
	for i in 2:
		var source_foot: Vector2 = _foot_positions[i]
		foot_targets[i] = player.global_position + source_foot
		if not grounded:
			continue
		var hit := _ground_at(source_foot.x)
		if hit.is_empty():
			continue
		var ground_y: float = float(hit.position.y) - player.global_position.y
		var correction := clampf(ground_y - target.z, -16.0, 16.0)
		# 腾空/摆动腿保留原姿态离地量；射线不会把它强拉到地面。
		if i == 0:
			target.x = correction
		else:
			target.y = correction
		foot_grounded[i] = source_foot.y > -2.5
		foot_targets[i] = Vector2(player.global_position.x + source_foot.x, player.global_position.y + ground_y + minf(source_foot.y, 0.0))
	var acceleration_x: float = (_signed_surface_speed - _previous_surface_speed) / maxf(delta, 0.001)
	target.w = clampf(-floor_angle * 0.11 + acceleration_x / 95000.0, -0.052, 0.052) if grounded else 0.0
	var response := 1.0 - exp(-delta * 28.0)
	_shape = _shape.lerp(target, response)
	_shape.z += _step_impulse * (1.0 - response)
	if grounded:
		# 图片换帧时脚的横向位置已经变化；沿用上一张的脚高会短暂穿坡。
		# 新脚点立即匹配当前坡面，重心和上身倾身仍平滑处理。
		_shape.x = target.x + target.z - _shape.z
		_shape.y = target.y + target.z - _shape.z
		_previous_shape.x = _shape.x
		_previous_shape.y = _shape.y
	if teleported:
		_shape = target
		_previous_shape = target
	_terrain_material.set_shader_parameter("previous_shape", _previous_shape)
	_terrain_material.set_shader_parameter("current_shape", _shape)


func _update_collar() -> void:
	var collar: Array = _frame_meta.get("collar", [-4.0, -73.0])
	var base := Vector2(float(collar[0]) * visual_facing, float(collar[1]))
	collar_offset = deform_point(base)


func deform_point(point: Vector2) -> Vector2:
	var gap: float = maxf(_foot_positions[1].x - _foot_positions[0].x, 1.0)
	var side := clampf((point.x - _foot_positions[0].x) / gap, 0.0, 1.0)
	var lower_leg: float = smoothstep(-37.0, -2.0, point.y)
	return Vector2(point.x + _shape.w * maxf(-point.y - 36.0, 0.0), point.y + lerpf(_shape.x, _shape.y, side) * lower_leg + _shape.z)


func get_visual_feet() -> PackedVector2Array:
	return PackedVector2Array([player.global_position + deform_point(_foot_positions[0]), player.global_position + deform_point(_foot_positions[1])])


func _process(_delta: float) -> void:
	if _terrain_material != null:
		# 只插值着色器中的下腿变形，不写入任何物理节点变换。
		_terrain_material.set_shader_parameter("interpolation", Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0)


func get_metadata() -> Dictionary:
	return _metadata.duplicate(true)
