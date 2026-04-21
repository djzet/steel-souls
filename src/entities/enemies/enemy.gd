extends CharacterBody2D

@export var data: EnemyResource
@export var attack_cooldown: float = 1.0
@export var data_path: String = ""

var hp: int
var is_dead: bool = false
var next_attack_time: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationEnemy 

func _ready() -> void:
	add_to_group("Enemies")
	if not multiplayer.is_server():
		if data_path == "":
			await get_tree().create_timer(0.01).timeout
	if data_path != "":
		data = load(data_path)
		_setup_enemy()

func _setup_enemy() -> void:
	hp = data.health
	sprite.texture = data.texture
	sprite.hframes = 8 
	sprite.vframes = 7
	if anim.has_animation("walk"):
		anim.play("walk")

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or is_dead or not data: return
	var target = _get_closest_player()
	if target:
		var dir = global_position.direction_to(target.global_position)
		velocity = dir * data.speed
		move_and_slide()
		if velocity.x != 0:
			sprite.flip_h = velocity.x < 0
		_check_attack_logic(delta)

func _check_attack_logic(delta: float) -> void:
	next_attack_time -= delta
	if next_attack_time > 0: return
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var body = collision.get_collider()
		if body.is_in_group("Players") and body.has_method("take_damage"):
			body.take_damage.rpc(data.damage)
			next_attack_time = attack_cooldown
			break

func _get_closest_player() -> Node2D:
	var players = get_tree().get_nodes_in_group("Players")
	var closest = null
	var min_dist = INF
	for p in players:
		if p.get("is_dead"): continue 
		var d = global_position.distance_to(p.global_position)
		if d < min_dist:
			min_dist = d
			closest = p
	return closest

@rpc("any_peer", "call_local")
func take_damage(amount: int) -> void:
	if not multiplayer.is_server() or is_dead: return
	hp -= amount
	if hp <= 0:
		_die()

func _die() -> void:
	is_dead = true
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	if anim.has_animation("death"):
		anim.play("death")
		await anim.animation_finished
	queue_free()
