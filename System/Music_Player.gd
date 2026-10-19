## 界面与关卡的单曲循环。只负责播放，不参与玩法。
## 曲目按文件名对应：mainscene 为主界面，1-1 到 1-4、2-1 到 2-4、3-1 到 3-4 依次为第 1 到第 12 关。
extends Node

const FADE_SECONDS := 1.0
const MENU_TRACK := "res://Audio/Music/mainscene.ogg"
const LEVELS_PER_GROUP := 4
const LEVEL_TRACK := "res://Audio/Music/%d-%d.ogg"
const BUS_NAME := "Music"

var music_linear: float = 1.0

var _players: Array[AudioStreamPlayer] = []
var _tweens: Array[Tween] = []
var _fade_target: Array[float] = []
var _active: int = 0
var _current_key: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_music_bus()
	for _index in 2:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_NAME
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		player.volume_db = linear_to_db(0.0001)
		add_child(player)
		_players.append(player)
		_tweens.append(null)
		_fade_target.append(0.0)

## 供以后的音量设置调用。1 为原音量。
func set_music_volume(linear: float) -> void:
	music_linear = clampf(linear, 0.0, 1.0)
	if _players.is_empty():
		return
	var player := _players[_active]
	if player.playing:
		player.volume_db = linear_to_db(maxf(music_linear, 0.0001))

func play_main_menu() -> void:
	_play(MENU_TRACK, "menu")

func play_level(level_id: int) -> void:
	var group := (level_id - 1) / LEVELS_PER_GROUP + 1
	var index := (level_id - 1) % LEVELS_PER_GROUP + 1
	_play(LEVEL_TRACK % [group, index], "level:%d" % level_id)

## 画面开始切走时淡出。失败时由 restore 把同一首淡回来。
func begin_transition() -> void:
	if _players.is_empty():
		return
	_fade(_players[_active], 0.0, true)

func restore() -> void:
	if _current_key.is_empty():
		return
	var player := _players[_active]
	if player.stream != null and not player.playing:
		player.play()
	_fade(player, 1.0, false)

func _play(path: String, key: String) -> void:
	if key == _current_key and _players[_active].playing and db_to_linear(_players[_active].volume_db) > 0.85:
		return
	if not ResourceLoader.exists(path):
		push_error("找不到音乐：%s" % path)
		return
	var stream := load(path) as AudioStream
	if stream == null:
		push_error("音乐无法加载：%s" % path)
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var incoming := 1 - _active
	var next := _players[incoming]
	next.stream = stream
	next.volume_db = linear_to_db(0.0001)
	next.play()
	if not _is_fading_out(_players[_active]):
		_fade(_players[_active], 0.0, true)
	_fade(next, 1.0, false)
	_active = incoming
	_current_key = key

func _fade(player: AudioStreamPlayer, target_linear: float, stop_when_silent: bool) -> void:
	var index := _players.find(player)
	if index < 0:
		return
	if _tweens[index] != null and _tweens[index].is_valid():
		_tweens[index].kill()
	_fade_target[index] = target_linear
	var from := db_to_linear(player.volume_db)
	var target := target_linear * music_linear
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tweens[index] = tween
	tween.tween_method(_set_linear.bind(player), from, target, FADE_SECONDS).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	if stop_when_silent:
		tween.finished.connect(_stop_if_inactive.bind(player), CONNECT_ONE_SHOT)

func _set_linear(linear: float, player: AudioStreamPlayer) -> void:
	player.volume_db = linear_to_db(maxf(linear, 0.0001))

func _is_fading_out(player: AudioStreamPlayer) -> bool:
	var index := _players.find(player)
	return (
		index >= 0
		and _fade_target[index] <= 0.001
		and _tweens[index] != null
		and _tweens[index].is_valid()
		and _tweens[index].is_running()
	)

func _stop_if_inactive(player: AudioStreamPlayer) -> void:
	if player != _players[_active]:
		player.stop()

func _ensure_music_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, &"Master")
