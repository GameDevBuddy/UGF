# Universal Gameplay Framework

A reusable, data-driven gameplay platform for **Godot 4.7**, built to support action RPG,
shooter, open-world sandbox, driving, survival, faction simulation, commerce and narrative
adventure games from one foundation — without any of those genres being baked into it.

Godot-native throughout: scenes compose entities, typed `Resource` definitions carry content,
signals handle local communication, and a narrow event bus carries cross-feature facts.

---

## Status: M0 – M5 complete ✅

M0 locks the architecture before any gameplay system is written. M1 builds the universal
runtime entity on top of it. M2 makes that entity a playable character. M3 gives it numbers
that other systems change, and a way to die. M4 gives it things to carry and wear. M5 gives
it a way to use the world. All six are green.

| M0 deliverable | Where |
| --- | --- |
| Core addon skeleton | `addons/universal_gameplay/` |
| Typed base Resources | `core/contracts/framework_definition.gd`, `module_manifest.gd` |
| EventBus | `core/event_bus.gd` |
| DefinitionRegistry | `core/registry/definition_registry.gd` |
| FrameworkSettings | `core/framework_settings.gd` |
| Validation issue type | `core/contracts/validation_issue.gd`, `validation_result.gd` |
| Test harness | `tests/` |

**M0 exit gate — proven by test, not assertion:**

- *Framework loads with zero game content* — `test_framework_core.gd::test_framework_loads_with_zero_game_content`
- *A sample module can register and unregister* — `test_framework_core.gd::test_sample_module_registers_and_unregisters`
- *No sibling dependency* — `test_module_registry.gd::test_removing_one_module_leaves_unrelated_modules_working`

### M1 — Entity + Save Identity ✅

| M1 deliverable | Where |
| --- | --- |
| DefinitionBinder | `entity/definition_binder.gd` |
| PersistentIdentity | `entity/persistent_identity.gd` |
| SemanticState | `entity/semantic_state.gd` |
| FrameworkComponent base | `entity/framework_component.gd` |
| Capture / restore state | `entity/entity_serializer.gd`, `entity_record.gd` |
| Entity debug inspector | `debug/entity_inspector.gd` |
| Spawn + rebuild from record | `entity/entity_factory.gd` |
| EntityDefinition | `definitions/entity_definition.gd` |

**M1 exit gate:**

- *An entity can bind a definition* — `test_definition_binder.gd::test_entity_binds_a_definition`
- *Capabilities are configured from data, not subclassed* — `..::test_capabilities_are_configured_from_definition_data`
- *Entity state round-trips* — `test_entity_persistence.gd::test_entity_state_round_trips`

### M2 — Character + Input + Locomotion ✅

| M2 deliverable | Where |
| --- | --- |
| CharacterBody3D scene | `character/character.tscn` |
| InputRouter | `input/input_router.gd` |
| MovementComponent | `locomotion/movement_component.gd` |
| MovementProfile | `locomotion/movement_profile.gd` |
| Camera adapter | `camera/camera_adapter.gd` |
| AnimationTree adapter | `animation/animation_adapter.gd` |
| CharacterDefinition | `character/character_definition.gd` |
| Default input bindings | `input/default_input_bindings.gd` |

**M2 exit gate:**

- *Walk, sprint, crouch and jump* — `test_character.gd::test_walking_from_input`,
  `..::test_sprinting_from_input`, `..::test_crouching_from_input`, `..::test_jumping_from_input`
- *Input contexts switch cleanly* —
  `..::test_handing_control_between_two_characters_leaves_one_driver`
- *AI can issue movement commands* — `..::test_an_ai_and_a_player_reach_the_same_velocity`,
  `..::test_a_character_still_moves_with_no_controller_at_all`

### M3 — Stats + Health + Damage + Effects ✅

| M3 deliverable | Where |
| --- | --- |
| Stats + modifiers | `stats/stat_calculator.gd`, `stats_component.gd` |
| Health | `health_damage/health_component.gd` |
| Resistance / armour pipeline | `health_damage/damage_pipeline.gd`, `resistance_profile.gd` |
| Status effects | `status_effects/status_effect_component.gd` |
| Death event | `health_damage/health_event_adapter.gd` |

**M3 exit gate:**

- *Damage is deterministic* — `test_damage_pipeline.gd::test_the_same_input_gives_the_same_output_every_time`
- *Death publishes an event* — `test_health.gd::test_the_adapter_publishes_a_death_to_the_bus`
- *Modifiers stack predictably* — `test_stat_calculator.gd::test_additive_percentages_sum_rather_than_compound`,
  `..::test_the_result_does_not_depend_on_the_order_they_were_added`

### M4 — Items + Inventory + Equipment ✅

| M4 deliverable | Where |
| --- | --- |
| ItemDefinition / ItemInstance | `items/item_definition.gd`, `item_instance.gd` |
| Containers, stacking, transfer | `inventory/inventory_component.gd` |
| Equipment slots | `equipment/equipment_slot_definition.gd` |
| Loadouts | `equipment/loadout_profile.gd` |
| Pickup scene | `items/item_pickup.tscn` |

**M4 exit gate:**

- *World pickup → inventory → equip → drop round trip* —
  `test_equipment.gd::test_world_pickup_to_inventory_to_equip_to_drop`

### M5 — Interaction Platform ✅

| M5 deliverable | Where |
| --- | --- |
| InteractionComponent (on the target) | `interaction/interaction_component.gd` |
| InteractorComponent (on the actor) | `interaction/interactor_component.gd` |
| Requirements | `interaction/item_requirement.gd`, `state_requirement.gd` |
| Prompts | `InteractionDefinition.prompt`, `InteractorComponent.prompt_changed` |
| Timed interactions | `InteractionDefinition.duration`, `interactor_component.gd` |
| Action strategies | `interaction/interaction_action.gd`, `toggle_state_action.gd` |

**M5 exit gate:**

- *Door, pickup, NPC and vehicle on one pipeline* —
  `test_interaction_pipeline.gd::test_all_four_are_the_same_component_and_the_same_call`

```
37 suite(s), 845 test(s), 845 passed, 0 failed, 1603 assertions
RESULT: PASS
```

Enabling the addon binds the framework's semantic actions to WASD, space, shift, ctrl, E and
the usual gamepad equivalents, for any action the project has not already defined. It never
overwrites: rebind `jump` and it stays rebound through every future version of the addon.
Without this the addon produces a character that compiles, spawns, validates and cannot move —
and an unbound action is indistinguishable from an unpressed one at runtime.

---

## Running the tests

Requires a Godot 4.7 binary. No addons, no plugins, no package manager.

```bash
godot --headless --path . --import              # once, on a clean checkout
godot --headless --path . --script tests/run_tests.gd
```

Exits non-zero on failure, so CI gates on it directly. `.github/workflows/tests.yml`
additionally fails the build on script errors or leaked objects, which pass tests but
should never ship.

> On a clean checkout the `--import` step is **required**. It builds the `.godot` cache
> and registers global class names; without it every `class_name` lookup fails to parse.

The harness is deliberately dependency-free. A framework whose tests need a third-party
addon installed before they run is one most contributors will never run.

---

## Architecture at a glance

```
Layer 0  Core contracts      registry / settings / events / results     addons/universal_gameplay/core/
Layer 1  Definitions         "what is it?"           Resource          core/contracts/
Layer 2  Entity scenes       "what exists?"          PackedScene       entity/definition_binder.gd
Layer 3  Capabilities        "what can it do?"       child Node        entity/framework_component.gd
Layer 4  Feature modules     "how does it work?"     module folder     locomotion/ character/ input/
Layer 5  Services            "what persists?"        registered Object core/registry/
Layer 6  Communication       signals / bus / groups                    core/event_bus.gd
Layer 7  Presentation        animation / UI / audio / VFX              animation/ camera/
Layer 8  Network authority   optional adapter                          (M18)
```

Communication rules, in the order you should reach for them:

| Situation | Mechanism |
| --- | --- |
| You know the target | typed method call |
| Local state changed | plain `signal` |
| A cross-feature fact occurred | `EventBus.publish()` |
| You need runtime discovery | SceneTree group |
| You need semantic identity in data | `StringName` constant / tag |

---

## Decisions made where the source documents conflict

The Ontology Rulebook and the Implementation Plan agree on principles and disagree in two
places in their reference code. Both are resolved here deliberately.

### 1. `apply_damage(context)`, not `apply_damage(amount, context)`

The Rulebook passes the amount alongside the context; the Plan puts it inside. The Plan wins.
`DamageContext` already carries instigator, source, hit point, normal and damage tags — the
amount belongs with them. Two sources of truth for one number is rule 4 violated on line one,
and the mitigation pipeline needs somewhere to write the post-armour figure back to.

See `core/contexts/damage_context.gd` (`amount`, `final_amount`, `was_lethal`).

### 2. Components emit local signals only; the bus relay is explicit

Plan §45 has `HealthComponent` emit `EventBus.actor_died` directly. The Rulebook's version of
the same component emits only a local `died` signal. The Rulebook wins, for two reasons:

- **Testability.** A component reaching for an autoload cannot be instantiated in a unit test
  without booting the singleton. Rule 33 wants domain logic testable without a live scene.
  `test_component.gd` demonstrates the payoff.
- **Removability.** If every component hard-references the bus, the bus becomes a mandatory
  runtime dependency of every entity and "which module publishes this fact" stops having an
  answer. Promoting a local signal to a cross-feature fact is a *decision*, and it belongs at
  the seam that owns it — the entity root or an adapter — not inside the capability.

Enforced by `test_component.gd::test_component_publishes_nothing_to_the_event_bus`.

### 3. Core declares only the events whose payload types it owns

The docs show `item_added`, `item_purchased` and `objective_completed` as signals on the bus.
Those payloads belong to modules that may not be installed, so Core declaring them would put
Inventory and Commerce types inside Core — rule 1 and rule 10, both broken.

Instead Core declares `actor_died` (its payload is built from `DamageContext`, a Core type) and
modules register their own via `EventBus.register_event()`. Everything publishes through one
`publish()` and everything reaches the `event_published` firehose, which is the hook the debug
event monitor needs.

---

## A Godot 4.7 finding worth knowing

**Object-typed signal parameters on an autoload script leak that parameter's script at exit.**

```gdscript
signal actor_died(event: ActorDiedEvent)   # leaks on every run
signal actor_died(event)                   # clean
```

Every run — a real game run, not just headless — prints:

```
WARNING: 3 ObjectDB instances were leaked at exit
ERROR: 2 resources still in use at exit
```

Verified by bisection against Godot 4.7.2: untyping the parameter removes it, and removing the
static calls does not.

**The restriction is autoload-specific.** Object-typed signal parameters on ordinary Nodes are
clean — verified by creating and freeing such nodes in a loop — so capability components keep
their typed signals and rule 27 holds everywhere except these two lines. Builtin-typed
parameters are unaffected either way, which is why `FrameworkCore`'s own
`module_registered(id: StringName)` stays typed.

The bus keeps its parameter types in the docstring and enforces the real invariant where it can
be enforced — `publish()` takes a typed `FrameworkEvent` and is the only route to those signals.
GDScript does not check signal handler signatures at connect time anyway.

**Related:** `Node._ready()` does not run until the first process frame, so an autoload is
reachable before its `_ready()` has. `FrameworkCore` therefore wires itself lazily on first use
rather than in `_ready()`, and `test_core_is_usable_before_ready_runs` pins that behaviour.
`PersistentIdentity` generates its id lazily for the same reason — an entity spawned and
serialised inside one frame would otherwise have no id.

**Node exports in a hand-written `.tscn` need a `node_paths` declaration.** Writing
`movement = NodePath("../MovementComponent")` under a node is not enough — Godot stores it as a
literal `NodePath` value and the typed export stays null. The node header has to name the
properties to resolve:

```
[node name="CharacterController" type="Node" parent="." node_paths=PackedStringArray("movement", "camera")]
```

The failure is silent: the scene loads, the character moves, and nothing animates. `test_character_scene.gd`
asserts every wired export in `character.tscn`, because a `.tscn` is the one part of a
composition-first design that no unit test otherwise touches.

**A component must not disable its own processing in `_ready()`.** Godot readies children in tree
order, so a `DefinitionBinder` sitting above a component initialises it *before* that component's
own `_ready()` runs. A bare `set_physics_process(false)` there switches the character off after
the binder has just switched it on — and only for some node orders, which makes it look like a
scene-layout bug. Every M2 component recomputes the condition instead:

```gdscript
set_physics_process(is_initialized() and auto_tick and body != null)
```

**A `Resource` that stores the context it was handed leaks the whole graph.** The CI gate fails
on `ObjectDB instances were leaked at exit`, and this is the easiest way to trip it. An
`InteractionContext` holds the `InteractionDefinition`, which holds the `InteractionAction` —
so an action that stashes `last_context` closes a `RefCounted` cycle that Godot's reference
counting cannot break, and every resource in it survives to exit. Godot reports the count, not
the culprit. Record the facts you need (`last_interactor`, `last_verb`), not the context.

**Also:** `Node3D.global_transform` is only legal inside the tree. `EntitySerializer` falls back
to the local transform when an entity is captured before it is parented, rather than erroring
and silently recording identity. The test harness yields one frame before running so its nodes
are genuinely in-tree — without that, nothing spatial or lifecycle-dependent is testable at all.

---

## Layout

```
addons/universal_gameplay/
├── core/
│   ├── framework_core.gd          control plane. lifecycle, registries, settings
│   ├── event_bus.gd               cross-feature facts
│   ├── framework_settings.gd      module toggles, content paths
│   ├── gameplay_names.gd          shared StringName vocabulary
│   ├── framework_version.gd       framework + save schema versions
│   ├── contracts/                 definitions, manifests, services, validation
│   ├── contexts/                  EntityContext, DamageContext, FrameworkResult
│   ├── events/                    FrameworkEvent + Core payloads
│   └── registry/                  definitions, services, modules
├── definitions/
│   └── entity_definition.gd       a definition with a scene, so it can be spawned
├── entity/
│   ├── framework_component.gd     capability base: initialise, capture, restore
│   ├── definition_binder.gd       the composition seam. marks an entity root
│   ├── persistent_identity.gd     save identity that outlives the scene
│   ├── semantic_state.gd          runtime state tags
│   ├── entity_record.gd           what one entity writes to a save
│   ├── entity_serializer.gd       capture / restore across an entity
│   ├── entity_factory.gd          spawn from definition, rebuild from record
│   └── entity_module.gd           the Entity module manifest
├── input/
│   ├── input_source.gd            where raw action state is read from
│   ├── engine_input_source.gd     the only place that touches Godot's Input
│   ├── input_context.gd           which actions are live, as a definition
│   ├── input_contexts.gd          the six standard contexts
│   ├── input_router.gd            the context stack. a service, not an autoload
│   └── default_input_bindings.gd  WASD and a gamepad, so the addon works enabled
├── locomotion/
│   ├── movement_profile.gd        speeds, acceleration, jump. reusable data
│   ├── movement_intent.gd         what something wants, with no idea who asked
│   ├── movement_solver.gd         all the maths. static, no node, no physics
│   └── movement_component.gd      the one API every driver shares
├── camera/
│   ├── camera_profile.gd          view mode, framing, look limits, FOV
│   ├── camera_solver.gd           look clamping and boom placement
│   └── camera_adapter.gd          drives a rig. works without one
├── animation/
│   ├── animation_profile.gd       semantic state -> AnimationTree parameters
│   └── animation_adapter.gd       observes movement. never writes back
├── character/
│   ├── character_definition.gd    a scene plus the profiles that configure it
│   ├── character_controller.gd    player input -> movement. one driver of many
│   └── character.tscn             the shared character scene
├── stats/
│   ├── stat_modifier.gd           one change, and where it came from
│   ├── stat_calculator.gd         the fixed order modifiers apply in
│   ├── stat_definition.gd         what a stat is: range, depletion, regen
│   ├── stats_profile.gd           which stats an entity has, and its bases
│   └── stats_component.gd         values, modifiers, depletion
├── health_damage/
│   ├── resistance_profile.gd      armour and per-tag resistance
│   ├── damage_pipeline.gd         mitigation. static, deterministic
│   ├── health_component.gd        one number: still standing or not
│   ├── damage_receiver_component.gd  the entry point for damage
│   └── health_event_adapter.gd    the seam that promotes a death to the bus
├── status_effects/
│   ├── status_effect_definition.gd  buffs and poisons as data
│   ├── status_effect_instance.gd    one live application
│   └── status_effect_component.gd   apply, stack, expire, tick
├── items/
│   ├── item_definition.gd         what an item is. shared, immutable
│   ├── item_instance.gd           one stack: count, condition, enchantments
│   ├── item_pickup.gd             an item lying in the world
│   └── item_pickup.tscn           the pickup scene
├── inventory/
│   ├── inventory_profile.gd       slots, weight, category filters
│   └── inventory_component.gd     one container. transfers are atomic
├── equipment/
│   ├── equipment_profile.gd       where an item goes and what it grants
│   ├── equipment_slot_definition.gd  one place a thing can be worn
│   ├── loadout_profile.gd         which slots, and what is worn to start
│   └── equipment_component.gd     wearing things, sourced per instance
├── interaction/
│   ├── interaction_definition.gd  one thing that can be done to something
│   ├── interaction_context.gd     everything one attempt knows about itself
│   ├── interaction_component.gd   what a target offers, and the transaction
│   ├── interactor_component.gd    focus, reach, and the timing of a hold
│   ├── interactor_profile.gd      how far something reaches, and how it looks
│   ├── interaction_requirement.gd a condition. checked often, committed once
│   ├── item_requirement.gd        the keycard, and the coin in the slot
│   ├── state_requirement.gd       open, locked, downed. either end
│   ├── interaction_action.gd      what happens on completion. usually nothing
│   └── toggle_state_action.gd     the door, and everything shaped like a door
├── debug/entity_inspector.gd      what is this entity, and would it persist?
├── validation/                    content validation and cycle detection
└── plugin.gd / plugin.cfg         one-click autoload installation

tests/
├── framework_test_case.gd         assertions
├── framework_test_runner.gd       discovery and execution
├── run_tests.gd                   headless entry point
├── cases/                         the suites
├── support/                       fixtures
├── content/                       sample .tres for content-loading tests
└── entities/                      sample entity scenes and definitions
```

Game content lives outside the addon entirely, in `res://game/`. The framework knows
`CharacterDefinition`; it must never know a named hero, city or mission.

---

## Roadmap

M0 through M5 are done. The build order follows dependency, not feature appeal.

| | Milestone | | | Milestone |
| --- | --- | --- | --- | --- |
| **M0** | **Foundation contract** ✅ | | M10 | Factions + reputation |
| **M1** | **Entity + save identity** ✅ | | M11 | Commerce + vendors + loot |
| **M2** | **Character + input + locomotion** ✅ | | M12 | Crafting + survival |
| **M3** | **Stats + health + damage + effects** ✅ | | M13 | Vehicles |
| **M4** | **Items + inventory + equipment** ✅ | | M14 | Spawn + world state + traffic |
| **M5** | **Interaction platform** ✅ | | M15 | Crime / heat |
| M6 | Combat + weapons | | M16 | Full persistence |
| M7 | AI + NPC roles | | M17 | UI framework + debug tooling |
| M8 | Dialogue + narrative state | | M18 | Networking adapter |
| M9 | Missions + objectives | | M19 | Packaging + documentation |

Vertical slices gate breadth: adventure, shooter RPG, survival, GTA-style sandbox, then full
hybrid. If a slice needs a circular dependency or a game-specific hack in Core, the
architecture is wrong and gets fixed before more systems land.

---

## The rules that actually bite

The full rulebooks live in [`docs/`](docs/) — the [Implementation Plan](docs/implementation-plan.md)
and the [Ontology Rulebook](docs/ontology-rulebook.md), with the original `.docx` kept in
[`docs/source/`](docs/source/). These are the ones that change what you type:

1. **Core is infrastructure.** It owns lifecycle, config, registries and contracts. Never
   `apply_damage()`, `buy_item()` or `complete_quest()`.
2. **Resources define; Nodes execute.** Immutable content in Resources, mutable state in Nodes.
3. **One authoritative owner per state.**
4. **Every module is removable.** Deleting Commerce must not stop Combat from loading.
5. **Commands are targeted; facts are broadcast.** If you know who should react, call them.
6. **NPC roles are configuration, not a class hierarchy.** Vendor, guard and civilian are the
   same character foundation with different data.
7. **Definitions and instances are separate.** Shared immutable definition, per-instance state.
8. **Presentation observes; it never owns.**
9. **Save IDs and state, never scene graphs.**
10. **No abstraction without demonstrated reuse.**
