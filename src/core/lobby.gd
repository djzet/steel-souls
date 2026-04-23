extends Node

signal player_connected(id: int, info: Dictionary)
signal player_disconnected(id: int)
signal connection_failed

const PORT: int = 7777
const MAX_CLIENTS: int = 2
const MAIN_SCENE: String = "res://src/world/Main.tscn"
const MENU_SCENE: String = "res://src/ui/menu/MainMenu.tscn"

var players: Dictionary = {}
var player_info: Dictionary = {"name": "Souls"}
var world_seed: int = 0
var ready_players: Array = []

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connection_ok)
	multiplayer.connection_failed.connect(_on_connection_fail)
	multiplayer.server_disconnected.connect(_on_connection_fail)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func create_game() -> Error:
	disconnect_game()
	world_seed = randi() 
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CLIENTS)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	players[1] = player_info
	return OK

func join_game(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(ip, PORT)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	return OK

@rpc("any_peer", "call_local", "reliable")
func load_game(path: String, incoming_seed: int = 0) -> void:
	ready_players.clear() 
	if incoming_seed != 0:
		world_seed = incoming_seed
	get_tree().change_scene_to_file(path)

@rpc("any_peer", "call_local", "reliable")
func notify_player_ready() -> void:
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	
	if not ready_players.has(sender_id):
		ready_players.append(sender_id)

	if ready_players.size() == players.size():

		await get_tree().create_timer(1.0).timeout
		
		var game_node = get_tree().root.find_child("Main", true, false)
		if game_node and game_node.has_method("start_game"): 
			game_node.start_game()

@rpc("any_peer", "reliable")
func _register_player(info: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	players[id] = info
	player_connected.emit(id, info)
	if multiplayer.is_server() and players.size() == MAX_CLIENTS:
		load_game.rpc(MAIN_SCENE, world_seed)

func _on_peer_connected(id: int) -> void:
	_register_player.rpc_id(id, player_info)

func _on_connection_ok() -> void:
	var id := multiplayer.get_unique_id()
	players[id] = player_info
	_register_player.rpc_id(1, player_info)

func _on_connection_fail() -> void:
	disconnect_game()
	if get_tree().current_scene.name != "MainMenu":
		get_tree().change_scene_to_file(MENU_SCENE)
	connection_failed.emit()

func _on_peer_disconnected(id: int) -> void:
	if players.has(id): players.erase(id)
	player_disconnected.emit(id)
	
	if multiplayer.is_server():
		var game = get_tree().root.find_child("Main", true, false)
		if game:
			var player_node = game.get_node_or_null(str(id))
			if player_node:
				player_node.queue_free()

func start_solo() -> void:
	disconnect_game()
	world_seed = randi()
	var peer := ENetMultiplayerPeer.new()
	peer.create_server(PORT, 1)
	multiplayer.multiplayer_peer = peer
	players[1] = player_info
	load_game(MAIN_SCENE, world_seed)

func disconnect_game() -> void:
	if multiplayer.multiplayer_peer: 
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	ready_players.clear()


func load_game_safe() -> void:
	if not multiplayer.is_server(): return
	var new_seed = randi()
	_load_game_rpc.rpc(MAIN_SCENE, new_seed)
	await get_tree().create_timer(0.7).timeout
	_perform_scene_change(MAIN_SCENE, new_seed)

@rpc("authority", "call_remote", "reliable")
func _load_game_rpc(path: String, incoming_seed: int) -> void:
	_perform_scene_change(path, incoming_seed)

func _perform_scene_change(path: String, incoming_seed: int) -> void:
	Lobby.world_seed = incoming_seed
	ready_players.clear()
	get_tree().change_scene_to_file(path)
