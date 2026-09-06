# ChildrenOfTime Prototype Architecture

This document is the working source of truth for the prototype's code boundaries. The goal is to keep each system responsible for one job so combat, AI, gathering, production, abilities, scoring, and evolution mechanics can grow without turning `main.gd` or `unit.gd` into god objects.

## Current flow

```text
Player input ------------------+
                               |
RTSAIController ---------------+
                               v
                      RTSCommandController
                 (orders / formations / fan-out)
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
          (path following / acceleration / separation / combat transitions)
```

## Responsibilities

### `main.gd`
Owns scene-level composition and player interaction.

- spawns prototype world objects
- tracks player selection
- resolves context clicks into high-level orders
- owns camera and prototype HUD
- wires services/controllers together
- does **not** calculate paths
- does **not** own health, damage, cooldowns, hostility, or AI decision rules
- does **not** execute unit movement/combat frame by frame

The current prototype treats team `1` as player-controlled and team `2` as hostile. That is temporary encounter setup, not a permanent faction model.

### `command_controller.gd`
Owns order orchestration for **both player and AI**.

- receives high-level orders such as move and attack
- calculates formation destinations
- requests global paths from the navigation service
- assigns intent/targets to units
- handles chase repath requests from units
- should remain agnostic about whether an order came from a mouse click, AI, scripted encounter, or future macro layer
- should remain agnostic about how a unit physically moves or deals damage each frame

Current public order API:

- `issue_move_order()`
- `issue_attack_order()`
- `issue_stop_order()`

This shared command API is an important architectural rule. Player control and AI control should never grow separate implementations of the same physical actions.

### `ai_controller.gd`
Owns the current prototype's simple PvE decision-making.

- controls one team
- thinks on a throttled interval instead of every frame
- looks for nearby hostile units
- sends attack orders through `RTSCommandController`
- does **not** pathfind
- does **not** directly move units
- does **not** directly deal damage
- does **not** bypass the same command pipeline used by the player

The current AI is intentionally tiny: idle hostile units acquire the nearest valid enemy inside an aggro radius. This is enough to prove the architecture before behavior trees, encounter scripting, threat scoring, or strategic AI exist.

### `navigation_manager.gd`
Owns global navigation only.

- builds and owns the `NavigationServer2D` map
- knows walkable space and static terrain obstructions
- answers path queries
- does **not** know about selection, combat, factions, AI, or unit intent

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
- does **not** make strategic AI decisions
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

An AI system may choose an order, but it should issue that order through the same interface used by the player.

A combat component may apply damage, but it should not decide who deserves to get hit.

Faction identity is data. Diplomacy is policy. Keep those separable.

The future macro/epoch layer should produce **world state and encounters**, not reach down and manipulate tactical units directly.

## Next extraction points

Do not split these until behavior actually demands it, but these are the intended seams:

- `UnitDefinition` Resource — reusable movement/combat/visual stats instead of spawn-time hard-coded numbers
- `SelectionController` — when selection/context-click rules become more complex
- `EncounterController` — tactical objectives, success/failure, encounter score, transition back to macro time
- `TargetingService` — when target scoring, aggro, threat, and visibility become real systems
- `DiplomacyService` — alliances, neutral factions, reputation, temporary hostility
- `World/Spawn service` — when prototype spawning becomes production gameplay
- `Death/Corpse system` — cleanup, loot, remains, resurrection, decomposition, etc.
- `Epoch/Macro state` — long-time-scale lineage state, adaptations, territory, history, and cumulative score

## Scaling notes

The current chase model is intentionally split across two layers:

1. `RTSUnit` notices that its target moved or left range and requests a repath.
2. `RTSCommandController` asks `RTSNavigationManager` for that path and gives it back to the unit.

The AI follows the same separation:

1. `RTSAIController` decides that an idle hostile should attack a nearby target.
2. It calls `RTSCommandController.issue_attack_order()` exactly as another control source would.
3. Commands, navigation, intent, movement, and damage proceed through the normal pipeline.

This keeps AI complexity from leaking into locomotion and means future scripted encounters or macro-layer events can issue tactical orders through the same boundary.

If hundreds of units later chase the same target, the command/navigation boundary is where route sharing and throttling belong.
