extends SceneTree
## 原创程序美术源：生成透明 PNG 与可编辑 SpriteFrames，不读取或修改参考图。
## 使用 Godot --headless --path . --script res://Art/Player/Build_Traveler.gd 重建。

const CELL_SIZE := Vector2i(96, 128)
const STATES: Array[String] = ["idle", "walk", "run", "rise", "fall", "dash"]
const SPEEDS: Array[float] = [6.0, 12.0, 16.0, 10.0, 10.0, 28.0]
const INK := "#3d344a"
const PAPER := "#f6ecd8"
const SHADE := "#c9b6b8"
const SCARF := "#d76a49"


func _initialize() -> void:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="768" height="768" viewBox="0 0 768 768">'
	for row in STATES.size():
		for frame in 8:
			svg += '<g transform="translate(%d,%d)">%s</g>' % [frame * CELL_SIZE.x, row * CELL_SIZE.y, _draw_traveler(STATES[row], frame)]
	svg += "</svg>"
	var image := Image.new()
	var result := image.load_svg_from_string(svg)
	if result != OK:
		push_error("TRAVELER_BUILD: SVG 栅格化失败 %d" % result)
		quit(1)
		return
	_write("res://Art/Player/Traveler_Atlas.svg", svg)
	result = image.save_png("res://Art/Player/Traveler_Atlas.png")
	if result != OK:
		push_error("TRAVELER_BUILD: PNG 保存失败 %d" % result)
		quit(1)
		return
	_write("res://Art/Player/Traveler_Frames.tres", _sprite_frames_text())
	print("TRAVELER_BUILD: 768×768 PNG，6 组动作，每组 8 帧；含描边足底边界 (48,115)。")
	quit()


func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents + "\n")


func _polygon(points: PackedVector2Array, color: String, outline: bool = true) -> String:
	var coordinates: Array[String] = []
	for point in points:
		coordinates.append("%.2f,%.2f" % [point.x, point.y])
	return '<polygon points="%s" fill="%s" stroke="%s" stroke-width="2" stroke-linejoin="round"/>' % [" ".join(coordinates), color, INK if outline else "none"]


func _line(points: PackedVector2Array, color: String, width: float = 1.3, opacity: float = 1.0) -> String:
	var coordinates: Array[String] = []
	for point in points:
		coordinates.append("%.2f,%.2f" % [point.x, point.y])
	return '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.2f" stroke-opacity="%.2f" stroke-linecap="round" stroke-linejoin="round"/>' % [" ".join(coordinates), color, width, opacity]


func _draw_traveler(state: String, frame: int) -> String:
	var phase := float(frame) / 8.0 * TAU
	var step := sin(phase)
	var lift := absf(cos(phase))
	var head_x: float = 48.0
	var head_y: float = 32.0
	var hem_y: float = 101.0
	var back_foot := Vector2(41, 112)
	var front_foot := Vector2(55, 112)
	var arm := Vector2(61, 83)
	var scarf_y: float = 61.0
	if state == "idle":
		head_y += sin(phase) * 0.7
		hem_y += sin(phase) * 0.25
	elif state == "walk":
		head_x += 1.0
		head_y -= lift * 0.8
		back_foot.x -= step * 10.0
		front_foot.x += step * 10.0
		if step > 0.0:
			back_foot.y -= step * 5.0
		else:
			front_foot.y += step * 5.0
		arm.x -= step * 5.0
	elif state == "run":
		head_x += 7.0
		head_y += 2.5 - lift * 1.4
		hem_y -= lift * 1.0
		back_foot.x -= step * 17.0
		front_foot.x += step * 17.0
		if step > 0.0:
			back_foot.y -= step * 15.0
		else:
			front_foot.y += step * 15.0
		arm = Vector2(66 - step * 6.0, 78 - lift * 3.0)
	elif state == "rise":
		head_x += 3.0
		head_y -= 1.0
		hem_y -= 2.0
		back_foot = Vector2(35 - cos(phase) * 2.0, 104 + sin(phase) * 1.0)
		front_foot = Vector2(59 + cos(phase) * 2.0, 110)
		arm = Vector2(67, 65 + sin(phase) * 1.5)
	elif state == "fall":
		head_y += 1.0
		hem_y -= 1.0
		back_foot = Vector2(36 - cos(phase) * 2.0, 109)
		front_foot = Vector2(60 + cos(phase) * 2.0, 112)
		arm = Vector2(68, 69 + sin(phase) * 2.0)
	elif state == "dash":
		head_x += 12.0
		head_y += 7.0
		hem_y -= 3.0
		back_foot = Vector2(25 + step * 4.0, 107)
		front_foot = Vector2(63 + step * 4.0, 112)
		arm = Vector2(70, 81 + lift * 1.0)
		scarf_y += 4.0
	var drawing := ""
	# 身体后侧的腿：站立时脚底相同，步行/奔跑的另一只脚离地。
	drawing += _line(PackedVector2Array([Vector2(43, 95), Vector2(39, 103), back_foot]), INK, 5.2)
	drawing += _line(PackedVector2Array([back_foot + Vector2(-3, 0), back_foot + Vector2(5, 0)]), INK, 3.0)
	# 围巾摆幅只改变纹理帧，不移动节点或碰撞。
	var scarf_tip := Vector2(18.0, scarf_y + sin(phase + 0.7) * 3.0)
	if state == "run" or state == "dash":
		scarf_tip.x = 8.0
		scarf_tip.y -= 3.0
	elif state == "rise":
		scarf_tip.y += 12.0
	elif state == "fall":
		scarf_tip.y -= 13.0
	drawing += _polygon(PackedVector2Array([Vector2(head_x - 8, 60), Vector2(28, scarf_y - 3), scarf_tip, scarf_tip + Vector2(5, 7), Vector2(28, scarf_y + 3), Vector2(head_x - 7, 67)]), SCARF, false)
	drawing += _line(PackedVector2Array([Vector2(29, scarf_y), scarf_tip + Vector2(6, 3)]), "#a7493f", 1.0, 0.8)
	# 不对称纸斗篷：主要躯干约 18 像素宽，脚底与 20×40 碰撞保持贴近。
	var robe := PackedVector2Array([Vector2(head_x - 10, 60), Vector2(head_x + 6, 61), Vector2(64, hem_y - 3), Vector2(52, hem_y + 2), Vector2(32, hem_y), Vector2(37, 74)])
	drawing += _polygon(robe, PAPER)
	drawing += _polygon(PackedVector2Array([Vector2(head_x - 9, 63), Vector2(39, 77), Vector2(33, hem_y - 1), Vector2(40, hem_y), Vector2(46, 77)]), SHADE, false)
	drawing += _line(PackedVector2Array([Vector2(head_x + 2, 70), Vector2(53, 84), Vector2(58, hem_y - 8)]), INK, 1.0, 0.65)
	drawing += _line(PackedVector2Array([Vector2(head_x + 3, 67), Vector2(58, 77), arm]), INK, 2.0)
	drawing += '<circle cx="%.2f" cy="%.2f" r="2" fill="%s"/>' % [arm.x, arm.y, PAPER]
	# 静态刻线与薄墨，数量克制，避免缩小后高频闪动。
	for index in 5:
		var line_y := 75.0 + float(index) * 3.5
		drawing += _line(PackedVector2Array([Vector2(43, line_y), Vector2(47.5, line_y - 1.4)]), "#bca6b0", 0.65, 0.52)
	# 面部留白，侧边是折起的纸页；没有与参考游戏相同的发型或衣裙。
	var hood := PackedVector2Array([Vector2(head_x - 8, head_y), Vector2(head_x + 10, head_y + 7), Vector2(head_x + 14, head_y + 20), Vector2(head_x + 4, head_y + 31), Vector2(head_x - 11, head_y + 26), Vector2(head_x - 16, head_y + 13)])
	drawing += _polygon(hood, PAPER)
	drawing += _polygon(PackedVector2Array([Vector2(head_x - 8, head_y + 2), Vector2(head_x - 13, head_y + 14), Vector2(head_x - 9, head_y + 25), Vector2(head_x - 3, head_y + 28), Vector2(head_x - 6, head_y + 15)]), SHADE, false)
	drawing += _line(PackedVector2Array([Vector2(head_x + 8, head_y + 9), Vector2(head_x + 5, head_y + 19), Vector2(head_x + 8, head_y + 25)]), INK, 1.0, 0.65)
	drawing += _polygon(PackedVector2Array([Vector2(head_x - 10, 59), Vector2(head_x + 7, 60), Vector2(head_x + 5, 66), Vector2(head_x - 9, 65)]), SCARF, false)
	# 前侧小脚完成剪影，固定最下方像素不越过 y=112。
	drawing += _line(PackedVector2Array([Vector2(53, 98), Vector2(56, 104), front_foot]), INK, 4.2)
	drawing += _line(PackedVector2Array([front_foot + Vector2(-2, 0), front_foot + Vector2(5, 0)]), INK, 2.6)
	return drawing


func _sprite_frames_text() -> String:
	var resource := '[gd_resource type="SpriteFrames" load_steps=50 format=3]\n\n[ext_resource type="Texture2D" path="res://Art/Player/Traveler_Atlas.png" id="1_atlas"]\n'
	for row in STATES.size():
		for frame in 8:
			var id := row * 8 + frame
			resource += '\n[sub_resource type="AtlasTexture" id="AtlasTexture_%d"]\natlas = ExtResource("1_atlas")\nregion = Rect2(%d, %d, 96, 128)\n' % [id, frame * 96, row * 128]
	resource += "\n[resource]\nanimations = [\n"
	for row in STATES.size():
		resource += '{\n"frames": [\n'
		for frame in 8:
			resource += '{"duration": 1.0, "texture": SubResource("AtlasTexture_%d")}%s\n' % [row * 8 + frame, "," if frame < 7 else ""]
		resource += '],\n"loop": true,\n"name": &"%s",\n"speed": %.1f\n}%s\n' % [STATES[row], SPEEDS[row], "," if row < STATES.size() - 1 else ""]
	resource += "]\n"
	return resource
