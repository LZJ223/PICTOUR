## 仅用于宣传片：保留原场景的相机、动态背景与角色，不显示任何菜单或标题。
extends "res://Interface/Main.gd"

func _ready() -> void:
	super._ready()
	_hide_ui()

func prepare_opening_back_ui() -> void:
	$MenuUI.hide()

func prepare_opening_menu() -> void:
	$Game/Player.show()
	$Game/Player.modulate.a = 1.0
	_hide_ui()

func _hide_ui() -> void:
	for path in ["Logo", "MainMenu", "LevelSelection", "GameOption", "MenuUI"]:
		get_node(path).hide()
