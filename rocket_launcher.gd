extends Gun
class_name RocketLauncher

@export var rocket_scene: PackedScene
@export var rocket_speed := 35.0
@export var explosion_damage := 50
@export var explosion_radius := 4.0

func shoot(owner):
	if is_reloading:
		return

	if mag <= 0:
		start_reload()
		return

	if not can_shoot:
		return

	_fire_rocket(owner)

func _fire_rocket(owner):
	$AnimationPlayer.play("shoot")

	can_shoot = false
	mag -= 1

	ammo_changed.emit(mag, mag_size)
	shot_fired.emit()
	muzzle_flash.emitting = true

	get_tree().create_timer(fire_rate).timeout.connect(func():
		can_shoot = true
	)

	_spawn_rocket.rpc(
		owner.multiplayer.get_unique_id(),
		$Muzzle.global_transform
	)

@rpc("any_peer", "call_local", "reliable")
func _spawn_rocket(shooter_id: int, spawn_transform: Transform3D):
	if rocket_scene == null:
		return

	var rocket = rocket_scene.instantiate()

	# optional safety cast
	if rocket is Rocket:
		var r: Rocket = rocket

		get_tree().current_scene.add_child(r)

		r.global_transform = spawn_transform
		r.shooter_id = shooter_id

		r.velocity = -spawn_transform.basis.z * rocket_speed

	else:
		push_error("rocket_scene is not a Rocket")

func start_reload():
	if is_reloading:
		return
	if mag == mag_size:
		return

	$AnimationPlayer.play("reload")

	is_reloading = true
	can_shoot = false
	reload_time = 0.0

	reload_started.emit()


func _finish_reload():
	mag = mag_size
	is_reloading = false
	can_shoot = true

	ammo_changed.emit(mag, mag_size)
	reload_finished.emit()
