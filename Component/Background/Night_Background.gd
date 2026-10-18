## 夜间背景复用原有取景；只有纯色底跟随活动计时器，星点保持固定。
@tool
extends "res://Component/Background/Background.gd"

@export_color_no_alpha var active_color := Color("#141924"):
	set(value):
		active_color = value
		if is_node_ready():
			_sync_color()

## 从全黑恢复到活动色的最长时间；正常倒计时仍保持线性变暗。
@export_range(0.01, 1.0, 0.01, "or_greater") var color_reset_duration: float = 0.15

var _color_progress: float = 1.0
@onready var _sky_color: ColorRect = $SkyColor

func _ready() -> void:
	super._ready()
	_sync_color(color_reset_duration)

func _process(delta: float) -> void:
	_sync_color(delta)

func _sync_color(delta: float = 0.0) -> void:
	var remaining: float = 1.0
	if not Engine.is_editor_hint() and SignalSystem.timer != null:
		remaining = clampf(SignalSystem.timer.time_left / maxf(SignalSystem.timer.wait_time, 0.001), 0.0, 1.0)
	# 限制颜色追赶速度，持续操作每帧重置计时器时也不会反复重启动画。
	_color_progress = move_toward(_color_progress, remaining, delta / maxf(color_reset_duration, 0.001))
	_sky_color.color = Color.BLACK.lerp(active_color, _color_progress)

func _update_layout() -> void:
	super._update_layout()
	## 使用实际取景原点而非屏幕坐标，窗口扩展和对话缩放不会重新排列星点。
	var stars := _sprite.material as ShaderMaterial
	if stars != null:
		stars.set_shader_parameter("region_origin", _sprite.region_rect.position)
