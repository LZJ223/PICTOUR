class_name Box
extends LayerObject

## 玩家是否能搬起这个箱子。大箱子设为 false 作为纯障碍物，只能换层不能搬。
@export var carriable: bool = false

## 是否正被玩家搬起。搬起时冻结物理、关闭碰撞与换层，位置由玩家同步。
var _carried: bool = false

## 玩家搬起或放下箱子时调用。
func set_carried(carried: bool) -> void:
	_carried = carried
	if carried:
		## 冻结为静态体，位置可由玩家直接赋值
		set("freeze", true)
		set("freeze_mode", RigidBody2D.FREEZE_MODE_STATIC)
		## 搬起时不与任何东西碰撞，避免卡墙或挤飞玩家
		collision_layer = 0
		collision_mask = 0
		## 搬起时不能被选中换层
		can_transfer = false
	else:
		set("freeze", false)
		can_transfer = true
		## 恢复所属图层的碰撞
		update_layer_slot()

func is_carried() -> bool:
	return _carried
