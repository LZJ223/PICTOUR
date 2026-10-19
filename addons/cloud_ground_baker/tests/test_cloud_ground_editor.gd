extends SceneTree

const Geometry = preload("res://addons/cloud_ground_baker/cloud_ground_geometry.gd")
const Writer = preload("res://addons/cloud_ground_baker/cloud_ground_scene_writer.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("CLOUD_GROUND_EDITOR: " + message)


func _run() -> void:
	for frame in range(40):
		await process_frame
	var plugin: EditorPlugin
	for candidate in root.find_children("*", "EditorPlugin", true, false):
		if candidate.get_script() != null and candidate.get_script().resource_path == "res://addons/cloud_ground_baker/plugin.gd":
			plugin = candidate
	check(plugin != null, "Plugin did not activate")
	if plugin == null:
		quit(1)
		return
	var template := "res://Component/Shadowed_Geometry/Shadowed_Ground.tscn"
	var original_hash := FileAccess.get_sha256(template)
	var source := load(template).instantiate() as StaticBody2D
	var points := PackedVector2Array([Vector2(0, 140), Vector2(450, 140), Vector2(450, 0), Vector2(1200, 0), Vector2(1200, 420), Vector2(0, 420)])
	for path in ["CollisionBox", "VisualRoot/Polygon2D", "Shadow"]:
		source.get_node(NodePath(path)).polygon = points
	source.transform = Transform2D(0.3, Vector2(1.2, 0.9), 0.1, Vector2(2000, 600))
	source.get_node("CollisionBox").scale = Vector2(1.3, 0.8)
	var original_transform := source.transform
	root.add_child(source)
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(source)
	await process_frame
	check(plugin.get("_source") == source, "Live selection not recognized")
	plugin.get("_profile").tile_size_px = 256
	plugin.call("_preview_pressed")
	check(plugin.get("_preview").texture != null, "Preview missing")
	var controls: VBoxContainer = plugin.get("_output_controls")
	var parent := "res://Generated/CloudGroundEditorTest_%d" % Time.get_ticks_usec()
	controls.directory_edit.text = parent
	controls.name_edit.text = "CloudGround_Custom_02"
	plugin.call("_save_pressed")
	while plugin.get("_busy"):
		await process_frame
	var status: Label = plugin.get("_status")
	check(status.text.begins_with("完成："), "Save failed: " + status.text)
	var base := parent.path_join("CloudGround_Custom_02/CloudGround_Custom_02")
	var path := base + ".tscn"
	if FileAccess.file_exists(path):
		var instance := load(path).instantiate() as StaticBody2D
		check(instance.transform.is_equal_approx(Transform2D.IDENTITY), "Saved root has a transform")
		check(Geometry.area_centroid(instance.get_node("CollisionBox").polygon).length() < 0.001, "Saved contour is off-center")
		check(instance.get("can_leave_shadow") and not instance.get("can_be_shadowed"), "Saved shadow flags incorrect")
		check(instance.get_node_or_null("VisualRoot/Area2D") == null, "Save added a pick area")
		var dots := instance.get_node("VisualRoot/CloudDots")
		check(dots.get_child_count() >= 4, "Live contour was not tiled")
		for index in range(dots.get_child_count()):
			var sprite := dots.get_child(index) as Sprite2D
			var expected := "%s_%03d.png" % [base, index + 1]
			check(sprite.texture.resource_path == expected, "Texture path/order is incorrect")
			check(sprite.texture.get_width() <= 264 and sprite.texture.get_height() <= 240, "Texture includes empty body pixels")
		check(not FileAccess.get_file_as_string(path).contains('[sub_resource type="Image"'), "Scene embeds raster data")
		instance.free()
		check(FileAccess.file_exists(base + ".tres") and FileAccess.file_exists(base + ".recipe.json"), "Parameter/recipe files missing")
		var before := FileAccess.get_sha256(path)
		plugin.call("_save_pressed")
		check(status.text.contains("拒绝输出") and FileAccess.get_sha256(path) == before, "Conflicting package was overwritten")
	# An empty dot strip is valid and should save just the native scene/resources.
	plugin.get("_profile").cloud_depth = 0.0
	controls.name_edit.text = ""
	plugin.call("_save_pressed")
	while plugin.get("_busy"):
		await process_frame
	check(status.text.begins_with("完成："), "Empty strip save failed: " + status.text)
	var default_base := parent.path_join("CloudGround_001/CloudGround_001")
	check(FileAccess.file_exists(default_base + ".tscn"), "Default name is not CloudGround_001")
	check(not FileAccess.file_exists(default_base + "_001.png"), "Empty strip exported a PNG")
	check(not Writer.reserve_directory(parent, "CloudGround_001").error.is_empty(), "Directory conflict was accepted")
	source.get_node("CollisionBox").polygon = PackedVector2Array([Vector2.ZERO, Vector2(40, 40), Vector2(0, 40), Vector2(40, 0)])
	controls.name_edit.text = "Invalid"
	plugin.call("_save_pressed")
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(parent.path_join("Invalid"))), "Invalid contour created files")
	check(source.transform.is_equal_approx(original_transform), "Source placement was changed")
	check(FileAccess.get_sha256(template) == original_hash, "Source scene file changed")
	selection.clear()
	await process_frame
	source.free()
	# The unique output directory is retained for GPU QA or manual inspection.
	var record := FileAccess.open("res://.godot/cloud_ground_editor_package.txt", FileAccess.WRITE)
	record.store_string(parent)
	record.close()
	for frame in range(10):
		await process_frame
	print("CLOUD_GROUND_EDITOR_RESULT checks=%d failures=%d package=%s" % [checks, failures, parent])
	quit(0 if failures == 0 else 1)
