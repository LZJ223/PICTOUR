## 持久化黑幕；场景只提出请求，加载与动画不依赖即将离场的节点。
extends CanvasLayer

signal transition_finished

const MAIN_SCENE := "res://Interface/Main.tscn"
const GAME_SCENE := "res://Interface/Game.tscn"
const LEVEL_PATH := "res://Level/Level_%02d.tscn"

@export_range(0.0, 2.0, 0.05, "or_greater") var fade_out_duration: float = 0.75
@export_range(0.0, 2.0, 0.05, "or_greater") var fade_in_duration: float = 0.75

var busy: bool = true
var _initial_scene: bool = true
var _black: ColorRect
var _next_play_dialogue: bool = true

func consume_dialogue_request() -> bool:
	var play_dialogue := _next_play_dialogue
	_next_play_dialogue = true
	return play_dialogue

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 128
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_black)
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().paused = true
	PhysicsServer2D.set_active(false)

## Main、Game 在首帧布局完成后通知；普通切换由切换协程负责淡入。
func scene_ready() -> void:
	if _initial_scene:
		_initial_scene = false
		_reveal_initial_scene.call_deferred()

func _reveal_initial_scene() -> void:
	PhysicsServer2D.set_active(false)
	await get_tree().process_frame
	await _fade(0.0, fade_in_duration)
	_finish(false)

func enter_level(level_id: int, keep_scene_running: bool = false, play_dialogue: bool = true) -> Error:
	if level_id < 1 or level_id > 12:
		push_error("无效的关卡编号：%d" % level_id)
		return ERR_INVALID_PARAMETER
	return await _change_scene(GAME_SCENE, level_id, keep_scene_running, play_dialogue)

func enter_main_menu(keep_scene_running: bool = false) -> Error:
	return await _change_scene(MAIN_SCENE, 0, keep_scene_running)

func quit_game() -> void:
	if busy:
		return
	_begin()
	await _fade(1.0, fade_out_duration)
	await get_tree().process_frame
	get_tree().quit()

func _change_scene(path: String, level_id: int = 0, keep_scene_running: bool = false, play_dialogue: bool = true) -> Error:
	if busy:
		return ERR_BUSY
	var was_paused: bool = get_tree().paused
	var previous_level_id: int = Global.next_level_id
	var previous_dialogue: bool = _next_play_dialogue
	_begin(keep_scene_running)
	await _fade(1.0, fade_out_duration)
	## 结算演出持续到全黑，之后与普通转场共用冻结、清理和淡入流程。
	get_tree().paused = true
	PhysicsServer2D.set_active(false)
	## 先让全黑画面提交一帧，再进行可能耗时的同步加载。
	await get_tree().process_frame
	var scene: PackedScene = load(path) as PackedScene if ResourceLoader.exists(path) else null
	var level_exists: bool = level_id == 0 or ResourceLoader.exists(LEVEL_PATH % level_id)
	var error: Error = ERR_CANT_OPEN
	if scene != null and level_exists:
		Global.next_level_id = level_id if level_id > 0 else 1
		_next_play_dialogue = play_dialogue
		error = get_tree().change_scene_to_packed(scene)
	if error == OK:
		await get_tree().scene_changed
		## 新场景的初始化可能唤醒物理服务器，淡入完成前继续冻结。
		PhysicsServer2D.set_active(false)
		await get_tree().process_frame
	else:
		Global.next_level_id = previous_level_id
		_next_play_dialogue = previous_dialogue
		push_error("场景切换失败（%s，关卡 %d）：%s" % [path, level_id, error_string(error)])
	await _fade(0.0, fade_in_duration)
	_finish(false if error == OK else was_paused)
	return error

func _begin(keep_scene_running: bool = false) -> void:
	busy = true
	get_tree().paused = not keep_scene_running
	PhysicsServer2D.set_active(keep_scene_running)
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	_black.show()

func _fade(alpha: float, duration: float) -> void:
	if duration <= 0.0:
		_black.color.a = alpha
		return
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_black, "color:a", alpha, duration).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

func _finish(paused: bool) -> void:
	_black.hide()
	busy = false
	get_tree().paused = paused
	## 失败时保留原场景的休息状态；菜单没有玩家，不受休息计时影响。
	PhysicsServer2D.set_active(not paused and (
		not is_instance_valid(Global.player) or not SignalSystem.timer.is_stopped()
	))
	transition_finished.emit()
