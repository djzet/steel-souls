extends CharacterBody2D

@export var speed: float = 300.0
@export var accel: float = 1200.0
@export var health: int = 10

var is_dead: bool = false

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())

func _ready() -> void:
	add_to_group("Players")
	var player_id = name.to_int()
	if player_id > 0:
		set_multiplayer_authority(player_id)
	if is_multiplayer_authority():
		camera.enabled = true
		camera.make_current()
	else:
		camera.enabled = false
		modulate.a = 0.5

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or is_dead: 
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = velocity.move_toward(dir * speed, accel * delta)
	move_and_slide()
	_update_animations(dir)

func _update_animations(dir: Vector2) -> void:
	if not is_multiplayer_authority(): 
		return
	if is_dead: return
	if anim.current_animation == "death": return
	if anim.current_animation == "hit" and anim.is_playing(): return
	if dir != Vector2.ZERO:
		if anim.current_animation != "run":
			anim.play("run")
		sprite.flip_h = dir.x < 0
	else:
		if anim.current_animation != "idle":
			anim.play("idle")

@rpc("any_peer", "call_local")
func take_damage(amount: int) -> void:
	if is_dead: return
	
	health -= amount
	if health <= 0:
		_die()
	else:
		_play_anim_rpc.rpc("hit")

@rpc("call_local")
func _play_anim_rpc(anim_name: String) -> void:
	anim.play(anim_name)

func _die() -> void:
	is_dead = true
	anim.play("death")
	$CollisionShape2D.set_deferred("disabled", true)
