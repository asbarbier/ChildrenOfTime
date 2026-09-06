# ChildrenOfTime Prototype Architecture

This document is the working source of truth for the prototype's code boundaries. The goal is to keep each system responsible for one job so combat, AI, gathering, production, abilities, and evolution mechanics can grow without turning `main.gd` or `unit.gd` into god objects.

## Current flow

```text
Player input
    |
    v
main.gd
(selection, camera, world composition, HUD)
    |
    v
RTSCommandController
(order interpretation, formation targets, command fan-out)
    |
    +------> RTSNavigationManager
    |        (global path queries only)
    |
    v
RTSUnit intent
(IDLE / MOVE / ATTACK / CHASE / DEAD)
    |
    +------> RTSFactionComponent
    |        (team identity / hostility)
    |
    +------> RTSCombatComponent
    |        (health / damage / range / cooldown)
    |
    v
RTSUnit execution
(path following, acceleration, local separation, intent transitions)
```

## Responsibilities

### `main.gd`
Owns scene-level composition and player interaction.

- spawns prototype world objects
- tracks player selection
- resolves context clicks into high-level orders
- owns camera and prototype HUD
- does **not** calculate paths
- does **not** own health, damage, cooldowns, or hostility rules
- does **not** execute unit movement/combat frame by frame

The current prototype treats team `1` as player-controlled and team `2` as hostile. That is temporary scene setup, not a permanent faction model.

### `command_controller.gd`
Owns player/AI order orchestration.

- receives high-level orders such as move and attack
- calculates formation destinations
- requests global paths from the navigation service
- assigns intent/targets to units
- handles chase repath requests from units
- should remain agnostic about how a unit physically moves or deals damage each frame

Current public order API:

- `issue_move_order()`
- `issue_attack_order()`
- `issue_stop_order()`

Future player input and AI should both call this same API.

### `navigation_manager.gd`
Owns global navigation only.

- builds and owns the `NavigationServer2D` map
- knows walkable space and static terrain obstructions
- answers path queries
- does **not** know about selection, combat, factions, or unit intent

If path-query load becomes significant later, this is the boundary where shared squad paths, caching, hierarchical navigation, or threaded path work can be introduced.

### `unit.gd`
Owns one unit's runtime intent and physical execution.

- exposes explicit intent state
- follows movement/chase paths
- handles acceleration and steering feel
- handles cheap local separation
- transitions between `CHASE` and `ATTACK` based on range
- requests a new chase path instead of calculating one itself
- composes faction and combat components
- does **not** interpret player input
- does **not** calculate global paths
- does **not** own faction diplomacy rules beyond delegating to its faction component
- does **not** own combat stats beyond delegating to its combat component

Current intents:

- `IDLE`
- `MOVE`
- `ATTACK`
- `CHASE`
- `DEAD`

### `faction_component.gd`
Owns unit affiliation.

- stores `team_id`
- answers allied/hostile relationship checks
- treats team `0` as neutral/unassigned

The current hostility rule is simply "different non-zero team IDs are hostile." When diplomacy becomes richer, this rule should move behind a faction/diplomacy service without changing unit or command APIs.

### `combat_component.gd`
Owns reusable combat state and timing.

- max/current health
- attack damage
- attack range
- attack cooldown
- damage application
- death signal
- attack cooldown timing

It deliberately does **not** choose targets, chase enemies, pathfind, or decide when an attack order should exist.

## Design rules

A unit may execute an order, but it should not invent the order.

A navigation system may find a route, but it should not decide why a unit wants that route.

A command system may decide what units should attempt, but it should not own frame-by-frame locomotion or damage timing.

A combat component may apply damage, but it should not decide who deserves to get hit.

Faction identity is data. Diplomacy is policy. Keep those separable.

## Next extraction points

Do not split these until behavior actually demands it, but these are the intended seams:

- `SelectionController` — when selection/context-click rules become more complex
- `UnitDefinition` Resource — reusable movement/combat/visual stats instead of spawn-time hard-coded numbers
- `AIController` — produces the same command API used by the player
- `TargetingService` — when target scoring, aggro, threat, and visibility become real systems
- `DiplomacyService` — alliances, neutral factions, reputation, temporary hostility
- `World/Spawn service` — when prototype spawning becomes production gameplay
- `Death/Corpse system` — cleanup, loot, remains, resurrection, decomposition, etc.

## Scaling notes

The current chase model is intentionally split across two layers:

1. `RTSUnit` notices that its target moved or left range and requests a repath.
2. `RTSCommandController` asks `RTSNavigationManager` for that path and gives it back to the unit.

This keeps navigation out of the unit while allowing moving targets. If hundreds of units later chase the same target, the command/navigation boundary is where route sharing and throttling belong.

The important long-term rule is that player control and AI control should converge on the same command layer. We should never grow separate "player unit" and "AI unit" behavior trees for the same physical actions.
