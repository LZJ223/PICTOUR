extends SceneTree
## 原创矢量精灵源；固定腿骨与支撑脚轨迹来自同一姿态表。

const Pose = preload("res://Art/Player/V3/Traveler_Pose.gd")
const INK := "#463744"
const FAR_INK := "#9a808a"
const PAPER := "#e8dac2"
const SHADE := "#baa4a0"
const RED := "#b64637"


func _initialize() -> void:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="4096" height="2560" viewBox="0 0 4096 2560">'
	for row in Pose.STATES.size():
		for frame in Pose.COUNTS[row]:
			svg += '<g transform="translate(%d,%d)">%s</g>' % [frame * 256, row * 256, _figure(Pose.STATES[row], float(frame) / Pose.COUNTS[row])]
	svg += '</svg>'
	var bitmap := Image.new()
	if bitmap.load_svg_from_string(svg) != OK:
		push_error("TRAVELER_V3_BUILD: 无法栅格化原创 SVG")
		quit(1)
		return
	_write("res://Art/Player/V3/Traveler_V3_Atlas.svg", svg)
	if bitmap.save_png("res://Art/Player/V3/Traveler_V3_Atlas.png") != OK:
		quit(1)
		return
	_write("res://Art/Player/V3/Traveler_V3_Frames.tres", _frames())
	# 直接输出姿态板，方便检查正侧面、支撑与腾空，不编辑任何参考图。
	var sheet := '<svg xmlns="http://www.w3.org/2000/svg" width="1536" height="540" viewBox="0 0 1536 540"><rect width="1536" height="540" fill="#eee5cf"/>'
	for row in 2:
		for i in 8:
			sheet += '<g transform="translate(%d,%d)"><path d="M0 236H192" stroke="#c6b5a6"/>' % [i * 192 - 32, row * 270]
			sheet += _figure(&"walk" if row == 0 else &"run", float(i) / 8.0) + '</g>'
	sheet += '</svg>'
	var preview := Image.new()
	preview.load_svg_from_string(sheet)
	preview.save_png("res://Art/Player/V3/Traveler_V3_Poses.png")
	print("TRAVELER_V3_BUILD: 72 帧，侧视工作服；走跑各 16 帧，固定双骨 IK，奔跑双脚离地。")
	quit()


func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents + "\n")


func _v(point: Vector2) -> String:
	return "%.2f %.2f" % [point.x, point.y]


func _path(data: String, fill: String, stroke: String = "none", width: float = 1.4) -> String:
	return '<path d="%s" fill="%s" stroke="%s" stroke-width="%.2f" stroke-linejoin="round" stroke-linecap="round"/>' % [data, fill, stroke, width]


func _line(points: Array[Vector2], color: String, width: float = 3.2) -> String:
	var data := "M " + _v(points[0])
	for i in range(1, points.size()):
		data += " L " + _v(points[i])
	return _path(data, "none", color, width)


func _leg(hip: Vector2, knee: Vector2, foot: Vector2, far: bool) -> String:
	var color := FAR_INK if far else INK
	return _line([hip, knee, foot + Vector2(0, -2)], color, 3.8) + _line([foot + Vector2(-2, -1), foot + Vector2(7, -1)], color, 3.2)


func _figure(action: StringName, phase: float) -> String:
	var p: Dictionary = Pose.pose(action, phase)
	var h: Vector2 = p.hip
	var s: Vector2 = p.shoulder
	var head: Vector2 = p.head
	var result := _leg(p.far_hip, p.far_knee, p.far_foot, true)
	# 袖臂都在侧面矢状平面运动，远臂不从左侧肩膀横伸。
	result += _line([s + Vector2(-4, 2), p.far_elbow, p.far_hand], FAR_INK, 6.2)
	result += _leg(p.near_hip, p.near_knee, p.near_foot, false)
	# 收身的一体式短工作衣：侧面开叉、长方贴袋，保留臀部与双腿。
	result += _path("M " + _v(s + Vector2(-11, -3)) + " Q " + _v(s + Vector2(0, -8)) + " " + _v(s + Vector2(11, -3)) + " L " + _v(h + Vector2(15, 5)) + " L " + _v(h + Vector2(3, 9)) + " L " + _v(h + Vector2(0, 4)) + " L " + _v(h + Vector2(-12, 9)) + " Q " + _v(h + Vector2(-19, -4)) + " " + _v(s + Vector2(-11, -3)) + " Z", PAPER, INK, 1.15)
	result += _path("M " + _v(s + Vector2(-11, -2)) + " Q " + _v(h + Vector2(-15, -17)) + " " + _v(h + Vector2(-12, 8)) + " L " + _v(h + Vector2(-3, 6)) + " L " + _v(s + Vector2(-5, 2)) + " Z", SHADE)
	result += _path("M " + _v(h + Vector2(3, -16)) + " l 10 -1 l 0 10 q -5 4 -10 1 Z", "#d1bdae", "#9e8389", 0.8)
	result += _line([s + Vector2(7, 3), h + Vector2(7, -24)], "#ad9292", 1.0)
	# 稀疏哑光针脚和印墨缺口，不使用厚重卡通描边或塑料高光。
	for i in 4:
		result += _line([h + Vector2(-7, -21 + i * 5), h + Vector2(-4, -22 + i * 5)], "#d7c5b3", 0.8)
	var elbow: Vector2 = p.near_elbow
	var hand: Vector2 = p.near_hand
	result += _line([s + Vector2(1, 4), elbow], INK, 8.0)
	result += _line([s + Vector2(1, 4), elbow], PAPER, 6.4)
	result += _line([elbow, hand], INK, 3.2)
	result += _line([hand + Vector2(-1, 0), hand + Vector2(3, -1)], PAPER, 3.4)
	# 留白侧脸与偏向后脑的短发，不用尖帽与蓝色长发轮廓。
	result += _path("M " + _v(head + Vector2(-10, -18)) + " Q " + _v(head + Vector2(11, -22)) + " " + _v(head + Vector2(15, -5)) + " L " + _v(head + Vector2(18, 0)) + " L " + _v(head + Vector2(14, 3)) + " Q " + _v(head + Vector2(14, 18)) + " " + _v(head + Vector2(1, 19)) + " L " + _v(head + Vector2(-6, 26)) + " L " + _v(head + Vector2(-14, 18)) + " Q " + _v(head + Vector2(-23, 0)) + " " + _v(head + Vector2(-10, -18)) + " Z", "#ead9bd", INK, 1.0)
	result += _path("M " + _v(head + Vector2(-17, 9)) + " Q " + _v(head + Vector2(-27, -6)) + " " + _v(head + Vector2(-13, -19)) + " L " + _v(head + Vector2(-16, -22)) + " Q " + _v(head + Vector2(4, -26)) + " " + _v(head + Vector2(14, -15)) + " Q " + _v(head + Vector2(10, -7)) + " " + _v(head + Vector2(-1, -8)) + " L " + _v(head + Vector2(-5, 4)) + " L " + _v(head + Vector2(-10, 3)) + " L " + _v(head + Vector2(-10, 16)) + " Z", INK)
	result += _line([head + Vector2(-17, -8), head + Vector2(-8, -16), head + Vector2(3, -16)], "#75616a", 1.2)
	result += _line([head + Vector2(9, -2), head + Vector2(12, -2)], INK, 1.3)
	# 平织领圈与独立围巾衔接，无闪亮中线。
	var collar: Vector2 = p.collar
	result += _path("M " + _v(collar + Vector2(-2, -3)) + " l 25 2 l -2 10 l -25 -2 Z", RED)
	result += _line([collar + Vector2(0, 5), collar + Vector2(18, 6)], "#923e38", 0.8)
	return result


func _frames() -> String:
	var total := 0
	for count in Pose.COUNTS:
		total += count
	var text := '[gd_resource type="SpriteFrames" load_steps=%d format=3]\n\n[ext_resource type="Texture2D" path="res://Art/Player/V3/Traveler_V3_Atlas.png" id="1_atlas"]\n' % (total + 2)
	for row in Pose.STATES.size():
		for index in Pose.COUNTS[row]:
			text += '\n[sub_resource type="AtlasTexture" id="Frame_%s_%d"]\natlas = ExtResource("1_atlas")\nregion = Rect2(%d, %d, 256, 256)\n' % [Pose.STATES[row], index, index * 256, row * 256]
	text += '\n[resource]\nanimations = [\n'
	for row in Pose.STATES.size():
		text += '{"frames": [\n'
		for index in Pose.COUNTS[row]:
			text += '{"duration": 1.0, "texture": SubResource("Frame_%s_%d")}%s\n' % [Pose.STATES[row], index, "," if index + 1 < Pose.COUNTS[row] else ""]
		text += '], "loop": true, "name": &"%s", "speed": 12.0}%s\n' % [Pose.STATES[row], "," if row + 1 < Pose.STATES.size() else ""]
	return text + ']\n'
