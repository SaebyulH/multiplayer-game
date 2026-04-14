extends CharacterBody3D
class_name Rocket

@export var speed := 35.0
@export var lifetime := 5.0

var shooter_id: int

func _ready():
	if multiplayer.is_server():
		await get_tree().create_timer(lifetime).timeout
		queue_free()


func _physics_process(delta):
	if not multiplayer.is_server():
		return

	var collision = move_and_collide(-global_transform.basis.z * speed * delta)

	if collision:
		_explode(collision.get_collider())


func _explode(hit):
	if hit and hit.has_method("take_damage"):
		hit.take_damage.rpc(
			50,
			shooter_id
		)

	queue_free()
