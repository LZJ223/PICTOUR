extends SceneTree

## 本项目原创的几何版画源；以 Godot 的 SVG 栅格器生成 2 倍密度透明 PNG。
## 在项目根目录运行：Godot --headless --path . --script res://Art/Environment/Generate_Environment.gd
const ROOT := "res://Art/Environment/"
const INK := "#3D344A"
const LIGHT := "#B58B96"
const PAPER := "#F2E8D4"
const SAGE := "#A8B8A4"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT + "SVG")
	DirAccess.make_dir_recursive_absolute(ROOT + "PNG")
	_save("Terrain", 128, 128, _terrain())
	_save("Fold_Step", 128, 96, _step())
	_save("Paper_Tree", 100, 650, _tree())
	_save("Paint_Box", 140, 114, _box())
	_save("Page_Bridge", 128, 40, _bridge())
	_save("Tall_Door", 60, 650, _door())
	_save("Transfer_Tag", 36, 40, _tag())
	print("ENVIRONMENT_SPRITES: 7 张原创 SVG 已栅格化为透明 PNG（2 倍密度）。")
	quit()

func _save(asset_name: String, width: int, height: int, content: String) -> void:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [width, height, width, height, content]
	var file := FileAccess.open(ROOT + "SVG/" + asset_name + ".svg", FileAccess.WRITE)
	assert(file != null)
	file.store_string(svg + "\n")
	var bitmap := Image.new()
	var parse_result := bitmap.load_svg_from_string(svg, 2.0)
	assert(parse_result == OK, asset_name + " SVG 解析失败")
	assert(bitmap.save_png(ROOT + "PNG/" + asset_name + ".png") == OK)

func _rect(x: float, y: float, w: float, h: float, fill: String, opacity: float = 1.0) -> String:
	return '<rect x="%s" y="%s" width="%s" height="%s" fill="%s" opacity="%s"/>' % [x, y, w, h, fill, opacity]

func _path(d: String, fill: String, stroke: String = "none", stroke_width: float = 1.0, opacity: float = 1.0) -> String:
	return '<path d="%s" fill="%s" stroke="%s" stroke-width="%s" opacity="%s"/>' % [d, fill, stroke, stroke_width, opacity]

func _engraving(width: int, height: int, spacing: int, seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result := ""
	for i in range(int(float(width * height) / float(spacing * spacing))):
		var x := rng.randf_range(8.0, width - 12.0)
		var y := rng.randf_range(8.0, height - 12.0)
		var length := rng.randf_range(2.0, 6.0)
		result += _path("M %.2f %.2f l %.2f -0.7" % [x, y, length], "none", LIGHT, 0.7, rng.randf_range(0.08, 0.24))
	return result

func _terrain() -> String:
	var body := _rect(0, 0, 128, 128, INK)
	body += _path("M 0 2 H 128 V 15 L 103 17 L 63 12 L 24 16 L 0 13 Z", LIGHT, "none", 1, 0.4)
	body += _path("M 0 34 L 23 29 L 54 34 L 87 27 L 128 31 M 0 62 L 32 57 L 69 61 L 103 55 L 128 58 M 0 103 L 41 95 L 75 103 L 128 94", "none", LIGHT, 1.2, 0.24)
	body += _path("M 13 17 L 7 28 M 60 15 L 53 25 M 102 16 L 94 26", "none", PAPER, 1, 0.23)
	body += _engraving(128, 128, 11, 31)
	return body

func _step() -> String:
	var body := _rect(0, 0, 128, 96, INK)
	body += _path("M 0 0 H 128 L 113 13 H 14 Z", LIGHT, "none", 1, 0.55)
	body += _path("M 0 0 L 14 13 V 83 L 0 96 Z", "#57465F")
	body += _path("M 128 0 L 113 13 V 83 L 128 96 Z", "#51445A")
	body += _path("M 14 13 H 113 V 83 H 14 Z", "none", LIGHT, 1.3, 0.54)
	body += _path("M 17 18 L 23 22 L 19 48 M 108 63 L 105 77 L 92 79 M 35 15 L 30 29", "none", PAPER, 1, 0.2)
	body += _engraving(128, 96, 11, 83)
	return body

func _tree() -> String:
	var body := _rect(0, 0, 100, 650, INK)
	body += _path("M 4 0 H 96 L 87 87 L 100 147 L 86 219 L 93 320 L 88 429 L 96 554 L 91 650 H 9 L 13 551 L 6 456 L 15 323 L 6 219 L 14 120 Z", "#504054")
	body += _path("M 48 650 V 192 C 48 168 40 158 27 147 V 75 M 52 402 C 52 372 73 362 73 333 V 239 M 47 510 C 47 475 22 463 22 435 V 354 M 53 244 C 53 215 78 198 78 174 V 112", "none", LIGHT, 3.5, 0.7)
	body += _path("M 24 77 Q 6 53 17 13 Q 41 12 43 36 Q 40 59 24 77 M 79 113 Q 61 86 66 46 Q 92 45 92 72 Q 89 96 79 113", LIGHT, "none", 1, 0.8)
	body += _path("M 28 85 L 23 24 M 80 112 L 81 61 M 20 354 L 12 319 L 27 294 L 33 326 Z M 75 238 L 60 209 L 80 180 L 88 210 Z", "none", PAPER, 1, 0.42)
	body += _path("M 3 0 H 97 M 8 14 L 6 197 M 7 223 L 9 410 M 9 448 L 7 638 M 93 7 L 95 213 M 93 223 L 94 442 M 94 450 L 92 638", "none", LIGHT, 1, 0.45)
	body += _engraving(100, 650, 16, 187)
	return body

func _box() -> String:
	var body := _rect(0, 0, 140, 114, INK)
	body += _path("M 0 0 H 140 L 127 13 H 13 Z", LIGHT, "none", 1, 0.8)
	body += _rect(8, 17, 124, 89, "#56435C")
	body += _path("M 12 21 H 128 V 48 H 12 Z M 12 55 H 128 V 100 H 12 Z", "none", LIGHT, 1.3, 0.78)
	body += _rect(58, 30, 25, 6, PAPER, 0.65)
	body += _rect(54, 71, 32, 8, PAPER, 0.65)
	body += _path("M 23 98 V 69 M 28 98 V 58 M 34 98 V 75 M 39 98 V 68 M 44 98 V 82 M 98 99 V 61 M 107 98 V 75 M 117 98 V 68", "none", SAGE, 2, 0.56)
	body += _path("M 4 15 V 110 H 136 V 15 M 18 4 H 48 M 91 4 H 123", "none", PAPER, 1.1, 0.35)
	body += _engraving(140, 114, 12, 491)
	return body

func _bridge() -> String:
	var body := _rect(0, 0, 128, 40, INK)
	body += _rect(0, 0, 128, 5, LIGHT, 0.72)
	body += _path("M 0 30 H 128 L 121 40 H 7 Z", "#544459")
	body += _path("M 19 5 V 29 M 47 5 V 29 M 77 5 V 29 M 106 5 V 29 M 0 29 H 128", "none", LIGHT, 1.25, 0.75)
	body += _path("M 23 10 H 41 M 52 22 H 72 M 82 11 H 100 M 111 21 H 124", "none", PAPER, 1, 0.38)
	body += _engraving(128, 40, 9, 337)
	return body

func _door() -> String:
	var body := _rect(0, 0, 60, 650, INK)
	body += _rect(4, 0, 52, 650, "#59465F")
	body += _path("M 8 650 V 37 Q 30 2 52 37 V 650 M 14 650 V 59 Q 30 29 46 59 V 650", "none", LIGHT, 2, 0.78)
	body += _path("M 30 80 L 43 109 L 30 138 L 17 109 Z M 30 220 L 43 249 L 30 278 L 17 249 Z M 30 360 L 43 389 L 30 418 L 17 389 Z M 30 500 L 43 529 L 30 558 L 17 529 Z", "none", PAPER, 1, 0.33)
	body += _rect(37, 571, 5, 16, PAPER, 0.75)
	body += _path("M 4 0 H 56 M 6 638 H 54", "none", LIGHT, 3, 0.5)
	body += _engraving(60, 650, 17, 701)
	return body

func _tag() -> String:
	var body := _path("M 5 2 H 30 V 33 L 18 39 L 5 33 Z", PAPER)
	body += _path("M 8 5 H 27 V 31 L 18 35 L 8 31 Z", "#D76A49")
	body += _path("M 12 18 H 23 M 18 12 L 12 18 L 18 24 M 18 12 L 24 18 L 18 24", "none", PAPER, 1.4)
	body += _path("M 8 4 H 27", "none", INK, 1.2, 0.4)
	return body
