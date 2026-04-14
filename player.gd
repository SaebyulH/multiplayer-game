extends CharacterBody3D

const SPEED = 4.0
const JUMP_VELOCITY = 10
const GRAVITY = 9.8
var MOUSE_SENSITIVITY = 0.003
const MAX_HEALTH = 100
const DAMAGE = 125
const FIRE_RATE = 0.5

var health = MAX_HEALTH
var can_shoot = true
var ads = false

@onready var head = $Head
@onready var camera = $Head/Camera3D
@onready var raycast = $Head/Camera3D/AttackRaycast
@onready var health_label = $CanvasLayer/VBoxContainer/HealthLabel
@onready var health_bar = $CanvasLayer/VBoxContainer/HealthBar

func _ready():
	if is_multiplayer_authority():
		camera.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		raycast.add_exception(self)
	else:
		camera.current = false
		$CanvasLayer.visible = false

func _unhandled_input(event):
	if not is_multiplayer_authority():
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(80))

func _input(event):
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event.is_action_pressed("ads"):
		ads = not ads
		MOUSE_SENSITIVITY = 0.001 if ads else 0.0025
	if event is InputEventMouseButton and event.pressed:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	if ads:
		$Head/Camera3D.fov = 30
	else:
		$Head/Camera3D.fov = 90
	if not is_multiplayer_authority():
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	var input_dir = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_backward")
	)
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
	move_and_slide()
	if Input.is_action_just_pressed("shoot") and can_shoot:
		_shoot()

func _shoot():
	can_shoot = false
	get_tree().create_timer(FIRE_RATE).timeout.connect(func(): can_shoot = true)
	$AnimationPlayer.play("shoot")
	
	if not raycast.is_colliding():
		return
	var hit = raycast.get_collider()
	if hit == null or hit == self:
		return
	print("Shot hit: ", hit.name)
	if hit is CharacterBody3D and hit.has_method("take_damage"):
		hit.take_damage.rpc_id(hit.get_multiplayer_authority(), DAMAGE)

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int):
	if not is_multiplayer_authority():
		return
	health -= amount
	health = max(health, 0)
	print("I took damage! Health: ", health)
	_update_hud()
	if health <= 0:
		_die()

func _update_hud():
	health_label.text = "HP: " + str(health)
	health_bar.value = health

@rpc("any_peer", "call_local", "reliable")
func set_position_on_all(pos: Vector3):
	position = pos

func _die():
	print("I died!")
	health = MAX_HEALTH
	_update_hud()
	# Tell the server to respawn us at the correct spawn point
	var game = get_parent()
	game.respawn_player.rpc_id(1, int(name))
