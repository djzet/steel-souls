extends Control

@onready var health_bar = $HBoxContainer/HealthBar
@onready var player_label = $HBoxContainer/PlayerLabel

var _current_observed_player = null 

func _ready() -> void:
	visible = false
	_find_my_player()

func _find_my_player() -> void:
	var my_player = null
	while my_player == null:
		var players = get_tree().get_nodes_in_group("Players")
		for p in players:
			if p.is_multiplayer_authority():
				my_player = p
				break
		if my_player == null:
			await get_tree().create_timer(0.2).timeout
	
	_setup_hud(my_player)

func _setup_hud(player) -> void:
	if _current_observed_player and is_instance_valid(_current_observed_player):
		if _current_observed_player.health_changed.is_connected(_update_health):
			_current_observed_player.health_changed.disconnect(_update_health)

	_current_observed_player = player

	health_bar.max_value = 10
	health_bar.value = player.health

	var player_id = player.name.to_int()
	
	if player_id == 1:
		player_label.text = "Player 1"
	else:
		player_label.text = "Player 2"
		
	if not player.health_changed.is_connected(_update_health):
		player.health_changed.connect(_update_health)
	
	visible = true

func _update_health(new_value: int) -> void:
	var tween = create_tween()
	tween.tween_property(health_bar, "value", new_value, 0.2).set_trans(Tween.TRANS_SINE)
