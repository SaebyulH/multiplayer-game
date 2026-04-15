extends StaticBody3D

@export var weapon_scene: PackedScene
@export var respawn_time := 10.0

@onready var display_point: Node3D = $DisplayPoint
@onready var claim_area: Area3D = $ClaimArea
@onready var collision: CollisionShape3D = $CollisionShape3D

var preview_weapon: Node3D = null
var claimed := false


func _ready() -> void:
	if weapon_scene:
		_spawn_preview()


# ─────────────────────────────────────────
# Preview display
# ─────────────────────────────────────────
func _spawn_preview():
	if preview_weapon:
		preview_weapon.queue_free()

	preview_weapon = weapon_scene.instantiate()
	display_point.add_child(preview_weapon)

	preview_weapon.visible = true
	preview_weapon.scale = Vector3(3.0, 3.0, 3.0)

	if preview_weapon.has_method("hide_arms"):
		preview_weapon.hide_arms()


# ─────────────────────────────────────────
# Client → request pickup
# ─────────────────────────────────────────
func _on_claim_area_body_entered(body: Node3D) -> void:
	if claimed:
		return

	if body is Player:
		var player := body as Player

		# send request to server (peer 1)
		_request_pickup.rpc_id(1, player.get_multiplayer_authority())


# ─────────────────────────────────────────
# Server handles pickup
# ─────────────────────────────────────────
@rpc("authority", "call_local", "reliable")
func _request_pickup(player_id: int):
	if claimed or not weapon_scene:
		return

	var player := get_parent().get_node_or_null(str(player_id))
	if not player:
		return

	claimed = true

	# tell ALL clients to give weapon
	_give_weapon.rpc(player_id)

	_disable_crate()

	await get_tree().create_timer(respawn_time).timeout
	_respawn()


# ─────────────────────────────────────────
# Give weapon on ALL clients
# ─────────────────────────────────────────
@rpc("any_peer", "call_local", "reliable")
func _give_weapon(player_id: int):
	var player := get_parent().get_node_or_null(str(player_id))
	if not player:
		return

	var new_weapon: Gun = weapon_scene.instantiate()

	player.gun_socket.add_child(new_weapon)
	new_weapon.visible = false

	player.guns.append(new_weapon)
	player._connect_gun(new_weapon)

	player.equip_gun(player.guns.size() - 1)


# ─────────────────────────────────────────
# Disable / respawn
# ─────────────────────────────────────────
func _disable_crate():
	if preview_weapon:
		preview_weapon.visible = false

	claim_area.monitoring = false
	collision.disabled = true


func _respawn():
	claimed = false

	_spawn_preview()

	claim_area.monitoring = true
	collision.disabled = false
