extends StudySystemController
## 预览和运行共用关卡上的唯一投影Y值。
func _ready() -> void:
	projection_anchor_y = level.editor_projection_anchor_y
	super._ready()
