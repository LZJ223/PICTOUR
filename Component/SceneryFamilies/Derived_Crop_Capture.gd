extends Node2D

func _ready() -> void:
	var atmosphere := PaperAtmosphere.new()
	add_child(atmosphere)
	var level := Level.new()
	level.layer_count = 2
	level.current_layer_index = 0
	add_child(level)
	var layer := DepthLayer.new()
	layer.layer_id = 0
	layer.slot = 0
	level.add_child(layer)
	var botanical := "--botanical" in OS.get_cmdline_user_args()
	var ids := DerivedCropLibrary.BOTANICAL_IDS if botanical else DerivedCropLibrary.IDS
	for index in range(ids.size()):
		var object := DerivedCropLibrary.create_botanical(ids[index]) if botanical else DerivedCropLibrary.create_piece(ids[index])
		object.position = Vector2(165+(index%4)*310,315+(index/4)*290)
		layer.add_child(object)
		object.apply_visual_transfer(Vector2(640,360))
		var label := Label.new()
		label.text = object.piece.display_name
		label.position = object.position+Vector2(-110,20)
		label.add_theme_color_override("font_color",Color("554755"))
		label.add_theme_font_size_override("font_size",18)
		add_child(label)
	if DisplayServer.get_name()=="headless":
		get_tree().quit()
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://Exports/DerivedCrops")
	get_viewport().get_texture().get_image().save_png("res://Exports/DerivedCrops/02_botanical.png" if botanical else "res://Exports/DerivedCrops/01_fragments.png")
	print("Derived crop GPU capture complete")
	get_tree().quit()
