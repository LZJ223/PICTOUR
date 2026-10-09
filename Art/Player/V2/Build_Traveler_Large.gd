extends SceneTree
## 原创程序精灵：只生成自有 SVG 与 PNG，不处理外部图像。

const CELL := Vector2i(192, 256)
const STATES: Array[String] = ["idle", "walk", "run", "rise", "fall", "dash", "takeoff", "land", "brake", "turn"]
const COUNTS: Array[int] = [8, 16, 16, 6, 6, 4, 4, 4, 4, 4]
const INK := "#40384b"
const PAPER := "#f3ead8"
const SHADE := "#c8b4b6"
const RED := "#c55547"


func _initialize() -> void:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="3072" height="2560" viewBox="0 0 3072 2560">'
	for row in STATES.size():
		for frame in COUNTS[row]:
			svg += '<g transform="translate(%d,%d)">%s</g>' % [frame * CELL.x, row * CELL.y, _draw_traveler(STATES[row], frame, COUNTS[row])]
	svg += "</svg>"
	var bitmap := Image.new()
	var result := bitmap.load_svg_from_string(svg)
	if result != OK:
		push_error("TRAVELER_LARGE_BUILD: SVG 转换失败")
		quit(1)
		return
	_write("res://Art/Player/V2/Traveler_Large_Atlas.svg", svg)
	result = bitmap.save_png("res://Art/Player/V2/Traveler_Large_Atlas.png")
	if result != OK:
		push_error("TRAVELER_LARGE_BUILD: PNG 保存失败")
		quit(1)
		return
	_write("res://Art/Player/V2/Traveler_Large_Frames.tres", _frames_resource())
	print("TRAVELER_LARGE_BUILD: 原创一体衣精灵 72 帧；步行/奔跑各 16 帧；单帧 192×256；脚底 y=236。")
	quit()


func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents + "\n")


func _path(d: String, color: String, stroke: String = INK, width: float = 2.0) -> String:
	return '<path d="%s" fill="%s" stroke="%s" stroke-width="%.2f" stroke-linejoin="round" stroke-linecap="round"/>' % [d, color, stroke, width]


func _line(points: Array[Vector2], color: String, width: float = 3.4, opacity: float = 1.0) -> String:
	var values: Array[String] = []
	for point in points:
		values.append("%.2f,%.2f" % [point.x, point.y])
	return '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.2f" opacity="%.2f" stroke-linecap="round" stroke-linejoin="round"/>' % [" ".join(values), color, width, opacity]


func _leg(hip: Vector2, knee: Vector2, foot: Vector2, far: bool) -> String:
	var result := _line([hip, knee, foot], "#7b6978" if far else INK, 4.0)
	result += _line([foot + Vector2(-2.5, 0), foot + Vector2(7, 0)], INK, 4.0)
	return result


func _draw_traveler(state: String, frame: int, count: int) -> String:
	var phase := float(frame) / float(count) * TAU
	var step := sin(phase)
	var bounce: float = 0.0
	var lean: float = 0.0
	var rear := Vector2(87, 234)
	var front := Vector2(107, 234)
	var rear_knee := Vector2(86, 204)
	var front_knee := Vector2(106, 204)
	var arm_swing: float = 0.0
	var crouch: float = 0.0
	if state == "idle":
		bounce = sin(phase) * 1.3
		arm_swing = sin(phase + 0.8) * 1.8
	elif state == "walk" or state == "run":
		var running := state == "run"
		var amplitude := 43.0 if running else 26.0
		bounce = -absf(cos(phase)) * (5.0 if running else 2.3)
		lean = 11.0 if running else 3.0
		rear.x -= step * amplitude
		front.x += step * amplitude
		rear.y -= maxf(step, 0.0) * (30.0 if running else 15.0)
		front.y -= maxf(-step, 0.0) * (30.0 if running else 15.0)
		rear_knee = Vector2(85 - step * amplitude * 0.35, 202 - maxf(step, 0.0) * 18)
		front_knee = Vector2(109 + step * amplitude * 0.35, 203 - maxf(-step, 0.0) * 18)
		rear_knee.x += cos(phase) * 4.0
		front_knee.x -= cos(phase) * 4.0
		arm_swing = step * (25.0 if running else 14.0)
	elif state == "rise" or state == "takeoff":
		lean = 7.0
		bounce = -3.0 - float(frame) * 0.45
		rear = Vector2(62 - frame, 217 + frame * 0.5)
		front = Vector2(114 + frame, 233)
		rear_knee = Vector2(66, 187)
		front_knee = Vector2(124, 202)
		arm_swing = -24.0 + frame
	elif state == "fall":
		bounce = 1.0 + frame * 0.5
		rear = Vector2(72, 229 + frame * 0.5)
		front = Vector2(118, 234)
		rear_knee = Vector2(76, 197)
		front_knee = Vector2(117, 202)
		arm_swing = -14.0 - frame
	elif state == "dash":
		lean = 24.0
		bounce = 9.0 + sin(phase) * 1.3
		rear = Vector2(47 + frame * 2, 225)
		front = Vector2(130 - frame * 2, 234)
		rear_knee = Vector2(74, 199)
		front_knee = Vector2(129, 208)
		arm_swing = 28.0 - frame * 3
	elif state == "land":
		crouch = (1.0 - float(frame) / 3.0) * 11.0
		bounce = crouch
		rear.x = 78
		front.x = 115
		rear_knee = Vector2(72, 206)
		front_knee = Vector2(126, 206)
		arm_swing = -crouch
	elif state == "brake":
		lean = -12.0 + frame * 2.0
		bounce = 3.0 - frame * 0.7
		rear = Vector2(85 - frame, 234)
		front = Vector2(132 - frame * 4, 234)
		front_knee = Vector2(117, 200)
		arm_swing = -18.0 + frame * 4
	elif state == "turn":
		lean = -8.0 + frame * 3
		bounce = absf(sin(phase)) * 3
		rear.x = 81 - frame
		front.x = 113 + frame
		arm_swing = -12.0 + frame * 5
	var head_x := 97.0 + lean
	var head_y := 57.0 + bounce
	var shoulder_y := 112.0 + bounce
	var hip := Vector2(96 + lean * 0.22, 174 + bounce)
	var art := _leg(hip + Vector2(-8, -3), rear_knee, rear, true)
	# 细线手臂和明显袖口形成具有肩膀的直身轮廓。
	art += _line([Vector2(83 + lean * 0.5, shoulder_y + 8), Vector2(74 - arm_swing * 0.6, 139 + bounce), Vector2(76 - arm_swing, 153 + bounce)], "#8d7784", 4.0)
	art += _path('M %.2f %.2f Q %.2f %.2f %.2f %.2f L %.2f %.2f Q 109 %.2f 81 %.2f L 77 %.2f Z' % [82 + lean * 0.55, shoulder_y, 94 + lean * 0.7, shoulder_y - 4, 110 + lean * 0.55, shoulder_y + 1, 116 + lean * 0.12, 169 + bounce, 181 + bounce, 176 + bounce, 136 + bounce], PAPER)
	art += _path('M %.2f %.2f L 84 %.2f L 85 %.2f Q 88 %.2f 95 %.2f L 89 %.2f Z' % [82 + lean * 0.55, shoulder_y + 2, 133 + bounce, 173 + bounce, 178 + bounce, 177 + bounce, 131 + bounce], SHADE, "none")
	# 工作服腰线、贴袋和针脚是衣着识别点，避免斗篷和长裙。
	art += _line([Vector2(85, 145 + bounce), Vector2(108 + lean * 0.15, 145 + bounce)], "#917887", 1.6, 0.65)
	art += _path('M 99 %.2f L 111 %.2f L 110 %.2f Q 104 %.2f 100 %.2f Z' % [149 + bounce, 149 + bounce, 163 + bounce, 166 + bounce, 162 + bounce], "#e0ccbf", "#a58b98", 1.2)
	art += _line([Vector2(95 + lean * 0.4, 120 + bounce), Vector2(97, 140 + bounce)], "#9d8594", 1.6, 0.72)
	for n in 4:
		art += _line([Vector2(87, 151 + n * 5 + bounce), Vector2(90, 149 + n * 5 + bounce)], "#bba6ad", 0.8, 0.58)
	var sleeve := Vector2(114 + lean * 0.65, shoulder_y + 11)
	art += _line([sleeve, Vector2(125 + arm_swing * 0.45, 137 + bounce), Vector2(126 + arm_swing, 152 + bounce - absf(arm_swing) * 0.2)], INK, 3.5)
	art += _path('M %.2f %.2f L %.2f %.2f L %.2f %.2f L %.2f %.2f Z' % [108 + lean * 0.6, shoulder_y + 1, 119 + lean * 0.6, shoulder_y + 6, 121 + lean * 0.5, shoulder_y + 18, 112 + lean * 0.5, shoulder_y + 20], PAPER, INK, 1.6)
	art += '<circle cx="%.2f" cy="%.2f" r="3.2" fill="%s"/>' % [126 + arm_swing, 152 + bounce - absf(arm_swing) * 0.2, PAPER]
	# 不尖顶的纸发与留白脸，右侧仅一笔眼睛；小卷发使头像与几何衣身不同。
	art += _path('M %.2f %.2f Q %.2f %.2f %.2f %.2f Q %.2f %.2f %.2f %.2f L %.2f %.2f Q %.2f %.2f %.2f %.2f Q %.2f %.2f %.2f %.2f Z' % [head_x - 19, head_y + 13, head_x - 18, head_y - 1, head_x + 1, head_y, head_x + 20, head_y - 2, head_x + 22, head_y + 20, head_x + 19, head_y + 40, head_x + 7, head_y + 53, head_x - 13, head_y + 41, head_x - 24, head_y + 30, head_x - 19, head_y + 13], PAPER)
	art += _path('M %.2f %.2f Q %.2f %.2f %.2f %.2f L %.2f %.2f Q %.2f %.2f %.2f %.2f Z' % [head_x - 19, head_y + 13, head_x - 10, head_y - 1, head_x + 8, head_y + 2, head_x - 8, head_y + 17, head_x - 5, head_y + 32, head_x - 13, head_y + 42], SHADE, "none")
	art += _path('M %.2f %.2f Q %.2f %.2f %.2f %.2f Q %.2f %.2f %.2f %.2f' % [head_x - 12, head_y + 2, head_x - 16, head_y - 5, head_x - 6, head_y - 3, head_x + 4, head_y - 6, head_x + 5, head_y + 3], "none", INK, 1.8)
	art += _line([Vector2(head_x + 13, head_y + 24), Vector2(head_x + 17, head_y + 25)], INK, 1.5)
	art += _line([Vector2(head_x + 18, head_y + 28), Vector2(head_x + 22, head_y + 31), Vector2(head_x + 17, head_y + 32)], "#a17c83", 1.2, 0.85)
	# 围巾领结只留在精灵中；长尾由独立程序丝带负责。
	art += _path('M %.2f %.2f L %.2f %.2f L %.2f %.2f L %.2f %.2f Z' % [head_x - 15, 104 + bounce, head_x + 15, 106 + bounce, head_x + 12, 117 + bounce, head_x - 17, 114 + bounce], RED, "none")
	art += _line([Vector2(head_x - 9, 109 + bounce), Vector2(head_x + 9, 111 + bounce)], "#e29472", 1.6, 0.85)
	art += _leg(hip + Vector2(9, -1), front_knee, front, false)
	return art


func _frames_resource() -> String:
	var total: int = 0
	for count in COUNTS:
		total += count
	var result := '[gd_resource type="SpriteFrames" load_steps=%d format=3]\n\n[ext_resource type="Texture2D" path="res://Art/Player/V2/Traveler_Large_Atlas.png" id="1_atlas"]\n' % (total + 2)
	for row in STATES.size():
		for frame in COUNTS[row]:
			result += '\n[sub_resource type="AtlasTexture" id="Frame_%s_%d"]\natlas = ExtResource("1_atlas")\nregion = Rect2(%d, %d, 192, 256)\n' % [STATES[row], frame, frame * CELL.x, row * CELL.y]
	result += '\n[resource]\nanimations = [\n'
	for row in STATES.size():
		result += '{"frames": [\n'
		for frame in COUNTS[row]:
			result += '{"duration": 1.0, "texture": SubResource("Frame_%s_%d")}%s\n' % [STATES[row], frame, "," if frame < COUNTS[row] - 1 else ""]
		result += '], "loop": %s, "name": &"%s", "speed": 12.0}%s\n' % ["true" if STATES[row] in ["idle", "walk", "run", "dash"] else "false", STATES[row], "," if row < STATES.size() - 1 else ""]
	return result + ']\n'
