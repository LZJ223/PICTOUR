extends Node
## 角色控制器不会推动刚体，静态的云也不会自己让开。玩家贴着物体走时，由物体自己横移。

const PUSH_SPEED := 160.0

func _physics_process(delta: float) -> void:
	var body := get_parent() as PhysicsBody2D
	var player := Global.player
	if body == null or player == null or not is_instance_valid(player):
		return
	if body is RigidBody2D and (body as RigidBody2D).freeze:
		return
	if (body.collision_layer & player.collision_mask) == 0:
		return
	var shape := body.get_node_or_null("CollisionBox") as CollisionPolygon2D
	if shape == null or shape.disabled or shape.polygon.size() < 3:
		return
	var min_x := 1.0e20
	var max_x := -1.0e20
	var min_y := 1.0e20
	var max_y := -1.0e20
	for point in shape.polygon:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_y = minf(min_y, point.y)
		max_y = maxf(max_y, point.y)
	var scale := shape.scale.abs()
	var left := body.global_position.x + min_x * scale.x
	var right := body.global_position.x + max_x * scale.x
	var top := body.global_position.y + min_y * scale.y
	var bottom := body.global_position.y + max_y * scale.y
	var player_x := player.global_position.x
	var player_y := player.global_position.y
	if player_x < left - 42.0 or player_x > right + 42.0:
		return
	if player_y < top + 16.0:
		return
	if player_y > bottom + 90.0:
		return
	var dx := (left + right) * 0.5 - player_x
	var input := Input.get_axis("move_left", "move_right")
	if absf(input) < 0.1 or absf(dx) < 1.0 or signf(input) != signf(dx):
		return
	var speed := signf(dx) * PUSH_SPEED
	if body is RigidBody2D:
		var rigid := body as RigidBody2D
		rigid.sleeping = false
		rigid.linear_velocity.x = speed
	else:
		body.global_position.x += speed * delta
