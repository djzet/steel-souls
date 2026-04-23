extends Node2D

const CHUNK_SIZE: int = 32
const RENDER_DISTANCE: int = 2
const CHECK_INTERVAL: float = 0.2
const MIN_DECOR_DISTANCE: int = 15

@export_group("Префабы")
@export var player_scene: PackedScene = preload("res://src/entities/player/Player.tscn")
@export var enemy_scene: PackedScene = preload("res://src/entities/enemies/Enemy.tscn")
@export var torch_light_scene: PackedScene = preload("res://src/world/TorchLight.tscn")

@export_group("Данные врагов")
@export var all_enemy_types: Array[EnemyResource] = [] 

@export_group("Состояние игры")
@export var time_elapsed: int = 0
@export var current_tier: int = 1
@export var world_seed: int = 0

var _generated_chunks: Array[Vector2i] = []
var _chunk_queue: Array[Vector2i] = []
var _check_timer: float = 0.0
var _is_wave_active: bool = false
var _game_ended: bool = false
var _game_started: bool = false

@onready var tile_map: TileMapLayer = $TileMapLayer
@onready var decor_layer: TileMapLayer = $DecorLayer
@onready var game_over: CanvasLayer = $GameOver
@onready var tile_size: float = tile_map.tile_set.tile_size.x

func _ready() -> void:
	world_seed = Lobby.world_seed
	if has_node("MultiplayerSynchronizer"):
		$MultiplayerSynchronizer.public_visibility = false
	_queue_chunks_around_player(Vector2(576, 324)) 
	if not is_node_ready(): await ready

	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		
	Lobby.notify_player_ready.rpc_id(1)

func _process(delta: float) -> void:
	_update_timer_ui()
	_process_chunk_generation(delta)
	if multiplayer.is_server() and not _game_ended: 
		_check_all_players_dead()

func start_game() -> void:
	if not multiplayer.is_server(): return
	if _game_started: return
	
	_game_started = true
	
	if has_node("MultiplayerSynchronizer"):
		$MultiplayerSynchronizer.public_visibility = true

	for id in Lobby.players:
		if has_node(str(id)): continue 
		_spawn_player(id)

	await get_tree().create_timer(0.2).timeout
	
	_start_timers()

func _spawn_player(id: int) -> void:
	if has_node(str(id)): return 
	var p = player_scene.instantiate()
	p.name = str(id)
	add_child(p, true) 
	p.global_position = Vector2(576, 324) + Vector2(randf_range(-60, 60), 0)

func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server(): return
	var player_node = get_node_or_null(str(id))
	if player_node:
		if player_node.has_node("MultiplayerSynchronizer"):
			player_node.get_node("MultiplayerSynchronizer").public_visibility = false
		player_node.queue_free()

func _start_timers() -> void:
	if has_node("GameTimer"):
		var gt = $GameTimer
		if not gt.timeout.is_connected(_on_timer_tick): 
			gt.timeout.connect(_on_timer_tick)
		gt.start()
			
	if has_node("EnemyTimer"):
		var et = $EnemyTimer
		if not et.timeout.is_connected(_on_enemy_spawn_tick): 
			et.timeout.connect(_on_enemy_spawn_tick)
		et.start()

func _check_all_players_dead() -> void:
	if not _game_started or _game_ended: return
	
	var players = get_tree().get_nodes_in_group("Players")
	if players.is_empty(): return
	
	var all_dead = true
	for p in players:
		if is_instance_valid(p) and not p.is_dead:
			all_dead = false
			break
			
	if all_dead:
		_trigger_game_over.rpc()

@rpc("call_local", "reliable")
func _trigger_game_over() -> void:
	_game_ended = true 
	if has_node("GameTimer"): $GameTimer.stop()
	if has_node("EnemyTimer"): $EnemyTimer.stop()
	
	var p_group = get_tree().get_nodes_in_group("Players")
	var death_point = p_group[0].global_position if not p_group.is_empty() else Vector2(576, 324)

	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if enemy.has_method("set_state_freeze"): 
			enemy.set_state_freeze()
			
	await get_tree().create_timer(1.5).timeout
	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if enemy.has_method("set_state_flee"): 
			enemy.set_state_flee(death_point)
			
	await get_tree().create_timer(2.5).timeout
	if game_over:
		game_over.show()
		_setup_restart_button()

func _setup_restart_button() -> void:
	var btn: Button = game_over.get_node_or_null("%Restart")
	if not btn: return
	if multiplayer.is_server():
		btn.disabled = false
		btn.text = "Начать заново"
		if not btn.pressed.is_connected(_on_restart_pressed): 
			btn.pressed.connect(_on_restart_pressed)
	else:
		btn.disabled = true
		btn.text = "Ожидание хоста..."

func _exit_tree() -> void:
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)

func _on_restart_pressed() -> void:
	if not multiplayer.is_server(): return

	if has_node("MultiplayerSpawner"):
		var spawner = $MultiplayerSpawner
		remove_child(spawner)
		spawner.queue_free()

	var synced_nodes = get_tree().get_nodes_in_group("Players") + get_tree().get_nodes_in_group("Enemies")
	for node in synced_nodes:
		if is_instance_valid(node):
			if node.has_node("MultiplayerSynchronizer"):
				var ms = node.get_node("MultiplayerSynchronizer")
				ms.public_visibility = false
				ms.process_mode = PROCESS_MODE_DISABLED
			node.process_mode = PROCESS_MODE_DISABLED

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	Lobby.load_game_safe()

func _queue_chunks_around_player(player_pos: Vector2) -> void:
	var p_x = int(floorf(player_pos.x / (CHUNK_SIZE * tile_size)))
	var p_y = int(floorf(player_pos.y / (CHUNK_SIZE * tile_size)))
	for x in range(p_x - RENDER_DISTANCE, p_x + RENDER_DISTANCE + 1):
		for y in range(p_y - RENDER_DISTANCE, p_y + RENDER_DISTANCE + 1):
			var coord = Vector2i(x, y)
			if not _generated_chunks.has(coord) and not _chunk_queue.has(coord): 
				_chunk_queue.append(coord)

func _process_chunk_generation(delta: float) -> void:
	_check_timer += delta
	if _check_timer >= CHECK_INTERVAL:
		_check_timer = 0.0
		for player in get_tree().get_nodes_in_group("Players"): 
			_queue_chunks_around_player(player.global_position)
	if _chunk_queue.size() > 0:
		var next = _chunk_queue.pop_front()
		if not _generated_chunks.has(next): 
			_generate_chunk(next)

func _generate_chunk(chunk_pos: Vector2i) -> void:
	_generated_chunks.append(chunk_pos)
	seed(Lobby.world_seed + hash(chunk_pos))
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	for x in range(start_x, start_x + CHUNK_SIZE):
		for y in range(start_y, start_y + CHUNK_SIZE):
			var tile_pos = Vector2i(x, y)
			var r = randf()
			var floor_tile = Vector2i(3, 1)
			if r < 0.75: floor_tile = Vector2i(3, 1)
			elif r < 0.88: floor_tile = [Vector2i(2, 0), Vector2i(2, 1), Vector2i(4, 0)].pick_random()
			elif r < 0.94: floor_tile = [Vector2i(2, 3), Vector2i(3, 3)].pick_random()
			else: floor_tile = [Vector2i(1, 0), Vector2i(1, 1)].pick_random()
			tile_map.set_cell(tile_pos, 0, floor_tile)
			if decor_layer and randf() < 0.04:
				if _is_pos_safe(tile_pos, MIN_DECOR_DISTANCE): 
					_spawn_decor_at(tile_pos)

func _spawn_decor_at(pos: Vector2i) -> void:
	if decor_layer.get_cell_source_id(pos) != -1: return
	if randf() < 0.5:
		decor_layer.set_cell(pos, 0, Vector2i(0, 2))
		decor_layer.set_cell(pos - Vector2i(0, 1), 0, Vector2i(0, 1))
		var light = torch_light_scene.instantiate()
		light.position = tile_map.map_to_local(pos) + Vector2(0, -tile_size)
		add_child(light)
	else:
		decor_layer.set_cell(pos, 0, Vector2i(0, 0))

func _is_pos_safe(check_pos: Vector2i, radius: int) -> bool:
	for x in range(check_pos.x - radius, check_pos.x + radius + 1):
		for y in range(check_pos.y - radius, check_pos.y + radius + 1):
			if decor_layer.get_cell_source_id(Vector2i(x, y)) != -1: return false
	return true

func _on_timer_tick() -> void:
	if not multiplayer.is_server(): return
	time_elapsed += 1
	if time_elapsed % 60 == 0 and current_tier < 6: 
		current_tier += 1
	if time_elapsed % 45 == 0: 
		spawn_wave.rpc()

func _on_enemy_spawn_tick() -> void:
	if not multiplayer.is_server() or _is_wave_active: return
	_spawn_enemy(false)

@rpc("call_local")
func spawn_wave() -> void:
	if not multiplayer.is_server(): return
	_is_wave_active = true
	var count = 15 + (current_tier * 5)
	for i in count: 
		_spawn_enemy(true)
	await get_tree().create_timer(10.0).timeout
	_is_wave_active = false

func _spawn_enemy(is_elite: bool) -> void:
	if not multiplayer.is_server(): return
	var players_list = get_tree().get_nodes_in_group("Players")
	if players_list.is_empty(): return
	
	var pool = all_enemy_types.filter(func(e_data): 
		return e_data.tier == current_tier if is_elite else e_data.tier <= current_tier
	)
	if pool.is_empty(): return
	var res = pool.pick_random()
	
	var e = enemy_scene.instantiate()
	e.name = "Enemy_" + str(Time.get_ticks_usec()) + "_" + str(randi() % 100)
	e.data_path = res.resource_path
	var target = players_list.pick_random()
	e.global_position = target.global_position + Vector2.from_angle(randf() * TAU) * 1200.0
	add_child(e)

func _update_timer_ui() -> void:
	var label: Label = get_node_or_null("TimerHud/%TimeLabel")
	if label: label.text = "%02d:%02d" % [int(time_elapsed / 60.0), time_elapsed % 60]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("exit"): _leave_to_menu()

func _leave_to_menu() -> void:
	Lobby.disconnect_game()
	get_tree().change_scene_to_file("res://src/ui/menu/MainMenu.tscn")
