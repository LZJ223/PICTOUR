extends Node2D

@export_range(2,4,2) var preview_layer_count := 2
var _family_index := 0
var _world: Node2D
var _level: Level
var _system: SystemController
var _pieces: Array[SceneryFamilyObject] = []
var _head: Label
var _status: Label
var _captions: Node
var _show_footholds := false
var _surface_lines: Array[Line2D] = []

func _ready() -> void:
	var atmosphere := PaperAtmosphere.new()
	add_child(atmosphere)
	var hud := CanvasLayer.new()
	hud.layer = 20
	add_child(hud)
	_head = _label(Vector2(40,24),26)
	hud.add_child(_head)
	var help := _label(Vector2(42,69),16)
	help.text = "1 / 2 / 3 古木、层岩、残廊  ·  左键选取 + W / S 换景  ·  4 切换两层 / 四层  ·  H 显示自然踏面"
	hud.add_child(help)
	_status = _label(Vector2(42,682),15)
	hud.add_child(_status)
	_captions = Node.new()
	hud.add_child(_captions)
	_build_world()
	Global.transfer_result.connect(_on_transfer_result)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1,KEY_2,KEY_3:
			_family_index = event.keycode-KEY_1
			_build_world()
		KEY_4:
			preview_layer_count = 4 if preview_layer_count==2 else 2
			_build_world()
		KEY_H:
			_show_footholds = not _show_footholds
			for line in _surface_lines:
				line.visible = _show_footholds

func _build_world() -> void:
	Global.clear_selection()
	_pieces.clear()
	_surface_lines.clear()
	if is_instance_valid(_world):
		remove_child(_world)
		_world.free()
	for child in _captions.get_children():
		_captions.remove_child(child)
		child.queue_free()
	_world = Node2D.new()
	add_child(_world)
	_level = Level.new()
	_level.layer_count = preview_layer_count
	_level.current_layer_index = 1 if preview_layer_count==4 else 0
	_level.allow_layer_cycle = false
	_level.allow_uav = false
	_level.allow_scenery_overlap_outside_player_layer = true
	_world.add_child(_level)
	for index in range(preview_layer_count):
		var layer := DepthLayer.new()
		layer.layer_id = index
		layer.slot = index
		_level.add_child(layer)
	var player := preload("res://Component/Player/Player.tscn").instantiate() as PlayerController
	player.position = Vector2(-5000,-5000)
	player.visible = false
	_world.add_child(player)
	player.activated = false
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.position = Vector2(640,360)
	_world.add_child(camera)
	_system = SystemController.new()
	_system.player = player
	_system.camera = camera
	_system.level = _level
	_system.camera_fixed = false
	_world.add_child(_system)
	var family := SceneryFamilyLibrary.FAMILIES[_family_index]
	var names: Array[String] = ["古木：生长、折断与再生", "层岩：侵蚀、错层与悬挑", "残廊：断柱、落檐与空窗"]
	_head.text = names[_family_index]+"  /  %s 景别"%preview_layer_count
	var ids: Array = SceneryFamilyLibrary.PIECES[family]
	for index in range(ids.size()):
		var object := SceneryFamilyLibrary.create_piece(ids[index])
		if object==null:
			continue
		var fit := minf(270.0/object.dimensions.x,355.0/object.dimensions.y)
		object.dimensions *= fit
		object.position = Vector2(178+index*310,510)
		_system.get_layer_at_slot(Global.current_layer_index).add_child(object)
		_pieces.append(object)
		for edge in object.get_footholds():
			var line := Line2D.new()
			line.points = edge
			line.width = 2.5
			line.default_color = Color("ad4745")
			line.visible = _show_footholds
			object.visual_root.add_child(line)
			_surface_lines.append(line)
		var caption := _label(Vector2(45+index*310,545),20)
		caption.text = object.piece.display_name
		_captions.add_child(caption)
		var note := _label(Vector2(45+index*310,582),15)
		note.size = Vector2(272,90)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.text = object.piece.affordance_note
		_captions.add_child(note)
	_system.reset_view_interpolation()
	_status.text = "独立素材观察场：踏面来自图中的结构断口；所有样本可往返换层。"

func _label(at: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = at
	label.add_theme_color_override("font_color",Color("554755"))
	label.add_theme_font_size_override("font_size",font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _on_transfer_result(object: LayerObject, success: bool, reason: String) -> void:
	if not is_instance_valid(object):
		return
	_status.text = "%s：%s"%[object.display_name,"已换到第 %s 景别"%(object.owner_layer.slot+1) if success else reason]
