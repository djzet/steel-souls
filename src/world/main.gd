extends Node2D

@export var player_scene: PackedScene = preload("res://src/entities/player/Player.tscn")

func _ready():
	await get_tree().process_frame
	Lobby.player_ready.rpc_id(1)

func start_game():
	if not multiplayer.is_server(): return
	
	for id in Lobby.players:
		var p = player_scene.instantiate()
		p.name = str(id)
		p.position = Vector2(200 + (randf() * 100), 200)
		add_child(p)
