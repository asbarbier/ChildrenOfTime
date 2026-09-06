class_name RTSCombatComponent
extends Node

signal health_changed(current_health: float, max_health: float)
signal damaged(amount: float, current_health: float)
signal died

@export var max_health: float = 100.0
@export var attack_damage: float = 20.0
@export var attack_range: float = 72.0
@export var attack_cooldown: float = 0.75

var current_health: float = 100.0
var cooldown_remaining: float = 0.0

func _ready() -> void:
	current_health = max_health

func _process(delta: float) -> void:
	if cooldown_remaining > 0.0:
		cooldown_remaining = maxf(0.0, cooldown_remaining - delta)

func configure(
	health: float,
	damage: float,
	range_value: float,
	cooldown: float
) -> void:
	max_health = maxf(1.0, health)
	attack_damage = maxf(0.0, damage)
	attack_range = maxf(1.0, range_value)
	attack_cooldown = maxf(0.05, cooldown)
	current_health = max_health
	cooldown_remaining = 0.0
	health_changed.emit(current_health, max_health)

func is_alive() -> bool:
	return current_health > 0.0

func can_attack_now() -> bool:
	return is_alive() and cooldown_remaining <= 0.0

func receive_damage(amount: float) -> void:
	if not is_alive() or amount <= 0.0:
		return

	current_health = maxf(0.0, current_health - amount)
	damaged.emit(amount, current_health)
	health_changed.emit(current_health, max_health)

	if current_health <= 0.0:
		died.emit()

func try_attack(target: RTSCombatComponent) -> bool:
	if target == null or not target.is_alive() or not can_attack_now():
		return false

	target.receive_damage(attack_damage)
	cooldown_remaining = attack_cooldown
	return true

func get_health_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return clampf(current_health / max_health, 0.0, 1.0)
