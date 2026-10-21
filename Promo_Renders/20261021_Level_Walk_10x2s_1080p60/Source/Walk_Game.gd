## 宣传素材使用完整 Game/Level 渲染链，只隐藏界面并禁止收集、过关等存档触发器。
extends "res://Interface/Game.gd"

func _ready() -> void:
	super._ready()
	$Camera/MenuUI.hide()
	_disable_areas($Level)

func _disable_areas(node: Node) -> void:
	if node is Area2D:
		node.monitoring = false
		node.monitorable = false
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		_disable_areas(child)
