@tool
extends Level
## 无磁盘进度的绘本箱庭。所有岸体和景物在.tscn中静态保存，供布景面板编辑。
@export var spawn := Vector2(360,1300)
@export var editor_projection_anchor_y := 920.0
@export var world_bounds := Rect2(-160,-350,5000,2100)
var player: PlayerController
var system: StudySystemController
var discovered: Array[StringName] = []
var _notes: CanvasLayer
var _feedback: Label
var _feedback_time := 0.0

func _enter_tree() -> void:
	if not Engine.is_editor_hint(): write_to_global()

func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_build_notes()
	for marker in $InkMarks.get_children():
		marker.z_index = 215
	$Atmosphere._add_wash(self,Rect2(210,-220,1200,1000),Color(0.63,0.48,0.55,0.16),Vector2(0.21,0.71))
	$Atmosphere._add_wash(self,Rect2(2530,120,1450,1150),Color(0.63,0.63,0.52,0.16),Vector2(0.65,0.22))
	$Atmosphere._add_wash(self,Rect2(3430,-550,1250,1120),Color(0.69,0.50,0.56,0.15),Vector2(0.39,0.18))
	call_deferred("_connect_game")

func _connect_game() -> void:
	player = get_parent().get_node("Player")
	system = get_parent().get_node("System")
	Global.transfer_result.connect(_on_transfer)
	system.history.message_changed.connect(_message)

func _physics_process(delta: float) -> void:
	_feedback_time = maxf(0.0,_feedback_time-delta)
	if is_instance_valid(_feedback): _feedback.modulate.a = minf(1.0,_feedback_time)
	if not is_instance_valid(player): return
	if not world_bounds.has_point(player.global_position): system.reset_study()
	for marker in $InkMarks.get_children():
		if marker.visible and player.is_on_floor() and player.global_position.distance_to(marker.position+Vector2(0,50))<65:
			marker.visible = false
			discovered.append(StringName(marker.name))
			_message("拾起一滴记忆。这里的每条来路，都有归路。")

func _on_transfer(object: LayerObject, success: bool, reason: String) -> void:
	if is_instance_valid(object) and is_ancestor_of(object):
		_message("%s · %s" % [object.display_name,"落入此页" if object.owner_layer.slot==0 else "退入远处"] if success else reason)

func _message(value: String) -> void:
	_feedback.text = value
	_feedback_time = 3.5

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint(): return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F8:
		_notes.visible = not _notes.visible
		get_viewport().set_input_as_handled()

func _build_notes() -> void:
	_notes = CanvasLayer.new()
	_notes.layer = 8
	add_child(_notes)
	var title := Label.new()
	title.text = "折 页 庭 园  ·  根井 / 页脊 / 天际回廊"
	title.position = Vector2(30,24)
	title.add_theme_font_size_override("font_size",16)
	title.add_theme_color_override("font_color",Color("8e7c79"))
	_notes.add_child(title)
	_feedback = Label.new()
	_feedback.position = Vector2(30,50)
	_feedback.add_theme_font_size_override("font_size",13)
	_feedback.add_theme_color_override("font_color",Color("8e7c79"))
	_notes.add_child(_feedback)
	var guide := Label.new()
	guide.text = "A D 移动 · Shift 冲刺/奔跑 · Space 跳跃 · 左键选景，W/S 换景 · Z 撤回 · R 重来 · F8 藏字"
	guide.position = Vector2(30,690)
	guide.add_theme_font_size_override("font_size",12)
	guide.add_theme_color_override("font_color",Color("8e7c79"))
	_notes.add_child(guide)
