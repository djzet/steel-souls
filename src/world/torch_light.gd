extends PointLight2D

@export var min_energy: float = 0.5
@export var max_energy: float = 1.0
@export var speed: float = 5.0

var _target_energy: float = 1.0

func _process(delta: float) -> void:
	if randf() < 0.05: _target_energy = randf_range(min_energy, max_energy)
	energy = lerp(energy, _target_energy, speed * delta)
