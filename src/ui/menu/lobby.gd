extends Control

@onready var host_btn = %Host
@onready var join_btn = %Join
@onready var ip_input = %IPInput

func _ready() -> void:
	Lobby.connection_failed.connect(_reset_ui)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_host_pressed() -> void:
	if Lobby.create_game() == OK:
		_set_ui("Ожидание...", true)

func _on_join_pressed() -> void:
	var target_ip = ip_input.text
	if target_ip == "":
		target_ip = "127.0.0.1"
	
	if Lobby.join_game(target_ip) == OK:
		_set_ui("Вход...", false)

func _set_ui(txt: String, is_host: bool) -> void:
	host_btn.disabled = true
	join_btn.disabled = true
	ip_input.editable = false
	
	if is_host:
		host_btn.text = txt
	else:
		join_btn.text = txt

func _reset_ui() -> void:
	host_btn.disabled = false
	join_btn.disabled = false
	ip_input.editable = true
	host_btn.text = "Создать"
	join_btn.text = "Присоединиться"

func _on_back_pressed() -> void:
	Lobby.disconnect_game()
	get_tree().change_scene_to_file("res://src/ui/menu/MainMenu.tscn")

func _on_server_disconnected() -> void:
	Lobby.disconnect_game()
	get_tree().change_scene_to_file("res://src/ui/menu/MainMenu.tscn")
