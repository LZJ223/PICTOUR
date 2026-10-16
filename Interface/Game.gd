extends Node2D

const LEVEL_PATH: String = "res://Level/Level_%02d.tscn"

func _enter_tree() -> void:
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
	SignalSystem.set_gameplay_active(true)
	SceneTransition.scene_ready()

func _exit_tree() -> void:
	SignalSystem.set_gameplay_active(false)
	Global.clear_scene_nodes()
