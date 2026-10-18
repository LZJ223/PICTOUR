extends SceneTree

const Output = preload("res://addons/texture_baker_common/bake_output.gd")
const LeafWriter = preload("res://addons/leaf_baker/leaf_scene_writer.gd")
const TrunkWriter = preload("res://addons/trunk_baker/trunk_scene_writer.gd")

var _failures := 0
var _test_directory: String


func _initialize() -> void:
	_test_directory = "res://.godot/baker_output_tests/%d" % Time.get_ticks_usec()
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check(file != null, "Cannot write test fixture: " + path)
	if file != null:
		file.store_string(content)
		file.close()


func _run() -> void:
	_test_custom_package()
	_test_defaults()
	_test_invalid_requests()
	_test_metadata_conflicts()
	if _failures == 0:
		print("BAKER_OUTPUT_TESTS_OK custom_name=true parent_directory=true defaults=true conflicts=true no_overwrite=true")
	quit(0 if _failures == 0 else 1)


func _test_custom_package() -> void:
	var parent := _test_directory.path_join("custom/nested")
	var output := Output.reserve_directory(parent, "Soil_02", "", "Soil")
	_check(output.error.is_empty(), "Custom package could not be reserved")
	if not output.error.is_empty():
		return
	_check(output.directory == parent.path_join("Soil_02"), "Package did not use custom parent/name")
	_check(output.base == parent.path_join("Soil_02/Soil_02"), "Resource base is outside package")
	_check(Output.texture_path(output, 1) == output.base + "_001.png", "First PNG name is incorrect")
	_check(Output.texture_path(output, 1001) == output.base + "_1001.png", "PNG numbering was truncated")
	# An existing empty directory is already a conflict.
	_check(not Output.reserve_directory(parent, "Soil_02", "", "Soil").error.is_empty(), "Empty package was reused")
	_check(DirAccess.get_files_at(output.directory).is_empty(), "Conflict created files")
	_write(output.base + ".tscn", "do not overwrite")
	var before := DirAccess.get_files_at(output.directory)
	_check(not Output.reserve_directory(parent, "soil_02", "", "Soil").error.is_empty(), "Windows case-insensitive conflict was missed")
	_check(not Output.reserve_directory(parent, "Soil_02", "", "Soil").error.is_empty(), "Populated package was reused")
	_check(FileAccess.get_file_as_string(output.base + ".tscn") == "do not overwrite", "Conflict overwrote a scene")
	_check(DirAccess.get_files_at(output.directory) == before, "Conflict added files")
	_write(parent.path_join("Leaf_02"), "same-name file")
	_check(not LeafWriter.reserve_directory(parent, "Leaf_02").error.is_empty(), "Same-name file was not a conflict")
	_check(FileAccess.get_file_as_string(parent.path_join("Leaf_02")) == "same-name file", "Conflict overwrote a file")
	var chinese := Output.reserve_directory(parent, "树干_02", "", "Trunk")
	_check(chinese.error.is_empty() and chinese.name == "树干_02", "Unicode custom name was rejected")


func _test_defaults() -> void:
	var parent := _test_directory.path_join("defaults")
	for prefix in ["Soil", "Leaf", "Trunk"]:
		var first := Output.reserve_directory("", "", parent, prefix)
		var second := Output.reserve_directory("", "", parent, prefix)
		_check(first.error.is_empty() and first.name == prefix + "_001", "Blank fields did not use defaults")
		_check(second.error.is_empty() and second.name == prefix + "_002", "Automatic numbering reused a directory")
	_write(parent.path_join("Trunk_003"), "number occupied by a file")
	var trunk := TrunkWriter.reserve_directory(parent)
	_check(trunk.error.is_empty() and trunk.name == "Trunk_004", "Trunk default prefix or occupied-file skipping is incorrect")
	var leaf := LeafWriter.reserve_directory(parent)
	_check(leaf.error.is_empty() and leaf.name == "Leaf_003", "Leaf default prefix is incorrect")
	var absolute := ProjectSettings.globalize_path(parent)
	var output := Output.reserve_directory(absolute, "Absolute", "", "Soil")
	_check(output.error.is_empty() and output.directory.begins_with("res://"), "Absolute in-project parent was not localized")
	output = Output.reserve_directory(parent.trim_prefix("res://"), "Relative", "", "Soil")
	_check(output.error.is_empty() and output.directory.begins_with(parent), "Project-relative parent was not supported")


func _test_invalid_requests() -> void:
	var parent := _test_directory.path_join("must_not_be_created")
	for name in ["../escape", "a/b", "a\\b", "a:bad", "bad?", "bad.tscn", ".", "..", "CON", "nul", "COM1", "bad\nname"]:
		_check(not Output.reserve_directory(parent, name, "", "Soil").error.is_empty(), "Invalid name accepted: " + name)
	_check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(parent)), "Invalid names created parent directory")
	for path in ["res://../OutsideProject", "user://BakerOutputs", "res://Invalid?Parent", "res://CON/Outputs"]:
		_check(not Output.reserve_directory(path, "Reject", "", "Soil").error.is_empty(), "Invalid parent accepted: " + path)


func _test_metadata_conflicts() -> void:
	var parent := _test_directory.path_join("metadata")
	for suffix in [".tscn", ".tres", ".recipe.json"]:
		var output := Output.reserve_directory(parent, "", "", "Soil")
		_check(Output.metadata_conflict(output).is_empty(), "New package reported a conflict")
		_write(output.base + suffix, "sentinel")
		# This preflight also runs before either writer packs/saves any resources.
		var saved := LeafWriter.save_result({}, {}, [], output)
		_check(not saved.error.is_empty(), "Leaf writer overwrote conflicting metadata")
		saved = TrunkWriter.save_result({}, {}, [], output)
		_check(not saved.error.is_empty(), "Trunk writer overwrote conflicting metadata")
		_check(FileAccess.get_file_as_string(output.base + suffix) == "sentinel", "Metadata sentinel was changed")
		_check(DirAccess.get_files_at(output.directory).size() == 1, "Metadata conflict wrote partial output")
