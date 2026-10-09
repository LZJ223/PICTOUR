extends Level
## 从树荫走入残廊，再以两种自然踏面组合跨过断页河谷。
@export var save_path: String = "user://Story_Garden_Save.json"
@export var enable_bookmarks: bool = true
var bookmarks: BookmarkManager
var player: PlayerController
var system: SystemController
var _notes: CanvasLayer
var _feedback: Label
var _feedback_time := 0.0
var _ink: Sprite2D

func _ready() -> void:
	if "--no-save" in OS.get_cmdline_user_args():
		enable_bookmarks = false
	_build_notes()
	_ink = Sprite2D.new()
	_ink.name = "StoryInk"
	_ink.texture = preload("res://Art/Scenery/Ink_Drop.png")
	_ink.scale = Vector2(0.17,0.17)
	_ink.position = Vector2(2390,440)
	_ink.z_index = 430
	add_child(_ink)
	call_deferred("_connect_game")

func _connect_game() -> void:
	player = get_parent().get_node("Player")
	system = get_parent().get_node("System")
	if enable_bookmarks:
		bookmarks = BookmarkManager.new()
		bookmarks.save_path = save_path
		bookmarks.show_messages = false
		bookmarks.show_prompt = false
		bookmarks.fall_y = 865.0
		bookmarks.world_min_x = -340.0
		bookmarks.world_max_x = 2780.0
		add_child(bookmarks)
		bookmarks.message_changed.connect(_message)
		var definitions: Array[Dictionary] = [
			{"id":0,"title":"树荫","position":Vector2(220,580),"map_position":Vector2(220,580)},
			{"id":1,"title":"残廊","position":Vector2(1080,520),"map_position":Vector2(1080,520)},
			{"id":2,"title":"远岸","position":Vector2(2350,484),"map_position":Vector2(2350,484)}
		]
		bookmarks.configure(player,system,self,definitions)
		## 标记根只负责外观；出生、记录和交互仍读取 definitions。
		for index in definitions.size():
			var marker := $Mid.get_node("Bookmark%d" % index) as BookmarkMarker
			marker.position.x -= 56.0
			marker.apply_projection(system.camera.global_position)
			marker.reset_physics_interpolation()
		bookmarks.progress_changed.connect(_refresh_ink)
		_refresh_ink()
	Global.transfer_result.connect(_on_transfer)

func _physics_process(delta: float) -> void:
	_feedback_time = maxf(0.0,_feedback_time-delta)
	if is_instance_valid(_feedback):
		_feedback.modulate.a = minf(1.0,_feedback_time)
	if not is_instance_valid(player) or not is_instance_valid(bookmarks):
		return
	if _ink.visible and player.global_position.distance_to(_ink.position+Vector2(0,35)) < 52:
		bookmarks.mark_ink("story_garden_ink")
		_message("一滴余墨，带回未完的画。")

func _refresh_ink() -> void:
	_ink.visible = not bookmarks.has_ink("story_garden_ink")

func _on_transfer(object: LayerObject, success: bool, reason: String) -> void:
	if not is_instance_valid(object) or not is_ancestor_of(object):
		return
	if success:
		_message("%s · %s" % [object.display_name,"落入此页" if object.owner_layer.slot == current_layer_index else "退入远处"])
	else:
		_message(reason)

func _message(value: String) -> void:
	_feedback.text = value
	_feedback_time = 3.5

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		_notes.visible = not _notes.visible
		get_viewport().set_input_as_handled()

func _build_notes() -> void:
	_notes = CanvasLayer.new()
	_notes.name = "StoryNotes"
	_notes.layer = 8
	add_child(_notes)
	var title := Label.new()
	title.text = "未 完 的 庭 园"
	title.position = Vector2(32,24)
	title.add_theme_font_size_override("font_size",16)
	title.add_theme_color_override("font_color",Color("89776e"))
	_notes.add_child(title)
	var guide := Label.new()
	guide.text = "A D 移动   Shift 冲刺 / 奔跑   Space 跳跃   ·   左键选景   W 移近 / S 移远   ·   E 记录   R 返回   M 书签   F8 藏字"
	guide.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	guide.offset_left = 30
	guide.offset_top = -28
	guide.offset_right = -30
	guide.offset_bottom = -8
	guide.add_theme_font_size_override("font_size",12)
	guide.add_theme_color_override("font_color",Color("89776e"))
	_notes.add_child(guide)
	_feedback = Label.new()
	_feedback.position = Vector2(32,51)
	_feedback.add_theme_font_size_override("font_size",13)
	_feedback.add_theme_color_override("font_color",Color("89776e"))
	_notes.add_child(_feedback)
