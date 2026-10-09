class_name PrologueTestLevel
extends Level

## 三个相连的实验片段；只记录本次运行，不写磁盘存档。
signal checkpoint_changed(section: int)
signal milestone_reached(milestone: String)

const SPAWN_POINTS := [Vector2(150, 600), Vector2(1460, 600), Vector2(2870, 600)]
const SECTION_TITLES := ["01  行走、冲刺与跑跳", "02  移走树，搬来垫脚箱", "03  视差拼桥、墨水与画室"]
var milestones: Dictionary = {"tree_moved": false, "plate_opened": false, "ink_collected": false, "canvas_painted": false}
var current_section: int = 0
var reset_count: int = 0
var player: PlayerController
var checkpoint_position: Vector2 = Vector2(150, 600)
var _room_checkpoint_active: bool = false
var _initial_states: Array[Dictionary] = []
var _message: String = "绘本实验：先试走、跳和 Shift，再用鼠标选择带朱砂纸签的物件。"
var _message_time: float = 0.0
var _hud_title: Label
var _hud_state: Label
var _hud_message: Label
var _hud_progress: Label
var _hud_performance: Label
var _frame_times: Array[float] = []
var _last_frame_usec: int = 0
var _performance_update_time: float = 0.0
var _diagnostics_visible: bool = false
var _motion_trace: Array[Dictionary] = []
var _previous_render_center: Vector2
var _previous_render_velocity: Vector2
var _has_previous_render: bool = false
var _render_pullbacks: int = 0
var _guides_visible: bool = true
var _guide_controls: Label
var _guide_panel: ColorRect
var _diagnostics_panel: ColorRect

const PAPER_TEXTURE = preload("res://Art/Scenery/Paper_Grain.png")
const GARDEN_TEXTURE = preload("res://Art/Scenery/Garden_Arch_AI.png")
const PLANT_TEXTURE = preload("res://Art/Scenery/Fan_Plant.png")
const INK_TEXTURE = preload("res://Art/Scenery/Ink_Drop.png")
const PLATE_TEXTURE = preload("res://Art/Scenery/Ink_Seal_Plate.png")
const CANVAS_TEXTURE = preload("res://Art/Scenery/Canvas_Frame.png")

func _ready() -> void:
	player = get_parent().get_node("Player") as PlayerController
	for path in ["PlayerLayer/BlockingTree", "BackgroundLayer/StepBox", "BackgroundLayer/BridgePiece"]:
		var item := get_node(path) as LayerObject
		_initial_states.append({"object": item, "parent": item.get_parent(), "position": item.position, "scale": item.get_node("CollisionBox").scale})
	_build_storybook_art()
	_build_hud()
	Global.transfer_result.connect(_on_transfer_result)
	RenderingServer.frame_post_draw.connect(_record_render_motion)
	call_deferred("_initialize_session")

func _initialize_session() -> void:
	spawn_for_section(0)

## F4用于玩家实际试玩环境诊断；墙钟帧间隔能记录编辑器/窗口带来的停顿。
func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_frame_usec > 0:
		_frame_times.append(float(now - _last_frame_usec) / 1000.0)
		if _frame_times.size() > 240:
			_frame_times.pop_front()
	_last_frame_usec = now
	_performance_update_time += delta
	if not _diagnostics_visible or _performance_update_time < 0.25 or _frame_times.is_empty():
		return
	_performance_update_time = 0.0
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var p95: float = sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))]
	var display_info := "屏幕刷新率未知"
	if DisplayServer.get_name() != "headless":
		var window_id := get_window().get_window_id()
		var screen := DisplayServer.window_get_current_screen(window_id)
		var refresh_rate := DisplayServer.screen_get_refresh_rate(screen)
		var vsync_names := ["关闭", "开启", "自适应", "Mailbox"]
		var vsync := clampi(DisplayServer.window_get_vsync_mode(window_id), 0, vsync_names.size() - 1)
		display_info = "窗口屏幕 %d：%s  /  VSync %s" % [screen + 1, "%.1f Hz" % refresh_rate if refresh_rate > 0.0 else "未知", vsync_names[vsync]]
	var system := get_parent().get_node("System") as SystemController
	_hud_performance.text = "诊断  %s  /  渲染 %d FPS  /  物理 %d Hz  /  插值%s  /  %s\n帧 P95 %.1f ms，最大 %.1f ms  /  回拉计数 %d  /  镜头%s（F7切换）  /  F4关闭并保存采样" % ["编辑器内嵌" if Engine.is_embedded_in_editor() else "独立窗口", Engine.get_frames_per_second(), Engine.physics_ticks_per_second, "开启" if get_tree().physics_interpolation else "关闭", display_info, p95, sorted.back(), _render_pullbacks, "跟随" if system.camera_fixed else "固定"]

## 只在诊断时读取绘制完成后的画布，不改相机或物理节点，也不进行GPU截图读回。
func _record_render_motion() -> void:
	if not _diagnostics_visible or not is_instance_valid(player):
		return
	var viewport := get_viewport()
	var center := viewport.canvas_transform.affine_inverse() * viewport.get_visible_rect().get_center()
	var velocity := player.velocity
	var pullback := false
	if _has_previous_render:
		var offset := center - _previous_render_center
		## 排除传送与反向输入；只判断同向移动中是否真的出现横向反向绘制。
		if offset.length() < 40.0 and absf(velocity.x) > 20.0 and absf(_previous_render_velocity.x) > 20.0 and signf(velocity.x) == signf(_previous_render_velocity.x):
			pullback = offset.x * signf(velocity.x) < -0.05
	_render_pullbacks += int(pullback)
	var system := get_parent().get_node("System") as SystemController
	_motion_trace.append({"time_usec": Time.get_ticks_usec(), "render_frame": Engine.get_process_frames(), "physics_frame": Engine.get_physics_frames(), "fraction": Engine.get_physics_interpolation_fraction(), "camera_x": center.x, "camera_y": center.y, "camera_follow": system.camera_fixed, "player_x": player.global_position.x, "velocity_x": velocity.x, "pullback": pullback})
	if _motion_trace.size() > 600:
		_motion_trace.pop_front()
	_previous_render_center = center
	_previous_render_velocity = velocity
	_has_previous_render = true

func _set_diagnostics_visible(enabled: bool) -> void:
	_diagnostics_visible = enabled
	_hud_performance.visible = enabled
	_diagnostics_panel.visible = enabled
	_has_previous_render = false
	if enabled:
		_motion_trace.clear()
		_render_pullbacks = 0
		_performance_update_time = 0.25
	else:
		_restore_follow_camera()
		_save_motion_trace()

func _restore_follow_camera() -> void:
	var system := get_parent().get_node("System") as SystemController
	if not system.camera_fixed:
		system.camera_fixed = true
		system.reset_view_interpolation()

func _save_motion_trace() -> void:
	if _motion_trace.is_empty():
		return
	var folder := "user://MotionDiagnostics"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		show_message("诊断采样无法写入本地目录。")
		return
	var path := folder + "/motion_trace_%d_%d.json" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		show_message("诊断采样保存失败。")
		return
	var result := {"embedded": Engine.is_embedded_in_editor(), "physics_hz": Engine.physics_ticks_per_second, "interpolation": get_tree().physics_interpolation, "jitter_fix": Engine.physics_jitter_fix, "pullbacks": _render_pullbacks, "samples": _motion_trace}
	result["fps"] = Engine.get_frames_per_second()
	result["max_fps"] = Engine.max_fps
	if DisplayServer.get_name() != "headless":
		var window_id := get_window().get_window_id()
		var screen := DisplayServer.window_get_current_screen(window_id)
		result["screen"] = screen
		result["screen_hz"] = DisplayServer.screen_get_refresh_rate(screen)
		result["vsync_mode"] = DisplayServer.window_get_vsync_mode(window_id)
	file.store_string(JSON.stringify(result))
	file.close()
	show_message("诊断采样已保存。镜头恢复跟随；可以继续正常试玩。")
	print("MOTION_TRACE_SAVED: ", ProjectSettings.globalize_path(path))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	_message_time = maxf(0.0, _message_time - delta)
	if player.position.y > 760.0 or player.position.x < -180.0:
		reset_current_section()
		show_message("跌落后回到本段起点；墨水和已经打开的门保留。")
		return
	if player.position.x >= 2820.0 and current_section < 2:
		_set_checkpoint(2)
	elif player.position.x >= 1400.0 and current_section < 1:
		_set_checkpoint(1)
	if not milestones.plate_opened and player.is_on_floor() and absf(player.position.y - 420.0) < 14.0 and player.position.x > 2395.0 and player.position.x < 2495.0:
		milestones.plate_opened = true
		_set_door_open(true)
		$WorldNotes/PressurePlate.color = Color(0.46, 0.87, 0.66, 1)
		$WorldNotes/PressurePlate/StorybookSprite.self_modulate = Color("c2c9ac")
		show_message("高台机关已开启前方的门。跳下来，继续前往下一片段。")
		milestone_reached.emit("plate_opened")
	if not milestones.ink_collected and player.position.distance_to(Vector2(3860, 575)) < 52.0:
		milestones.ink_collected = true
		$WorldNotes/Ink.visible = false
		show_message("获得第一份墨水。把它带到右侧小画室。")
		milestone_reached.emit("ink_collected")
	if milestones.ink_collected and not milestones.canvas_painted and player.position.x > 4130.0:
		milestones.canvas_painted = true
		$WorldNotes/Canvas/FirstStroke.visible = true
		show_message("空画卷留下了第一笔。后续章节会从这里出发，再带着墨水回来。", 12.0)
		milestone_reached.emit("canvas_painted")
	if player.position.x > 4100.0 and not _room_checkpoint_active:
		_room_checkpoint_active = true
		checkpoint_position = Vector2(4120, 600)
		show_message("已到达画室恢复点。墨水会让画卷留下第一笔；可以回头观察已有通路。")
	_update_hud()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_R:
			reset_current_section()
		KEY_F1:
			spawn_for_section(0)
		KEY_F2:
			spawn_for_section(1)
		KEY_F3:
			spawn_for_section(2)
		KEY_F4:
			_set_diagnostics_visible(not _diagnostics_visible)
		KEY_F8:
			_set_guides_visible(not _guides_visible)
		KEY_F7:
			if not _diagnostics_visible:
				_set_diagnostics_visible(true)
			var system := get_parent().get_node("System") as SystemController
			system.camera_fixed = not system.camera_fixed
			system.reset_view_interpolation()
			_has_previous_render = false
			show_message("镜头跟随已恢复。" if system.camera_fixed else "诊断：镜头暂时固定，角色可以在静止背景中移动；F7恢复，F4关闭诊断。")

## 测试与关卡协调接口，index 从 0 起。
func spawn_for_section(index: int) -> void:
	current_section = clampi(index, 0, SPAWN_POINTS.size() - 1)
	checkpoint_position = SPAWN_POINTS[current_section]
	_room_checkpoint_active = false
	_restore_objects_for_section(current_section)
	_teleport_player(checkpoint_position)
	checkpoint_changed.emit(current_section)
	show_message("回到「" + SECTION_TITLES[current_section].substr(4) + "」起点。")

func reset_current_section() -> void:
	reset_count += 1
	_restore_objects_for_section(current_section)
	_teleport_player(checkpoint_position)
	show_message("已恢复本段物件和出生点；墨水、画卷与已打开的门保留。")

func _teleport_player(point: Vector2) -> void:
	Global.clear_selection()
	_has_previous_render = false
	player.position = point
	player.reset_motion()
	var system := get_parent().get_node_or_null("System") as SystemController
	if system != null and system.is_node_ready():
		system.camera_fixed = true
		system.reset_view_interpolation()
	else:
		player.reset_physics_interpolation()

func _restore_objects_for_section(section: int) -> void:
	if section == 1:
		milestones.tree_moved = false
	for index in range(_initial_states.size()):
		if (section == 1 and index < 2) or (section == 2 and index == 2):
			var state: Dictionary = _initial_states[index]
			var item: LayerObject = state.object
			var original_parent: DepthLayer = state.parent
			if item.get_parent() != original_parent:
				item.reparent(original_parent, false)
			item.owner_layer = original_parent
			item.position = state.position
			item.collision_box.scale = state.scale
			item.collision_layer = 1 << original_parent.layer_id
			item.collision_mask = 1 << original_parent.layer_id
			item.set_pick_condition(false)
	_set_door_open(milestones.plate_opened)

func _set_checkpoint(section: int) -> void:
	current_section = section
	checkpoint_position = SPAWN_POINTS[section]
	_room_checkpoint_active = false
	checkpoint_changed.emit(section)
	show_message("到达新的恢复点：" + SECTION_TITLES[section])

func _set_door_open(opened: bool) -> void:
	var door := $PlayerLayer/MechanismDoor as TransferPlatform
	door.get_node("CollisionBox").set_deferred("disabled", opened)
	door.get_node("VisualRoot").visible = not opened
	$WorldNotes/DoorNote.text = "门已开启" if opened else "站上高台机关，打开这扇门"

func _on_transfer_result(object: LayerObject, success: bool, reason: String) -> void:
	if success:
		if object.name == "BlockingTree":
			milestones.tree_moved = object.owner_layer.layer_id == 1
			if milestones.tree_moved:
				milestone_reached.emit("tree_moved")
		var object_caption: String = object.caption if object is TransferPlatform and not object.caption.is_empty() else "物件"
		show_message("%s 已进入%s。搬入后位置固定；送回背景后，可换站位再次搬入。" % [object_caption, "中景" if object.owner_layer.layer_id == 0 else "背景"])
	else:
		show_message("搬运失败：" + reason, 7.0)

func show_message(message: String, duration: float = 6.0) -> void:
	_message = message
	_message_time = duration

func _build_storybook_art() -> void:
	var paper_layer := CanvasLayer.new()
	paper_layer.name = "StorybookPaper"
	paper_layer.layer = -20
	add_child(paper_layer)
	var paper := TextureRect.new()
	paper.name = "PaperTexture"
	paper.texture = PAPER_TEXTURE
	paper.stretch_mode = TextureRect.STRETCH_TILE
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper_layer.add_child(paper)
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := $BackgroundLayer as DepthLayer
	for index in range(5):
		var positions := [Vector2(430, 330), Vector2(1470, 330), Vector2(2310, 320), Vector2(3450, 330), Vector2(4270, 330)]
		_add_decoration(background, "PrintedGarden%d" % index, positions[index], GARDEN_TEXTURE, Vector2(720, 480), Color(1, 1, 1, 0.62))
	for index in range(8):
		var plant_x := [260.0, 845.0, 1180.0, 1760.0, 2605.0, 2910.0, 3760.0, 4530.0]
		_add_decoration($PlayerLayer, "InkPlant%d" % index, Vector2(plant_x[index], 550), PLANT_TEXTURE, Vector2(34, 100), Color(1, 1, 1, 0.75))
	$WorldNotes/Ink.color.a = 0.0
	_attach_sprite($WorldNotes/Ink, INK_TEXTURE, Vector2(40, 47))
	$WorldNotes/PressurePlate.color = Color("d76a49")
	$WorldNotes/PressurePlate.polygon = PackedVector2Array()
	_attach_sprite($WorldNotes/PressurePlate, PLATE_TEXTURE, Vector2(90, 30), Vector2(0, -8))
	$WorldNotes/Canvas/Frame.color.a = 0.0
	$WorldNotes/Canvas/BlankPage.color.a = 0.0
	_attach_sprite($WorldNotes/Canvas/Frame, CANVAS_TEXTURE, Vector2(360, 260))
	$WorldNotes/Canvas/FirstStroke.default_color = Color("4d5b8c")
	$WorldNotes/Canvas/FirstStroke.width = 9.0
	for node in $WorldNotes.get_children():
		if node is Label:
			node.add_theme_color_override("font_color", Color("625468"))
			node.add_theme_font_size_override("font_size", 17)
			node.add_theme_color_override("font_shadow_color", Color("f2e8d4"))
			node.add_theme_constant_override("shadow_offset_x", 1)
			node.add_theme_constant_override("shadow_offset_y", 1)
	$WorldNotes/MoveNote.text = "A / D 行走\nSpace 跳跃"
	$WorldNotes/RunNote.text = "按住 Shift 奔跑\n短按释放，向前冲刺"
	$WorldNotes/TreeNote.text = "一棵树挡住去路。\n点选它，按 S 送入背景。"
	$WorldNotes/BoxNote.text = "纸匣沉在背景。\nW 搬近，S 送远。\n换个站位，再试一次。"
	$WorldNotes/BridgeNote.text = "站位会改变背景桥的位置。\n把它带到中景，再越过缺口。"
	$WorldNotes/InkNote.text = "一滴墨水，带回画室。"
	$WorldNotes/RoomNote.text = "小画室 · 空画卷\n每段旅程，留下一笔。"
	$WorldNotes/GapNote.visible = false
	$WorldNotes/GapLengthNote.visible = false
	$WorldNotes/Section1Checkpoint.default_color = Color("b58b96")
	$WorldNotes/Section2Checkpoint.default_color = Color("b58b96")

func _add_decoration(layer: DepthLayer, decoration_name: String, point: Vector2, art: Texture2D, size: Vector2, color_tint: Color) -> void:
	var decoration := LayerDecoration.new()
	decoration.name = decoration_name
	decoration.position = point
	decoration.texture = art
	decoration.display_size = size
	decoration.tint = color_tint
	layer.add_child(decoration)

func _attach_sprite(parent_node: Node2D, art: Texture2D, size: Vector2, offset: Vector2 = Vector2.ZERO) -> void:
	var sprite := Sprite2D.new()
	sprite.name = "StorybookSprite"
	sprite.texture = art
	sprite.scale = size / art.get_size()
	sprite.position = offset
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	parent_node.add_child(sprite)

func _set_guides_visible(enabled: bool) -> void:
	_guides_visible = enabled
	_guide_controls.visible = enabled
	_guide_panel.visible = enabled
	_hud_state.visible = enabled
	_hud_progress.visible = enabled
	for node in $WorldNotes.get_children():
		if node is Label:
			node.visible = enabled and node.name not in ["GapNote", "GapLengthNote"]
	for layer in [$PlayerLayer, $BackgroundLayer]:
		for node in layer.get_children():
			if node is TransferPlatform:
				node.show_layer_label = enabled
				node.show_caption = false
	_hud_title.text = "失页花园 · " + SECTION_TITLES[current_section] + "　F8 教学%s" % ["开" if enabled else "关"]

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	hud.name = "PrologueHUD"
	hud.layer = 10
	add_child(hud)
	_guide_panel = ColorRect.new()
	_guide_panel.position = Vector2(12, 10)
	_guide_panel.size = Vector2(1256, 126)
	_guide_panel.color = Color(0.96, 0.92, 0.84, 0.94)
	_guide_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_guide_panel)
	var title_paper := ColorRect.new()
	title_paper.position = Vector2(12, 10)
	title_paper.size = Vector2(740, 38)
	title_paper.color = Color(0.96, 0.92, 0.84, 0.94)
	title_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(title_paper)
	_hud_title = _make_label(hud, Vector2(26, 17), 22)
	_guide_controls = _make_label(hud, Vector2(26, 49), 16)
	_guide_controls.text = "A / D 左右　短按 Shift 释放冲刺　按住 Shift 奔跑　Space 跳跃　左键选择　W 搬近　S 送远　R 恢复　F1–F3 切段　F8 教学"
	_hud_state = _make_label(hud, Vector2(26, 77), 17)
	_hud_progress = _make_label(hud, Vector2(26, 104), 17)
	_diagnostics_panel = ColorRect.new()
	_diagnostics_panel.position = Vector2(12, 600)
	_diagnostics_panel.size = Vector2(1256, 50)
	_diagnostics_panel.color = Color(0.96, 0.92, 0.84, 0.96)
	_diagnostics_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_diagnostics_panel.visible = false
	hud.add_child(_diagnostics_panel)
	_hud_performance = _make_label(hud, Vector2(24, 606), 14)
	_hud_performance.visible = false
	var message_paper := ColorRect.new()
	message_paper.position = Vector2(12, 652)
	message_paper.size = Vector2(1256, 58)
	message_paper.color = Color(0.96, 0.92, 0.84, 0.96)
	message_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(message_paper)
	_hud_message = _make_label(hud, Vector2(24, 656), 18)
	_hud_message.size = Vector2(1220, 58)
	_hud_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _make_label(parent: Node, point: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = point
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("3d344a"))
	label.add_theme_color_override("font_shadow_color", Color("f2e8d4"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _update_hud() -> void:
	_hud_title.text = "失页花园 · " + SECTION_TITLES[current_section] + "　F8 教学%s" % ["开" if _guides_visible else "关"]
	var selected: String = "无（点击朱砂纸签物件）"
	if is_instance_valid(Global.object_selected):
		selected = "%s / %s" % [Global.object_selected.name, "玩家层" if Global.object_selected.owner_layer.layer_id == 0 else "背景层"]
	var gait_names := ["步行", "奔跑", "冲刺", "空中", "无人机"]
	_hud_state.text = "角色：中景 / %s　选择：%s　中景 ⇄ 背景　恢复点：%s" % [gait_names[player.gait], selected, "画室" if _room_checkpoint_active else str(current_section + 1)]
	_hud_progress.text = "树已移开：%s　机关门：%s　墨水：%d / 1　画卷：%s" % ["是" if milestones.tree_moved else "待尝试", "已开" if milestones.plate_opened else "待触发", int(milestones.ink_collected), "已有第一笔" if milestones.canvas_painted else "空白"]
	var visible_message: String = _message if _guides_visible else _message.get_slice("。", 0) + "。"
	_hud_message.text = visible_message if _message_time > 0.0 else ("朱砂纸签表示可搬运；选中后可用 W / S 换层。F8 隐藏教学，F4 查看诊断。" if _guides_visible else "R 恢复本段 · F8 显示教学")
