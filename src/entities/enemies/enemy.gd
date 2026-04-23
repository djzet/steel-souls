extends CharacterBody2D

@export var data: EnemyResource
@export var data_path: String = "":
	set(value):
		data_path = value
		if not data_path.is_empty():
			_load_data_from_path.call_deferred()

@export var attack_cooldown: float = 0.5
@export var attack_range: float = 50.0

var hp: int
var is_dead: bool = false
var is_fleeing: bool = false
var _next_attack_time: float = 0.0
var _flee_direction: Vector2 = Vector2.ZERO
var _flee_speed: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var anim: AnimationPlayer = $AnimationEnemy

func _enter_tree() -> void:
	set_multiplayer_authority(1)

func _ready() -> void:
	add_to_group("Enemies")
	if not data_path.is_empty():
		_load_data_from_path()
	elif data:
		_setup_enemy()

func _load_data_from_path() -> void:
	if data_path.is_empty(): return
	var res = load(data_path)
	if res is EnemyResource:
		data = res
		_setup_enemy()

func _physics_process(delta: float) -> void:
	if is_fleeing:
		_process_flee(delta)
		return
		
	if not multiplayer.is_server():
		return

	if is_dead or not data: return
	
	var target = _get_closest_player()
	if target:
		var dist = global_position.distance_to(target.global_position)
		var flip = sprite.flip_h
		
		if dist <= attack_range:
			velocity = velocity.move_toward(Vector2.ZERO, data.speed * 2)
			_try_attack(target, delta)
		else:
			velocity = global_position.direction_to(target.global_position) * data.speed
			flip = velocity.x < 0
			_play_anim.rpc("walk", 0.7, flip)
		
		move_and_slide()
	else:
		_play_anim.rpc("idle", 1.0, sprite.flip_h)

func _process_flee(delta: float) -> void:
	_flee_speed += 1000.0 * delta
	velocity = _flee_direction * _flee_speed
	if velocity.x != 0 and sprite: 
		sprite.flip_h = velocity.x < 0
	
	if multiplayer.is_server() and anim.current_animation != "walk":
		_play_anim.rpc("walk", 1.5)
	move_and_slide()

func _try_attack(target: Node2D, delta: float) -> void:
	_next_attack_time -= delta
	
	if _next_attack_time <= 0:
		_play_anim.rpc("attack", 1.0 / attack_cooldown, sprite.flip_h)
		
		if target.has_method("take_damage"):
			target.take_damage.rpc(data.damage)
		
		_next_attack_time = attack_cooldown

@rpc("any_peer", "call_local", "unreliable")
func _play_anim(anim_name: String, speed: float, flip: bool) -> void:
	if sprite: sprite.flip_h = flip
	if anim and anim.has_animation(anim_name):
		anim.speed_scale = speed
		if anim_name in ["attack", "hit", "death"]:
			anim.play(anim_name)
		elif anim.current_animation != anim_name:
			anim.play(anim_name)

@rpc("any_peer", "call_local")
func take_damage(amount: int) -> void:
	if not multiplayer.is_server() or is_dead or is_fleeing: return
	
	hp -= amount
	if anim: anim.play("hit")
	if hp <= 0: 
		_die()

func _setup_enemy() -> void:
	if not data: return
	if sprite == null: sprite = get_node_or_null("Sprite2D")
	if sprite == null: return
	
	hp = data.health
	sprite.texture = data.texture
	sprite.hframes = 8 
	sprite.vframes = 7

func _die() -> void:
	if is_dead: return
	is_dead = true
	set_collision_layer_value(1, false)
	set_collision_mask_value(1, false)
	if is_inside_tree():
		_play_anim.rpc("death", 1.0, sprite.flip_h)
	if multiplayer.is_server():
		var d_time = anim.current_animation_length if (anim and anim.has_animation("death")) else 1.0
		get_tree().create_timer(d_time + 0.5).timeout.connect(func():
			if is_instance_valid(self) and is_inside_tree():
				queue_free()
		)

func set_state_freeze() -> void:
	velocity = Vector2.ZERO
	if anim: anim.speed_scale = 0.0

func set_state_flee(target_pos: Vector2) -> void:
	is_fleeing = true
	var diff = global_position - target_pos
	if diff == Vector2.ZERO: 
		diff = Vector2(randf_range(-1, 1), randf_range(-1, 1))
	_flee_direction = diff.normalized()
	_flee_speed = data.speed
	if anim: 
		anim.speed_scale = 1.5
		anim.play("walk")

func _get_closest_player() -> Node2D:
	var p_group = get_tree().get_nodes_in_group("Players")
	var closest = null
	var min_dist = INF
	for p in p_group:
		if p.is_dead: continue
		var d = global_position.distance_to(p.global_position)
		if d < min_dist: 
			min_dist = d
			closest = p
	return closest
