extends CharacterBody2D

signal health_changed(current_hp)

@export var speed: float = 300.0
@export var accel: float = 1200.0
@export var health: int = 10
@export var invulnerability_time: float = 1.0

var _current_anim_state: String = ""
var is_dead: bool = false
var is_invulnerable: bool = false
var is_network_ready: bool = false

@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var sprite: Sprite2D = $Sprite2D
@onready var col: CollisionShape2D = $CollisionShape2D

func _enter_tree() -> void:
	var id = name.to_int()
	if id > 0:
		set_multiplayer_authority(id)

func _ready() -> void:
	add_to_group("Players")

	set_physics_process(false)
	
	if is_multiplayer_authority():
		$Camera2D.enabled = true
		$Camera2D.make_current()
	else:
		$Camera2D.enabled = false
		modulate.a = 0.5

	await get_tree().process_frame
	await get_tree().process_frame
	
	is_network_ready = true
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not is_network_ready or not is_inside_tree(): return
	if not is_inside_tree() or not is_node_ready(): return
	if not is_multiplayer_authority() or is_dead: return
		
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = velocity.move_toward(dir * speed, accel * delta)
	move_and_slide()
	
	_update_animations_logic(dir)

func _update_animations_logic(dir: Vector2) -> void:
	if not is_inside_tree() or is_dead: return
	
	if anim.current_animation == "hit" and anim.is_playing(): return
		
	var target_anim = "idle"
	var target_flip = sprite.flip_h
	
	if dir.length() > 0.05:
		target_anim = "run"
		target_flip = dir.x < 0
	
	if anim.current_animation != target_anim or target_flip != sprite.flip_h:
		if multiplayer.multiplayer_peer and not multiplayer.get_peers().is_empty():
			_sync_anim.rpc(target_anim, target_flip)

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int) -> void:
	if is_dead or is_invulnerable: return
	health -= amount
	health_changed.emit(health)
	if health <= 0: _die()
	else: _start_invulnerability()

func _update_animations(dir: Vector2) -> void:
	if anim.current_animation == "hit" and anim.is_playing(): 
		return
		
	var new_anim = "idle"
	var flip = sprite.flip_h
	
	if dir != Vector2.ZERO:
		new_anim = "run"
		flip = dir.x < 0
		
	if new_anim != _current_anim_state or flip != sprite.flip_h:
		_current_anim_state = new_anim
		_sync_anim.rpc(new_anim, flip)

@rpc("any_peer", "call_local", "unreliable")
func _sync_anim(anim_name: String, flip: bool) -> void:
	if not is_inside_tree() or not anim: return
	
	if sprite: sprite.flip_h = flip
	if anim:
		if anim_name == "hit": anim.play("hit")
		elif anim.current_animation != anim_name:
			anim.play(anim_name)

func _die() -> void:
	if is_dead: return
	is_dead = true
	
	if has_node("MultiplayerSynchronizer"):
		$MultiplayerSynchronizer.process_mode = PROCESS_MODE_DISABLED
	
	velocity = Vector2.ZERO
	if col: col.set_deferred("disabled", true)
	
	if is_inside_tree():
		_sync_death_anim.rpc(sprite.flip_h)
	
	if is_multiplayer_authority():
		_switch_to_spectator()

@rpc("any_peer", "call_local", "reliable")
func _sync_death_anim(flip: bool) -> void:
	is_dead = true
	velocity = Vector2.ZERO
	if sprite: sprite.flip_h = flip
	if anim: anim.play("death")

func _switch_to_spectator() -> void:
	await get_tree().create_timer(1.0).timeout
	
	while is_dead and is_inside_tree():
		var all_players = get_tree().get_nodes_in_group("Players")
		var living = all_players.filter(func(p): 
			return is_instance_valid(p) and p.is_inside_tree() and not p.is_dead
		)
		
		if living.size() > 0:
			var target = living[0] 
			var target_cam = target.get_node_or_null("Camera2D")
			if is_instance_valid(target_cam):
				target_cam.enabled = true
				target_cam.make_current()
				
			if is_multiplayer_authority():
				var hud = get_tree().root.find_child("HealthHud", true, false)
				if hud and hud.has_method("_setup_hud"):
					hud._setup_hud(target)
		await get_tree().create_timer(1.0).timeout

func _start_invulnerability() -> void:
	is_invulnerable = true
	anim.play("hit")
	var tween = create_tween().set_loops(5)
	tween.tween_property(sprite, "modulate:a", 0.5, 0.1)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.1)
	await get_tree().create_timer(invulnerability_time).timeout
	is_invulnerable = false
