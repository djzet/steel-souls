extends Node2D

@export_group("Префабы")
@export var player_scene: PackedScene = preload("res://src/entities/player/Player.tscn")
@export var enemy_scene: PackedScene = preload("res://src/entities/enemies/Enemy.tscn")
@export var torch_light_scene: PackedScene = preload("res://src/world/TorchLight.tscn")

@export_group("Данные врагов")
@export var all_enemy_types: Array[EnemyResource] = [] 

@export_group("Состояние игры")
@export var time_elapsed: int = 0
@export var current_tier: int = 1

const CHUNK_SIZE = 32
const RENDER_DISTANCE = 2
const CHECK_INTERVAL = 0.2
const MIN_DECOR_DISTANCE = 15

@onready var tile_map: TileMapLayer = $TileMapLayer
@onready var tile_size: float = tile_map.tile_set.tile_size.x

var generated_chunks: Array = []
var chunk_queue: Array = []
var check_timer: float = 0.0
var is_wave_active: bool = false

func _ready() -> void:
	_queue_chunks_around_player(Vector2(576, 324)) 
	await get_tree().process_frame
	Lobby.player_ready.rpc_id(1)

func start_game() -> void:
	if not multiplayer.is_server(): return
	for id in Lobby.players:
		if has_node(str(id)): continue
		var p = player_scene.instantiate()
		p.name = str(id)
		add_child(p, true)
		p.position = Vector2(576, 324) + Vector2(randf_range(-60, 60), 0)
	if has_node("GameTimer"):
		$GameTimer.start()
		$GameTimer.timeout.connect(_on_timer_tick)
	if has_node("EnemyTimer"):
		$EnemyTimer.start()
		$EnemyTimer.timeout.connect(_on_enemy_spawn_tick)


func _process(delta: float) -> void:
	_update_timer_ui()
	check_timer += delta
	if check_timer >= CHECK_INTERVAL:
		check_timer = 0.0
		for player in get_tree().get_nodes_in_group("Players"):
			_queue_chunks_around_player(player.global_position)
	if chunk_queue.size() > 0:
		var next_chunk = chunk_queue.pop_front()
		if not generated_chunks.has(next_chunk):
			_generate_chunk(next_chunk)

func _on_timer_tick() -> void:
	if not multiplayer.is_server(): return
	time_elapsed += 1
	if time_elapsed % 60 == 0 and current_tier < 6:
		current_tier += 1
	if time_elapsed % 45 == 0:
		spawn_wave.rpc()

func _queue_chunks_around_player(player_pos: Vector2) -> void:
	var p_x = int(floorf(player_pos.x / (CHUNK_SIZE * tile_size)))
	var p_y = int(floorf(player_pos.y / (CHUNK_SIZE * tile_size)))
	for x in range(p_x - RENDER_DISTANCE, p_x + RENDER_DISTANCE + 1):
		for y in range(p_y - RENDER_DISTANCE, p_y + RENDER_DISTANCE + 1):
			var coord = Vector2i(x, y)
			if not generated_chunks.has(coord) and not chunk_queue.has(coord):
				chunk_queue.append(coord)

func _generate_chunk(chunk_pos: Vector2i) -> void:
	generated_chunks.append(chunk_pos)
	seed(Lobby.world_seed + hash(chunk_pos))
	var clean_floor = [Vector2i(3, 1)]
	var light_cracks = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(2, 1), Vector2i(4, 1)]
	var medium_cracks = [Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]
	var heavy_cracks = [Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)]
	var huge_cracks = [Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)]
	var start_x = chunk_pos.x * CHUNK_SIZE
	var start_y = chunk_pos.y * CHUNK_SIZE
	for x in range(start_x, start_x + CHUNK_SIZE):
		for y in range(start_y, start_y + CHUNK_SIZE):
			var tile_pos = Vector2i(x, y)
			var r = randf()
			var floor_tile = clean_floor[0]
			if r < 0.75: floor_tile = clean_floor[0]
			elif r < 0.88: floor_tile = light_cracks.pick_random()
			elif r < 0.94: floor_tile = medium_cracks.pick_random()
			elif r < 0.98: floor_tile = heavy_cracks.pick_random()
			else: floor_tile = huge_cracks.pick_random()
			tile_map.set_cell(tile_pos, 0, floor_tile)
			if has_node("DecorLayer") and randf() < 0.04:
				if _is_pos_safe(tile_pos, MIN_DECOR_DISTANCE):
					_spawn_decor_at(tile_pos)

func _spawn_decor_at(pos: Vector2i) -> void:
	if $DecorLayer.get_cell_source_id(pos) != -1: return
	var type = randf()
	if type < 0.5:
		$DecorLayer.set_cell(pos, 0, Vector2i(0, 2))
		$DecorLayer.set_cell(pos - Vector2i(0, 1), 0, Vector2i(0, 1))
		var light = torch_light_scene.instantiate()
		light.position = tile_map.map_to_local(pos) + Vector2(0, -tile_size)
		add_child(light)
	else:
		$DecorLayer.set_cell(pos, 0, Vector2i(0, 0))

func _is_pos_safe(check_pos: Vector2i, radius: int) -> bool:
	for x in range(check_pos.x - radius, check_pos.x + radius + 1):
		for y in range(check_pos.y - radius, check_pos.y + radius + 1):
			if $DecorLayer.get_cell_source_id(Vector2i(x, y)) != -1:
				return false
	return true

@rpc("call_local")
func spawn_wave() -> void:
	if not multiplayer.is_server(): return
	var count = 15 + (current_tier * 5)
	for i in count:
		_spawn_enemy(true)

func _on_enemy_spawn_tick() -> void:
	if not multiplayer.is_server(): return
	_spawn_enemy(false)

func _spawn_enemy(is_elite: bool) -> void:
	var players = get_tree().get_nodes_in_group("Players")
	if players.is_empty(): return
	var pool = all_enemy_types.filter(func(res): 
		return res.tier == current_tier if is_elite else res.tier <= current_tier
	)
	if pool.is_empty(): return
	var selected_res = pool.pick_random()
	var new_enemy = enemy_scene.instantiate()
	new_enemy.data = selected_res
	new_enemy.data_path = selected_res.resource_path
	var target = players.pick_random()
	var pos = target.global_position + Vector2.from_angle(randf() * TAU) * 850.0
	new_enemy.position = pos
	add_child(new_enemy, true)

func _update_timer_ui() -> void:
	var minutes: int = int(time_elapsed / 60.0)
	var seconds: int = time_elapsed % 60
	var label = get_node_or_null("TimerHud/%TimeLabel")
	if label:
		label.text = "%02d:%02d" % [minutes, seconds]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("exit"):
		_leave_to_menu()

func _leave_to_menu() -> void:
	Lobby.disconnect_game()
	get_tree().change_scene_to_file("res://src/ui/menu/MainMenu.tscn")
