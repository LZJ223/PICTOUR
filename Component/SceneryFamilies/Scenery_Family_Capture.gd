extends "res://Component/SceneryFamilies/Scenery_Family_Catalog.gd"

func _ready() -> void:
	super._ready()
	call_deferred("_capture_catalog")

func _capture_catalog() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("目录截图需要实际 GPU 窗口。")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://Exports/SceneryFamilies")
	for family_index in range(3):
		_family_index = family_index
		_build_world()
		await _save_frame("%02d_%s_mid"%[family_index+1,SceneryFamilyLibrary.FAMILIES[family_index]])
		for object in _pieces:
			_system.transfer(-1,object)
		await _save_frame("%02d_%s_back"%[family_index+1,SceneryFamilyLibrary.FAMILIES[family_index]])
	preview_layer_count = 4
	_family_index = 2
	_build_world()
	for index in range(_pieces.size()):
		var object := _pieces[index]
		while object.owner_layer.slot!=index:
			_system.transfer(1 if object.owner_layer.slot>index else -1,object)
	await _save_frame("04_arcade_four_layers")
	print("Scenery family GPU catalog: 7 captures")
	get_tree().quit()

func _save_frame(filename: String) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://Exports/SceneryFamilies/%s.png"%filename)
