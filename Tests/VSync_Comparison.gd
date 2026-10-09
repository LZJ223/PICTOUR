extends Node

## 仅供手动显示对照：在同一白模和帧率上限下临时开启同步，不写回配置。
const GAME_SCENE = preload("res://Prologue_Test_Game.tscn")

func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	add_child(GAME_SCENE.instantiate())
	print("VSYNC_COMPARISON: 同步开启对照；F4查看实际同步与帧率，退出后恢复项目默认。")
