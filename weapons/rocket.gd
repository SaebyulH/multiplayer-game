extends RigidBody3D
class_name Rocket

var shooter_id: int = 0

const DAMAGE = 100
const SPLASH_RADIUS = 5.0
const SPEED = 20.0
const SELF_DAMAGE = 0.25

@export var knockback_force: float = 20.0   # ← NEW

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
	_explode.rpc()

@rpc("authority", "call_local", "reliable")
func _explode():
	print("_explode called on peer: ", multiplayer.get_unique_id())
	$MeshInstance3D.hide()
	$Radius.show()
	
	set_physics_process(false)
	freeze = true
	$Explosion.emitting = true

	if multiplayer.is_server():
		var explosion_origin = global_position
		var space = get_world_3d().direct_space_state
		var players = get_tree().get_nodes_in_group("players")

		for player in players:
			if not player is Player:
				continue

			var player_id = player.name.to_int()
			var to_player = player.global_position - explosion_origin
			var dist = to_player.length()

			if dist > SPLASH_RADIUS:
				continue

			# Line of sight check
			var ray = PhysicsRayQueryParameters3D.new()
			ray.from = explosion_origin
			ray.to = player.global_position + Vector3(0, 0.5, 0)
			ray.collision_mask = 1
			ray.exclude = [get_rid()]

			var obstruction = space.intersect_ray(ray)
			if not obstruction.is_empty():
				continue

			var falloff = 1.0 - clamp(dist / SPLASH_RADIUS, 0.0, 1.0)

			# DAMAGE (skip shooter)

				
			
			var dmg = int(DAMAGE * falloff)
			if player_id == shooter_id:
				dmg *= SELF_DAMAGE
			player.take_damage.rpc_id(player_id, dmg, shooter_id)
			
			# KNOCKBACK (applies to everyone, including shooter)
			var dir = to_player.normalized()
			var force = dir * knockback_force * falloff

			# Optional: slightly reduce self-knockback
			#if player_id == shooter_id:
			#	force *= 0.8

			if player.has_method("add_velocity"):
				player.add_velocity(force)
			elif "velocity" in player:
				player.velocity += force
			elif player is RigidBody3D:
				player.apply_impulse(Vector3.ZERO, force)

		await get_tree().create_timer($Explosion.lifetime).timeout
		queue_free()
