extends RigidBody3D
class_name Rocket

var shooter_id: int = 0
const DAMAGE = 100
const SPLASH_RADIUS = 6.0
const SPEED = 20.0

func _ready():
	if not multiplayer.is_server():
		freeze = true
		return
	contact_monitor = true
	max_contacts_reported = 4
	linear_velocity = -global_transform.basis.z * SPEED
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if not multiplayer.is_server():
		return
	print("Rocket collided with: ", body.name)
	_explode.rpc()

@rpc("authority", "call_local", "reliable")
func _explode():
	if multiplayer.is_server():
		var explosion_origin = global_position
		var space = get_world_3d().direct_space_state

		# Debug sphere
		var debug_mesh = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = SPLASH_RADIUS
		sphere_mesh.height = SPLASH_RADIUS * 2
		debug_mesh.mesh = sphere_mesh
		debug_mesh.global_position = explosion_origin
		get_tree().get_root().add_child(debug_mesh)
		get_tree().create_timer(3.0).timeout.connect(func(): debug_mesh.queue_free())

		# Get every player in the scene directly
		var players = get_tree().get_nodes_in_group("players")
		print("Checking ", players.size(), " players for splash damage")

		for player in players:
			if not player is Player:
				continue
			var dist = explosion_origin.distance_to(player.global_position)
			print("Player ", player.name, " is ", dist, " units away (radius: ", SPLASH_RADIUS, ")")
			if dist > SPLASH_RADIUS:
				continue

			# Line of sight check through world geometry (layer 1)
			var ray = PhysicsRayQueryParameters3D.new()
			ray.from = explosion_origin
			ray.to = player.global_position + Vector3(0, 0.5, 0)
			ray.collision_mask = 1
			# Exclude the rocket itself
			ray.exclude = [get_rid()]
			var obstruction = space.intersect_ray(ray)
			if not obstruction.is_empty():
				print("Player ", player.name, " is behind a wall: ", obstruction["collider"].name)
				continue

			var falloff = 1.0 - clamp(dist / SPLASH_RADIUS, 0.0, 1.0)
			var dmg = int(DAMAGE * falloff)
			print("Dealing ", dmg, " to player ", player.name)
			player.take_damage.rpc_id(player.name.to_int(), dmg, shooter_id)

	queue_free()
