# ChildrenOfTime Prototype Architecture

This document is the working source of truth for the prototype's code boundaries. The goal is to keep each system responsible for one job so combat, AI, gathering, production, abilities, scoring, and evolution mechanics can grow without turning `main.gd` or `unit.gd` into god objects.

## Current flow

```text
                 RTSLineageState
             (epoch / score / adaptations)
                         |
                         +------> RTSAdaptationDefinition
                         |        (evolutionary modifiers + visuals)
                         |
                         v
                RTSUnitDefinition
          (base organism data Resource)
                         |
                  lineage resolves
                         |
                         v
                  RTSUnitFactory
             (instantiate resolved data)
                         |
                         v
                      RTSUnit

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

The key long-term loop is:

```text
history -> lineage -> organism definitions -> tactical encounter -> result -> history
```

Build 10 proves the first half of that loop: a lineage choice now changes both the statistics and appearance of the organisms that enter an encounter.

## Responsibilities

### `main.gd`
Owns scene-level composition and player interaction.

- creates the prototype lineages
- presents the temporary/debug adaptation choice UI
- selects which `UnitDefinition` resources participate in the encounter
- spawns prototype world objects through `RTSUnitFactory`
- tracks player selection
- resolves context clicks into high-level orders
- owns camera and prototype HUD
- wires services/controllers together
- does **not** calculate paths
- does **not** hard-code organism combat/movement stats
- does **not** implement adaptation stat math
- does **not** own health, damage, cooldowns, hostility, or AI decision rules
- does **not** execute unit movement/combat frame by frame

The current prototype treats team `1` as player-controlled and team `2` as hostile. The current `First Lineage` and `Rival Lineage` are encounter scaffolding, not final lore.

### `unit_definition.gd`
Defines reusable base organism data as a Godot `Resource`.

Current data includes:

- definition ID and display name
- movement speed
- acceleration
- body radius
- max health
- attack damage
- attack range
- attack cooldown
- body texture and visual size
- descriptive tags

Concrete definitions live under `data/units/`. Build 10 has `primitive_hunter.tres` and `rival_hunter.tres`.

A definition describes what a base organism is. It should not contain runtime health, targets, path state, AI decisions, or historical lineage state.

### `adaptation_definition.gd`
Defines one evolutionary change as reusable data.

Current adaptation data can modify:

- movement speed and acceleration
- max health
- attack damage/range/cooldown
- body radius
- visual size
- visual texture
- organism tags

Adaptations can require tags, so a future adaptation can apply only to appropriate organism families without adding `if has_adaptation(...)` branches inside tactical code.

Build 10 contains two proof adaptations under `data/adaptations/`:

- `carapace.tres` — slower, larger, much tougher hunter with armored visuals
- `predatory_limbs.tres` — faster, more lethal, less durable hunter with predatory visuals

An adaptation describes a historical/evolutionary modifier. It does not own a runtime unit and does not issue tactical orders.

### `lineage_state.gd`
Owns persistent civilization/lineage state that can survive across tactical encounters.

Current state includes:

- lineage name
- epoch
- cumulative score
- chosen `RTSAdaptationDefinition` resources

`resolve_unit_definition()` duplicates the base organism definition and applies the lineage's adaptations to that copy. The source definition remains unchanged.

This is a critical boundary: historical choices become encounter-ready organism data here, before any runtime unit exists.

The lineage is the long-lived object. Individual RTS units are temporary expressions of it.

### `unit_factory.gd`
Owns the translation from persistent organism data into runtime tactical actors.

- accepts a base `RTSUnitDefinition`
- asks the lineage to resolve that definition
- instantiates `RTSUnit`
- applies resolved movement/combat values
- applies resolved visuals
- applies encounter-specific team/color affiliation
- returns the finished runtime unit

This prevents `main.gd` from knowing how organism data maps into components and prevents `RTSUnit` from knowing why its stats or appearance have the values they do.

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
- does **not** know about selection, combat, factions, AI, lineage, evolution, or unit intent

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
- renders an already-resolved body texture/size
- accepts already-resolved runtime values
- does **not** interpret player input
- does **not** make strategic AI decisions
- does **not** calculate global paths
- does **not** know which adaptations or epoch produced its stats or appearance
- does **not** own faction diplomacy rules beyond delegating to its faction component
- does **not** own combat state beyond delegating to its combat component

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

A `UnitDefinition` describes an organism; it is not the organism's runtime state.

An `AdaptationDefinition` describes how historical lineage state modifies compatible organisms; it is not a runtime buff system.

A lineage may explain why an organism has certain traits, but a tactical unit should not know the historical reason.

Faction identity is data. Diplomacy is policy. Keep those separable.

The future macro/epoch layer should produce lineage/world state and encounters, not reach down and manipulate tactical units directly.

## Next extraction points

Do not split these until behavior actually demands it, but these are the intended seams:

- `EncounterController` — tactical objectives, success/failure, encounter score, transition back to macro time
- `SelectionController` — when selection/context-click rules become more complex
- `TargetingService` — when target scoring, aggro, threat, and visibility become real systems
- `DiplomacyService` — alliances, neutral factions, reputation, temporary hostility
- `World/Spawn service` — when prototype spawning becomes production gameplay
- `Death/Corpse system` — cleanup, loot, remains, resurrection, decomposition, etc.
- `Epoch/Macro board` — territory, events, time jumps, ecology, history, and cumulative scoring

The next concept-facing milestone should close the loop in the other direction: tactical results should produce an encounter result/score that can become persistent lineage history.

## Scaling notes

The current chase model is intentionally split across two layers:

1. `RTSUnit` notices that its target moved or left range and requests a repath.
2. `RTSCommandController` asks `RTSNavigationManager` for that path and gives it back to the unit.

The AI follows the same separation:

1. `RTSAIController` decides that an idle hostile should attack a nearby target.
2. It calls `RTSCommandController.issue_attack_order()` exactly as another control source would.
3. Commands, navigation, intent, movement, and damage proceed through the normal pipeline.

Evolution follows a similar boundary:

1. A persistent `RTSLineageState` owns historical state and chosen adaptations.
2. A base `RTSUnitDefinition` describes the unevolved/base organism.
3. `RTSAdaptationDefinition` resources describe compatible evolutionary changes.
4. The lineage duplicates and resolves the base definition into encounter-ready data.
5. `RTSUnitFactory` turns the resolved data into a runtime `RTSUnit`.
6. The runtime unit never asks which adaptation, epoch, or historical event produced those values.

If hundreds of units later chase the same target, the command/navigation boundary is where route sharing and throttling belong.
