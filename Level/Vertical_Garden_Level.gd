extends Level
## 仅三件主实体的折页井；不创建或写入任何书签存档。
const OBJECT := preload("res://Component/VerticalGarden/Vertical_Object.tscn")
const TERRAIN := preload("res://Component/VerticalGarden/Vertical_Terrain.gd")
var player: PlayerController
var system: SystemController
var goal_reached := false
var _notes: CanvasLayer
var _feedback: Label
var _feedback_time := 0.0
var _goal_ink: Sprite2D

func _ready() -> void:
	_build_world()
	_build_notes()
	## 顶页的墨晕是无实体色洗；没有另放不能搬动的树、石或建筑。
	$Atmosphere._add_wash(self,Rect2(240,-220,1060,620),Color(0.68,0.49,0.57,0.18),Vector2(0.31,0.72))
	$Atmosphere._add_wash(self,Rect2(720,50,960,720),Color(0.64,0.68,0.55,0.18),Vector2(0.77,0.22))
	_goal_ink = Sprite2D.new()
	_goal_ink.texture = preload("res://Art/Scenery/Ink_Drop.png")
	_goal_ink.position = Vector2(820,130)
	_goal_ink.scale = Vector2(0.17,0.17)
	_goal_ink.z_index = 215
	add_child(_goal_ink)
	call_deferred("_connect_game")

func _build_world() -> void:
	var lower_top := _rounded_line([Vector2(-70,1100),Vector2(100,1095),Vector2(250,1100),Vector2(440,1100),Vector2(515,1104),Vector2(600,1100),Vector2(1000,1100),Vector2(1080,1180),Vector2(1230,1180),Vector2(1340,1100),Vector2(1450,1082),Vector2(1550,1050),Vector2(1650,1009),Vector2(1750,975),Vector2(1860,939),Vector2(1960,908),Vector2(2010,890),Vector2(2120,889),Vector2(2160,896)],18)
	_shore($Mid,"LowerFold",lower_top,_rounded_line([Vector2(2168,910),Vector2(2080,940),Vector2(1940,983),Vector2(1840,1020),Vector2(1740,1080),Vector2(1640,1100),Vector2(1540,1160),Vector2(1420,1210),Vector2(1300,1280),Vector2(1210,1320),Vector2(1110,1270),Vector2(1010,1220),Vector2(930,1240),Vector2(840,1250),Vector2(720,1210),Vector2(610,1200),Vector2(510,1215),Vector2(400,1245),Vector2(300,1250),Vector2(170,1215),Vector2(50,1200),Vector2(-70,1175)],35),Color("735a6a"),31)
	_shore($Mid,"UpperLip",PackedVector2Array([Vector2(1510,800),Vector2(1900,800)]),_rounded_line([Vector2(1904,805),Vector2(1900,815),Vector2(1860,821),Vector2(1800,828),Vector2(1740,824),Vector2(1670,831),Vector2(1600,826),Vector2(1545,813),Vector2(1510,809)],14),Color("725867"),14)
	var upper_top := _rounded_line([Vector2(260,184),Vector2(370,178),Vector2(550,189),Vector2(720,180),Vector2(850,180),Vector2(950,205),Vector2(1040,280),Vector2(1140,370),Vector2(1250,455),Vector2(1380,525),Vector2(1435,578),Vector2(1510,635)],25)
	_shore($Mid,"ReturnFold",upper_top,_rounded_line([Vector2(1518,657),Vector2(1485,680),Vector2(1390,637),Vector2(1320,617),Vector2(1270,550),Vector2(1170,527),Vector2(1120,454),Vector2(1020,405),Vector2(966,350),Vector2(860,347),Vector2(760,311),Vector2(625,349),Vector2(500,310),Vector2(375,309),Vector2(280,271),Vector2(245,224)],28),Color("7c6372"),43)
	## 背景折壁形成有限空腔。不是不可搬的树或石；实体与可见纸岸完全重合。
	_terrain($Back,"LeftBackFold",[Vector2(-260,930),Vector2(-80,900),Vector2(100,955),Vector2(280,950),Vector2(440,905),Vector2(555,839),Vector2(610,808),Vector2(650,805),Vector2(690,828),Vector2(700,880),Vector2(706,980),Vector2(705,1080),Vector2(700,1150),Vector2(700,1240),Vector2(625,1270),Vector2(560,1280),Vector2(360,1260),Vector2(110,1230),Vector2(-260,1230)],Color("b8b39a"),12)
	_shore($Back,"RightBackFold",_rounded_line([Vector2(1180,1250),Vector2(1370,1260),Vector2(1490,1210),Vector2(1550,1110),Vector2(1600,970),Vector2(1700,970),Vector2(1790,910),Vector2(1900,800),Vector2(1940,630),Vector2(1980,580),Vector2(2130,525),Vector2(2250,550)],30),_rounded_line([Vector2(2330,645),Vector2(2260,734),Vector2(2120,761),Vector2(2020,869),Vector2(1920,1065),Vector2(1800,1088),Vector2(1690,1220),Vector2(1530,1290),Vector2(1430,1400),Vector2(1270,1405),Vector2(1180,1310)],30),Color("b6b9a0"),57)
	## 后方根座对应C的实际空白，不把仅可见的画面当作有效容积。
	_terrain($Back,"LowRootShelf",[Vector2(1490,820),Vector2(1745,820),Vector2(1810,863),Vector2(1720,897),Vector2(1580,892),Vector2(1490,858)],Color("b8b69d"),33)
	var a_outline := PackedVector2Array([Vector2(54,985),Vector2(150,951),Vector2(203,934),Vector2(240,902),Vector2(280,872),Vector2(314,854),Vector2(309,803),Vector2(278,731),Vector2(266,679),Vector2(240,623),Vector2(271,615),Vector2(376,615),Vector2(426,620),Vector2(480,631),Vector2(441,572),Vector2(399,512),Vector2(367,450),Vector2(418,441),Vector2(514,441),Vector2(575,445),Vector2(611,432),Vector2(610,386),Vector2(582,330),Vector2(546,284),Vector2(535,257),Vector2(576,246),Vector2(687,243),Vector2(758,244),Vector2(806,230),Vector2(822,188),Vector2(811,150),Vector2(809,125),Vector2(861,122),Vector2(935,124),Vector2(1036,130),Vector2(1024,158),Vector2(1010,180),Vector2(1060,196),Vector2(1110,236),Vector2(1165,253),Vector2(1240,309),Vector2(1300,366),Vector2(1353,423),Vector2(1390,497),Vector2(1402,547),Vector2(1405,620),Vector2(1390,685),Vector2(1350,744),Vector2(1340,781),Vector2(1360,827),Vector2(1326,800),Vector2(1300,770),Vector2(1298,725),Vector2(1315,681),Vector2(1335,640),Vector2(1332,597),Vector2(1310,555),Vector2(1287,531),Vector2(1240,509),Vector2(1191,480),Vector2(1152,446),Vector2(1109,420),Vector2(1054,404),Vector2(1004,399),Vector2(954,409),Vector2(902,434),Vector2(858,458),Vector2(806,504),Vector2(768,554),Vector2(742,609),Vector2(723,660),Vector2(714,705),Vector2(737,752),Vector2(773,799),Vector2(799,834),Vector2(816,870),Vector2(856,900),Vector2(881,913),Vector2(896,940),Vector2(934,958),Vector2(964,987),Vector2(920,989),Vector2(882,976),Vector2(859,953),Vector2(824,943),Vector2(800,966),Vector2(770,978),Vector2(756,988),Vector2(704,989),Vector2(657,981),Vector2(631,969),Vector2(602,975),Vector2(573,988),Vector2(535,989),Vector2(505,981),Vector2(481,988),Vector2(452,993),Vector2(421,994),Vector2(390,981),Vector2(352,976),Vector2(323,971),Vector2(283,975),Vector2(249,989),Vector2(218,989),Vector2(184,985),Vector2(151,991),Vector2(114,989),Vector2(81,989)])
	_painted_object($Mid,"RootGate",Vector2(800,1100),a_outline,Vector2(750,994),0.25,"res://Art/VerticalGarden/Generated/Curled_Root_Gate.png","卷根门")
	var b_outline := PackedVector2Array([Vector2(46,280),Vector2(110,274),Vector2(185,316),Vector2(272,354),Vector2(342,369),Vector2(440,379),Vector2(590,394),Vector2(710,399),Vector2(910,399),Vector2(1100,390),Vector2(1210,373),Vector2(1300,350),Vector2(1370,322),Vector2(1369,356),Vector2(1384,378),Vector2(1370,401),Vector2(1380,437),Vector2(1350,503),Vector2(1340,560),Vector2(1330,620),Vector2(1336,651),Vector2(1301,655),Vector2(1275,628),Vector2(1247,576),Vector2(1238,550),Vector2(1220,604),Vector2(1215,626),Vector2(1195,615),Vector2(1190,570),Vector2(1163,538),Vector2(1110,512),Vector2(1070,510),Vector2(1030,526),Vector2(1000,555),Vector2(991,580),Vector2(1006,596),Vector2(994,627),Vector2(1004,685),Vector2(989,749),Vector2(981,799),Vector2(992,854),Vector2(995,912),Vector2(980,946),Vector2(947,970),Vector2(922,947),Vector2(906,931),Vector2(908,913),Vector2(928,899),Vector2(953,907),Vector2(969,903),Vector2(966,880),Vector2(940,848),Vector2(913,810),Vector2(900,773),Vector2(885,710),Vector2(862,643),Vector2(840,591),Vector2(815,554),Vector2(781,529),Vector2(737,507),Vector2(678,485),Vector2(584,468),Vector2(495,458),Vector2(433,462),Vector2(362,483),Vector2(310,510),Vector2(276,540),Vector2(274,569),Vector2(256,582),Vector2(240,619),Vector2(216,658),Vector2(196,655),Vector2(179,625),Vector2(165,580),Vector2(143,561),Vector2(127,565),Vector2(114,553),Vector2(121,528),Vector2(113,509),Vector2(111,480),Vector2(98,511),Vector2(88,507),Vector2(83,480),Vector2(74,460),Vector2(58,436),Vector2(50,410),Vector2(25,395),Vector2(20,367),Vector2(25,343),Vector2(50,337)])
	_painted_object($Back,"KeelBridge",Vector2(1290,1170),b_outline,Vector2(700,970),0.375,"res://Art/VerticalGarden/Generated/Hanging_Bough_Bridge.png","垂腹枝")
	var low_root := DerivedCropLibrary.create_piece("low_root",Vector2(225,119.4))
	low_root.name = "LowRoot"
	low_root.position = Vector2(1640,821.74)
	low_root.set_meta("persistent_id","LowRoot")
	$Back.add_child(low_root)

func _terrain(layer: DepthLayer, title: String, points: Array, color: Color, seed: int) -> void:
	var terrain := TERRAIN.new()
	terrain.name = title
	terrain.contour = PackedVector2Array(points)
	terrain.ink_color = color
	terrain.seed_value = seed
	terrain.top_vertices = {"LowerFold":7,"UpperLip":2,"ReturnFold":3,"LeftBackFold":14,"RightBackFold":8,"LowRootShelf":2}.get(title,2)
	layer.add_child(terrain)

func _shore(layer: DepthLayer, title: String, upper: PackedVector2Array, lower: PackedVector2Array, color: Color, seed: int) -> void:
	var terrain := TERRAIN.new()
	terrain.name = title
	terrain.contour = upper.duplicate()
	terrain.contour.append_array(lower)
	terrain.top_vertices = upper.size()
	terrain.ink_color = color
	terrain.seed_value = seed
	layer.add_child(terrain)

## 局部圆钝不会超出相邻边的斜率；脚下没有装饰图与实体不一致的捷径。
func _rounded_line(raw: Array, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array([raw[0]])
	for index in range(1,raw.size()-1):
		var a: Vector2 = raw[index-1]
		var b: Vector2 = raw[index]
		var c: Vector2 = raw[index+1]
		var p := b.move_toward(a,minf(radius,a.distance_to(b)*0.32))
		var q := b.move_toward(c,minf(radius,c.distance_to(b)*0.32))
		for step in range(7):
			var t := float(step)/6.0
			result.append(p.lerp(b,t).lerp(b.lerp(q,t),t))
	result.append(raw[-1])
	return result

func _painted_object(layer: DepthLayer, title: String, origin: Vector2, source: PackedVector2Array, pivot: Vector2, unit: float, image_path: String, label: String) -> void:
	var object := OBJECT.instantiate() as VerticalGardenObject
	object.name = title
	object.position = origin
	object.display_name = label
	var points := PackedVector2Array()
	for point in source: points.append((point-pivot)*unit)
	object.solid_polygons.append(points)
	object.painting = load(image_path)
	object.painting_rect = Rect2(-pivot*unit,object.painting.get_size()*unit)
	object.set_meta("persistent_id",title)
	layer.add_child(object)

func _connect_game() -> void:
	player = get_parent().get_node("Player")
	system = get_parent().get_node("System")
	Global.transfer_result.connect(_on_transfer)
	if system.get("history") != null:
		system.get("history").message_changed.connect(_message)

func _physics_process(delta: float) -> void:
	_feedback_time = maxf(0.0,_feedback_time-delta)
	if is_instance_valid(_feedback): _feedback.modulate.a = minf(1.0,_feedback_time)
	if not is_instance_valid(player): return
	if player.global_position.y > 1510 or player.global_position.x < -160 or player.global_position.x > 2360:
		system.call("reset_study")
	if player.is_on_floor() and player.global_position.distance_to(Vector2(820,180))<85 and not goal_reached:
		goal_reached = true
		_goal_ink.visible = false
		_message("抵达折页上缘。试着沿现在的道路走回树根。")

func _on_transfer(object: LayerObject, success: bool, reason: String) -> void:
	if is_instance_valid(object) and is_ancestor_of(object):
		_message("%s · %s" % [object.display_name,"落入此页" if object.owner_layer.slot==0 else "退入远处"] if success else reason)

func _message(value: String) -> void:
	_feedback.text = value
	_feedback_time = 3.5

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F8:
		_notes.visible = not _notes.visible
		get_viewport().set_input_as_handled()

func _build_notes() -> void:
	_notes = CanvasLayer.new()
	_notes.layer = 8
	add_child(_notes)
	var title := Label.new()
	title.text = "折 页 井  ·  三件景物，两条归路"
	title.position = Vector2(30,24)
	title.add_theme_font_size_override("font_size",16)
	title.add_theme_color_override("font_color",Color("8e7c79"))
	_notes.add_child(title)
	_feedback = Label.new()
	_feedback.position = Vector2(30,50)
	_feedback.add_theme_font_size_override("font_size",13)
	_feedback.add_theme_color_override("font_color",Color("8e7c79"))
	_notes.add_child(_feedback)
	var guide := Label.new()
	guide.text = "A D 移动  ·  Shift 冲刺/奔跑  ·  Space 跳跃  ·  左键选景，W/S 换景  ·  Z 撤回上次换景  ·  R 重来  ·  F8 藏字"
	guide.position = Vector2(30,690)
	guide.add_theme_font_size_override("font_size",12)
	guide.add_theme_color_override("font_color",Color("8e7c79"))
	_notes.add_child(guide)
