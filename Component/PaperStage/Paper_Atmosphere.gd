@tool
class_name PaperAtmosphere
extends Node2D

## 封装只使用连续色洗和纸面，不绘制另一个不可搬的完整树或拱门。
@export var camera_path: NodePath
var _far: Node2D
var _near: Node2D
var _camera_origin := Vector2.ZERO
var _camera_initialized := false

func _ready() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = -20
	add_child(canvas)
	var paper := ColorRect.new()
	paper.color = Color("f0e5ce")
	paper.size = Vector2(4096,2160)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(paper)
	var texture := TextureRect.new()
	texture.texture = preload("res://Art/Scenery/Paper_Grain.png")
	texture.size = Vector2(4096,2160)
	texture.stretch_mode = TextureRect.STRETCH_TILE
	texture.modulate = Color(1,0.95,0.87,0.36)
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(texture)
	_far = Node2D.new()
	canvas.add_child(_far)
	_near = Node2D.new()
	canvas.add_child(_near)
	## 大面积晕染通过不规则软边消散，避免硬矩形被误读为景物立柱。
	_add_wash(_far,Rect2(-340,-210,840,840),Color(0.62,0.68,0.57,0.30),Vector2(0.1,0.3))
	_add_wash(_far,Rect2(390,-300,700,890),Color(0.74,0.68,0.65,0.18),Vector2(0.3,0.7))
	_add_wash(_far,Rect2(830,-160,840,860),Color(0.58,0.64,0.53,0.28),Vector2(0.6,0.2))
	_add_wash(_near,Rect2(-450,290,1310,360),Color(0.59,0.67,0.55,0.23),Vector2(0.7,0.5))
	_add_wash(_near,Rect2(650,400,1370,250),Color(0.69,0.68,0.57,0.18),Vector2(0.4,0.1))
	set_physics_process(not Engine.is_editor_hint())

func _add_wash(parent: Node2D,rect: Rect2,color: Color,offset: Vector2) -> void:
	var wash := Polygon2D.new()
	wash.position = rect.position
	wash.polygon = PackedVector2Array([Vector2.ZERO,Vector2(rect.size.x,0),rect.size,Vector2(0,rect.size.y)])
	wash.uv = PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN])
	wash.color = color
	var material := ShaderMaterial.new()
	material.shader = preload("res://Art/PaperStage/Paper_Wash.gdshader")
	material.set_shader_parameter("grain",preload("res://Art/Materials/Dry_Ink_AI.png"))
	material.set_shader_parameter("grain_offset",offset)
	material.set_shader_parameter("shape_size",rect.size)
	wash.material = material
	parent.add_child(wash)

func _physics_process(_delta: float) -> void:
	var camera := get_node_or_null(camera_path) as Camera2D if not camera_path.is_empty() else get_viewport().get_camera_2d()
	if not is_instance_valid(camera):
		return
	if not _camera_initialized:
		_camera_origin = camera.global_position
		_camera_initialized = true
	var drift := camera.global_position-_camera_origin
	_far.position = -drift*Vector2(0.045,0.02)
	_near.position = -drift*Vector2(0.09,0.03)
