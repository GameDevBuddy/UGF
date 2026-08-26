# Godot 4.7 Universal Gameplay Framework

Complete Implementation Plan and Scalable Technical Specification

GDScript • RPG • Shooter • Driving • GTA-style Sandbox • Survival • Combat • Factions • Trading • Adventure • Narrative

Design target: a reusable gameplay platform, not a single game.

## 1. Executive Vision

The framework is a reusable Godot 4.7 gameplay platform intended to support multiple genres from one coherent foundation: action RPG, shooter, open-world sandbox, driving, survival, faction simulation, commerce, narrative adventure, mission-driven games, and hybrids of those genres. The platform should feel closer to a suite of interoperable gameplay systems than a monolithic template.

The fundamental design goal is controlled composition: game projects opt into modules, definitions configure them, entity scenes assemble capabilities, signals handle local communication, and a narrow EventBus carries cross-feature facts. No feature module is allowed to become a mandatory dependency unless it belongs to the Core contract layer.

## 2. Non-Negotiable Architecture Principles

Godot-native composition first: scenes, Nodes, Resources, signals and groups.

Typed GDScript for public framework APIs and reusable data contracts.

Resources define content; runtime Nodes own mutable state.

Feature modules may depend on Core, not casually on sibling modules.

Direct method calls are commands; signals/EventBus facts are events.

Autoloads are scarce and broad-scoped.

Every major module must be removable without breaking unrelated modules.

Game-specific content lives outside the framework addon.

Save/persistence uses stable IDs plus runtime state, not serialized SceneTree graphs.

Networking is designed as an optional authority layer, not entangled with every local implementation.

## 3. Platform Scope

| Genre / capability | Framework support |
| --- | --- |
| RPG | stats, progression, equipment, loot, quests, factions, reputation, dialogue, vendors, skills |
| Shooter | weapons, ammo, damage, recoil, hitscan/projectiles, targeting, cover hooks, combat AI |
| Driving | vehicle definitions, seats, possession, fuel/damage, storage, upgrades, cameras, traffic hooks |
| GTA-style sandbox | world state, vehicles, factions, crime/heat hooks, NPC roles, missions, shops, spawning, persistence |
| Survival | needs, temperature, hunger/thirst, status effects, crafting, gathering, durability, shelter hooks |
| Combat | damage pipeline, health, armor, resistance, effects, teams/factions, death, rewards |
| Factions | membership, relationships, reputation, hostility, territories/hooks, diplomacy data |
| Trading | currencies, vendor stock, prices, buy/sell, barter hooks, restock, economy modifiers |
| Adventure | interaction, items, doors, puzzles, objectives, dialogue, narrative state, save/load |
| Narrative | dialogue graphs/data, conditions, variables, event triggers, mission integration, cinematic hooks |

## 4. Full Layered Architecture

```
GAME PROJECT
│
├── Game-specific content
│   ├── characters
│   ├── items
│   ├── vehicles
│   ├── missions
│   ├── dialogue
│   └── world
│
└── Universal Framework Addon
    │
    ├── Layer 0: Core Contracts
    ├── Layer 1: Definitions / Profiles
    ├── Layer 2: Entity Scenes
    ├── Layer 3: Capability Nodes
    ├── Layer 4: Feature Modules
    ├── Layer 5: Persistent Services
    ├── Layer 6: Communication
    ├── Layer 7: Presentation Adapters
    └── Layer 8: Optional Network Authority
```

## 5. Core Contract Layer

Core must stay tiny. Its job is to make modules interoperable without owning their gameplay.

| Core element | Responsibility |
| --- | --- |
| FrameworkCore | startup, settings, service discovery, feature availability |
| EventBus | cross-feature factual events only |
| DefinitionRegistry | resolve IDs to typed Resources |
| GameplayNames | shared StringName constants for common semantics |
| FrameworkSettings | global framework configuration Resource |
| Result/Context types | stable request/result payloads |
| Save IDs | persistent entity identity contract |
| Versioning | framework/schema version and migrations |

```
# framework_core.gd
extends Node

var services: Dictionary[StringName, Object] = {}
var features: Dictionary[StringName, bool] = {}

func register_service(id: StringName, service: Object) -> void:
    services[id] = service

func get_service(id: StringName) -> Object:
    return services.get(id)

func has_feature(id: StringName) -> bool:
    return features.get(id, false)
```

## 6. Definition and Profile Layer

Every major gameplay concept receives a typed Resource definition. Definitions reference reusable Profile Resources rather than accumulating hundreds of fields.

| Definition | Contains |
| --- | --- |
| CharacterDefinition | identity, scene, appearance, movement, stats, loadout, AI, faction, role tags |
| ItemDefinition | presentation, stacking, category, world scene, fragments/profiles |
| WeaponDefinition | fire mode, damage, ammo, recoil, projectile/hitscan, FX hooks |
| VehicleDefinition | scene, seats, handling, fuel, damage, storage, camera, upgrade slots |
| AIProfile | perception, decision brain, navigation, aggression, combat strategy |
| FactionDefinition | identity, relations, default reputation, hostility rules |
| VendorDefinition | stock, currency, pricing, restock, restrictions |
| InteractionDefinition | prompt, requirements, duration, action strategy |
| MissionDefinition | objectives, sequencing, rewards, failure rules |
| ObjectiveDefinition | event criteria, counters, filters, completion |
| DialogueDefinition | conversation data, conditions, branches, actions |
| LootDefinition | weighted pools, quantities, conditions, rarity |
| RecipeDefinition | inputs, tools, requirements, outputs, duration |
| StatusEffectDefinition | duration, stacking, modifiers, periodic effects |
| SpawnDefinition | entity pools, conditions, density, respawn rules |
| WorldObjectDefinition | scene, interaction, health, loot, state |

## 7. Runtime Entity Model

```
FrameworkEntity
├── DefinitionBinder
├── PersistentIdentity
├── SemanticState
└── optional capability Nodes

CharacterEntity (CharacterBody3D)
├── MovementComponent
├── StatsComponent
├── HealthComponent
├── InventoryComponent
├── EquipmentComponent
├── InteractionComponent
├── FactionComponent
├── StatusEffectComponent
├── CombatComponent
├── AnimationAdapter
└── AIControllerComponent (optional)

VehicleEntity
├── VehicleController
├── SeatComponent
├── HealthComponent
├── FuelComponent
├── StorageComponent
├── InteractionComponent
└── UpgradeComponent

WorldObjectEntity
├── InteractionComponent
├── StateComponent
├── HealthComponent (optional)
├── LootComponent (optional)
└── SaveIdentityComponent
```

## 8. Capability Component Standard

Capabilities are reusable child Nodes with explicit APIs, typed signals, serializable state methods, and no hard dependency on sibling feature implementations.

```
class_name FrameworkComponent
extends Node

func initialize(context: EntityContext) -> void:
    pass

func capture_state() -> Dictionary:
    return {}

func restore_state(data: Dictionary) -> void:
    pass
```

Recommended baseline capabilities:

HealthComponent

StatsComponent

InventoryComponent

EquipmentComponent

InteractionComponent

FactionComponent

StatusEffectComponent

DamageReceiverComponent

VendorComponent

DialogueComponent

LootComponent

NeedsComponent

CraftingComponent

SeatComponent

FuelComponent

UpgradeComponent

SaveIdentityComponent

## 9. Communication Architecture

| Situation | Mechanism | Example |
| --- | --- | --- |
| Known target command | typed method | inventory.add_item(instance) |
| Local component state | signal | health_changed |
| Parent/child orchestration | typed reference + signal | Character -> MovementComponent |
| Cross-feature fact | EventBus | actor_died, item_purchased |
| Runtime discovery | group | interactable, saveable, traffic_agent |
| Semantic identity | StringName / Resource tags | faction.police, state.wanted |

```
Combat ── emits actor_died ──> EventBus
                                  │
                 ┌────────────────┼───────────────┐
                 ▼                ▼               ▼
             Missions          Loot           Reputation
```

## 10. Module Catalogue

| Module | Primary responsibility |
| --- | --- |
| Core | contracts, event bus, definitions, registry, settings, migrations |
| Entity | definition binding, persistent IDs, semantic state |
| Character | character assembly, controller handoff, common contexts |
| Locomotion | movement modes, sprint/crouch/jump, traversal hooks, movement profiles |
| Animation | AnimationTree adapter, state presentation, animation events |
| Camera | first/third person, vehicle, lock-on, cinematic hooks |
| Input | action abstraction, input contexts, rebinding, device switching |
| Stats | attributes, modifiers, derived stats, regeneration |
| Health/Damage | damage pipeline, armor/resistance, death, healing |
| Status Effects | buff/debuff, duration, stacking, periodic effects |
| Combat | targeting, melee/ranged orchestration, teams/factions integration |
| Weapons | hitscan/projectile, ammo, reload, recoil, spread, attachments hooks |
| Inventory | containers, stacking, transfer, capacity, item instances |
| Equipment | slots, equip/unequip, loadouts, appearance hooks |
| Items | definitions, instances, use actions, world pickups |
| Interaction | focus, prompts, requirements, actions, interaction channels |
| Dialogue | conversation runtime, conditions, variables, choices, actions |
| Narrative State | global/local narrative variables, flags, consequences |
| Missions/Objectives | event-driven objectives, sequencing, rewards, failure |
| Factions | membership, reputation, relations, hostility, standing |
| Commerce | currency, pricing, transactions, stock, vendor rules |
| Vendors | vendor capability and stock binding |
| Loot | loot tables, drops, rewards |
| Crafting | recipes, stations, requirements, queues |
| Survival Needs | hunger, thirst, fatigue, temperature, exposure |
| Gathering | resource nodes, yields, tools, respawn |
| Vehicles | possession, seats, storage, damage, fuel, upgrades |
| Traffic | spawn lanes/points, traffic agents, despawn, density hooks |
| AI | perception, brain adapters, navigation, combat decisions |
| NPC Roles | role definitions: vendor, civilian, guard, quest giver, companion |
| Spawn/Encounter | pools, spawn rules, encounter groups, population budgets |
| World State | persistent flags, global simulation values, region state |
| Crime/Heat | witness hooks, wanted level, law faction responses |
| Save/Persistence | profiles, slots, entity state, migrations, autosave |
| UI Presentation | view-model/presenter patterns, notifications, menus |
| Audio/VFX Hooks | presentation event adapters |
| Networking Optional | authority, RPC boundary, replication adapters |
| Debug/Developer | console, inspectors, cheats, event monitor, data validation |

## 11. Module Dependency Policy

```
FrameworkCore
   ▲
   │
   ├── Inventory
   ├── Combat
   ├── Missions
   ├── Vehicles
   ├── Commerce
   ├── AI
   └── Survival

Optional adapters may bridge two modules:
CommerceInventoryAdapter
CombatFactionAdapter
MissionDialogueAdapter

The base modules do not import one another merely to react to events.
```

When two features genuinely require a synchronous command relationship, place the smallest stable interface/context in Core or create an explicit adapter module. Adapters are preferred to hidden bidirectional coupling.

## 12. RPG Feature Specification

### Stats

base values

flat and multiplicative modifiers

derived stats

regen

clamps

source tracking

### Progression

XP tracks

levels

skill points

perk/skill unlock hooks

reputation progression

### Equipment

typed slots

requirements

equip rules

loadouts

stat modifiers

visual attachment hooks

### Loot

weighted tables

rarity

conditions

nested pools

currency rewards

### Quests

event-driven objectives

chains

branch conditions

rewards

fail states

hidden objectives

## 13. Shooter Feature Specification

```
WeaponComponent
├── WeaponDefinition
├── fire_controller
├── ammo_state
├── reload_state
├── recoil_state
└── presentation hooks

Fire strategies
├── HitscanFireStrategy
├── ProjectileFireStrategy
├── BurstFireStrategy
└── ChargeFireStrategy
```

DamageContext carries instigator, source, hit point, normal, semantic damage tags and optional weapon ID.

Recoil and spread are data-driven profiles.

Ammo can be magazine-based, reserve-based, energy-based or infinite via strategy/config.

Weapon presentation emits local signals; combat outcomes emit cross-feature events.

Aim/ADS is a character/camera state, not hardcoded inside each weapon.

## 14. Melee / Action Combat Specification

AttackDefinition Resource: timing, damage window, stamina cost, combo tags, animation key, hit shape profile.

CombatAction state machine: idle, startup, active, recovery, interrupted.

Hit detection strategy: Area3D, shape cast, weapon hurtbox, animation event.

Defense: block, parry, dodge, poise/stagger hooks.

Targeting: free aim, soft target, hard lock optional adapter.

Status effects and damage modifiers stay in dedicated modules.

## 15. Survival Specification

| System | Design |
| --- | --- |
| Needs | generic meters driven by NeedDefinition: hunger, thirst, fatigue, oxygen, sanity, etc. |
| Temperature | environment sample -> body temperature model -> effects |
| Gathering | resource node definition + tool requirements + yield table |
| Crafting | recipe definitions + station capabilities + timed queue |
| Durability | item instance state, degradation policies, repair hooks |
| Shelter | environment modifiers exposed through zones/areas |

## 16. Factions, Reputation and Crime

```
FactionDefinition
├── id
├── display data
├── default relations
├── hostility thresholds
└── role tags

FactionService
├── get_relation(a, b)
├── modify_relation(a, b, amount)
├── get_reputation(actor, faction)
└── resolve_attitude(observer, target)
```

Crime/heat is optional and layered on top:

CrimeEvent Resource/context: type, severity, victim faction, location, witnesses.

Witness AI reports crime through an event rather than directly modifying wanted state.

HeatService converts validated crimes into wanted tiers.

Law/guard AI reacts to semantic wanted state and faction relationships.

## 17. Commerce, Vendors and Economy

| Part | Responsibility |
| --- | --- |
| CurrencyDefinition | money type, display, precision |
| WalletComponent | balances on an entity |
| VendorDefinition | stock source, pricing profile, restock |
| VendorComponent | binds vendor data to NPC/terminal |
| CommerceService | validate + execute atomic transactions |
| PricingPolicy | base value, faction/reputation, scarcity, difficulty hooks |
| StockPolicy | fixed, generated, rotating, finite, unlimited |

Transactions must be atomic: validate currency, stock, capacity and restrictions first; only then mutate all participating state and emit the completion event.

## 18. Narrative and Dialogue Platform

Narrative is split into data, runtime state, conditions and actions. The framework should not require one editor format; it should expose stable runtime contracts so future custom graph tools can feed the same system.

```
DialogueDefinition
├── Nodes
│   ├── Line
│   ├── Choice
│   ├── Branch
│   ├── Action
│   ├── Jump
│   └── End
├── Conditions
└── Actions

NarrativeStateService
├── global flags
├── scoped variables
├── counters
└── relationship variables
```

Conditions query data; they do not mutate state.

Actions mutate narrative/world state or issue explicit feature commands.

Dialogue completion and important choices emit cross-feature events.

Mission objectives subscribe to narrative events rather than reading dialogue internals.

Cinematic/camera control is an adapter, not embedded in dialogue data.

## 19. Mission and Objective Runtime

```
MissionRuntime
├── definition_id
├── state
├── current_objectives[]
└── local variables

ObjectiveRuntime
├── definition
├── progress
├── status
└── event subscriptions
```

Baseline objective types:

ReachArea

InteractWith

AcquireItem

DeliverItem

Kill/Defeat

TalkTo

Purchase/Sell

DriveTo

EnterVehicle

CraftItem

SurviveDuration

GainReputation

SetNarrativeFlag

CustomEvent

## 20. AI Platform

AI is deliberately algorithm-agnostic. The framework provides perception facts, action requests, blackboard-like runtime context, navigation adapters and reusable actions. A project may use a finite state machine, hierarchical states, utility AI, GOAP, behavior-tree addon, or a hybrid.

```
AIControllerComponent
├── AIProfile
├── PerceptionComponent
├── MemoryComponent
├── BrainAdapter
├── NavigationAgent3D
└── ActionExecutor

Perception facts
├── seen_actor
├── heard_event
├── damaged_by
├── crime_witnessed
└── interaction stimulus
```

Reusable AI actions should issue the same gameplay commands a player controller would use: move, aim, fire, interact, enter vehicle, use item.

## 21. NPC Role System

NPC roles are additive capabilities/data, not subclasses.

| Role | Required pieces |
| --- | --- |
| Civilian | CharacterDefinition + civilian AI profile |
| Guard | Faction + combat capability + guard AI profile |
| Vendor | VendorComponent + VendorDefinition + interaction |
| Quest giver | Dialogue + mission hooks + interaction |
| Companion | AI profile + party relation + follow/command hooks |
| Driver | vehicle-use capability + traffic/driver AI |
| Craftsperson | Vendor/Crafting capabilities + dialogue |

## 22. Vehicle and Driving Platform

Vehicle handling must use an adapter boundary. The framework owns vehicle identity, seats, fuel, damage, storage, upgrades, cameras and possession; the concrete motion implementation may use VehicleBody3D or a custom CharacterBody3D/physics controller.

```
VehicleControllerAdapter
├── set_throttle(value)
├── set_brake(value)
├── set_steering(value)
├── set_handbrake(active)
├── get_speed()
└── get_motion_state()
```

SeatDefinition specifies role: driver, passenger, turret, cargo operator.

Possession swaps input/controller context rather than changing entity identity.

Vehicle inventory/storage is the same Inventory capability with a different container definition.

Damage and faction logic reuse generic systems.

Traffic AI uses VehicleControllerAdapter, not vehicle-specific methods.

## 23. World / GTA-style Sandbox Layer

Population budgets by region/category.

Spawn anchors and encounter definitions.

Traffic density and despawn policies.

WorldStateService for persistent global/region flags.

Faction presence hooks.

Crime/heat optional module.

Interior/exterior scene streaming policy owned by game layer or SceneFlow service.

Save system persists important entities; ambient population may be regenerated from definitions.

## 24. Input Context Architecture

```
InputRouter
├── on_foot context
├── vehicle_driver context
├── vehicle_passenger context
├── UI context
├── dialogue context
└── disabled/cinematic context
```

Gameplay code asks for semantic actions, never raw keyboard/gamepad inputs. Godot InputMap remains the engine-level binding source. Context routing decides which controller receives those actions.

## 25. Animation and Presentation Layer

AnimationTree and AnimationPlayer are presentation mechanisms.

Movement/Combat state is authoritative outside animation.

Animation events may request local presentation or invoke narrowly-defined gameplay windows through adapter callbacks.

Characters use AnimationProfile Resources to map semantic states/actions to tree parameters and animation keys.

UI uses presenters/view-model Nodes that subscribe to local signals and selected global events.

Audio/VFX consume presentation events; they do not calculate gameplay results.

## 26. Save, Persistence and Schema Migration

```
SaveGame
├── framework_version
├── save_schema_version
├── profile
├── world_state
├── narrative_state
├── faction_state
├── mission_state
└── entity_records[]

EntityRecord
├── persistent_id
├── definition_id
├── scene/region key
├── transform
└── component_state{}
```

Use explicit serializers rather than serializing arbitrary Nodes. Each persistent component owns capture_state()/restore_state(). SaveService aggregates those records. A migration registry upgrades older schemas step by step.

## 27. Optional Multiplayer Architecture

Do not make networking a mandatory dependency. Instead, define mutation APIs so an authority adapter can sit in front of them. For networked projects, gameplay-critical decisions become server-authoritative and clients send requests/intents.

```
Offline:
Controller -> Component command -> mutate

Networked:
Controller -> NetworkAuthorityAdapter -> RPC/request
                                -> server validates
                                -> component command
                                -> replicated result/state
```

Inventory, commerce, combat results and mission progression are authority-owned.

Presentation signals remain local.

Network identifiers are separate from persistent save IDs.

Use MultiplayerSpawner/Synchronizer only where they suit the chosen topology; do not expose them to feature APIs.

## 28. Data Validation and Authoring

The framework needs editor-time validation almost as much as runtime code.

Every Definition Resource has validate() returning typed validation issues.

A validation runner scans framework/game definition folders.

Check duplicate IDs, missing Resources, invalid ranges, circular mission chains, invalid faction references, broken item references and impossible recipes.

Provide debug-friendly display names and source paths in errors.

Add optional @tool inspector helpers only after runtime contracts stabilize.

## 29. Debug / Developer Tooling

| Tool | Purpose |
| --- | --- |
| Event Monitor | live EventBus feed with source and payload |
| Entity Inspector | definition ID, components, tags, faction, save ID |
| Inventory Inspector | containers, item instances, capacity |
| Mission Inspector | active missions/objective progress |
| AI Debug Panel | brain state, target, perception facts, path |
| Faction Matrix | live relations/reputation |
| Save Inspector | current persistent records |
| Spawn Debugger | budgets, active populations, reasons for rejection |
| Console/Cheats | spawn item, set stat, start mission, change faction, enter vehicle |

## 30. Performance and Scale Rules

Do not process every component every frame. Disable _process/_physics_process unless actively needed.

Prefer event-driven updates for inventory, missions, stats and narrative.

Use timers/ticked services for low-frequency survival/economy simulation.

Pool high-frequency transient objects such as projectiles only after profiling proves value.

Avoid global group scans in hot loops; cache owned references or maintain registries.

Keep Resource definitions immutable and shared.

Use distance/region budgets for AI and world population.

Separate ambient simulation from persistent authored entities.

Profile before replacing clear GDScript with specialized/native code.

## 31. Testing Strategy

| Test tier | Examples |
| --- | --- |
| Pure logic | pricing policies, stat modifiers, loot rolls, faction attitude, objective filters |
| Component tests | inventory transfer, damage, effects, needs, wallet |
| Scene integration | character interaction, weapon firing, vehicle entry, vendor transaction |
| Feature integration | kill -> loot -> objective -> reputation |
| Persistence | save/load round trip + schema migration |
| Content validation | all definitions resolve and validate |
| Performance | AI population, inventory scale, mission event volume |
| Network optional | authority rejection, replication correctness |

## 32. Recommended Folder Structure

```
res://addons/universal_gameplay/
├── core/
│   ├── framework_core.gd
│   ├── event_bus.gd
│   ├── gameplay_names.gd
│   ├── framework_settings.gd
│   ├── contracts/
│   ├── contexts/
│   └── registry/
│
├── entity/
├── definitions/
├── character/
├── locomotion/
├── animation/
├── camera/
├── input/
├── stats/
├── health_damage/
├── status_effects/
├── combat/
├── weapons/
├── items/
├── inventory/
├── equipment/
├── interaction/
├── dialogue/
├── narrative/
├── missions/
├── factions/
├── commerce/
├── vendors/
├── loot/
├── crafting/
├── survival/
├── gathering/
├── vehicles/
├── traffic/
├── ai/
├── npc_roles/
├── spawn/
├── world_state/
├── crime_heat/
├── save/
├── ui/
├── networking/
├── debug/
└── tests/

res://game/
├── definitions/
├── scenes/
├── characters/
├── vehicles/
├── items/
├── missions/
├── dialogue/
├── world/
└── ui/
```

## 33. Public API Naming Convention

```
Types:
CharacterDefinition
InventoryComponent
CommerceService
DamageContext
MissionRuntime

Signals:
health_changed
item_added
transaction_completed
objective_completed

Commands:
apply_damage()
add_item()
equip_item()
interact()
purchase()
start_mission()

Events:
EventBus.actor_died
EventBus.item_purchased
EventBus.reputation_changed

IDs:
&"character.guard"
&"item.weapon.rifle"
&"faction.police"
&"mission.main.intro"
```

## 34. Milestone Roadmap

### M0 - Foundation Contract

Lock architecture before content systems.

Deliverables: Core addon skeleton; typed base Resources; EventBus; DefinitionRegistry; FrameworkSettings; test harness; validation issue type.

Exit gate: Framework loads with zero game content; sample module can register/unregister; no sibling dependency.

### M1 - Entity + Save Identity

Create universal runtime entity pattern.

Deliverables: DefinitionBinder; PersistentIdentity; FrameworkComponent base; capture/restore state; entity debug inspector.

Exit gate: Character/world object can bind a definition; entity state round-trip works.

### M2 - Character + Input + Locomotion

Playable reusable character base.

Deliverables: CharacterBody3D scene; InputRouter; MovementComponent; MovementProfile; camera adapter; AnimationTree adapter.

Exit gate: walk/sprint/crouch/jump; switch input context cleanly; AI can issue movement commands.

### M3 - Stats + Health + Damage + Effects

Shared RPG/combat foundation.

Deliverables: Stats; Health; DamageContext; resistance/armor pipeline; status effects; death event.

Exit gate: damage is deterministic; death publishes event; modifiers stack predictably.

### M4 - Items + Inventory + Equipment

Universal ownership/equipment model.

Deliverables: ItemDefinition/Instance; containers; stacking; transfer; equipment slots; loadouts; pickup scene.

Exit gate: world pickup -> inventory -> equip -> drop round trip.

### M5 - Interaction Platform

Generic interaction for all genres.

Deliverables: InteractorComponent; InteractionComponent; requirements; prompts; timed interactions; action strategies.

Exit gate: door, pickup, NPC and vehicle use same interaction pipeline.

### M6 - Combat + Weapons

Shooter and action-combat baseline.

Deliverables: hitscan/projectile; ammo/reload; recoil/spread; melee action windows; targeting hooks.

Exit gate: ranged and melee share DamageContext; AI and player use same command API.

### M7 - AI + NPC Roles

Reusable actors controlled by data.

Deliverables: AIControllerComponent; Perception; Memory; BrainAdapter; NavigationAgent3D integration; vendor/guard/civilian role profiles.

Exit gate: civilian, guard and combatant built from same character base.

### M8 - Dialogue + Narrative State

Narrative platform.

Deliverables: DialogueDefinition/runtime; conditions; actions; NarrativeStateService; UI presenter.

Exit gate: branching conversation; persistent flags; events emitted for choices.

### M9 - Missions + Objectives

Event-driven quest/adventure system.

Deliverables: MissionDefinition; ObjectiveDefinition; runtime state; reward hooks; failure hooks.

Exit gate: mission reacts to combat/inventory/dialogue without importing them.

### M10 - Factions + Reputation

Social/world relationship layer.

Deliverables: FactionDefinition; FactionService; reputation; attitude resolver; faction events.

Exit gate: AI hostility and vendor pricing can consume faction results via adapters.

### M11 - Commerce + Vendors + Loot

Trading/economy foundation.

Deliverables: Wallet; currencies; VendorDefinition; CommerceService; pricing/stock policies; loot tables.

Exit gate: atomic purchase/sale; restock; reputation pricing adapter.

### M12 - Crafting + Survival

Survival/RPG feature pack.

Deliverables: recipes; stations; needs; temperature hooks; durability; gathering.

Exit gate: gather -> craft -> consume loop; needs save/load.

### M13 - Vehicles

Driving/GTA foundation.

Deliverables: VehicleDefinition; controller adapter; seats; enter/exit; fuel; damage; storage; camera contexts.

Exit gate: player and AI can drive through same adapter; vehicle persists.

### M14 - Spawn + World State + Traffic

Sandbox population layer.

Deliverables: SpawnService; encounter definitions; population budgets; world state; traffic agents/hooks.

Exit gate: region population scales without global per-frame scans.

### M15 - Crime / Heat

Optional GTA-style law system.

Deliverables: crime events; witness reporting; wanted tiers; law response hooks.

Exit gate: crime can alter faction/AI response without combat dependency cycles.

### M16 - Full Persistence

Production-grade save platform.

Deliverables: save slots; autosave; world/entity state; mission/narrative/faction state; schema migration.

Exit gate: full feature-stack round-trip; old save migration test.

### M17 - UI Framework + Debug Tooling

Production authoring layer.

Deliverables: presenters/view models; HUD shells; inventory/shop/dialogue/mission widgets; debug monitors; console.

Exit gate: UI contains no domain authority; debug event/entity inspectors operational.

### M18 - Networking Adapter

Optional multiplayer-ready layer.

Deliverables: authority facade; RPC validation; spawn/sync adapters; network test scenes.

Exit gate: offline mode unchanged; server-authoritative inventory/combat prototype.

### M19 - Packaging + Documentation

Turn framework into reusable product.

Deliverables: addon packaging; example projects; API docs; migration guide; module enablement docs; benchmarks.

Exit gate: new project integrates Core + chosen modules without copying game-specific code.

## 35. Recommended Build Order by Dependency

```
CORE
 ↓
ENTITY
 ↓
CHARACTER / INPUT / MOVEMENT
 ↓
STATS + HEALTH + DAMAGE
 ↓
ITEMS + INVENTORY + EQUIPMENT
 ↓
INTERACTION
 ↓
COMBAT / WEAPONS
 ↓
AI
 ↓
DIALOGUE + NARRATIVE
 ↓
MISSIONS
 ↓
FACTIONS
 ↓
COMMERCE / LOOT
 ↓
CRAFTING / SURVIVAL
 ↓
VEHICLES
 ↓
SPAWN / TRAFFIC / WORLD STATE
 ↓
CRIME / HEAT
 ↓
PRODUCTION SAVE + UI + DEBUG
 ↓
OPTIONAL NETWORKING
```

## 36. Vertical Slice Gates

| Slice | Proves |
| --- | --- |
| Slice A - Adventure | move -> interact -> pickup -> dialogue -> mission -> save |
| Slice B - Shooter RPG | weapon -> damage -> loot -> equip -> XP/reputation -> mission |
| Slice C - Survival | gather -> craft -> consume -> needs/status -> persistence |
| Slice D - GTA sandbox | enter vehicle -> drive -> vendor -> crime -> faction/AI response -> save |
| Slice E - Full hybrid | all modules active with no direct sibling dependency violations |

## 37. Definition Authoring Examples

```
character_guard.tres
├── CharacterDefinition
├── movement = movement_human_standard.tres
├── stats = stats_guard_standard.tres
├── combat = combat_ranged_guard.tres
├── ai = ai_guard_patrol.tres
├── faction = faction_police.tres
├── loadout = loadout_guard_rifle.tres
└── tags = [&"role.guard", &"character.human"]

character_shopkeeper.tres
├── same base character scene
├── ai = ai_shopkeeper.tres
├── faction = faction_town.tres
├── vendor = vendor_general_store.tres
└── tags = [&"role.vendor"]

vehicle_sedan.tres
├── scene = sedan.tscn
├── handling = handling_sedan.tres
├── seats = [driver, front_passenger, rear_left, rear_right]
├── storage = storage_trunk_medium.tres
└── fuel = fuel_petrol_standard.tres
```

## 38. Feature Toggle / Module Availability

Avoid compile-time assumptions that every feature exists. The project configuration declares enabled modules. Adapters check availability before binding optional integrations.

```
[framework]
inventory=true
combat=true
missions=true
vehicles=true
survival=false
crime_heat=false
networking=false
```

## 39. Adapter Catalogue

| Adapter | Purpose |
| --- | --- |
| CombatFactionAdapter | damage/death -> reputation/hostility consequences |
| MissionInventoryAdapter | item events -> objective progress |
| MissionCombatAdapter | defeat events -> objective progress |
| MissionDialogueAdapter | conversation outcomes -> objective progress |
| CommerceFactionAdapter | reputation -> price modifiers |
| AIFactionAdapter | faction attitude -> target selection |
| VehicleInteractionAdapter | interaction -> seat entry/exit |
| SurvivalStatusAdapter | needs thresholds -> status effects |
| CrimeFactionAdapter | crime -> faction/wanted consequences |

## 40. What Must NOT Go Into Core

weapon logic

inventory mutation

quest progression

vendor pricing

AI decisions

vehicle physics

survival meters

dialogue execution

UI state

game-specific enums/classes

## 41. Framework Rulebook

1. Core is a control plane.  It owns contracts, discovery, settings, stable names and lifecycle. It never becomes the gameplay router.

2. Definitions are immutable.  Shared Resource definitions do not hold per-instance mutable state.

3. Scenes compose entities.  Prefer capability Nodes over deep class inheritance.

4. One owner writes each state.  Every mutable gameplay fact has a single authority.

5. Commands are explicit.  Known targets receive typed method calls.

6. Facts are broadcast.  Cross-feature outcomes use EventBus only when consumers should be unknown.

7. Signals are local first.  Use native signals for entity/UI/component observation before reaching for the global bus.

8. Autoloads are exceptional.  Only broad-lifetime services deserve global presence.

9. Sibling modules are independent.  Cross-feature integrations live in adapters or contracts, not hidden imports.

10. Every module must be removable.  Unrelated features still load and function when a sibling is disabled.

11. Resources describe content.  Ordinary new game content should not require new framework classes.

12. Profiles are reusable data atoms.  Share movement, AI, stat, combat and presentation profiles.

13. NPC roles are capabilities/data.  Vendor, guard, civilian and quest giver are not separate inheritance trees by default.

14. Player and AI share commands.  AI drives the same gameplay-facing APIs used by player controllers.

15. Vehicles use a control adapter.  Feature logic must not depend on one concrete physics implementation.

16. Inventory owns item instances.  Definitions are shared; quantity, durability and modifiers are instance state.

17. Commerce transactions are atomic.  Validate the entire operation before mutating any participant.

18. Missions observe events.  Mission logic never imports every feature whose actions can satisfy objectives.

19. Narrative conditions are pure.  Conditions query; actions mutate.

20. Faction attitude is centralized.  AI, commerce and crime consume a common relationship/reputation resolution model.

21. Presentation is not authority.  Animation, UI, audio and VFX observe gameplay state.

22. Save data is explicit.  Persist stable IDs and component state, never arbitrary SceneTree internals.

23. Schema migration is mandatory.  Persisted formats are versioned from the first production save.

24. Networking is an adapter layer.  Offline code remains clean; authoritative projects wrap mutations behind server validation.

25. No hot-loop global discovery.  Cache owned references and maintain registries for frequently accessed populations.

26. No permanent _process by default.  Components tick only when their behavior genuinely requires it.

27. Data validation is a feature.  Definitions must be scan-validatable before shipping.

28. Debugability is architecture.  Events, entity state, AI, missions and saves require runtime inspection tools.

29. No framework-specific game lore.  The addon knows faction and mission definitions, not a particular city, hero or story.

30. No abstraction without demonstrated reuse.  Do not build a mini-language where a typed method or Resource profile is enough.

31. Optional modules degrade gracefully.  Missing feature adapters are valid states, not errors.

32. Use semantic IDs, not scene paths, as gameplay identity.  Paths are implementation details; stable IDs drive persistence and references.

33. Favor deterministic domain logic.  Pricing, stat math, loot, objectives and faction calculations should be testable without a live scene.

34. Keep entity roots thin.  Root scripts orchestrate owned capabilities; they do not absorb every feature.

35. Feature APIs expose intent, not internals.  Call purchase(), equip(), apply_damage(), not private state mutation.

36. Document every dependency.  If a module requires another, that relationship is explicit in its manifest/readme and tests.

37. Vertical slices precede breadth.  Prove complete loops before adding more subsystems.

38. Profile before optimizing.  GDScript remains the default until measured bottlenecks justify specialized solutions.

39. Treat content tooling as part of the product.  Validation, inspectors, example assets and migration helpers are framework deliverables.

40. The framework should survive a genre swap.  A module must not assume the current game is an RPG, shooter, survival game or sandbox unless that is its explicit domain.

## 42. Definition of Done for a Module

Public typed API documented.

No undocumented sibling dependency.

Definition Resources validated.

Save capture/restore implemented if stateful.

Signals/events documented.

Debug inspection available.

Unit/component tests for domain logic.

Example scene/resource provided.

Performance behavior documented.

Network authority expectations documented, even if networking is disabled.

## 43. Versioning Strategy

```
Framework version: MAJOR.MINOR.PATCH
Save schema: independent integer version
Definition schema: per major definition family if needed

Breaking API:
major version

New optional feature/profile fields:
minor version

Bugfix:
patch version
```

## 44. Recommended First Production Target

Do not attempt to finish all modules before proving the architecture. The first production target should be a compact hybrid vertical slice that touches the key boundaries.

Third-person character.

One firearm and one melee action.

Inventory/equipment.

One NPC vendor.

One guard AI and one civilian AI.

Two factions with reputation.

One branching dialogue.

One mission requiring interaction, combat and purchase.

One drivable vehicle.

One survival need.

Save/load of the entire slice.

If that slice can be built without circular dependencies or game-specific hacks in Core, the architecture is healthy enough to scale.

## 45. Reference Implementation Skeleton

```
# health_component.gd
class_name HealthComponent
extends Node

signal health_changed(current: float, maximum: float)
signal died(context: DamageContext)

@export var maximum_health: float = 100.0
var current_health: float

func _ready() -> void:
    current_health = maximum_health

func apply_damage(context: DamageContext) -> void:
    if context.amount <= 0.0 or current_health <= 0.0:
        return

    var final_amount := context.amount
    current_health = maxf(0.0, current_health - final_amount)
    health_changed.emit(current_health, maximum_health)

    if is_zero_approx(current_health):
        died.emit(context)
        EventBus.actor_died.emit(ActorDiedEvent.new(owner, context))


# inventory_component.gd
class_name InventoryComponent
extends Node

signal item_added(item: ItemInstance)
signal item_removed(item: ItemInstance)

var items: Array[ItemInstance] = []

func add_item(item: ItemInstance) -> bool:
    # Validate capacity / stacking here.
    items.append(item)
    item_added.emit(item)
    EventBus.item_added.emit(ItemEvent.new(owner, item))
    return true
```

## 46. Final System Map

```
                               GAME CONTENT
                                   │
                                   ▼
                              DEFINITIONS
                                   │
      ┌───────────┬───────────────┼───────────────┬───────────────┐
      ▼           ▼               ▼               ▼               ▼
 CHARACTERS     ITEMS          VEHICLES         MISSIONS        WORLD
      │           │               │               │               │
      └────────── CAPABILITY NODES / RUNTIME ENTITIES ────────────┘
                                   │
       ┌─────────────┬─────────────┼─────────────┬──────────────┐
       ▼             ▼             ▼             ▼              ▼
     COMBAT       INVENTORY     INTERACTION    FACTIONS       VEHICLES
       │             │             │             │              │
       └─────────────┴────── CROSS-FEATURE EVENT BUS ───────────┘
                                   │
                         NARRATIVE / MISSIONS
                                   │
                       COMMERCE / SURVIVAL / AI
                                   │
                           WORLD SIMULATION
                                   │
                              SAVE SERVICE
                                   │
                              FRAMEWORK CORE

Local observation: signals
Known commands: typed calls
Runtime classification: groups
Data semantics: StringName IDs/tags
Presentation: AnimationTree / UI / Audio / VFX
Optional authority: multiplayer adapter
```

## 47. Implementation Summary

Build the platform from the inside out: Core contracts, entity composition, common character state, items/inventory, interaction and combat first. Then layer AI, narrative, missions, factions and commerce. Survival and vehicles come after the common gameplay grammar is proven. Only then add world-population systems, crime/heat, full persistence tooling and optional networking. The framework's quality should be measured less by how many systems it contains and more by whether those systems can be enabled, disabled, combined and extended without rewriting one another.

## 48. Godot 4.7 Technical Basis

The design assumes Godot 4.7's Node/SceneTree model, typed GDScript, custom Resources and PackedScenes, signals and Groups, InputMap, AnimationTree, NavigationAgent3D/navigation APIs, FileAccess-based persistence options, and optional high-level MultiplayerAPI. The framework wraps these engine facilities behind domain contracts where replacement or specialization may be useful.
