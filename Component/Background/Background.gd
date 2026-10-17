## 核心区域映射设计窗口；冗余和越界部分由 Sprite 原生采样 clamp。
@tool
extends CanvasLayer

@export var design_size := Vector2(1280, 720):
	set(value):
		design_size = value.max(Vector2.ONE)
		if is_node_ready():
			_update_layout()

@export var core_size := Vector2(2560, 1440):
	set(value):
		core_size = value.max(Vector2.ONE)
		if is_node_ready():
			_update_layout()

@onready var _frame: Control = $Frame
@onready var _sprite: Sprite2D = $Frame/Sprite
var _zoom_ratio := Vector2.ONE
var _screen_shift := Vector2.ZERO

func _ready() -> void:
	add_to_group(&"level_backgrounds")
	get_viewport().size_changed.connect(_update_layout)
	_sprite.texture_changed.connect(_update_layout)
	_update_layout()

## 相机控制器统一传入镜头相对正常构图的缩放与屏幕位移。
func set_camera_framing(zoom_ratio: Vector2, screen_shift: Vector2) -> void:
	_zoom_ratio = zoom_ratio.max(Vector2.ONE * 0.0001)
	_screen_shift = screen_shift
	_update_layout()

func _update_layout() -> void:
	if _sprite.texture == null:
		return
	var view_size := design_size if Engine.is_editor_hint() else get_viewport().get_visible_rect().size
	var pixel_scale := design_size / core_size * _zoom_ratio
	## Sprite 的区域几何按像素取整，向外覆盖并居中补偿以避免亚像素缝隙。
	var region_size := (view_size / pixel_scale).ceil()
	var region_origin := (_sprite.texture.get_size() - region_size) * 0.5 - _screen_shift / pixel_scale
	_frame.position = (view_size - region_size * pixel_scale) * 0.5
	_frame.size = region_size
	_frame.scale = pixel_scale
	## 允许 region 超出贴图；Repeat Disabled 会延展边缘，而不是露黑或重复。
	_sprite.region_rect = Rect2(region_origin, region_size)
