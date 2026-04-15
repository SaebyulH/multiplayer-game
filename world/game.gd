extends Node3D

const PLAYER_SCENE = preload("res://player/player.tscn")
const ROCKET_SCENE = preload("res://weapons/rocket.tscn")

func spawn_rocket(shooter_id: int, spawn_transform: Transform3D):
	if not multiplayer.is_server():
		return
	var rocket = ROCKET_SCENE.instantiate()
	rocket.shooter_id = shooter_id
	# Push spawn point forward so it clears the camera/player
	spawn_transform.origin += -spawn_transform.basis.z * 1.5
	rocket.global_transform = spawn_transform
	$Rockets.add_child(rocket)
	
func _ready():
	print("Game scene loaded. Is server: ", multiplayer.is_server())

	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_remove_player)
		_spawn_player(1)
	else:
		# Tell server we are loaded and ready
		_client_ready.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func _client_ready():
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	print("Client is ready: ", peer_id)
	
	# Spawn this client's player on ALL peers
	_spawn_player_on_all.rpc(peer_id)

@rpc("any_peer", "call_local", "reliable")
func _spawn_player_on_all(peer_id: int):
	print("Spawning player ", peer_id, " on peer ", multiplayer.get_unique_id())
	# Don't duplicate
	if get_node_or_null(str(peer_id)) != null:
		print("Player already exists, skipping")
		return
	_spawn_player(peer_id)
	
func _spawn_player(peer_id: int):
	var player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.add_to_group("players")	# ← add this line
	if peer_id == 1:
		player.position = $HostPosition.position
	else:
		player.position = $ClientPosition.position
	add_child(player)

func _remove_player(peer_id: int):
	var player = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
		
func _on_peer_connected(peer_id: int):
	print("Peer connected: ", peer_id)
	# Spawn existing players on the newly connected peer
	for child in get_children():
		if child is CharacterBody3D:
			_spawn_player_on_all.rpc_id(peer_id, child.name.to_int())
			
@rpc("any_peer", "call_local", "reliable")
func respawn_player(peer_id: int):
	if not multiplayer.is_server():
		return
	var player = get_node_or_null(str(peer_id))
	if player == null:
		return
	var pos
	if peer_id == 1:
		pos = $HostPosition.position
	else:
		pos = $ClientPosition.position
	player.set_position_on_all.rpc(pos)
