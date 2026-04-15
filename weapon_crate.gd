extends StaticBody3D

@export var weapon_scene: PackedScene
@export var respawn_time := 10.0

@onready var display_point: Node3D    = $DisplayPoint
@onready var claim_area: Area3D       = $ClaimArea
@onready var collision: CollisionShape3D = $CollisionShape3D

var preview_weapon: Node3D = null
var claimed := false


func _ready() -> void:
	if weapon_scene:
		_spawn_preview()


func _spawn_preview() -> void:
	if preview_weapon:
		preview_weapon.queue_free()

	preview_weapon = weapon_scene.instantiate()
	display_point.add_child(preview_weapon)
	preview_weapon.scale = Vector3(3, 3, 3)

	if preview_weapon.has_method("hide_arms"):
		preview_weapon.hide_arms()


# ─────────────────────────────────────────
# CLIENT: enters the pickup zone
# ─────────────────────────────────────────
func _on_claim_area_body_entered(body: Node3D) -> void:
	if not (body is Player) or claimed:
		return
	if not body.is_multiplayer_authority():
		return

	if multiplayer.is_server():
		# Host is peer 1 — rpc_id(1) to self is a no-op, so call directly.
		_request_pickup()
	else:
		_request_pickup.rpc_id(1)


# ─────────────────────────────────────────
# SERVER: validates and authorises pickup
# ─────────────────────────────────────────
@rpc("any_peer", "reliable")
func _request_pickup() -> void:
	if claimed or not multiplayer.is_server():
		return

	# get_remote_sender_id() returns 0 when the host triggers the RPC locally.
	# The host's real peer ID is always 1.
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	var player := _get_player_by_id(sender_id)
	if player == null:
		return

	claimed = true
	_set_crate_state.rpc(true)

	var scene_path := weapon_scene.resource_path

	if sender_id == 1:
		# Host is picking up — rpc_id(1) from the server to itself is a no-op,
		# so call the delivery function directly instead.
		_deliver_gun_to_peer(scene_path)
	else:
		_deliver_gun_to_peer.rpc_id(sender_id, scene_path)

	await get_tree().create_timer(respawn_time).timeout
	_set_crate_state.rpc(false)


# ─────────────────────────────────────────
# PEER: receives and instantiates its gun
# ─────────────────────────────────────────
# Not marked @rpc — the server calls this directly for the host,
# and via rpc_id for remote clients.
func _deliver_gun_to_peer(scene_path: String) -> void:
	var local_player := _get_local_authority_player()
	if local_player == null:
		return
	local_player.receive_gun(scene_path)


# ─────────────────────────────────────────
# CRATE STATE SYNC (all peers)
# ─────────────────────────────────────────
@rpc("call_local", "reliable")
func _set_crate_state(is_claimed: bool) -> void:
	claimed = is_claimed

	if claimed:
		if preview_weapon:
			preview_weapon.visible = false
		claim_area.monitoring = false
		collision.disabled    = true
	else:
		_spawn_preview()
		claim_area.monitoring = true
		collision.disabled    = false


# ─────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────
func _get_player_by_id(id: int) -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.get_multiplayer_authority() == id:
			return node
	return null


## Returns the Player node that this local machine owns.
func _get_local_authority_player() -> Player:
	for node in get_tree().get_nodes_in_group("players"):
		if node is Player and node.is_multiplayer_authority():
			return node
	return null
