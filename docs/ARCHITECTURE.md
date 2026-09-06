# ChildrenOfTime Prototype Architecture

This document is the working source of truth for the prototype's code boundaries. The goal is to keep each system responsible for one job so future combat, AI, gathering, production, and abilities can grow without turning `main.gd` into a god object.

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
    v
RTSUnit execution
(path following, acceleration, local separation)
```

## Responsibilities

### `main.gd`
Owns scene-level composition and player interaction.

- spawns prototype world objects
- tracks selection
- translates mouse/keyboard input into high-level orders
- owns camera and prototype HUD
- does **not** calculate paths or execute unit behavior

### `command_controller.gd`
Owns player/AI order orchestration.

- receives high-level orders such as move, attack, gather, patrol
- calculates formation destinations
- requests global paths from the navigation service
- assigns intent to units
- should remain agnostic about how a unit physically moves each frame

Future command entry points should live here, e.g. `issue_attack_order()`, `issue_gather_order()`, and `issue_stop_order()`.

### `navigation_manager.gd`
Owns global navigation only.

- builds and owns the NavigationServer2D map
- knows walkable space and static terrain obstructions
- answers path queries
- does **not** know about selection, combat, factions, or unit state

If path-query load becomes significant later, this is the boundary where shared squad paths, caching, or threaded path work can be introduced.

### `unit.gd`
Owns one unit's runtime state and execution.

- exposes an explicit intent state
- executes movement paths
- handles acceleration / steering feel
- handles cheap local separation
- does **not** decide where global paths go
- does **not** interpret player input

Current intents are deliberately broader than current behavior:

- `IDLE`
- `MOVE`
- `ATTACK`
- `CHASE`
- `DEAD`

Only `IDLE`, `MOVE`, and the `DEAD` lifecycle hook are implemented today. `ATTACK` and `CHASE` reserve the state vocabulary for the next combat slice without prematurely building combat logic.

## Design rule

A unit may execute an order, but it should not invent the order.

A navigation system may find a route, but it should not decide why a unit wants that route.

A command system may decide what units should attempt, but it should not own frame-by-frame locomotion.

## Near-term extraction points

Do not split these until behavior actually demands it, but these are the intended seams:

- `SelectionController` — when selection rules become more complex
- `CombatComponent` — health, damage, attack timing, targeting
- `Faction/Team` data — ownership and hostility rules
- `UnitDefinition` Resource — reusable unit stats instead of hard-coded exports
- `AIController` — produces the same command API used by the player
- `World/Spawn service` — when prototype spawning becomes production gameplay

The important part is that both player input and AI should eventually feed the same command layer. That keeps unit behavior deterministic and avoids building separate "player units" and "AI units" code paths.
