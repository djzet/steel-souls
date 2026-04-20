extends Node

signal player_connected(id: int, info: Dictionary)
signal connection_failed

const PORT = 7777
const MAX_CLIENTS = 2
const MAIN_SCENE = "res://src/world/Main.tscn"

var players = {}
var player_info = {"name": "Souls"}
var players_ready = 0

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connection_ok)
	multiplayer.connection_failed.connect(_on_connection_fail)
	multiplayer.server_disconnected.connect(_on_connection_fail)

func create_game():
	var peer = ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_CLIENTS) != OK: return ERR_CANT_CREATE
	multiplayer.multiplayer_peer = peer
	players[1] = player_info
	return OK

func join_game(ip):
	var peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip, PORT) != OK: return ERR_CANT_CONNECT
	multiplayer.multiplayer_peer = peer
	return OK

@rpc("call_local", "reliable")
func load_game(path):
	get_tree().change_scene_to_file(path)

@rpc("any_peer", "call_local", "reliable")
func player_ready():
	if multiplayer.is_server():
		players_ready += 1
		if players_ready == players.size():
			get_node("/root/Game").start_game()
			players_ready = 0

@rpc("any_peer", "reliable")
func _register_player(info):
	var id = multiplayer.get_remote_sender_id()
	players[id] = info
	player_connected.emit(id, info)
	if multiplayer.is_server() and players.size() == MAX_CLIENTS:
		load_game.rpc(MAIN_SCENE)

func _on_peer_connected(id):
	_register_player.rpc_id(id, player_info)

func _on_connection_ok():
	var id = multiplayer.get_unique_id()
	players[id] = player_info
	_register_player.rpc_id(1, player_info)

func _on_connection_fail():
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	connection_failed.emit()
