extends Node3D

const PLAYER_SCENE = preload("res://player.tscn")

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
	
	if peer_id == 1:
		player.position = $HostPosition.position
	else:
		player.position = $ClientPosition.position
	
	add_child(player)
	print("Player spawned locally for peer: ", peer_id, " on machine: ", multiplayer.get_unique_id())

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
