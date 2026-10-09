extends "res://Tests/Illustrated_Garden_Regression.gd"
## 仅定位东外沿净空。开头明确传送，不作为完整路线交付证据。
func _run() -> void:
	game = (load(GAME_PATH) as PackedScene).instantiate()
	add_child(game)
	level = game.get_node("Level")
	player = game.get_node("Player")
	system = game.get_node("System")
	await _ticks(20)
	player.position = Vector2(3780,840)
	player.velocity = Vector2.ZERO
	system.reset_view_interpolation()
	await _ticks(8)
	print("DEBUG_ONLY: 起点经过传送；仅检查实际东外岸步行和天际跳回。")
	if not await _move_to(4420,550): return
	if not await _jump_to(Vector2(4330,439),true): return
	if not await _move_to(3840,450): return
	if not _require(&"EastMemory" in level.get("discovered"),"真实东段跃回达到天际"): return
	if not await _move_to(4330,450): return
	if not await _jump_to(Vector2(4420,519),true): return
	if not await _jump_to(Vector2(4570,862),true,180): return
	if not await _move_to(3100,1000): return
	var tower := level.get_node("Mid/PageSpine") as LayerObject
	if not await _click_object(tower): return
	await _tap_key(KEY_S)
	if not _require(tower.owner_layer.slot==1,"从真实低路右侧送回塔，不与背景拱腔重叠"): return
	finished = true
	print("ILLUSTRATED_EAST_DEBUG: %d checks, 0 failures"%checks)
	get_tree().quit()
