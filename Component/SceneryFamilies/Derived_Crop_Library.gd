class_name DerivedCropLibrary
extends RefCounted

const IDS: Array[String] = ["rose_fan","twin_fan","branch_elbow","low_root","slate_shelf","slate_chip","wall_cap","broken_lintel"]
const OBJECT := preload("res://Component/SceneryFamilies/Derived_Crop_Object.tscn")
const BOTANICAL_IDS: Array[String] = ["fern_mat","moon_reeds","bell_spray","broken_fan_bough","flower_clump","root_sprout","hanging_seeds","twin_leaf"]

static func create_piece(id: String, size_override := Vector2.ZERO) -> DerivedCropObject:
	var path := "res://Art/SceneryFamilies/Crops/%s.tres"%id
	return _create(path,size_override)

static func create_botanical(id: String, size_override := Vector2.ZERO) -> DerivedCropObject:
	return _create("res://Art/SceneryFamilies/Botanical/Pieces/%s.tres"%id,size_override)

static func _create(path: String, size_override: Vector2) -> DerivedCropObject:
	if not ResourceLoader.exists(path):
		return null
	var object := OBJECT.instantiate() as DerivedCropObject
	object.piece = load(path) as DerivedCropPiece
	if size_override.x>0 and size_override.y>0:
		object.dimensions = size_override
	return object
