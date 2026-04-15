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


func _spawn_preview():
	if preview_weapon:
		preview_weapon.queue_free()

	preview_weapon = weapon_scene.instantiate()
	display_point.add_child(preview_weapon)
	preview_weapon.scale = Vector3(3, 3, 3)

	if preview_weapon.has_method("hide_arms"):
		preview_weapon.hide_arms()


# ─────────────────────────────────────────
# CLIENT REQUEST
# ─────────────────────────────────────────
func _on_claim_area_body_entered(body: Node3D) -> void:
	if body is Player and not claimed:
		_request_pickup.rpc_id(1)


# ─────────────────────────────────────────
# SERVER HANDLES PICKUP
# ─────────────────────────────────────────
@rpc("any_peer", "reliable")
func _request_pickup():
	if claimed or not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	var player := _get_player_by_id(sender_id)

	if player == null:
		return

	claimed = true

	# sync crate state
	_set_crate_state.rpc(true)

	# give weapon to everyone
	_give_weapon.rpc(sender_id)

	await get_tree().create_timer(respawn_time).timeout
	_set_crate_state.rpc(false)


# ─────────────────────────────────────────
# SAFE PLAYER RESOLVE
# ─────────────────────────────────────────
func _get_player_by_id(id: int) -> Player:
	for child in get_tree().get_nodes_in_group("players"):
		if child is Player and child.get_multiplayer_authority() == id:
			return child
	return null


# ─────────────────────────────────────────
# CRATE STATE SYNC
# ─────────────────────────────────────────
@rpc("call_local", "reliable")
func _set_crate_state(is_claimed: bool):
	claimed = is_claimed

	if claimed:
		if preview_weapon:
			preview_weapon.visible = false
		claim_area.monitoring = false
		collision.disabled = true
	else:
		_spawn_preview()
		claim_area.monitoring = true
		collision.disabled = false


# ─────────────────────────────────────────
# GIVE WEAPON (ALL CLIENTS)
# ─────────────────────────────────────────
@rpc("call_local", "reliable")
func _give_weapon(player_id: int):
	var player := _get_player_by_id(player_id)
	if player == null:
		return

	var new_weapon: Gun = weapon_scene.instantiate()

	player.gun_socket.add_child(new_weapon)
	new_weapon.visible = false

	player.guns.append(new_weapon)
	player._connect_gun(new_weapon)

	if player.is_multiplayer_authority():
		player.equip_gun(player.guns.size() - 1)
