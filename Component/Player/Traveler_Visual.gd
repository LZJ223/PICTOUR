extends AnimatedSprite2D
## 只读取角色既有运动状态；帧与朝向不写入物理位置。

@onready var player: PlayerController = get_parent().get_parent() as PlayerController


func _ready() -> void:
	process_physics_priority = 1
	play(&"idle")


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(player) or player.UAV_activated:
		return
	flip_h = player.facing_direction < 0
	var next_animation: StringName = &"idle"
	if player.dash_active:
		next_animation = &"dash"
	elif not player.is_on_floor():
		next_animation = &"rise" if player.velocity.y < -20.0 else &"fall"
	elif absf(player.velocity.x) > 12.0:
		next_animation = &"run" if player.is_running else &"walk"
	if animation != next_animation:
		play(next_animation)
