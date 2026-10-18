@tool
class_name CloudRoundProfile
extends Resource

## 半径与精度均以 CollisionBox 的本地单位计，随物体一起缩放。
@export_range(0.0, 4096.0, 0.5, "or_greater") var outer_radius: float = 32.0
@export_range(0.0, 4096.0, 0.5, "or_greater") var inner_radius: float = 8.0
## 圆弧与采样折线之间允许的最大距离。
@export_range(0.01, 4.0, 0.01, "or_greater") var max_chord_error: float = 0.5
## 限制碰撞多边形复杂度；超限时可适当提高弦误差。
@export_range(16, 4096, 16) var max_vertices: int = 1024


func validation_error() -> String:
	if not is_finite(outer_radius) or not is_finite(inner_radius) or outer_radius < 0.0 or inner_radius < 0.0:
		return "圆角半径必须是有限的非负数。"
	if inner_radius > outer_radius:
		return "内角半径不能大于外角半径。"
	if not is_finite(max_chord_error) or max_chord_error < 0.01:
		return "圆弧最大弦误差至少为 0.01。"
	if max_vertices < 16 or max_vertices > 4096:
		return "最大顶点数应在 16～4096 之间。"
	return ""
