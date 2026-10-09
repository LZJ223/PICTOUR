extends Level
## 一屏构图试验；与旧庭园保存空间隔离。
@export var save_path: String = "user://Paper_Stage_Save.json"
@export var enable_bookmarks: bool = true
var bookmarks: BookmarkManager
var player: PlayerController
var system: SystemController
var _notes: CanvasLayer
var _feedback: Label
var _guide: Label
var _feedback_time := 0.0
var _ink: Sprite2D

func _ready() -> void:
	if "--no-save" in OS.get_cmdline_user_args():
		enable_bookmarks = false
	_build_notes()
	_ink = Sprite2D.new()
	_ink.name = "ArchInk"
	_ink.texture = preload("res://Art/Scenery/Ink_Drop.png")
	_ink.scale = Vector2(0.17,0.17)
	_ink.position = Vector2(1020,172)
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
		bookmarks.world_min_x = -420.0
		bookmarks.world_max_x = 1700.0
		add_child(bookmarks)
		bookmarks.message_changed.connect(_message)
		var definitions: Array[Dictionary] = [
			{"id":0,"title":"折页","position":Vector2(640,510),"map_position":Vector2(640,510)},
			{"id":1,"title":"余墨","position":Vector2(1530,470),"map_position":Vector2(1530,470)}
		]
		bookmarks.configure(player,system,self,definitions)
		bookmarks.progress_changed.connect(_refresh_ink)
		_refresh_ink()
	Global.transfer_result.connect(_on_transfer)
	_message("改变站位，让远处的残拱接住断开的纸岸。")

func _physics_process(delta: float) -> void:
	_feedback_time = maxf(0.0, _feedback_time-delta)
	if is_instance_valid(_feedback):
		_feedback.modulate.a = minf(1.0,_feedback_time)
	if not is_instance_valid(player) or not is_instance_valid(bookmarks):
		return
	if _ink.visible and player.global_position.distance_to(_ink.position+Vector2(0,35)) < 52:
		bookmarks.mark_ink("arch_ink")
		_message("一滴余墨，已留在书签里。")

func _refresh_ink() -> void:
	_ink.visible = not bookmarks.has_ink("arch_ink")

func _on_transfer(object: LayerObject, success: bool, reason: String) -> void:
	if not is_instance_valid(object) or not is_ancestor_of(object):
		return
	if success:
		_message("%s · %s" % [object.display_name, "落入此页" if object.owner_layer.slot == current_layer_index else "退入远处"])
	else:
		_message(reason)

func _message(value: String) -> void:
	_feedback.text = value
	_feedback_time = 4.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		_notes.visible = not _notes.visible
		get_viewport().set_input_as_handled()

func _build_notes() -> void:
	_notes = CanvasLayer.new()
	_notes.name = "PageNotes"
	_notes.layer = 8
	add_child(_notes)
	var title := Label.new()
	title.text = "折 页 之 间"
	title.position = Vector2(720,28)
	title.add_theme_font_size_override("font_size",18)
	title.add_theme_color_override("font_color",Color("76636c"))
	_notes.add_child(title)
	_guide = Label.new()
	_guide.text = "A D 移动   Shift 冲刺 / 奔跑   Space 跳跃   ·   左键选景   W 移近 / S 移远   ·   E 记录   R 返回   M 书签   F8 藏字"
	_guide.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_guide.offset_left = 30
	_guide.offset_top = -32
	_guide.offset_right = -30
	_guide.offset_bottom = -8
	_guide.add_theme_font_size_override("font_size",13)
	_guide.add_theme_color_override("font_color",Color("76636c"))
	_notes.add_child(_guide)
	_feedback = Label.new()
	_feedback.position = Vector2(720,56)
	_feedback.add_theme_font_size_override("font_size",14)
	_feedback.add_theme_color_override("font_color",Color("89776e"))
	_notes.add_child(_feedback)
