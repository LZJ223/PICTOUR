extends SceneTree

## 原创程序绘图：从保存的 SVG 源生成纸纹与叙事物件 PNG。
const OUTPUT := "res://Art/Scenery/"

func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	var grain := ""
	for index in range(1400):
		grain += '<ellipse cx="%.2f" cy="%.2f" rx="%.2f" ry="%.2f" fill="#72644f" opacity="%.3f"/>' % [rng.randf_range(0, 512), rng.randf_range(0, 512), rng.randf_range(0.3, 1.3), rng.randf_range(0.25, 0.8), rng.randf_range(0.02, 0.065)]
	_save_svg("Paper_Grain", 512, 512, '<rect width="512" height="512" fill="#f2e8d4"/>' + grain)
	var ink := '<path d="M48 7 C43 28 18 45 19 62 C19 87 78 91 78 62 C78 43 54 26 48 7Z" fill="#4d5b8c" stroke="#3d344a" stroke-width="2"/><path d="M43 30 C38 43 29 47 29 57" fill="none" stroke="#e7dfcd" stroke-width="3" opacity="0.65"/><ellipse cx="47" cy="72" rx="10" ry="5" fill="#f2e8d4" opacity="0.8"/><path d="M20 92 L76 92 L68 101 L28 101Z" fill="#3d344a"/><path d="M28 95 L69 95" stroke="#b58b96" stroke-width="2"/>'
	_save_svg("Ink_Drop", 96, 112, ink)
	var plate := '<path d="M4 11 L91 8 L91 19 L4 19Z" fill="#d76a49"/><path d="M4 20 L91 20 L82 28 L12 28Z" fill="#3d344a"/><path d="M15 13 L81 12" stroke="#f2e8d4" stroke-width="2"/><path d="M39 15 L46 10 L53 15 L46 19Z" fill="#f2e8d4"/>'
	_save_svg("Ink_Seal_Plate", 96, 32, plate)
	var frame := '<rect x="8" y="8" width="344" height="244" rx="2" fill="#3d344a"/><rect x="18" y="18" width="324" height="224" fill="#b58b96"/><rect x="28" y="28" width="304" height="204" fill="#efe2c8"/><path d="M14 18 L348 18 M18 12 L18 248 M14 244 L348 244 M344 12 L344 248" stroke="#f2e8d4" opacity="0.6"/><path d="M36 34 L324 34 M34 40 L34 222" stroke="#c7b893" stroke-width="2"/><path d="M166 8 L180 0 L194 8" fill="none" stroke="#3d344a" stroke-width="2"/>'
	_save_svg("Canvas_Frame", 360, 260, frame)
	var sprout := '<path d="M28 157 L28 33 M28 104 L12 79 M28 76 L46 54" stroke="#6b556a" stroke-width="3" fill="none"/><path d="M27 60 L3 41 L7 22 L28 48Z M30 90 L53 75 L52 59 L30 78Z" fill="#b58b96"/><path d="M27 41 L5 11 L26 4 L48 11 L30 41Z" fill="#3d344a"/><path d="M27 40 L26 7 M24 37 L12 15 M30 35 L40 14" stroke="#f2e8d4" opacity="0.6"/>'
	_save_svg("Fan_Plant", 56, 164, sprout)
	print("SCENERY_BUILT: five original PNG sprites and SVG sources")
	quit()

func _save_svg(asset_name: String, width: int, height: int, body: String) -> void:
	var source := '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [width, height, width, height, body]
	var file := FileAccess.open(OUTPUT + asset_name + ".svg", FileAccess.WRITE)
	file.store_string(source + "\n")
	file.close()
	var bitmap := Image.new()
	var result := bitmap.load_svg_from_string(source, 2.0)
	assert(result == OK, "SVG栅格化失败：" + asset_name)
	assert(bitmap.save_png(OUTPUT + asset_name + ".png") == OK, "PNG保存失败：" + asset_name)
