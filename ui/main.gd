extends Control

const PORT = 7000
const MAX_CLIENTS = 10
const GAME_SCENE = "res://world/game.tscn"
var peer : ENetMultiplayerPeer
@onready var address_input = $VBoxContainer/AddressInput
@onready var ip_label = $VBoxContainer/IPLabel
func _ready():
	var local_ip = IP.get_local_addresses()
	for addr in local_ip:
		# Skip loopback, link-local (169.254), and IPv6
		if "." in addr \
		and not addr.begins_with("127.") \
		and not addr.begins_with("169.254."):
			ip_label.text = "Your IP: " + addr
			break

	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)

func _on_HostButton_pressed():
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		print("Failed to create server: ", err)
		return
	multiplayer.multiplayer_peer = peer
	print("Server started!")
	# Host goes straight to the game
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_JoinButton_pressed():
	var address = address_input.text
	if address == "":
		address = "127.0.0.1"
	peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, PORT)
	if err != OK:
		print("Failed to connect: ", err)
		return
	multiplayer.multiplayer_peer = peer
	print("Connecting to ", address, "...")

func _on_connected_to_server():
	print("Connected! My ID: ", multiplayer.get_unique_id())
	get_tree().change_scene_to_file(GAME_SCENE)

func _on_connection_failed():
	print("Connection failed!")

func _on_peer_connected(id: int):
	print("Peer connected: ", id)
