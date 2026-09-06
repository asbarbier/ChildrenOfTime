class_name RTSUnit
extends Node2D

@export var move_speed: float = 190.0
@export var radius: float = 14.0

var selected: bool = false
var target_position: Vector2
var has_target: bool = false
var unit_id: int = 0

func _ready() -> void:
    target_position = global_position
    queue_redraw()

func set_selected(value: bool) -> void:
    selected = value
    queue_redraw()

func set_move_target(world_position: Vector2) -> void:
    target_position = world_position
    has_target = true

func _process(delta: float) -> void:
    if not has_target:
        return

    var to_target := target_position - global_position
    var distance := to_target.length()

    if distance <= 2.0:
        global_position = target_position
        has_target = false
        return

    var step := move_speed * delta
    global_position += to_target.normalized() * min(step, distance)
    queue_redraw()

func contains_point(world_point: Vector2) -> bool:
    return global_position.distance_to(world_point) <= radius + 6.0

func _draw() -> void:
    # Placeholder unit art: readable now, replaceable later.
    draw_circle(Vector2.ZERO, radius, Color("87a96b"))
    draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color("c7d7b5"), 2.0)
    draw_circle(Vector2(5, -4), 2.5, Color("172017"))

    if selected:
        draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 32, Color("f0d96b"), 3.0)
