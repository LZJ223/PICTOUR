## 复用完整片头，仅把 Main 换成无 UI 的继承场景；录制期间忽略跳过输入。
extends "res://Opening/Opening.gd"

func _load_menu() -> PackedScene:
	var original := await super._load_menu()
	if original == null:
		return null
	return load("res://Promo_Renders/20261021_Opening_NoUI_1080p60/Source/Promo_Main.tscn") as PackedScene

func _input(_event: InputEvent) -> void:
	pass
