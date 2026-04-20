extends Control

@onready var host_btn = %HostButton
@onready var join_btn = %JoinButton

func _ready():
	Lobby.connection_failed.connect(_reset_ui)

func _on_host_button_pressed():
	if Lobby.create_game() == OK:
		_set_ui("Ожидание...")

func _on_join_button_pressed():
	if Lobby.join_game("127.0.0.1") == OK:
		_set_ui("Вход...")

func _set_ui(txt):
	host_btn.disabled = true
	join_btn.disabled = true
	host_btn.text = txt

func _reset_ui():
	host_btn.disabled = false
	join_btn.disabled = false
	host_btn.text = "Создать игру"
