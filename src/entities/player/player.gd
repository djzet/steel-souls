extends CharacterBody2D

@export var speed = 300.0
@export var accel = 1200.0

func _ready():
	add_to_group("Players")
	$MultiplayerSynchronizer.set_multiplayer_authority(name.to_int())
	
	if $MultiplayerSynchronizer.is_multiplayer_authority():
		$Camera2D.enabled = true
		$Camera2D.make_current()
	else:
		$Camera2D.enabled = false
		modulate.a = 0.5

func _physics_process(delta):
	if not $MultiplayerSynchronizer.is_multiplayer_authority(): 
		return
	
	var dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = velocity.move_toward(dir * speed, accel * delta)
	
	if dir.x != 0:
		$Sprite2D.flip_h = dir.x < 0
		
	move_and_slide()
