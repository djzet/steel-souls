extends Node2D

@export var player_scene: PackedScene = preload("res://src/entities/player/Player.tscn")

func _ready() -> void:
	await get_tree().process_frame
	Lobby.player_ready.rpc_id(1)

func start_game() -> void:
	if not multiplayer.is_server(): return
	for id in Lobby.players:
		if has_node(str(id)): continue
		var p = player_scene.instantiate()
		p.name = str(id)
		add_child(p, true)
		
		p.position = Vector2(576, 324) + Vector2(randf_range(-50, 50), 0)
		print("СЕРВЕР: Создан узел для ID: ", id)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("exit"):
		_leave_to_menu()

func _leave_to_menu() -> void:
	Lobby.disconnect_game()
	get_tree().change_scene_to_file("res://src/ui/menu/MainMenu.tscn")
