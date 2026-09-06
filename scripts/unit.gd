class_name RTSUnit
extends Node2D

@export var move_speed: float = 190.0
@export var radius: float = 14.0
@export var separation_radius: float = 34.0
@export var separation_strength: float = 1.35

var selected: bool = false
var target_position: Vector2
var has_target: bool = false
var unit_id: int = 0

func _ready() -> void:
    target_position = global_position
    add_to_group("rts_units")
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

    var desired_velocity := to_target.normalized() * move_speed
    var separation := _get_separation_force()

    if separation != Vector2.ZERO:
        desired_velocity += separation * move_speed * separation_strength

    if desired_velocity.length() > move_speed:
        desired_velocity = desired_velocity.normalized() * move_speed

    var step := desired_velocity * delta
    if step.length() > distance:
        global_position = target_position
        has_target = false
    else:
        global_position += step

    queue_redraw()

func _get_separation_force() -> Vector2:
    var force := Vector2.ZERO

    for node in get_tree().get_nodes_in_group("rts_units"):
        if node == self or not node is RTSUnit:
            continue

        var other := node as RTSUnit
        var offset := global_position - other.global_position
        var distance := offset.length()

        if distance > 0.001 and distance < separation_radius:
            var weight := 1.0 - (distance / separation_radius)
            force += offset.normalized() * weight

    return force

func contains_point(world_point: Vector2) -> bool:
    return global_position.distance_to(world_point) <= radius + 6.0

func _draw() -> void:
    # Placeholder unit art: readable now, replaceable later.
    draw_circle(Vector2.ZERO, radius, Color("87a96b"))
    draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color("c7d7b5"), 2.0)
    draw_circle(Vector2(5, -4), 2.5, Color("172017"))

    if selected:
        draw_arc(Vector2.ZERO, radius + 6.0, 0.0, TAU, 32, Color("f0d96b"), 3.0)
