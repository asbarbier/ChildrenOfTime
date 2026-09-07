# ChildrenOfTime Prototype Architecture

This document is the working source of truth for the prototype's code boundaries. The goal is to keep each system responsible for one job so combat, AI, scoring, evolution, and the macro/epoch layer can grow without turning `main.gd` or `unit.gd` into god objects.

## Current loop

```text
                    RTSMacroState
             (turn / regions / deep time)
                         |
                         v
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
                         |
Player input ------------+-------------------+
                                             |
RTSAIController -----------------------------+
                                             v
                                  RTSCommandController
                               (orders / paths / fan-out)
                                             |
                                             v
                                    tactical execution
                                             |
                                             v
                                  RTSEncounterController
                               (facts -> outcome / score)
                                             |
                          +------------------+------------------+
                          v                                     v
                  RTSLineageState                        RTSMacroState
                (score / history)                  (territory / time / run)
```

The prototype now represents the intended game loop end to end:

```text
history -> pressure -> adaptation -> organism -> RTS encounter -> consequence -> history
```

Build 10 proved that lineage history can change the organism entering battle. Build 11 proved that a tactical battle can produce persistent score/history. Build 12 proves the missing outer loop: a macro-region decision creates the encounter, and the tactical result changes the macro world when the player returns.

## Responsibilities

### `main.gd`
Owns scene composition, phase presentation, and player interaction.

Current prototype phases are:

- `MACRO` — inspect the small historical region board and choose the next pressure
- `ADAPTATION` — choose how the lineage changes before the encounter
- `TACTICAL` — normal RTS control
- `RESULT` — review encounter facts before returning to deep time

`main.gd` wires systems together and presents their state, but should not absorb their rules. It does **not** calculate paths, adaptation math, combat damage, encounter score, or macro-region state transitions.

Team `1`, team `2`, `First Lineage`, `Rival Lineage`, and the current three-region board remain prototype scaffolding, not final lore.

### `macro_region_state.gd`
Owns the persistent state of one abstract world region.

Current region states are:

- `UNKNOWN`
- `HOME`
- `CONTESTED`
- `SECURED`
- `LOST`

A macro region describes historical/world state. It does not spawn tactical units or know how a battle is simulated.

### `macro_state.gd`
Owns the tiny Build 12 macro/epoch proof.

Current state includes:

- current macro turn
- approximate elapsed deep time
- whether the lineage run has ended
- region states for Cradle Nest, Glass Forest, and Eastern Basin

Current behavior:

- Cradle Nest begins as `HOME`
- Glass Forest begins `UNKNOWN`
- Eastern Basin begins `CONTESTED`
- a victory in Eastern Basin changes it to `SECURED`, advances the turn, and jumps deep time forward
- a defeat changes it to `LOST` and ends the run

The macro layer consumes an encounter outcome. It does not reach into tactical units to manufacture that outcome.

### `lineage_state.gd`
Owns persistent civilization/lineage state across tactical encounters and deep-time transitions.

Current state includes:

- lineage name
- epoch
- cumulative score
- chosen adaptations
- historical entries

`resolve_unit_definition()` duplicates a base organism definition and applies lineage adaptations to the copy. `record_history()` stores durable narrative results.

The lineage is the long-lived biological/cultural identity. The macro state is the world/history around it. Individual RTS units are temporary expressions of the lineage.

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

- receives participating units and faction IDs
- tracks encounter duration
- observes unit deaths
- detects victory or lineage collapse
- calculates prototype score components
- writes score/history into `RTSLineageState`
- emits one encounter-finished report

The encounter controller produces tactical meaning from tactical facts. The macro layer may consume the resulting victory/defeat, but tactical units do not know whether a death secured territory, ended a lineage, or changed history.

Current score components remain deliberately temporary:

- hostile defeats
- surviving lineage members
- victory tempo bonus
- victory completion bonus

The score model is scaffolding. Build 12 intentionally emphasizes **world-state consequence** over score alone.

### `command_controller.gd`
Owns order orchestration for both player and AI.

- receives move/attack/stop orders
- calculates formation destinations
- requests global paths
- assigns unit intent and targets
- handles chase repath requests
- remains agnostic about whether an order came from the player, AI, a scripted encounter, or future macro content

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
- knows nothing about combat, AI, scoring, lineage, evolution, macro regions, or history

### `unit.gd`
Owns one unit's runtime intent and physical execution.

- follows movement/chase paths
- handles acceleration and local separation
- transitions between chase and attack based on range
- requests repaths rather than calculating them
- composes faction and combat components
- renders already-resolved visuals
- does not interpret macro choices
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

An encounter controller interprets tactical facts into an outcome; tactical units should not know the historical meaning of that outcome.

A macro state may choose **where/why** an encounter happens and consume its result, but it should not directly control tactical simulation.

Faction identity is data. Diplomacy is policy. Keep them separable.

## Build 12 scope boundary

The Build 12 macro board is intentionally tiny:

- three abstract regions
- one actionable historical expansion
- one adaptation decision
- one RTS encounter
- one return-to-history transition
- victory changes territory and advances deep time
- defeat ends the lineage run

Glass Forest is deliberately non-actionable. We are proving the loop, not building the full macro game yet.

## Next-step discussion after Build 12

Do not automatically expand the board after this build. Once the loop is tested, the next design conversation should decide whether the next vertical slice needs:

- richer macro decisions/events
- an `EncounterDefinition` data layer
- population/ecology state
- discovery/ancient-machine state
- multiple encounters per epoch
- more tactical depth such as roles, objectives, production, or abilities
- a scoring redesign around legacy/resilience/discovery rather than simple combat optimization

The next system should be chosen by the next **playable question** we want answered, not merely because an architectural seam exists.

## Scaling notes

Navigation scaling belongs at the command/navigation boundary through route sharing, caching, hierarchical navigation, or threading.

Evolution scaling belongs at lineage resolution: base definitions + compatible adaptation data -> resolved encounter organism.

Scoring scaling belongs at the encounter boundary: tactical events -> encounter report -> persistent lineage history.

Macro scaling belongs above the encounter boundary: world/history state -> encounter request -> encounter result -> changed world/history state.

That separation lets deep time, evolution, and RTS combat influence each other without collapsing into one giant system.