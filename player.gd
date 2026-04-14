extends CharacterBody3D
class_name Player
# Movement physics
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
const JUMP_VELOCITY: float = 5.5
# CS-like movement tuning
const MAX_SPEED := 8.0
const ACCEL := 40.0
const AIR_ACCEL := 4.0
const FRICTION := 10.0
const STOP_SPEED := 1.5
var coyote_timer := 0.0
@export var guns: Array[Gun] = []
var current_gun_index := 0
var current_gun: Gun
var movement_direction


# Spread / inaccuracy
var spread := 0.0
var shoot_spread := 0.0

const BASE_SPREAD := 0.002
const MOVE_SPREAD := 0.2
const AIR_SPREAD := 0.025
const SHOOT_SPREAD_ADD := 0.5
const SPREAD_DECAY := 4.0


# Mouse
const MOUSE_SENS_X: float = 0.002
const MOUSE_SENS_Y: float = 0.002
@onready var mesh: MeshInstance3D = $MeshInstance3D

# Stats
const MAX_HEALTH = 100
#enum MovementMode { WALK, SPRINT, CROUCH }
#var movement_mode = MovementMode.WALK
var jump_cooldown_timer
enum MovementState { IDLE, WALKING, GLIDING, IN_AIR}
var movement_state = MovementState.IDLE

# Movement tuning
const COYOTE_DURATION = 0.1
const JUMP_COOLDOWN_DURATION = 0.1
# Combat
var health = MAX_HEALTH
var can_shoot = true
var ads = false
var kills = 0
var is_reloading = false
# Nodes
@onready var head = $Head
#@onready var gun = $Head/CSGCombiner3D
#@onready var gun: Gun = $Head/Gun
@onready var camera = $Head/Camera3D
#@onready var raycast = $Head/Camera3D/AttackRaycast
@onready var health_label = $CanvasLayer/VBoxContainer/HBoxContainer/HealthLabel
@onready var health_bar = $CanvasLayer/VBoxContainer/HealthBar
@onready var reload_bar = $CanvasLayer/VBoxContainer/ReloadBar

@onready var ammo_label = $CanvasLayer/VBoxContainer/HBoxContainer/AmmoLabel


@onready var kills_label = $CanvasLayer/KillsLabel
@onready var shoot_sound = $ShootSound
@onready var hit_sound = $HitSound
@onready var kill_sound = $KillSound

@onready var gun_socket = $Head/GunSocket
func equip_gun(index: int):
	if index < 0 or index >= guns.size():
		return

	if current_gun:
		current_gun.visible = false

	current_gun_index = index
	current_gun = guns[index]
	current_gun.visible = true

	_update_hud()

func _ready():
	# Hide own model only for the owning client
	if is_multiplayer_authority():
		mesh.visible = false
		$EyeRight.visible = false
		$EyeLeft.visible = false

	if is_multiplayer_authority():
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		camera.current = false
		$CanvasLayer.visible = false
	#$MeshInstance3D.hide()
	if is_multiplayer_authority():
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		camera.current = false
		$CanvasLayer.visible = false


	for gun in guns:
		#var gun_instance: Gun = scene.instantiate()
		#gun_instance.visible = false
		#gun_socket.add_child(gun_instance)

		_connect_gun(gun)

	equip_gun(0)
func _connect_gun(gun_instance: Gun):
	gun_instance.ammo_changed.connect(func(current, max):
		if gun_instance == current_gun:
			ammo_label.text = "Ammo: %d/%d" % [current, max]
	)

	gun_instance.shot_fired.connect(func():
		if gun_instance == current_gun:
			#current_gun.play("shoot")
			shoot_sound.play()
	)

	gun_instance.hit_confirmed.connect(func():
		if gun_instance == current_gun:
			hit_sound.play()
	)

	gun_instance.kill_confirmed.connect(func():
		if gun_instance == current_gun:
			kill_sound.play()
	)

	#gun_instance.reload_started.connect(func():
		#$AnimationPlayer.play("reload")
		#if gun_instance == current_gun:
			#reload_bar.visible = true
			#reload_bar.value = 0
	#)

	gun_instance.reload_progress.connect(func(value):
		if gun_instance == current_gun:
			reload_bar.value = value * 100.0
	)

	gun_instance.reload_finished.connect(func():
		if gun_instance == current_gun:
			reload_bar.visible = false
			reload_bar.value = 0
	)
func _unhandled_input(event):
	if not is_multiplayer_authority():
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var sens_scale = (30.0 / 90.0) if ads else 1.0
		rotate_y(-event.relative.x * MOUSE_SENS_X * sens_scale)
		head.rotate_x(-event.relative.y * MOUSE_SENS_Y * sens_scale)
		head.rotation.x = clampf(head.rotation.x, -deg_to_rad(90), deg_to_rad(85))

func _input(event):
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event.is_action_pressed("ads"):
		ads = not ads
	if Input.is_action_just_pressed("jump"):
		jump()
	if event.is_action_pressed("reload"):
		current_gun.start_reload()
		
	if event.is_action_pressed("weapon_next"):
		_cycle_weapon(1)

	if event.is_action_pressed("weapon_prev"):
		_cycle_weapon(-1)
		
func _cycle_weapon(dir: int):
	if guns.is_empty():
		return
	
	var new_index = current_gun_index + dir
	
	# wrap around
	if new_index < 0:
		new_index = guns.size() - 1
	elif new_index >= guns.size():
		new_index = 0
	
	equip_gun(new_index)
	_update_hud()
	
func _physics_process(delta):
	if global_position.y < -100:
		_die()
	if not is_multiplayer_authority():
		return

	camera.fov = 30 if ads else 90
	movement_direction = get_movement_direction()

	# ─── Gravity ─────────────────────────────
	if not is_on_floor():
		velocity.y -= gravity * delta
		coyote_timer -= delta
	else:
		coyote_timer = COYOTE_DURATION
		if velocity.y < 0:
			velocity.y = 0

	# ─── Horizontal movement (simple placeholder) ─────
	#var speed = 8
	#var dir = movement_direction
	#velocity.x = dir.x * speed
	#velocity.z = dir.z * speed
	var wish_dir = movement_direction
	var wish_speed = MAX_SPEED

	if is_on_floor():
		_apply_friction(delta)
		_accelerate(wish_dir, wish_speed, ACCEL, delta)
	else:
		_accelerate(wish_dir, wish_speed, AIR_ACCEL, delta)
	# ─── Shooting ─────────────────────────────
	if current_gun.automatic:
		if Input.is_action_pressed("shoot") and can_shoot:
			_shoot()
	else:
		if Input.is_action_just_pressed("shoot") and can_shoot:
			_shoot()
	_update_spread(delta)
	_apply_gun_spread()
	move_and_slide()


func _update_spread(delta):
	# movement-based spread
	var horizontal_speed = Vector3(velocity.x, 0, velocity.z).length()
	var move_factor = clamp(horizontal_speed / MAX_SPEED, 0.0, 1.0)

	var target_spread = BASE_SPREAD + move_factor * MOVE_SPREAD

	if not is_on_floor():
		target_spread += AIR_SPREAD

	# combine with shooting spread
	spread = target_spread + shoot_spread

	# decay shooting spread
	shoot_spread = max(shoot_spread - SPREAD_DECAY * delta, 0.0)
	
	if movement_direction == Vector3.ZERO and is_on_floor():
		shoot_spread = max(shoot_spread - SPREAD_DECAY * delta * 2.0, 0.0)
	
func _apply_gun_spread():
	if not gun_socket:
		return

	# small random offsets
	var x = randf_range(-spread, spread)
	var y = randf_range(-spread, spread)

	# apply rotation (pitch + yaw)
	gun_socket.rotation.x = lerp(gun_socket.rotation.x, x, 0.2)
	gun_socket.rotation.y = lerp(gun_socket.rotation.y, y, 0.2)
		
func _apply_friction(delta):
	var speed = velocity.length()
	if speed < 0.01:
		return

	var drop = 0.0

	var control = max(speed, STOP_SPEED)
	drop += control * FRICTION * delta

	var new_speed = max(speed - drop, 0.0)
	new_speed /= speed

	velocity.x *= new_speed
	velocity.z *= new_speed
	
func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float):
	var current_speed = velocity.dot(wish_dir)
	var add_speed = wish_speed - current_speed

	if add_speed <= 0:
		return

	var accel_speed = accel * delta * wish_speed
	if accel_speed > add_speed:
		accel_speed = add_speed

	velocity.x += accel_speed * wish_dir.x
	velocity.z += accel_speed * wish_dir.z
# ─── Movement Direction ───────────────────────────────────────────────────────
func jump():
	if is_on_floor() or coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
func get_movement_direction() -> Vector3:
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var forward = camera.global_transform.basis.z
	var right = camera.global_transform.basis.x
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	return (forward * input_dir.y + right * input_dir.x).normalized()

# ─── State Management ─────────────────────────────────────────────────────────


# ─── Combat ───────────────────────────────────────────────────────────────────

func _shoot():
	if current_gun:
		current_gun.shoot(self)
		shoot_spread += SHOOT_SPREAD_ADD


@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, shooter_id: int):
	if not is_multiplayer_authority():
		return
	health -= amount
	health = max(health, 0)
	_update_hud()
	if health <= 0:
		var shooter = get_parent().get_node_or_null(str(shooter_id))
		if shooter:
			shooter._notify_kill.rpc_id(shooter_id)
		_die()
	else:
		var shooter = get_parent().get_node_or_null(str(shooter_id))
		if shooter:
			shooter._notify_hit.rpc_id(shooter_id)

@rpc("any_peer", "call_local", "reliable")
func _notify_hit():
	if not is_multiplayer_authority():
		return
	hit_sound.play()

@rpc("any_peer", "call_local", "reliable")
func _notify_kill():
	if not is_multiplayer_authority():
		return
	kill_sound.play()
	kills += 1
	health = min(health + 20, MAX_HEALTH)
	_update_hud()

func _update_hud():
	health_label.text = "HP: " + str(health)
	health_bar.value = health
	kills_label.text = "Kills: " + str(kills)
	ammo_label.text = "Ammo: " + str(current_gun.mag) + "/" + str(current_gun.mag_size)

@rpc("any_peer", "call_local", "reliable")
func set_position_on_all(pos: Vector3):
	position = pos

func _die():
	health = MAX_HEALTH
	_update_hud()
	var game = get_parent()
	game.respawn_player.rpc_id(1, int(name))
