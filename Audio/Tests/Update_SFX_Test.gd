## 使用 .godot/audio_qa/ 内的隔离用户目录，验证音源和真实收集入口。
extends Node

var _checks: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error("UPDATE_SFX_TEST: " + message)

func _run() -> void:
	if not "/.godot/audio_qa/" in OS.get_user_data_dir().replace("\\", "/"):
		push_error("请为音效回归设置 .godot/audio_qa/ 内的隔离用户目录")
		get_tree().quit(2)
		return
	for cue: StringName in [&"opening_piano", &"collection_triangle"]:
		var stream := SoundPlayer._make_stream(cue, false) as AudioStreamWAV
		_check(stream != null, "%s 音源可加载" % cue)
		if stream == null:
			continue
		_check(stream.stereo and stream.mix_rate == 44100 and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s 为非循环的 44.1 kHz 立体声" % cue)
		var expected_duration: float = 6.4 if cue == &"opening_piano" else 2.3
		_check(absf(stream.get_length() - expected_duration) < 0.01, "%s 保留完整自然衰减" % cue)
		var playback := stream.instantiate_playback()
		playback.start()
		var frames := playback.mix_audio(1.0, 22050)
		var peak: float = 0.0
		for frame in frames:
			peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		_check(peak > 0.1 and peak < 0.8, "%s 真实解码有声且留有峰值余量" % cue)
	_check(SaveSystem.set_audio_volume("SFX", 35.0) == OK, "音效音量设置可保存")
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))), 0.35), "新音效复用现有音效音量总线")
	SaveSystem.set_audio_volume("SFX", 100.0)
	SaveSystem.reset_progress()
	SceneTransition.begin_opening()
	var game: Node2D = load("res://Interface/Game.tscn").instantiate()
	game.play_dialogue = false
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	Global.player.set_physics_process(false)
	SceneTransition._opening_active = false
	SceneTransition.busy = false
	get_tree().paused = false
	var layer := Global.get_layer_at_slot(Global.current_layer_index)
	var letter: LetterCollectible = load("res://Component/Collection/Collection.tscn").instantiate()
	letter.character = "I"
	letter.position = Vector2(10000, -10000)
	layer.add_child(letter)
	var cursor: int = SoundPlayer._cursor
	var other := Node2D.new()
	add_child(other)
	letter._area.body_entered.emit(other)
	Global.player.current_state = PlayerController.PlayerState.UAV
	letter._area.body_entered.emit(Global.player)
	Global.player.current_state = PlayerController.PlayerState.NORMAL
	var original_layer: int = Global.current_layer_index
	Global.current_layer_index = (original_layer + 1) % Global.layer_count
	letter._area.body_entered.emit(Global.player)
	Global.current_layer_index = original_layer
	SignalSystem.dialogue_active = true
	letter._area.body_entered.emit(Global.player)
	SignalSystem.dialogue_active = false
	get_tree().paused = true
	letter._area.body_entered.emit(Global.player)
	get_tree().paused = false
	_check(SoundPlayer._cursor == cursor and letter._state == LetterCollectible.State.IDLE, "其他物体、无人机、其他图层、对话及暂停不会误播收集音效")
	letter._area.body_entered.emit(Global.player)
	_check(letter._state == LetterCollectible.State.COLLECTING and SoundPlayer._cursor == (cursor + 1) % SoundPlayer.POOL_SIZE, "有效拾取开始时立即播放一次三角铁")
	var player: AudioStreamPlayer = SoundPlayer._players[cursor]
	_check(player.playing and player.stream.resource_path == SoundPlayer.CUES["collection_triangle"] and player.bus == &"SFX", "收集音效由全局 SFX 通道实际播放")
	letter._area.body_entered.emit(Global.player)
	_check(SoundPlayer._cursor == (cursor + 1) % SoundPlayer.POOL_SIZE, "动画期间重复碰撞不重复发声")
	await get_tree().create_timer(0.8).timeout
	_check(letter._state == LetterCollectible.State.DISABLED and SaveSystem.is_character_collected("I"), "收集动画及存档流程正常完成")
	_check(player.playing, "物件停用后不会截断三角铁余音")
	var duplicate: LetterCollectible = load("res://Component/Collection/Collection.tscn").instantiate()
	duplicate.character = "I"
	layer.add_child(duplicate)
	duplicate._area.body_entered.emit(Global.player)
	_check(duplicate._state == LetterCollectible.State.DISABLED and SoundPlayer._cursor == (cursor + 1) % SoundPlayer.POOL_SIZE, "已收集的同字母实例不发声")
	game.queue_free()
	await get_tree().process_frame
	print("UPDATE_SFX_TEST_RESULT ", JSON.stringify({"checks": _checks, "failures": _failures}))
	get_tree().quit(0 if _failures.is_empty() else 1)
