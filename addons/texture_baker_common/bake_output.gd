@tool
extends RefCounted


## Reserve a new package before rendering anything. An explicit name is never
## renamed or merged with an existing package, including an empty directory.
static func reserve_directory(parent: String, requested_name: String, default_parent: String, prefix: String) -> Dictionary:
	var resolved := _resolve_parent(parent if not parent.strip_edges().is_empty() else default_parent)
	if not resolved.error.is_empty():
		return resolved
	var directory: String = resolved.directory
	var name := requested_name.strip_edges()
	if name.is_empty():
		var index := 1
		name = "%s_%03d" % [prefix, index]
		while _exists(directory.path_join(name)):
			index += 1
			name = "%s_%03d" % [prefix, index]
	else:
		if not name.is_valid_filename() or name.validate_node_name() != name or name.ends_with(".") or _reserved_name(name):
			return {"error": "素材名称无效，请填写不含路径和扩展名的文件名。"}
		for index in range(name.length()):
			if name.unicode_at(index) < 32:
				return {"error": "素材名称不能包含控制字符。"}
	var package := directory.path_join(name)
	var conflict := ensure_absent(PackedStringArray([package]))
	if not conflict.is_empty():
		return {"error": conflict}
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK:
		return {"error": "无法创建输出父目录（错误 %d）：%s" % [error, directory]}
	# make_dir (not recursive) reserves this exact new package exclusively.
	error = DirAccess.make_dir_absolute(ProjectSettings.globalize_path(package))
	if error != OK:
		return {"error": "素材目录已存在或无法创建，已拒绝输出（错误 %d）：%s" % [error, package]}
	return {"error": "", "name": name, "directory": package, "base": package.path_join(name)}


static func texture_path(output: Dictionary, index: int) -> String:
	return "%s_%03d.png" % [output.base, index]


static func ensure_absent(paths: PackedStringArray) -> String:
	for path in paths:
		if _exists(path):
			return "目标已存在，已拒绝输出：%s" % path
	return ""


static func metadata_conflict(output: Dictionary) -> String:
	return ensure_absent(PackedStringArray([output.base + ".tscn", output.base + ".tres", output.base + ".recipe.json"]))


static func _exists(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	return FileAccess.file_exists(absolute) or DirAccess.dir_exists_absolute(absolute)


static func _resolve_parent(value: String) -> Dictionary:
	var path := value.strip_edges().replace("\\", "/")
	if path.contains("://") and not path.begins_with("res://"):
		return {"error": "请选择项目内的输出父目录（res://），以便 Godot 导入和加载贴图。"}
	if not path.begins_with("res://") and not path.is_absolute_path():
		path = "res://".path_join(path)
	path = ProjectSettings.localize_path(ProjectSettings.globalize_path(path).simplify_path())
	if not path.begins_with("res://"):
		return {"error": "请选择项目内的输出父目录（res://），以便 Godot 导入和加载贴图。"}
	for segment in path.trim_prefix("res://").split("/", false):
		if not segment.is_valid_filename() or segment.ends_with(".") or segment.ends_with(" ") or _reserved_name(segment):
			return {"error": "输出父目录包含无效的目录名：%s" % segment}
	return {"error": "", "directory": path.trim_suffix("/") if path != "res://" else path}


static func _reserved_name(value: String) -> bool:
	var stem := value.get_slice(".", 0).to_upper()
	return stem in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]
