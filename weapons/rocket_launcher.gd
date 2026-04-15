extends Gun
class_name RocketLauncher

func shoot(player: Player):
	if is_reloading:
		return
	if mag <= 0:
		start_reload()
		return
	if not can_shoot:
		return

	can_shoot = false
	mag -= 1
	ammo_changed.emit(mag, mag_size)
	shot_fired.emit()
	muzzle_flash.emitting = true
	$AnimationPlayer.play("shoot")
	get_tree().create_timer(fire_rate).timeout.connect(func(): can_shoot = true)

	if player.is_multiplayer_authority():
		_request_rocket.rpc_id(1,
			player.get_multiplayer_authority(),
			$Muzzle.global_transform
		)

@rpc("any_peer", "call_local", "reliable")
func _request_rocket(shooter_id: int, spawn_transform: Transform3D):
	if not multiplayer.is_server():
		return
	get_tree().get_root().get_node("Game").spawn_rocket(shooter_id, spawn_transform)
