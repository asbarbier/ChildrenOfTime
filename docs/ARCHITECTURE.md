# ChildrenOfTime Prototype Architecture

This document is the working source of truth for the prototype's code boundaries. The goal is to keep each system responsible for one job so combat, AI, scoring, evolution, and the future macro/epoch layer can grow without turning `main.gd` or `unit.gd` into god objects.

## Current flow

```text
                 RTSLineageState
       (epoch / score / adaptations / history)
                         |
                         +------> RTSAdaptationDefinition
                         |        (evolutionary modifiers + visuals)
                         |
                         v
                RTSUnitDefinition
             (base organism Resource)
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
                               |
                               v
                   RTSEncounterController
          (outcome / score / persistent result)
                               |
                               v
                       RTSLineageState
```

The long-term game loop is now represented end to end:

```text
history -> lineage -> organism -> tactical encounter -> result -> score/history
```

Build 10 proved that lineage history can change the organism entering battle. Build 11 proves that the tactical battle can produce a persistent result that returns to the lineage.

## Responsibilities

### `main.gd`
Owns scene composition and player interaction.

- creates prototype lineages
- presents the temporary adaptation-choice UI
- selects encounter organism definitions
- spawns through `RTSUnitFactory`
- tracks player selection and context clicks
- owns camera and prototype HUD/result panels
- wires controllers and services together
- does **not** calculate paths
- does **not** hard-code organism combat/movement stats
- does **not** implement adaptation math
- does **not** calculate encounter scoring
- does **not** execute movement/combat frame by frame

Team `1`, team `2`, `First Lineage`, `Rival Lineage`, and the Eastern Basin encounter are prototype scaffolding, not final lore.

### `unit_definition.gd`
Defines reusable base organism data as a Godot `Resource`.

Current data includes movement, body radius, combat stats, body texture/visual size, and organism tags. Concrete definitions live under `data/units/`.

A definition describes a base organism. It does not contain runtime state, AI decisions, or lineage history.

### `adaptation_definition.gd`
Defines one evolutionary change as reusable data.

Adaptations may modify movement, health, damage, range, cooldown, body radius, visual size, texture, and tags. Tag requirements allow adaptations to target organism families without scattering historical checks through tactical code.

Current proof adaptations:

- `carapace.tres` — slower, larger, tougher, armored hunter
- `predatory_limbs.tres` — faster, more lethal, less durable hunter

### `lineage_state.gd`
Owns persistent civilization/lineage state across tactical encounters.

Current state includes:

- lineage name
- epoch
- cumulative score
- chosen adaptations
- historical result entries

`resolve_unit_definition()` duplicates the base definition and applies lineage adaptations to the copy. `record_history()` stores durable narrative results from encounters.

The lineage is the long-lived object. Individual RTS units are temporary expressions of it.

### `unit_factory.gd`
Translates persistent organism data into runtime tactical actors.

- accepts a base `RTSUnitDefinition`
- asks the lineage to resolve it
- instantiates `RTSUnit`
- applies resolved movement/combat/visual values
- applies encounter-specific faction information

The factory prevents `main.gd` from knowing component details and prevents `RTSUnit` from knowing why evolution produced its stats or appearance.

### `encounter_controller.gd`
Owns tactical encounter completion and scoring.

- receives the participating units, player team, hostile team, and player lineage
- tracks encounter duration
- observes unit deaths
- detects victory or lineage collapse
- calculates score components
- writes the final score into `RTSLineageState`
- records a historical result entry
- emits one encounter-finished report for presentation

Current prototype score components are intentionally simple:

- hostile defeats
- surviving lineage members
- time/tempo bonus on victory
- victory completion bonus

This scoring model is scaffolding. The important architecture is that tactical systems produce facts, while the encounter controller interprets those facts into an encounter result. Future ecological, discovery, objective, population, and legacy scoring belongs here or in services called from this boundary—not in `RTSUnit`.

### `command_controller.gd`
Owns order orchestration for both player and AI.

- receives move/attack/stop orders
- calculates formation destinations
- requests global paths
- assigns unit intent and targets
- handles chase repath requests
- remains agnostic about whether an order came from the player, AI, scripted encounter, or future macro layer

Player and AI must continue to use the same command API.

### `ai_controller.gd`
Owns current prototype PvE decision-making.

- controls one team
- thinks on a throttled interval
- finds nearby hostiles
- issues attack orders through `RTSCommandController`
- does not pathfind, move units directly, or apply damage directly

### `navigation_manager.gd`
Owns global navigation only.

- builds and owns the `NavigationServer2D` map
- knows static walkable space and terrain obstructions
- answers path queries
- knows nothing about combat, AI, scoring, lineage, evolution, or encounter history

### `unit.gd`
Owns one unit's runtime intent and physical execution.

- follows movement/chase paths
- handles acceleration and local separation
- transitions between chase and attack based on range
- requests repaths rather than calculating them
- composes faction and combat components
- renders already-resolved visuals
- does not interpret player input
- does not make strategic AI decisions
- does not know which adaptation or historical event produced its stats
- does not calculate encounter score or persistent history

Current intents: `IDLE`, `MOVE`, `ATTACK`, `CHASE`, `DEAD`.

### `faction_component.gd`
Owns unit affiliation and the current simple allied/hostile check. Rich diplomacy should later move behind a diplomacy service without changing tactical unit APIs.

### `combat_component.gd`
Owns health, damage, attack range, cooldown, damage application, death signaling, and attack timing. It does not select targets, pathfind, or interpret encounter meaning.

## Design rules

A unit may execute an order, but it should not invent the order.

A navigation system may find a route, but it should not decide why a unit wants that route.

A command system may decide what units should attempt, but it should not own frame-by-frame locomotion or damage timing.

An AI system may choose an order, but it should issue that order through the same interface used by the player.

A combat component may apply damage, but it should not decide who deserves to get hit.

A `UnitDefinition` describes an organism; it is not runtime state.

An `AdaptationDefinition` describes how historical lineage state modifies compatible organisms; it is not a runtime buff system.

A lineage explains why organisms have certain traits and stores what persists across encounters.

An encounter controller interprets tactical facts into outcomes; tactical units should not know whether their death was worth points or historically significant.

Faction identity is data. Diplomacy is policy. Keep them separable.

The future macro/epoch layer should produce lineage/world state and encounters, then consume encounter results. It should not reach down and manipulate tactical units directly.

## Next seams — intentionally paused after Build 11

We are deliberately stopping feature work after Build 11 to reassess the next vertical slice. Likely future seams include:

- `Epoch/Macro board` — territory, events, time jumps, ecology, history, cumulative scoring
- richer `EncounterDefinition` data — objectives, map setup, environmental pressures, score rules
- `SelectionController` — when selection/context-click logic grows
- `TargetingService` — threat, visibility, target scoring, aggro policy
- `DiplomacyService` — alliances, neutral populations, temporary hostility
- `World/Spawn service` — when prototype spawning becomes production gameplay
- `Death/Corpse system` — remains, biomass, decomposition, resurrection, loot

No one of these should be built merely because the seam exists. The next system should be chosen by the next playable concept we want to prove.

## Scaling notes

Navigation scaling belongs at the command/navigation boundary through route sharing, caching, hierarchical navigation, or threading.

Evolution scaling belongs at lineage resolution: base definitions + compatible adaptation data -> resolved encounter organism.

Scoring scaling belongs at the encounter boundary: tactical events -> encounter report -> persistent lineage history.

That separation gives the game its core loop without forcing the future macro layer, tactical simulation, and evolutionary data model to know each other's implementation details.
