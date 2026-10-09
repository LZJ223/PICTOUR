extends "res://Tests/Illustrated_Garden_Regression.gd"
## 最终材质的开场实机短录；从默认出生点用实际输入登根，不传送。
func _run() -> void:
	game = (load(GAME_PATH) as PackedScene).instantiate()
	add_child(game)
	level = game.get_node("Level")
	player = game.get_node("Player")
	system = game.get_node("System")
	await _ticks(30)
	level._notes.visible = false
	if not await _move_to(630,180): return
	if not await _jump_to(Vector2(689,1205),false): return
	if not await _jump_to(Vector2(725,1162),false): return
	if not await _jump_to(Vector2(785,1112),false): return
	if not await _jump_to(Vector2(840,1083),false): return
	_release()
	await _ticks(60)
	finished = true
	print("ILLUSTRATED_GARDEN_VISUAL_CLIP: %d checks, 0 failures" % checks)
	get_tree().quit()
