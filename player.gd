extends CharacterBody3D
class_name Player

@export var guns: Array[Gun] = []
var current_gun_index := 0
var current_gun: Gun

# Mouse
const MOUSE_SENS_X: float = 0.002
const MOUSE_SENS_Y: float = 0.002

# Stats
const MAX_HEALTH = 100
#const DAMAGE = 10
#const CRIT = 3.0
#const FIRE_RATE = 0.08
#const MAG_SIZE = 20
#var mag = MAG_SIZE
#const RELOAD_RATE = 1.0
# Movement modes
enum MovementMode { WALK, SLIDE }
var movement_mode = MovementMode.WALK

enum MovementState { IDLE, WALKING, GLIDING, IN_AIR, WALL_GLIDING }
var movement_state = MovementState.IDLE

# Movement tuning
const COYOTE_DURATION = 0.5
const JUMP_COOLDOWN_DURATION = 0.2
const TERMINAL_VELOCITY = 1000.0
const AIR_DRAG = 0.05
const MIN_SLIDE_SPEED = 3.0

const WALK_MAX_SPEED = 4.5
const WALK_ACCEL = 40.0
const WALK_FRICTION = 30.0
const WALK_JUMP_POWER = 8.0
const WALK_JUMP_ANGLE = 10.0

const SLIDE_MAX_SPEED = 8.0
const SLIDE_ACCEL = 4.0
const SLIDE_FRICTION = 5.0
const SLIDE_ENTRY_BOOST = 2.0
const SLIDE_JUMP_POWER = 8.0
const SLIDE_JUMP_ANGLE = 27.0

const GUN_SLIDE_ROTATION = deg_to_rad(-35.0)
const GUN_ROTATE_SPEED = 10.0

const AIR_ACCEL = 20.0
const AIR_MAX_SPEED = 5.0

const DOUBLE_JUMP_POWER = 8.0

const WALL_JUMP_POWER = 8.0
const WALL_JUMP_NORMAL = 1.5
const WALL_JUMP_FACING = 1.0
const WALL_JUMP_VERTICAL = 3.0
const STICK_FORCE = 150.0
const STICK_GRAVITY_ROTATION = 0.7
const WALL_RUN_ASSIST = 0.4

const SLOPE_ACCEL_MULTIPLIER = 5.0
const MIN_SLOPE_ANGLE = 5.0
const MAX_SLOPE_ANGLE = 60.0

# Movement state vars
var coyote_timer: float = 0.0
var jump_cooldown_timer: float = 0.2
var has_double_jump: bool = false
var is_jumping_from_wall: bool = false
var is_near_magnetic_wall: bool = false
var wall_normal: Vector3
var movement_direction: Vector3
var current_velocity: Vector3
var can_slide: bool = true
var on_unslidable_surface: bool = false

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
@onready var magnetic_range: Area3D = $MagneticRange
@onready var wall_raycasts = [
	$WallDetection/RayCastLeft,
	$WallDetection/RayCastRight,
	$WallDetection/RayCastUp,
	$WallDetection/RayCastForward,
	$WallDetection/RayCastBackward,
]
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
	$MeshInstance3D.hide()
	if is_multiplayer_authority():
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		camera.current = false
		$CanvasLayer.visible = false

	magnetic_range.body_entered.connect(near_magnetic_wall)
	magnetic_range.body_exited.connect(left_magnetic_wall)

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
	if event.is_action_pressed("slide"):
		start_slide()
	if event.is_action_released("slide"):
		stop_slide()
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
	
	var horiz_vel = Vector3(current_velocity.x, 0, current_velocity.z)
	can_slide = horiz_vel.length() >= MIN_SLIDE_SPEED
	
	current_velocity = velocity
	
	update_coyote_timer(delta)
	update_jump_cooldown_timer(delta)
	update_movement_states()
	apply_forces(delta)
	#update_gun_rotation(delta)
	
	current_velocity = current_velocity.clamp(
		Vector3(-999, -TERMINAL_VELOCITY, -999),
		Vector3(999, 999, 999)
	)
	velocity = current_velocity
	move_and_slide()
	
	if current_gun.automatic:	
		if Input.is_action_pressed("shoot") and can_shoot and movement_mode != MovementMode.SLIDE:
			_shoot()
	else:
		if Input.is_action_just_pressed("shoot") and can_shoot and movement_mode != MovementMode.SLIDE:
			_shoot()

# ─── Movement Direction ───────────────────────────────────────────────────────

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

func update_coyote_timer(delta: float):
	if movement_state == MovementState.IN_AIR:
		coyote_timer = -1.0
		return
	if is_on_floor():
		coyote_timer = COYOTE_DURATION
		has_double_jump = true
	else:
		coyote_timer -= delta

func update_jump_cooldown_timer(delta: float):
	if movement_state != MovementState.IN_AIR:
		jump_cooldown_timer = JUMP_COOLDOWN_DURATION
	else:
		jump_cooldown_timer -= delta

func update_movement_states():
	if is_on_floor():
		if movement_direction.length() > 0.1:
			if movement_mode == MovementMode.WALK:
				movement_state = MovementState.WALKING
			else:
				movement_state = MovementState.GLIDING
		elif movement_mode == MovementMode.SLIDE:
			movement_state = MovementState.GLIDING
		else:
			movement_state = MovementState.IDLE
	else:
		if coyote_timer >= 0.0:
			return
		if movement_state != MovementState.WALL_GLIDING:
			movement_state = MovementState.IN_AIR
			
#func update_gun_rotation(delta: float):
	#var target_rot = 0.0
	#
	#if movement_mode == MovementMode.SLIDE:
		#target_rot = GUN_SLIDE_ROTATION
	#
	#current_gun.rotation.x = lerp(current_gun.rotation.x, target_rot, GUN_ROTATE_SPEED * delta)

# ─── Forces ───────────────────────────────────────────────────────────────────

func apply_forces(delta: float):
	current_velocity += get_movement_force(delta)
	current_velocity += get_gravity_force(delta)
	current_velocity += get_friction_force(delta)
	current_velocity += get_wall_stick_force(delta)
	if is_on_floor():
		current_velocity += get_slope_acceleration(delta)

func get_movement_force(delta: float) -> Vector3:
	if movement_direction.length() == 0:
		return Vector3.ZERO
	var horiz_vel = Vector3(current_velocity.x, 0, current_velocity.z)
	match movement_state:
		MovementState.IN_AIR, MovementState.WALL_GLIDING:
			return get_airstrafe_force(delta, horiz_vel, movement_direction, AIR_ACCEL, AIR_MAX_SPEED)
		MovementState.GLIDING:
			return get_gliding_force(delta, horiz_vel, movement_direction, SLIDE_ACCEL, SLIDE_MAX_SPEED)
		_:
			return get_ground_force(delta, horiz_vel, movement_direction, WALK_ACCEL, WALK_MAX_SPEED)

func get_airstrafe_force(delta, horiz_vel, wish_dir, accel, max_speed) -> Vector3:
	var dv = _accelerate(horiz_vel, wish_dir, max_speed, accel, delta)
	return Vector3(dv.x, 0.0, dv.z)

func get_gliding_force(delta, horiz_vel, wish_dir, accel, max_speed) -> Vector3:
	var target_velocity = movement_direction * current_velocity.length()
	var velocity_diff = target_velocity - horiz_vel
	var dv = _accelerate(horiz_vel, wish_dir, max_speed, accel, delta)
	return velocity_diff * delta + dv

func get_ground_force(delta, horiz_vel, wish_dir, accel, max_speed) -> Vector3:
	var dv = _accelerate(horiz_vel, wish_dir, max_speed, accel, delta)
	return Vector3(dv.x, 0.0, dv.z)

func _accelerate(horiz_vel: Vector3, wish_dir: Vector3, wish_speed: float, accel: float, delta: float) -> Vector3:
	var current = horiz_vel.dot(wish_dir)
	var add = wish_speed - current
	if add <= 0.0:
		return Vector3.ZERO
	var accel_speed = accel * wish_speed * delta
	if accel_speed > add:
		accel_speed = add
	return wish_dir * accel_speed

func get_gravity_force(delta: float) -> Vector3:
	if is_on_floor():
		return Vector3.ZERO
	var gravity = get_gravity()
	if movement_state == MovementState.WALL_GLIDING:
		var wall_gravity = wall_normal * gravity.length()
		gravity = gravity.lerp(wall_gravity, STICK_GRAVITY_ROTATION)
	return gravity * delta * 2.0

func get_friction_force(delta: float) -> Vector3:
	if is_on_floor():
		var friction = WALK_FRICTION if movement_mode == MovementMode.WALK else SLIDE_FRICTION
		var horiz_vel = Vector3(current_velocity.x, 0, current_velocity.z)
		if horiz_vel.length() > 0:
			var mag = min(friction * delta, horiz_vel.length())
			return -horiz_vel.normalized() * mag
	else:
		if movement_state == MovementState.WALL_GLIDING:
			return Vector3.ZERO
		return -current_velocity * AIR_DRAG * delta
	return Vector3.ZERO

func get_slope_acceleration(delta: float) -> Vector3:
	if movement_state != MovementState.GLIDING or on_unslidable_surface:
		return Vector3.ZERO
	var floor_normal = get_floor_normal()
	var slope_angle = rad_to_deg(acos(floor_normal.dot(Vector3.UP)))
	if slope_angle < MIN_SLOPE_ANGLE:
		return Vector3.ZERO
	slope_angle = min(slope_angle, MAX_SLOPE_ANGLE)
	var slope_gravity = Vector3.DOWN - floor_normal * Vector3.DOWN.dot(floor_normal)
	slope_gravity = slope_gravity.normalized()
	var gravity_strength = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
	return slope_gravity * gravity_strength * sin(deg_to_rad(slope_angle)) * SLOPE_ACCEL_MULTIPLIER * delta

# ─── Wall Riding ──────────────────────────────────────────────────────────────

func get_wall_stick_force(delta) -> Vector3:
	if is_on_floor():
		is_jumping_from_wall = false
		return Vector3.ZERO
	if movement_mode != MovementMode.SLIDE:
		if movement_state == MovementState.WALL_GLIDING:
			movement_state = MovementState.IN_AIR
		is_jumping_from_wall = false
		return Vector3.ZERO
	var wall_hit = detect_wall()
	if wall_hit.is_empty() or not is_near_magnetic_wall:
		if movement_state == MovementState.WALL_GLIDING:
			movement_state = MovementState.IN_AIR
		is_jumping_from_wall = false
		return Vector3.ZERO
	if is_jumping_from_wall:
		movement_state = MovementState.IN_AIR
		return Vector3.ZERO
	
	wall_normal = wall_hit["normal"]
	
	if movement_state != MovementState.WALL_GLIDING:
		if current_velocity.y < 0:
			current_velocity += Vector3(0, -current_velocity.y, 0) * 1.2
		movement_state = MovementState.WALL_GLIDING
	
	var stick_velocity = -wall_normal * STICK_FORCE
	var wall_assist = get_wall_slide_assist()
	return (stick_velocity + wall_assist) * delta

func detect_wall() -> Dictionary:
	for raycast in wall_raycasts:
		if raycast.is_colliding():
			return {
				"position": raycast.get_collision_point(),
				"normal": raycast.get_collision_normal(),
				"object": raycast.get_collider()
			}
	return {}

func near_magnetic_wall(_body):
	is_near_magnetic_wall = true

func left_magnetic_wall(_body):
	if wall_normal.dot(Vector3.DOWN) > 0.8:
		return
	if magnetic_range.get_overlapping_bodies().size() > 0:
		return
	movement_state = MovementState.IN_AIR
	is_near_magnetic_wall = false

func get_wall_slide_assist() -> Vector3:
	var wall_tangent = wall_normal.cross(Vector3.UP)
	if wall_tangent.dot(current_velocity) < 0:
		wall_tangent = -wall_tangent
	var velocity_diff = wall_tangent * current_velocity.length() - current_velocity
	return velocity_diff * WALL_RUN_ASSIST

# ─── Slide ────────────────────────────────────────────────────────────────────

func start_slide():
	movement_state = MovementState.GLIDING
	movement_mode = MovementMode.SLIDE
	if not can_slide or on_unslidable_surface:
		return
	var horiz_vel = Vector3(current_velocity.x, 0, current_velocity.z)
	if horiz_vel.length() > 0 and is_on_floor():
		velocity += horiz_vel.normalized() * SLIDE_ENTRY_BOOST

func stop_slide():
	if movement_mode != MovementMode.SLIDE:
		return
	movement_mode = MovementMode.WALK
	movement_state = MovementState.WALKING if is_on_floor() else MovementState.IN_AIR

# ─── Jump ─────────────────────────────────────────────────────────────────────

func jump():
	if not has_double_jump:
		if movement_state == MovementState.IN_AIR and coyote_timer <= 0.0:
			return
		if jump_cooldown_timer <= 0.0:
			return
	
	var jump_vector = Vector3.UP
	
	match movement_state:
		MovementState.IDLE, MovementState.WALKING:
			velocity += jump_vector * WALK_JUMP_POWER
			has_double_jump = true
		
		MovementState.WALL_GLIDING:
			var facing = -camera.global_basis.z
			jump_vector = (
				jump_vector * WALL_JUMP_VERTICAL +
				facing * WALL_JUMP_FACING +
				wall_normal * WALL_JUMP_NORMAL
			).normalized()
			velocity += jump_vector * WALL_JUMP_POWER
			has_double_jump = true
			is_jumping_from_wall = true
		
		MovementState.GLIDING:
			if movement_direction.length_squared() > 0.01:
				jump_vector = (jump_vector + movement_direction * (SLIDE_JUMP_ANGLE / 90.0)).normalized()
			else:
				jump_vector = jump_vector.rotated(-camera.global_basis.x, deg_to_rad(SLIDE_JUMP_ANGLE))
			velocity += jump_vector * SLIDE_JUMP_POWER
			has_double_jump = true
		
		MovementState.IN_AIR:
			if not has_double_jump:
				return
			if movement_direction.length_squared() > 0.01:
				jump_vector = (jump_vector + movement_direction * (SLIDE_JUMP_ANGLE / 90.0)).normalized()
			else:
				jump_vector = jump_vector.rotated(-camera.global_basis.x, deg_to_rad(SLIDE_JUMP_ANGLE))
			var downwards = velocity.y if velocity.y < 0.0 else 0.0
			velocity += jump_vector * DOUBLE_JUMP_POWER + Vector3(0, -downwards, 0)
			has_double_jump = false
	
	movement_state = MovementState.IN_AIR

# ─── Combat ───────────────────────────────────────────────────────────────────

func _shoot():
	if current_gun:
		current_gun.shoot(self)
	#if is_reloading:
		#return
	#if mag <= 0:
		#start_reload()
		#return
		#
	#can_shoot = false
	#mag -= 1
	#_update_hud()
	#get_tree().create_timer(FIRE_RATE).timeout.connect(func(): can_shoot = true)
	#$AnimationPlayer.play("shoot")
	#shoot_sound.play()
	#if not raycast.is_colliding():
		#return
	#var hit = raycast.get_collider()
	#if hit == null or hit == self:
		#return
	#
	#if hit is Area3D and hit.get_parent() and hit.get_parent().has_method("take_damage"):
		#if hit.is_in_group("head"):
			#hit.get_parent().take_damage.rpc_id(hit.get_multiplayer_authority(), DAMAGE * CRIT, multiplayer.get_unique_id())
			#kill_sound.play()
			#
		#else:
			#hit.get_parent().take_damage.rpc_id(hit.get_multiplayer_authority(), DAMAGE, multiplayer.get_unique_id())
			

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
	
#func start_reload():
	#if is_reloading:
		#return
	#if mag == MAG_SIZE:
		#return
	#
	#is_reloading = true
	#can_shoot = false
	#
	#reload_bar.visible = true
	#reload_bar.value = 0
	#
	#_reload()
#
#func _reload():
	#var elapsed := 0.0
	#
	#while elapsed < RELOAD_RATE:
		#await get_tree().process_frame
		#elapsed += get_process_delta_time()
		#reload_bar.value = (elapsed / RELOAD_RATE) * 100.0
	#
	#_finish_reload()
	#
#func _finish_reload():
	#mag = MAG_SIZE
	#is_reloading = false
	#can_shoot = true
	#
	#reload_bar.visible = false
	#reload_bar.value = 0
	#_update_hud()
	#
func _die():
	health = MAX_HEALTH
	_update_hud()
	var game = get_parent()
	game.respawn_player.rpc_id(1, int(name))
