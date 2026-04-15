extends CharacterBody3D
class_name Player

# ─── Movement Constants ───────────────────────────────────────────────────────
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
const JUMP_VELOCITY:  float = 5.5
const MAX_SPEED       := 7.0
const ACCEL           := 20.0
const AIR_ACCEL       := 4.0
const FRICTION        := 7.0
const STOP_SPEED      := 2.5
const COYOTE_DURATION := 0.1

var coyote_timer := 0.0

# ─── Guns ─────────────────────────────────────────────────────────────────────
## Guns that this player spawns with / respawns with.
@export var default_guns: Array[Gun] = []
## Active gun inventory — only mutated on the authority peer.
var guns: Array[Gun] = []
var current_gun_index := 0
var current_gun: Gun

# ─── Mouse ────────────────────────────────────────────────────────────────────
const MOUSE_SENS_X: float = 0.002
const MOUSE_SENS_Y: float = 0.002

# ─── Stats ────────────────────────────────────────────────────────────────────
const MAX_HEALTH = 100
var health      = MAX_HEALTH
var kills       = 0
var ads         = false
var can_shoot   = true

# ─── State ────────────────────────────────────────────────────────────────────
enum MovementState { IDLE, WALKING, IN_AIR }
var movement_state    = MovementState.IDLE
var movement_direction := Vector3.ZERO

# ─── Nodes ────────────────────────────────────────────────────────────────────
@onready var mesh:        MeshInstance3D = $MeshInstance3D3
@onready var head                        = $Head
@onready var camera                      = $Head/Camera3D
@onready var gun_socket                  = $Head/GunSocket
@onready var health_label                = $CanvasLayer/VBoxContainer/HBoxContainer/HealthLabel
@onready var health_bar                  = $CanvasLayer/VBoxContainer/HealthBar
@onready var reload_bar                  = $CanvasLayer/VBoxContainer/ReloadBar
@onready var ammo_label                  = $CanvasLayer/VBoxContainer/HBoxContainer/AmmoLabel
@onready var kills_label                 = $CanvasLayer/KillsLabel
@onready var shoot_sound                 = $ShootSound
@onready var hit_sound                   = $HitSound
@onready var kill_sound                  = $KillSound


# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready():
	add_to_group("players")

	if is_multiplayer_authority():
		mesh.visible = false
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		# Build the gun inventory only on the owning peer so the host's
		# pickup actions never bleed into other clients.
		guns = default_guns.duplicate()
		for gun in guns:
			_connect_gun(gun)
		equip_gun(0)
	else:
		camera.current = false
		$CanvasLayer.visible = false
		# Non-authority peers hide every gun; the authority peer drives
		# visibility through MultiplayerSynchronizer or RPCs as needed.
		for gun in default_guns:
			gun.hide()


# ─── Gun Management ───────────────────────────────────────────────────────────
func equip_gun(index: int) -> void:
	# Guard: only the authority should be changing equipped guns.
	if not is_multiplayer_authority():
		return

	if guns.is_empty():
		return

	# Clamp to valid range instead of silently bailing out.
	index = clampi(index, 0, guns.size() - 1)

	# Hide every gun first.
	for gun in guns:
		gun.hide()

	current_gun_index = index
	current_gun       = guns[index]
	current_gun.show()   # Use show() so the node itself becomes visible.
	_update_hud()


func _connect_gun(gun_instance: Gun) -> void:
	gun_instance.ammo_changed.connect(func(current, max_ammo):
		if gun_instance == current_gun:
			ammo_label.text = "Ammo: %d/%d" % [current, max_ammo]
	)
	gun_instance.shot_fired.connect(func():
		if gun_instance == current_gun:
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
	gun_instance.reload_progress.connect(func(value):
		if gun_instance == current_gun:
			reload_bar.value = value * 100.0
	)
	gun_instance.reload_finished.connect(func():
		if gun_instance == current_gun:
			reload_bar.visible = false
			reload_bar.value   = 0
	)


func _cycle_weapon(dir: int) -> void:
	if guns.is_empty():
		return
	var new_index = posmod(current_gun_index + dir, guns.size())
	equip_gun(new_index)


# ─── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event) -> void:
	if not is_multiplayer_authority():
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var sens_scale = (30.0 / 90.0) if ads else 1.0
		rotate_y(-event.relative.x * MOUSE_SENS_X * sens_scale)
		head.rotate_x(-event.relative.y * MOUSE_SENS_Y * sens_scale)
		head.rotation.x = clampf(head.rotation.x, -deg_to_rad(90), deg_to_rad(85))


func _input(event) -> void:
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
		_jump()

	if event.is_action_pressed("reload") and current_gun:
		current_gun.start_reload()

	if event.is_action_pressed("weapon_next"):
		_cycle_weapon(1)

	if event.is_action_pressed("weapon_prev"):
		_cycle_weapon(-1)


# ─── Physics ──────────────────────────────────────────────────────────────────
func _physics_process(delta) -> void:
	if global_position.y < -100:
		_die()
		return  # Prevent further processing this frame after dying.

	if not is_multiplayer_authority():
		return

	camera.fov            = 30 if ads else 90
	gun_socket.visible    = not ads
	movement_direction    = _get_movement_direction()

	# Gravity
	if not is_on_floor():
		velocity.y     -= gravity * delta
		coyote_timer   -= delta
	else:
		coyote_timer    = COYOTE_DURATION
		if velocity.y < 0:
			velocity.y  = 0

	# Horizontal movement
	if is_on_floor():
		_apply_friction(delta)
		_accelerate(movement_direction, MAX_SPEED, ACCEL, delta)
	else:
		_accelerate(movement_direction, MAX_SPEED, AIR_ACCEL, delta)

	# Shooting — guard against null current_gun
	if current_gun:
		if current_gun.automatic:
			if Input.is_action_pressed("shoot"):
				_shoot()
		else:
			if Input.is_action_just_pressed("shoot"):
				_shoot()

	move_and_slide()


func _apply_friction(delta) -> void:
	var speed = Vector2(velocity.x, velocity.z).length()
	if speed < 0.01:
		return
	var control   = maxf(speed, STOP_SPEED)
	var drop      = control * FRICTION * delta
	var new_speed = maxf(speed - drop, 0.0) / speed
	velocity.x   *= new_speed
	velocity.z   *= new_speed


func _accelerate(wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> void:
	var current_speed = velocity.dot(wish_dir)
	var add_speed     = wish_speed - current_speed
	if add_speed <= 0:
		return
	var accel_speed = minf(accel * delta * wish_speed, add_speed)
	velocity.x += accel_speed * wish_dir.x
	velocity.z += accel_speed * wish_dir.z


func _get_movement_direction() -> Vector3:
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	var forward   = camera.global_transform.basis.z
	var right     = camera.global_transform.basis.x
	forward.y = 0
	right.y   = 0
	return (forward.normalized() * input_dir.y + right.normalized() * input_dir.x).normalized()


func _jump() -> void:
	if is_on_floor() or coyote_timer > 0.0:
		velocity.y   = JUMP_VELOCITY
		coyote_timer = 0.0


# ─── Gun Pickup ───────────────────────────────────────────────────────────────
## Called by the weapon crate RPC on the owning peer only.
## Instantiates and equips a new gun from the given PackedScene path.
func receive_gun(scene_path: String) -> void:
	if not is_multiplayer_authority():
		return

	var scene: PackedScene = load(scene_path)
	if scene == null:
		push_error("Player.receive_gun: could not load scene: " + scene_path)
		return

	var new_gun: Gun = scene.instantiate()
	gun_socket.add_child(new_gun)
	new_gun.hide()  # equip_gun will show it
	guns.append(new_gun)
	_connect_gun(new_gun)
	equip_gun(guns.size() - 1)


# ─── Combat ───────────────────────────────────────────────────────────────────
func _shoot() -> void:
	if current_gun:
		current_gun.shoot(self)


@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, shooter_id: int) -> void:
	if not is_multiplayer_authority():
		return

	health = maxi(health - amount, 0)
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
func _notify_hit() -> void:
	if not is_multiplayer_authority():
		return
	hit_sound.play()


@rpc("any_peer", "call_local", "reliable")
func _notify_kill() -> void:
	if not is_multiplayer_authority():
		return
	kill_sound.play()
	kills  += 1
	health  = mini(health + 20, MAX_HEALTH)
	_update_hud()


func _update_hud() -> void:
	if not is_multiplayer_authority():
		return
	health_label.text = "HP: %d"    % health
	health_bar.value  = health
	kills_label.text  = "Kills: %d" % kills
	if current_gun:
		ammo_label.text = "Ammo: %d/%d" % [current_gun.mag, current_gun.mag_size]


@rpc("any_peer", "call_local", "reliable")
func set_position_on_all(pos: Vector3) -> void:
	position = pos


func _die() -> void:
	if not is_multiplayer_authority():
		return
	# Duplicate so the host's default_guns array is never aliased.
	guns = default_guns.duplicate()
	for gun in guns:
		_connect_gun(gun)
	health = MAX_HEALTH
	equip_gun(0)
	_update_hud()
	get_parent().respawn_player.rpc_id(1, int(name))
