## 先播放结尾对话，再复用普通 Goal 的通关保存和离场演出。
class_name EndingGoal
extends LevelGoal

const DialogueLine = preload("res://Interface/Dialogue/Dialogue_Line.gd")

@export_group("结尾对话")
## 与关卡开场对话独立；空数组或开启跳过对话时直接结算。
@export var ending_dialogue: Array[DialogueLine] = []

func _on_reached() -> void:
	if SaveSystem.skip_dialogue or not ending_dialogue.any(func(line: DialogueLine) -> bool: return line != null):
		super._on_reached()
		return
	## 先锁定输入，再离开物理查询回调启动演出，期间 completed 仍为 false。
	SignalSystem.set_dialogue_active(true)
	_start_ending_dialogue.call_deferred()

func _start_ending_dialogue() -> void:
	var game := get_parent().get_parent()
	var dialogue := game.get_node("DialogueSystem") as DialogueSystem
	var controller := game.get_node("LayerControllerSystem") as LayerControllerSystem
	assert(dialogue != null and controller != null, "结尾 Goal 需要 Game 中的对话和图层控制系统")
	## 使用绑定到 Goal 的一次性回调；重启、离场释放 Goal 时自动断开。
	dialogue.finished.connect(_finish_ending_dialogue, CONNECT_ONE_SHOT)
	dialogue.start(ending_dialogue, controller)

func _finish_ending_dialogue() -> void:
	super._on_reached()
