extends Resource
class_name EnemyResource

@export var enemy_name: String = "Enemy"
@export var texture: Texture2D
@export_range(1, 6) var tier: int = 1

@export_group("Характеристики")
@export var health: int = 5
@export var damage: int = 1
@export var speed: float = 120.0

@export_group("Анимация")
@export var hframes: int = 8
