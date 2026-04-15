extends Node3D
class_name Gun

@export var damage = 10
@export var crit = 3.0
@export var fire_rate = 0.08
@export var mag_size = 20
@export var reload_rate = 1.0
@export var bullet_hole_scene: PackedScene = preload("res://weapons/models/bullet_hole.tscn")
@export var automatic = true

@export var arms: Array[MeshInstance3D] = []


var reload_time := 0.0
var mag = mag_size
@onready var muzzle_flash = $Muzzle/MuzzleFlash

var can_shoot := true
var is_reloading := false

@onready var raycasts: Array = $Raycasts.get_children()

signal shot_fired
signal hit_confirmed
signal kill_confirmed
signal ammo_changed(current, max)
signal reload_started
signal reload_finished
signal reload_progress(value)

func hide_arms():
	for arm in arms:
		arm.hide()

func show_arms():
	for arm in arms:
		arm.show()

func _ready() -> void:
	mag = mag_size

func _process(delta):
	if not is_reloading:
		return
	
	reload_time += delta
	
	var progress = reload_time / reload_rate
	progress = clamp(progress, 0.0, 1.0)
	
	reload_progress.emit(progress)
	
	if reload_time >= reload_rate:
		_finish_reload()

func shoot(owner):
	if is_reloading:
		return
	
	if mag <= 0:
		start_reload()
		return
	
	if not can_shoot:
		return
	$AnimationPlayer.play("shoot")
	
	can_shoot = false
	mag -= 1
	ammo_changed.emit(mag, mag_size)
	shot_fired.emit()
	muzzle_flash.emitting = true
	
	get_tree().create_timer(fire_rate).timeout.connect(func(): can_shoot = true)
	
	for ray in raycasts:
		if not ray.is_colliding():
			continue
		
		var hit = ray.get_collider()
		if hit == null or hit == owner:
			continue
		
		var hit_point = ray.get_collision_point()
		var hit_normal = ray.get_collision_normal()
		
		# spawn bullet hole
		if bullet_hole_scene:
			var hole = bullet_hole_scene.instantiate()
			get_tree().current_scene.add_child(hole)
			
			hole.global_position = hit_point
			hole.look_at(hit_point + hit_normal, Vector3.UP)
		
		if hit is Area3D and hit.get_parent() and hit.get_parent().has_method("take_damage"):
			var dmg = damage
			
			if hit.is_in_group("head"):
				dmg *= crit
			
			hit.get_parent().take_damage.rpc_id(
				hit.get_multiplayer_authority(),
				dmg,
				owner.multiplayer.get_unique_id()
			)
			
			hit_confirmed.emit()

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
