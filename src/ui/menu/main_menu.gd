extends Control

func _on_play_pressed() -> void:
	Lobby.start_solo()

func _on_coop_pressed() -> void:
	get_tree().change_scene_to_file("res://src/ui/menu/Lobby.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
