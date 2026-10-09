extends SceneTree
## 读取透明母图和手校足点，创建无损 AtlasTexture 资源。
## 不修改原 PNG，不做逐帧缩放，不用几何图形替代位图角色。

const DIRECTORY := "res://Art/Player/V4/"
const ACTIONS := {
	"idle": ["actions", [0, 1]],
	"walk": ["walk", [0, 1, 2, 3, 4, 5, 6, 7]],
	"run": ["run", [0, 1, 2, 3, 4, 5, 6, 7]],
	"takeoff": ["actions", [2]],
	"rise": ["actions", [3]],
	"apex": ["actions", [4]],
	"fall": ["actions", [5]],
	"land": ["actions", [6]],
	"brake": ["actions", [7]],
}


func _initialize() -> void:
	var path := DIRECTORY + "Traveler_V4_Layout.json"
	if not FileAccess.file_exists(path):
		push_error("TRAVELER_V4_BUILD: 缺少经画面检查的格网与锚点布局。")
		quit(1)
		return
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var metadata: Dictionary = {
		"version": 1, "scale": float(layout.scale),
		"canvas": layout.canvas, "canvas_pivot": layout.canvas_pivot,
		"walk_stride": float(layout.walk_stride), "run_stride": float(layout.run_stride),
		"animations": {}, "source_sheets": {},
	}
	var atlas_sources := ""
	var resources := ""
	var animations := ""
	var total_frames := 0
	var sheet_data: Dictionary = {}
	for key: String in layout.sheets:
		var sheet: Dictionary = layout.sheets[key]
		var bitmap := Image.load_from_file(ProjectSettings.globalize_path(sheet.path))
		if bitmap == null or bitmap.is_empty():
			push_error("TRAVELER_V4_BUILD: 无法读取 " + str(sheet.path))
			quit(1)
			return
		var columns: int = int(sheet.grid[0])
		var rows: int = int(sheet.grid[1])
		var size := Vector2i(bitmap.get_width() / columns, bitmap.get_height() / rows)
		var cells: Array = []
		for i in columns * rows:
			var rectangle := Rect2i(Vector2i(i % columns, i / columns) * size, size)
			var source_area := rectangle
			if sheet.has("regions"):
				var supplied: Array = sheet.regions[i]
				source_area = Rect2i(supplied[0], supplied[1], supplied[2], supplied[3])
			var occupied := _occupied(bitmap, source_area)
			var red := _collar(bitmap, source_area) + Vector2(source_area.position - rectangle.position)
			var root := Vector2(sheet.roots[i][0], sheet.roots[i][1])
			if sheet.has("collars") and i < sheet.collars.size():
				red = Vector2(sheet.collars[i][0], sheet.collars[i][1])
			var cell: Dictionary = {"rect": rectangle, "occupied": occupied, "root": root, "collar": red}
			cells.append(cell)
			print("TRAVELER_V4_CELL: %s/%d bounds=%s root=%s collar=%s" % [key, i, str(occupied), str(root), str(red)])
		sheet_data[key] = {"image": bitmap, "cells": cells, "cell_size": size, "path": sheet.path}
		metadata.source_sheets[key] = {"path": sheet.path, "grid": sheet.grid, "width": bitmap.get_width(), "height": bitmap.get_height()}
		atlas_sources += '[ext_resource type="Texture2D" path="%s" id="%s"]\n' % [sheet.path, key]
	for action: String in ACTIONS:
		var definition: Array = ACTIONS[action]
		var sheet_key: String = definition[0]
		var indexes: Array = definition[1]
		var per_frame_meta: Array = []
		var frame_refs := ""
		for output_index in indexes.size():
			var source_index: int = int(indexes[output_index])
			var cell: Dictionary = sheet_data[sheet_key].cells[source_index]
			var occupied: Rect2i = cell.occupied
			var cell_rect: Rect2i = cell.rect
			var canvas := Vector2(layout.canvas[0], layout.canvas[1])
			var pivot := Vector2(layout.canvas_pivot[0], layout.canvas_pivot[1])
			var margin_origin: Vector2 = Vector2(occupied.position - cell_rect.position) - Vector2(cell.root) + pivot
			var margin_size := canvas - Vector2(occupied.size)
			var identifier := "%s_%d" % [action, output_index]
			resources += '\n[sub_resource type="AtlasTexture" id="%s"]\natlas = ExtResource("%s")\nregion = Rect2(%d, %d, %d, %d)\nmargin = Rect2(%.3f, %.3f, %.3f, %.3f)\nfilter_clip = true\n' % [identifier, sheet_key, occupied.position.x, occupied.position.y, occupied.size.x, occupied.size.y, margin_origin.x, margin_origin.y, margin_size.x, margin_size.y]
			frame_refs += '{"duration": 1.0, "texture": SubResource("%s")},\n' % identifier
			var collar_offset: Vector2 = (Vector2(cell.collar) - Vector2(cell.root)) * float(layout.scale)
			var foot_y: float = (occupied.end.y - cell_rect.position.y - float(cell.root.y)) * float(layout.scale)
			per_frame_meta.append({"sheet": sheet_key, "source_frame": source_index, "collar": [collar_offset.x, collar_offset.y], "lowest_pixel_y": foot_y, "source_root": [cell.root.x, cell.root.y], "source_bounds": [occupied.position.x, occupied.position.y, occupied.size.x, occupied.size.y]})
			total_frames += 1
		metadata.animations[action] = per_frame_meta
		animations += '{"frames": [\n%s], "loop": true, "name": &"%s", "speed": 12.0},\n' % [frame_refs, action]
	var frames := '[gd_resource type="SpriteFrames" load_steps=%d format=3]\n\n%s%s\n[resource]\nanimations = [\n%s]\n' % [1 + layout.sheets.size() + total_frames, atlas_sources, resources, animations]
	_write(DIRECTORY + "Traveler_V4_Frames.tres", frames)
	_write(DIRECTORY + "Traveler_V4_Metadata.json", JSON.stringify(metadata, "\t") + "\n")
	print("TRAVELER_V4_BUILD: %d AI生成原始位图帧；仅裁切、透明边距与锚点，无像素重绘。" % total_frames)
	quit(0)


func _occupied(bitmap: Image, rectangle: Rect2i) -> Rect2i:
	var minimum := rectangle.end
	var maximum := rectangle.position
	var found := false
	for y in range(rectangle.position.y, rectangle.end.y):
		for x in range(rectangle.position.x, rectangle.end.x):
			if bitmap.get_pixel(x, y).a < 0.12:
				continue
			minimum.x = mini(minimum.x, x)
			minimum.y = mini(minimum.y, y)
			maximum.x = maxi(maximum.x, x)
			maximum.y = maxi(maximum.y, y)
			found = true
	if not found:
		push_error("TRAVELER_V4_BUILD: 空白单元格 " + str(rectangle))
		return rectangle
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)


func _collar(bitmap: Image, rectangle: Rect2i) -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for y in range(rectangle.position.y, rectangle.end.y):
		for x in range(rectangle.position.x, rectangle.end.x):
			var pixel := bitmap.get_pixel(x, y)
			if pixel.a > 0.6 and pixel.r > 0.42 and pixel.g < pixel.r * 0.72 and pixel.b < pixel.r * 0.68:
				sum += Vector2(x - rectangle.position.x, y - rectangle.position.y)
				count += 1
	return sum / count if count > 0 else Vector2(rectangle.size.x * 0.5, rectangle.size.y * 0.2)


func _write(path: String, contents: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(contents)
