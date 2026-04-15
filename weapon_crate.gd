extends StaticBody3D

@export var weapon_scene: PackedScene
@onready var display_point: Node3D = $DisplayPoint


var preview_weapon: Node3D = null


func _ready() -> void:
	if weapon_scene:
		preview_weapon = weapon_scene.instantiate()
		display_point.add_child(preview_weapon)


func _on_claim_area_body_entered(body: Node3D) -> void:
	if body is Player and weapon_scene:
		var player := body as Player

		# create new weapon
		var new_weapon: Gun = weapon_scene.instantiate()

		# IMPORTANT: put it in the gun socket, not root
		player.gun_socket.add_child(new_weapon)

		# hide it initially (equip_gun will show)
		new_weapon.visible = false

		# add to list
		player.guns.append(new_weapon)

		# 🔥 CONNECT SIGNALS
		player._connect_gun(new_weapon)

		# equip it (last index)
		player.equip_gun(player.guns.size() - 1)

		# remove crate
		queue_free()
