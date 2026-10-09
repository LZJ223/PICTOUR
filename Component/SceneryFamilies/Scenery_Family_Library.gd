class_name SceneryFamilyLibrary
extends RefCounted

const FAMILIES: Array[StringName] = [&"oldwood", &"strata", &"arcade"]
const PIECES: Dictionary = {
	&"oldwood": ["oldwood_stump", "oldwood_bridge", "oldwood_fork", "oldwood_hollow"],
	&"strata": ["strata_wedge", "strata_shelf", "strata_spire", "strata_hollow"],
	&"arcade": ["arcade_base", "arcade_lintel", "arcade_half", "arcade_double"],
}
const OBJECT_SCENE := preload("res://Component/SceneryFamilies/Scenery_Family_Object.tscn")

static func piece_path(id: String) -> String:
	return "res://Art/SceneryFamilies/Pieces/%s.tres"%id

static func load_piece(id: String) -> SceneryFamilyPiece:
	var path := piece_path(id)
	return load(path) as SceneryFamilyPiece if ResourceLoader.exists(path) else null

static func create_piece(id: String, size_override: Vector2 = Vector2.ZERO) -> SceneryFamilyObject:
	var data := load_piece(id)
	if data == null:
		return null
	var object := OBJECT_SCENE.instantiate() as SceneryFamilyObject
	object.piece = data
	if size_override.x > 0 and size_override.y > 0:
		object.dimensions = size_override
	return object
