extends Node
## 核对编辑器所读Level值也是运行和初始撤回历史的唯一来源。
var checks := 0
var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("GARDEN_PROJECTION: " + message)


func _run() -> void:
	for expected in [920.0, 1060.0]:
		var game := (load("res://Illustrated_Garden_Game.tscn") as PackedScene).instantiate()
		var level := game.get_node("Level")
		if expected == 920:
			_check(is_equal_approx(float(level.get("editor_projection_anchor_y")), expected), "实际新地图默认基准920")
		else:
			level.set("editor_projection_anchor_y", expected)
		add_child(game)
		var system := game.get_node("System") as StudySystemController
		_check(is_equal_approx(system.projection_anchor_y, expected), "System初始化从Level读取基准：%s" % expected)
		_check(is_equal_approx(Vector2(system.history._initial.anchor).y, expected), "首份R基线已使用同源基准：%s" % expected)
		for tick in 4:
			await get_tree().physics_frame
			await get_tree().process_frame
		_check(is_equal_approx(system.get_projection_anchor().y, expected), "实际投影持续使用同源值：%s" % expected)
		game.queue_free()
		await get_tree().process_frame
		await get_tree().physics_frame
	print("GARDEN_PROJECTION: %d checks, %d failures." % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)
