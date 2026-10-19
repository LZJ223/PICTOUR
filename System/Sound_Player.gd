## 操作音效。短音效只播一次，不淡入淡出，也不循环。
## 跟随着操作的长音效走独立通道，操作结束时立刻停掉，不会继续播完。
## 音效包里没有的操作保持安静。按钮共用 ui_press，旁白打字借用玩家说话声。
extends Node

const BUS_NAME := "SFX"
const POOL_SIZE := 8

const CUES := {
	"player_step": "res://Audio/SFX/player_step.mp3",
	"player_jump": "res://Audio/SFX/player_jump.mp3",
	"player_land": "res://Audio/SFX/player_land.mp3",
	"uav_on": "res://Audio/SFX/uav_on.mp3",
	"uav_move": "res://Audio/SFX/uav_move.mp3",
	"uav_off": "res://Audio/SFX/uav_off.mp3",
	"uav_fail": "res://Audio/SFX/layer_cycle_fail.mp3",
	"layer_cycle": "res://Audio/SFX/layer_cycle.mp3",
	"layer_cycle_fail": "res://Audio/SFX/layer_cycle_fail.mp3",
	"transfer_tree": "res://Audio/SFX/transfer_tree.mp3",
	"tree_transform_1": "res://Audio/SFX/tree-transform1.mp3",
	"tree_transform_3": "res://Audio/SFX/tree-transform3.mp3",
	"transfer_bush": "res://Audio/SFX/transfer_bush.mp3",
	"transfer_cloud": "res://Audio/SFX/transfer_cloud.mp3",
	"transfer_box": "res://Audio/SFX/transfer_box.mp3",
	"transfer_fail": "res://Audio/SFX/transfer_fail.mp3",
	"select": "res://Audio/SFX/select.mp3",
	"destination_in": "res://Audio/SFX/destination_in.mp3",
	"goal": "res://Audio/SFX/goal.mp3",
	"dialogue_player": "res://Audio/SFX/dialogue_player.mp3",
	"dialogue_spirit": "res://Audio/SFX/dialogue_spirit.mp3",
	"ui_press": "res://Audio/SFX/ui_press.mp3",
}

const TREE_CUES: Array[String] = ["transfer_tree", "tree_transform_1", "tree_transform_3"]

var _players: Array[AudioStreamPlayer] = []
var _cursor: int = 0
var _channels: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_sfx_bus()
	for _index in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_NAME
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_players.append(player)

func play(cue: StringName) -> void:
	var stream := _make_stream(cue)
	if stream == null:
		return
	var player := _players[_cursor]
	_cursor = (_cursor + 1) % POOL_SIZE
	player.stop()
	player.stream = stream
	player.play()

## 长音效独占一条通道。同一条通道再次播放会换掉上一段，stop 会立刻停掉它。
func play_for(channel: StringName, cue: StringName) -> void:
	var player := _channel_player(channel)
	var stream := _make_stream(cue)
	player.stop()
	if stream == null:
		return
	player.stream = stream
	player.play()

func stop(channel: StringName) -> void:
	var player: AudioStreamPlayer = _channels.get(channel)
	if player != null:
		player.stop()

## 切场景时停掉还挂在操作上的长音效。过关音是结果，留给它自己播完。
func stop_actions() -> void:
	for channel: StringName in [&"dialogue", &"uav_move", &"destination", &"jump"]:
		stop(channel)

func play_transfer(object: LayerObject) -> void:
	var scene_path := object.scene_file_path
	if scene_path.contains("Tree"):
		play(TREE_CUES[randi() % TREE_CUES.size()])
	elif scene_path.contains("Bush") or scene_path.contains("Brush"):
		play(&"transfer_bush")
	elif scene_path.contains("Cloud"):
		play(&"transfer_cloud")
	elif scene_path.contains("Box"):
		play(&"transfer_box")

func play_dialogue(speaker: int) -> void:
	var cue: StringName = (
		&"dialogue_spirit"
		if speaker == DialogueLine.Speaker.BOOK_SPIRIT
		else &"dialogue_player"
	)
	play_for(&"dialogue", cue)

func _make_stream(cue: StringName) -> AudioStream:
	var path: String = CUES.get(cue, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var stream := load(path) as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	return stream

func _channel_player(channel: StringName) -> AudioStreamPlayer:
	var existing: AudioStreamPlayer = _channels.get(channel)
	if existing != null:
		return existing
	var player := AudioStreamPlayer.new()
	player.bus = BUS_NAME
	## 跟操作走的声音在暂停时一起停住，短按钮音仍走始终播放的音源池。
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	_channels[channel] = player
	return player

func _ensure_sfx_bus() -> void:
	if AudioServer.get_bus_index(BUS_NAME) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS_NAME)
	AudioServer.set_bus_send(index, &"Master")
