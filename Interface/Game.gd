extends Node2D

const LEVEL_PATH: String = "res://Level/Level_%02d.tscn"
const DialogueLine = preload("res://Interface/Dialogue/Dialogue_Line.gd")

@export var play_dialogue: bool = true

func _enter_tree() -> void:
	var requested_dialogue := SceneTransition.consume_dialogue_request()
	play_dialogue = play_dialogue and requested_dialogue and not SaveSystem.skip_dialogue
	var level_id: int = Global.next_level_id
	Global.next_level_id = 1
	assert(level_id >= 1 and level_id <= 12, "关卡编号必须在 1 到 12 之间")
	var level_scene: PackedScene = load(LEVEL_PATH % level_id) as PackedScene
	assert(level_scene != null, "找不到关卡 %d" % level_id)
	var selected_level: Level = level_scene.instantiate() as Level
	assert(selected_level != null, "关卡场景根节点必须挂载 Level.gd")
	selected_level.name = "Level"
	selected_level.write_to_global()
	add_child(selected_level)
	move_child(selected_level, 0)

func _ready() -> void:
	Global.camera_fixed = true
	$LayerControllerSystem.initialize()
	play_dialogue = play_dialogue and Global.level.dialogue.any(func(line: DialogueLine) -> bool: return line != null)
	## 淡入解除暂停前就锁定操作，防止玩家在开场首帧移动。
	SignalSystem.set_dialogue_active(play_dialogue)
	SignalSystem.set_gameplay_active(true)
	if play_dialogue:
		if SceneTransition.busy:
			SceneTransition.transition_finished.connect(_start_dialogue, CONNECT_ONE_SHOT)
		else:
			_start_dialogue()
	SceneTransition.scene_ready()

func _start_dialogue() -> void:
	$DialogueSystem.start(Global.level.dialogue, $LayerControllerSystem)

func _exit_tree() -> void:
	SignalSystem.set_gameplay_active(false)
	Global.clear_scene_nodes()
