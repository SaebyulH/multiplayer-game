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
	# clear old if exists
	if preview_weapon:
		preview_weapon.queue_free()

	preview_weapon = weapon_scene.instantiate()
	display_point.add_child(preview_weapon)
	preview_weapon.visible = true
	preview_weapon.scale = Vector3(3.0, 3.0, 3.0)
	preview_weapon.hide_arms()


func _on_claim_area_body_entered(body: Node3D) -> void:
	if claimed:
		return

	if body is Player and weapon_scene:
		claimed = true

		var player := body as Player

		# give weapon
		var new_weapon: Gun = weapon_scene.instantiate()
		player.gun_socket.add_child(new_weapon)
		new_weapon.visible = false

		player.guns.append(new_weapon)
		player._connect_gun(new_weapon)
		player.equip_gun(player.guns.size() - 1)

		# disable crate
		_disable_crate()

		# respawn timer
		await get_tree().create_timer(respawn_time).timeout

		_respawn()


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
