extends PointLight2D

@export var min_energy = 0.5
@export var max_energy = 1.0
@export var speed = 5.0 # Чем меньше число, тем медленнее мерцание

var target_energy = 1.0

func _process(delta) -> void:
	if randf() < 0.05: 
		target_energy = randf_range(min_energy, max_energy)
	energy = lerp(energy, target_energy, speed * delta)
