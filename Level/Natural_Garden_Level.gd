class_name NaturalGardenLevel
extends Level
## 可搬景物围绕固定地平线组成两条回路，不将建筑烘焙进背景。
@export var save_path: String = "user://Natural_Garden_Save.json"
@export var enable_bookmarks: bool = true
var bookmarks: Node
var player: PlayerController
var system: SystemController
var _feedback: Label
var _guide: Label
var _ink_nodes: Dictionary = {}
var _guides_visible: bool = true

func _ready() -> void:
	_build_paper()
	_build_hud()
	_build_ink("arch_ink", Vector2(1080,355))
	_build_ink("tree_ink", Vector2(1930,345))
	call_deferred("_connect_game")

func _connect_game() -> void:
	player = get_parent().get_node("Player") as PlayerController
	system = get_parent().get_node("System") as SystemController
	_feedback.text = "地平线是纸页的底面；树、岩、拱门、枝与花都能换层。"
	if enable_bookmarks:
		bookmarks = preload("res://Level/Bookmark_Manager.gd").new()
		bookmarks.name = "Bookmarks"
		bookmarks.save_path = save_path
		bookmarks.show_messages = false
		bookmarks.fall_y = 820.0
		bookmarks.world_min_x = -420.0
		bookmarks.world_max_x = 3100.0
		add_child(bookmarks)
		bookmarks.message_changed.connect(func(message: String): _feedback.text = message)
		var definitions: Array[Dictionary] = [
			{"id":0,"title":"纸岸","position":Vector2(180,600),"map_position":Vector2(180,600)},
			{"id":1,"title":"折枝庭","position":Vector2(2260,600),"map_position":Vector2(2260,600)}
		]
		bookmarks.configure(player, system, self, definitions)
		bookmarks.progress_changed.connect(_update_ink)
		_update_ink()
	Global.transfer_result.connect(_on_transfer)

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(bookmarks):
		return
	for id in _ink_nodes:
		var ink := _ink_nodes[id] as Node2D
		if ink.visible and player.global_position.distance_to(ink.position + Vector2(0,42)) < 58:
			bookmarks.mark_ink(id)
			_feedback.text = "带回一滴墨。M 打开书签地图，随时回到纸岸。"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		_guides_visible = not _guides_visible
		_guide.visible = _guides_visible
		if is_instance_valid(bookmarks):
			bookmarks.show_prompt = _guides_visible
		get_viewport().set_input_as_handled()

func _on_transfer(object: LayerObject, success: bool, reason: String) -> void:
	if not is_instance_valid(object):
		return
	var title: String = object.display_name if object is NaturalObject else str(object.name)
	_feedback.text = "%s已成为%s；位置与大小保留，可继续换站位再搬。" % [title,"实体" if object.owner_layer.slot == current_layer_index else "背景"] if success else reason

func _update_ink() -> void:
	for id in _ink_nodes:
		(_ink_nodes[id] as Node2D).visible = not bookmarks.has_ink(id)

func _build_ink(id: String, point: Vector2) -> void:
	var ink := Node2D.new()
	ink.name = id
	ink.position = point
	ink.z_index = 450
	var sprite := Sprite2D.new()
	sprite.texture = preload("res://Art/Scenery/Ink_Drop.png")
	sprite.scale = Vector2(0.18,0.18)
	ink.add_child(sprite)
	add_child(ink)
	_ink_nodes[id] = ink

func _build_paper() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "Paper"
	canvas.layer = -10
	add_child(canvas)
	var paper := TextureRect.new()
	paper.texture = preload("res://Art/Scenery/Paper_Grain.png")
	paper.stretch_mode = TextureRect.STRETCH_TILE
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(paper)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0,0.96,0.86,0.12), Color(0.84,0.73,0.68,0.17)])
	var wash := GradientTexture2D.new()
	wash.gradient = gradient
	wash.fill_from = Vector2(0.4,0)
	wash.fill_to = Vector2(0.7,1)
	var atmosphere := TextureRect.new()
	atmosphere.texture = wash
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(atmosphere)

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "ReadingNotes"
	canvas.layer = 5
	add_child(canvas)
	var title := Label.new()
	title.position = Vector2(24,16)
	title.text = "纸岸 · 一滴墨的回路"
	title.add_theme_color_override("font_color",Color("514151"))
	title.add_theme_font_size_override("font_size",22)
	canvas.add_child(title)
	_guide = Label.new()
	_guide.position = Vector2(24,48)
	_guide.text = "A / D 走 · Shift 短冲 / 长跑 · Space 轻跳 / 长跳\n左键选景物 · W 移近 · S 移远 · E 落书签 · R 回书签 · M 地图 · F8 藏提示"
	_guide.add_theme_color_override("font_color",Color("6d5e6d"))
	_guide.add_theme_font_size_override("font_size",16)
	canvas.add_child(_guide)
	_feedback = Label.new()
	_feedback.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_feedback.offset_left = 24
	_feedback.offset_top = -96
	_feedback.offset_right = -24
	_feedback.offset_bottom = -68
	_feedback.add_theme_color_override("font_color",Color("f4ead6"))
	_feedback.add_theme_font_size_override("font_size",16)
	_feedback.add_theme_color_override("font_shadow_color",Color("493744"))
	_feedback.add_theme_constant_override("shadow_offset_x",1)
	_feedback.add_theme_constant_override("shadow_offset_y",1)
	canvas.add_child(_feedback)
