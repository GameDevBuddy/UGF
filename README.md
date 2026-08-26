# Universal Gameplay Framework

A reusable, data-driven gameplay platform for **Godot 4.7**, built to support action RPG,
shooter, open-world sandbox, driving, survival, faction simulation, commerce and narrative
adventure games from one foundation — without any of those genres being baked into it.

Godot-native throughout: scenes compose entities, typed `Resource` definitions carry content,
signals handle local communication, and a narrow event bus carries cross-feature facts.

---

## Status: M0 + M1 complete ✅

M0 locks the architecture before any gameplay system is written. M1 builds the universal
runtime entity on top of it. Both are green.

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

```
14 suite(s), 228 test(s), 228 passed, 0 failed, 453 assertions
RESULT: PASS
```

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
Layer 4  Feature modules     "how does it work?"     module folder     (M2+)
Layer 5  Services            "what persists?"        registered Object core/registry/
Layer 6  Communication       signals / bus / groups                    core/event_bus.gd
Layer 7  Presentation        animation / UI / audio / VFX              (M2+)
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

M0 is done. The build order follows dependency, not feature appeal.

| | Milestone | | | Milestone |
| --- | --- | --- | --- | --- |
| **M0** | **Foundation contract** ✅ | | M10 | Factions + reputation |
| **M1** | **Entity + save identity** ✅ | | M11 | Commerce + vendors + loot |
| M2 | Character + input + locomotion | | M12 | Crafting + survival |
| M3 | Stats + health + damage + effects | | M13 | Vehicles |
| M4 | Items + inventory + equipment | | M14 | Spawn + world state + traffic |
| M5 | Interaction platform | | M15 | Crime / heat |
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
