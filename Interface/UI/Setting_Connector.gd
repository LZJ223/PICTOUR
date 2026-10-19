## 标签和操作控件之间的装饰虚线；跟随手动布局，在编辑器和运行时均可预览。
@tool
extends Control

@export var label_path: NodePath = NodePath("../Label")
@export var target_path: NodePath = NodePath("../Key")
@export var line_color := Color(0.04, 0.5, 0.24, 0.6):
	set(value):
		line_color = value
		queue_redraw()
@export_range(0.0, 128.0, 1.0) var minimum_gap: float = 2.0:
	set(value):
		minimum_gap = value
		queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := get_node_or_null(label_path) as Label
	var target := get_node_or_null(target_path) as Control
	for control: Control in [label, target]:
		if control != null:
			control.item_rect_changed.connect(queue_redraw)
			control.minimum_size_changed.connect(queue_redraw)
			control.theme_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var label := get_node_or_null(label_path) as Label
	var target := get_node_or_null(target_path) as Control
	if label == null or target == null or label.text.is_empty():
		return
	var font := label.get_theme_font("font")
	var width := minf(label.size.x, font.get_string_size(
		label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")
	).x)
	var text_left: float = 0.0
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER:
		text_left = (label.size.x - width) * 0.5
	elif label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		text_left = label.size.x - width
	var inverse := get_global_transform().affine_inverse()
	var start := inverse * label.get_global_transform() * Vector2(text_left + width, label.size.y * 0.5)
	var end := inverse * target.get_global_transform() * Vector2.ZERO
	start.x += 4.0
	end.x -= 4.0
	if end.x - start.x < minimum_gap:
		return
	var dash := minf(6.0, (end.x - start.x) / 3.0)
	draw_dashed_line(start, Vector2(end.x, start.y), line_color, 2.0, dash, true, true)
