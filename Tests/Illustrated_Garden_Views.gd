extends Node
var game: Node2D
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	get_window().size = Vector2i(1280,720)
	game = (load("res://Illustrated_Garden_Game.tscn") as PackedScene).instantiate()
	add_child(game)
	await _ticks(20)
	game.get_node("Level")._notes.visible = false
	var player := game.get_node("Player") as PlayerController
	var system := game.get_node("System") as StudySystemController
	for shot in [["01_start",Vector2(360,1300)],["02_root",Vector2(1740,1000)],["03_page_spine",Vector2(2540,1250)],["04_bridge",Vector2(3300,884)],["05_sky",Vector2(4190,323)]]:
		player.global_position = shot[1]
		player.velocity = Vector2.ZERO
		system.reset_view_interpolation()
		await _ticks(3)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://Exports/Illustrated_Garden")
		get_viewport().get_texture().get_image().save_png("res://Exports/Illustrated_Garden/%s.png"%shot[0])
	# 仅供整体构图审阅；运行关卡仍使用正常镜头与玩家位置投影。
	player.global_position = Vector2(360,1300)
	player.velocity = Vector2.ZERO
	system.camera_fixed = false
	var camera := game.get_node("Camera") as Camera2D
	camera.zoom = Vector2(0.25,0.25)
	camera.global_position = Vector2(2350,720)
	system.reset_view_interpolation()
	await _ticks(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://Exports/Illustrated_Garden/06_overview.png")
	get_tree().quit()
func _ticks(count: int) -> void:
	for n in count: await get_tree().physics_frame
