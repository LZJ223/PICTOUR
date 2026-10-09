extends Node2D
## 在子节点入树、Study捕获初始历史之前使用Level的唯一设计值。
func _enter_tree() -> void:
	var garden := get_node("Level")
	get_node("Player").position = garden.spawn
	get_node("System").projection_anchor_y = garden.editor_projection_anchor_y
