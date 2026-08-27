# Reusable Godot 4.7 Framework

GDScript Ontology • System Layers • Architecture Tree • Rulebook

A scalable, data-driven, scene-composed architecture for characters, NPCs, AI, vehicles, vendors, inventory, combat, missions, save systems, UI, and game-specific content.

## 1. Architectural North Star

Godot should remain Godot-shaped. The framework uses scenes and Nodes for composition, custom Resources for definitions and profiles, signals for local decoupling, a small Event Bus only for true cross-feature facts, groups for lightweight runtime classification, and Autoloads only for broad-scoped persistent services. The Core coordinates contracts and lifecycle; it does not become a god object.

```
CORE = contracts + registry + configuration
DEFINITIONS = what something is
SCENES = reusable entity composition
COMPONENT NODES = what an entity can do
SYSTEMS = feature/domain logic
SERVICES = broad-scoped persistent coordination
SIGNALS = local events
EVENT BUS = cross-feature facts
GROUPS / STRINGNAMES = lightweight semantic vocabulary
PRESENTATION = animation / camera / UI / audio / VFX
```

## 2. Complete Ontology Tree

```
Framework
├── Core
│   ├── Framework Core Autoload (small)
│   ├── Module / Service Registry
│   ├── Framework Settings Resource
│   ├── Shared StringName constants
│   ├── Event payload classes / Resources
│   ├── Shared result/context types
│   └── Definition registry / loader
│
├── Definitions  [custom Resource types]
│   ├── CharacterDefinition
│   │   ├── Identity
│   │   ├── AppearanceProfile
│   │   ├── MovementProfile
│   │   ├── AnimationProfile
│   │   ├── StatsProfile
│   │   ├── CombatProfile
│   │   ├── StartingLoadout
│   │   ├── AIProfile (optional)
│   │   ├── FactionDefinition
│   │   └── semantic tags
│   ├── AIDefinition / AIProfile
│   │   ├── Behavior profile
│   │   ├── Perception profile
│   │   ├── Navigation profile
│   │   ├── Combat behavior
│   │   └── awareness rules
│   ├── VehicleDefinition
│   │   ├── PackedScene
│   │   ├── HandlingProfile
│   │   ├── PhysicsProfile
│   │   ├── SeatDefinitions
│   │   ├── StorageProfile
│   │   ├── DamageProfile
│   │   ├── CameraProfile
│   │   └── PresentationProfile
│   ├── ItemDefinition
│   │   ├── Presentation
│   │   ├── Inventory data
│   │   ├── Equippable data
│   │   ├── Weapon data
│   │   ├── Consumable data
│   │   ├── Durability data
│   │   └── Crafting data
│   ├── VendorDefinition
│   ├── EconomyDefinition
│   ├── FactionDefinition
│   ├── InteractionDefinition
│   ├── MissionDefinition
│   ├── ObjectiveDefinition
│   ├── DialogueDefinition
│   ├── LootDefinition
│   ├── RecipeDefinition
│   ├── WorldObjectDefinition
│   └── Spawn / EncounterDefinition
│
├── Entity Scenes
│   ├── Character
│   ├── Vehicle
│   ├── WorldObject
│   ├── Pickup / ItemWorldActor
│   └── Interaction object
│
├── Capability Nodes
│   ├── HealthComponent
│   ├── StatsComponent
│   ├── InventoryComponent
│   ├── EquipmentComponent
│   ├── InteractionComponent
│   ├── VendorComponent
│   ├── DialogueComponent
│   ├── FactionComponent
│   ├── LootComponent
│   ├── DamageReceiverComponent
│   ├── StatusComponent
│   ├── SeatComponent
│   └── SaveIdentityComponent
│
├── Feature Modules
│   ├── Character
│   ├── Locomotion
│   ├── AI
│   ├── Combat
│   ├── Inventory
│   ├── Equipment
│   ├── Interaction
│   ├── Commerce
│   ├── Vehicles
│   ├── Dialogue
│   ├── Missions / Objectives
│   ├── Crafting
│   ├── Factions
│   ├── Save / Persistence
│   └── UI
│
├── Services  [Autoload only when scope warrants it]
│   ├── SaveService
│   ├── SceneFlowService
│   ├── WorldStateService
│   ├── SpawnService
│   ├── ObjectiveService
│   └── EventBus
│
├── Communication
│   ├── Signals = local / parent-child / direct observers
│   ├── EventBus = cross-feature facts
│   ├── Callable = explicit injected behavior
│   ├── Groups = runtime classification / discovery
│   └── typed methods = targeted commands
│
└── Presentation
    ├── AnimationTree / AnimationPlayer
    ├── locomotion controller
    ├── Camera
    ├── UI
    ├── Audio
    └── VFX
```

## 3. The Godot Translation

| Architecture concept | Godot 4.7 tool | Purpose |
| --- | --- | --- |
| Data Asset / Definition | Custom Resource | Immutable content/config |
| Actor Component | Child Node with class_name | Reusable stateful capability |
| Prefab / entity assembly | PackedScene / scene inheritance/composition | Reusable entity structure |
| Local delegate | Signal | Local decoupled notification |
| Cross-module message | EventBus Autoload signal/API | Cross-feature facts |
| Gameplay Tag | StringName constants + Groups where runtime discovery is needed | Semantic vocabulary |
| Subsystem / service | Autoload Node only for broad scope | Persistent service |
| Interface | Duck typing / typed base class / capability Node lookup | Polymorphic contract |
| Soft asset reference | Resource/PackedScene path or loaded resource strategy | Asset indirection |

## 4. System Layers

| Layer | Question | Primary Godot mechanism | Examples |
| --- | --- | --- | --- |
| 0. Core | What may every feature know? | small Autoload + shared scripts/resources | contracts, names, registry |
| 1. Definition | What is it? | Resource | character, item, vehicle, vendor |
| 2. Scene Composition | What exists and how is it assembled? | PackedScene / Nodes | character scene, vehicle scene |
| 3. Capability | What can this entity do? | child Node | health, inventory, vendor |
| 4. Feature | How does the domain work? | feature folder/addon + scripts/scenes/resources | combat, commerce, AI |
| 5. Service | What must persist across scenes? | Autoload when justified | save, scene flow, world state |
| 6. Communication | How do independent systems communicate? | signals / event bus / groups | death, purchase, item added |
| 7. Presentation | How does gameplay look/sound? | AnimationTree/UI/audio/VFX | locomotion, HUD, effects |
| 8. Game Content | What belongs only to this game? | project scenes/resources | named NPCs, missions, enemies |

## 5. Definitions and Profiles

Use typed custom Resources as the primary data-definition layer. A Resource describes design-time identity and configuration. Runtime mutable state belongs in Nodes or explicit runtime state objects, never in a shared definition Resource.

```
# character_definition.gd
class_name CharacterDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var scene: PackedScene
@export var appearance: AppearanceProfile
@export var movement: MovementProfile
@export var stats: StatsProfile
@export var combat: CombatProfile
@export var ai: AIProfile
@export var faction: FactionDefinition
@export var tags: Array[StringName]
```

Use smaller Profile Resources to prevent giant definition files and to allow reuse. One HumanMovementProfile can be shared by many civilians, guards, vendors and companions.

## 6. Character / NPC Ontology

```
Character.tscn
CharacterBody3D
├── CharacterDefinitionBinder
├── MovementComponent
├── HealthComponent
├── StatsComponent
├── InventoryComponent
├── EquipmentComponent
├── InteractionComponent
├── FactionComponent
├── AnimationComponent
└── optional AIControllerComponent
```

NPC, enemy, companion, civilian and vendor are usually configurations of the same character foundation. Do not create a new inheritance branch simply because the character has a different role.

```
DA-like Resource: char_blacksmith.tres
CharacterDefinition
├── tags = [&"character.npc", &"role.vendor", &"role.blacksmith"]
├── vendor profile = vendor_blacksmith.tres
├── AI profile = ai_shopkeeper.tres
└── faction = faction_town.tres
```

## 7. AI Architecture

AI is a control/decision layer acting on an entity. Keep sensing, decision making and movement requests outside the character's core identity.

```
Character
   │
AIControllerComponent
├── PerceptionComponent
├── DecisionBrain
│   ├── State Machine / State Chart
│   ├── Behavior Tree addon if chosen
│   └── Utility scoring if chosen
├── NavigationAgent3D
└── Combat/Interaction commands

AIProfile Resource
├── perception values
├── decision profile
├── navigation settings
├── aggression / awareness
└── semantic tags
```

The framework should not dictate one AI algorithm. Define an AIProfile contract and allow multiple brain implementations behind it.

## 8. Vehicle Architecture

```
VehicleDefinition Resource
├── id
├── packed_scene
├── handling_profile
├── physics_profile
├── seat_definitions
├── storage_profile
├── damage_profile
├── camera_profile
└── presentation_profile

Vehicle Scene
VehicleBody / CharacterBody / custom body
├── VehicleController
├── SeatComponent
├── HealthComponent
├── StorageComponent
├── InteractionComponent
└── EquipmentComponent
```

Cars, boats and aircraft can use different runtime scene roots while sharing common definition and capability contracts.

## 9. Item / Inventory Architecture

```
ItemDefinition Resource
├── id
├── display data
├── category
├── tags
├── world_scene
├── stack rules
├── equipment profile (optional)
├── weapon profile (optional)
├── consumable profile (optional)
└── crafting profile (optional)

ItemInstance
├── definition
├── quantity
├── durability
├── modifiers
└── unique runtime state
```

Separate ItemDefinition from ItemInstance. Hundreds of inventory entries may point to the same immutable definition while retaining independent mutable state.

## 10. Vendor / Commerce Architecture

```
NPC / Terminal / Vending Machine / Vehicle
                  │
            VendorComponent
                  │
            VendorDefinition
                  │
             CommerceService
        ┌─────────┼─────────┐
        ↓         ↓         ↓
      Validate   Price    Transact
        │                   │
        └──── EventBus ─────┘
             purchased
             sold
             restocked
```

Vendor is a capability, not an entity class. Commerce is the feature domain. VendorDefinition is data. This allows the same commerce code to serve people, kiosks, vending machines and remote terminals.

## 11. Messaging Model

Use direct typed calls for commands, local signals for nearby observers, and a deliberately small global EventBus for cross-feature facts. Do not route every interaction through the EventBus.

```
TARGETED COMMAND
door.open()
inventory.add_item(item)

LOCAL EVENT
health_component.health_changed.emit(current, maximum)

CROSS-FEATURE FACT
EventBus.actor_died.emit(event)
EventBus.item_purchased.emit(event)
```

```
# event_bus.gd
extends Node

signal actor_died(event: ActorDiedEvent)
signal item_added(event: ItemAddedEvent)
signal item_purchased(event: CommerceEvent)
signal objective_completed(event: ObjectiveEvent)
```

## 12. Groups and Semantic Vocabulary

Godot Groups are excellent for runtime classification, discovery and fan-out calls. Use them where membership in the SceneTree matters. For pure data semantics, prefer typed StringName constants or arrays on Resources rather than forcing every tag through Groups.

```
# gameplay_names.gd
class_name GameplayNames

const STATE_DEAD := &"state.dead"
const STATE_SPRINTING := &"state.movement.sprinting"
const FACTION_ROBOTS := &"faction.robots"
const ROLE_VENDOR := &"role.vendor"
const EVENT_ACTOR_DIED := &"event.actor.died"

# SceneTree discovery
add_to_group(&"interactable")
add_to_group(&"damageable")
```

## 13. Interaction Architecture

```
InteractorComponent
       │
       ├── ray/area query
       ▼
InteractionComponent on target
       │
InteractionDefinition Resource
├── prompt
├── duration
├── requirements
└── action strategy
       │
       ▼
targeted command executes
       │
       ▼
signal / EventBus fact
```

A door, NPC, vehicle, terminal, pickup and crafting station can all expose the same interaction capability without sharing an entity superclass.

## 14. Missions / Objectives

```
MissionDefinition
├── ObjectiveDefinition[]
├── sequencing rules
├── completion rules
└── rewards

Objective runtime state
       │
       └── subscribes to relevant EventBus facts:
           actor_died
           item_added
           interaction_completed
           area_entered
           purchase_completed
```

The mission system should not depend directly on combat, inventory, commerce or interaction. It observes facts emitted by those features.

## 15. Save / Persistence Model

Persist stable IDs plus mutable state. Rebuild scenes from definitions and then apply saved state.

```
SavedEntity
├── persistent_id
├── definition_id
├── transform
├── component_state
│   ├── health
│   ├── inventory
│   ├── equipment
│   └── status
└── domain-specific state

Load:
definition_id
   ↓
DefinitionRegistry
   ↓
PackedScene.instantiate()
   ↓
bind definition
   ↓
apply saved state
```

## 16. UI Architecture

UI is an observer. Widgets should bind to presentation models or component signals rather than reaching deep into the SceneTree to discover gameplay state.

```
Gameplay Component
      │
    signal
      ▼
Presenter / ViewModel Node
      │
      ▼
Control Scene
```

## 17. Recommended Project / Addon Tree

```
res://
├── addons/
│   └── framework/
│       ├── core/
│       │   ├── framework_core.gd
│       │   ├── event_bus.gd
│       │   ├── gameplay_names.gd
│       │   ├── framework_settings.gd
│       │   └── registry/
│       │
│       ├── definitions/
│       ├── character/
│       ├── locomotion/
│       ├── ai/
│       ├── interaction/
│       ├── inventory/
│       ├── equipment/
│       ├── combat/
│       ├── vehicles/
│       ├── commerce/
│       ├── dialogue/
│       ├── objectives/
│       ├── crafting/
│       ├── factions/
│       ├── save/
│       └── ui/
│
└── game/
    ├── definitions/
    ├── characters/
    ├── vehicles/
    ├── items/
    ├── missions/
    ├── world/
    └── ui/
```

## 18. Core Manager Design

A central Core is useful, but it must remain a control plane rather than a gameplay switchboard. It may register services, expose configuration, perform startup/shutdown, and provide definition lookup. Features communicate with one another through contracts, signals and events instead of Core routing.

```
FrameworkCore (Autoload)
├── settings
├── service registry
├── definition registry
├── feature availability
└── lifecycle hooks

NOT:
├── damage()
├── buy_item()
├── complete_quest()
├── reload_weapon()
└── open_door()
```

## 19. Autoload Policy

Autoloads are powerful but contagious. Use them only when a system genuinely must survive scene changes or be reachable across unrelated scene branches.

| Candidate | Default | Reason |
| --- | --- | --- |
| FrameworkCore | Yes, small | Framework lifecycle and registries |
| EventBus | Yes | Cross-feature facts |
| SaveService | Usually | Persists across scene changes |
| SceneFlowService | Usually | Owns global transitions |
| WorldStateService | Sometimes | Only if state spans scenes |
| Health | No | Entity-local |
| Inventory | Usually no | Entity-local; save service may serialize it |
| Combat | No | Feature/entity-local |
| Audio | Prefer scene-local first | Use global only for genuinely global playback |
| Vendor | No | Capability Node |

## 20. Dependency Law

```
GOOD

Combat ────────┐
Inventory ─────┤
Commerce ──────┼──> Core contracts
Objectives ────┤
Vehicles ──────┘

Combat → EventBus(actor_died) → Objectives


BAD

Combat → Inventory → Objectives → Interaction → Combat
```

## 21. GDScript Type Policy

Use typed GDScript for framework APIs. Dynamic typing remains useful at narrow boundaries, but core contracts should be statically typed to improve editor completion, refactoring safety and error detection.

```
class_name HealthComponent
extends Node

signal health_changed(current: float, maximum: float)
signal died(context: DamageContext)

@export var maximum_health: float = 100.0
var current_health: float

func apply_damage(amount: float, context: DamageContext) -> void:
    if amount <= 0.0:
        return
    current_health = maxf(0.0, current_health - amount)
    health_changed.emit(current_health, maximum_health)
    if is_zero_approx(current_health):
        died.emit(context)
```

## 22. Framework Rulebook

1. Core is infrastructure only.  Core owns lifecycle, configuration, registries and stable contracts. It does not contain feature gameplay.

2. Godot composition comes first.  Build entities from scenes and child Nodes before introducing deep inheritance.

3. Resources define; Nodes execute.  Immutable content/configuration lives in Resources. Runtime behavior and mutable state live in Nodes or runtime objects.

4. One authoritative owner per state.  Health, inventory, movement state and other mutable facts have exactly one writer/owner.

5. NPC is a configuration, not a hierarchy.  Enemy, civilian, companion, vendor and quest giver are usually roles/capabilities on a shared character foundation.

6. Vendor is a capability.  VendorComponent + VendorDefinition + Commerce system can serve any suitable entity.

7. Signals are the default local event mechanism.  Use them for parent-child, sibling via composition, UI observation and entity-local state changes.

8. EventBus is for cross-feature facts only.  Use it when producer and consumers genuinely should not know one another.

9. Commands stay targeted.  A request to open, equip, buy or interact should call a known target/capability rather than broadcast globally.

10. Groups are runtime classifications, not a universal type system.  Use Groups for SceneTree membership/discovery. Use StringName semantics in data where tree membership is irrelevant.

11. Autoloads are rare.  A system must justify global lifetime or broad scope before becoming an Autoload.

12. No universal manager.  FrameworkCore coordinates lifecycle and discovery, not gameplay execution.

13. Feature folders are removable.  Deleting Commerce should not make Combat fail to load. Sibling coupling is a design warning.

14. Profiles prevent giant Resources.  Movement, AI, stats, combat and presentation settings should be reusable sub-resources.

15. Data defines content; GDScript defines mechanisms.  Adding ordinary characters/items/vehicles/vendors should mostly create .tres/.res/.tscn content.

16. ItemDefinition and ItemInstance are separate.  Shared immutable item data must not contain per-stack or per-instance mutable state.

17. AI is a controller layer.  Decision logic acts on the same entity/capability APIs used by players or scripts.

18. Presentation observes authority.  Animation, UI, audio and VFX must not become authoritative gameplay-state owners.

19. Scene roots should remain thin.  A CharacterBody3D or Vehicle root coordinates components rather than accumulating every system in one script.

20. Prefer dependency injection by node references/resources.  Export typed references or bind dependencies at composition time rather than repeatedly searching the tree.

21. Avoid get_node() archaeology.  Do not encode fragile ../../../../ paths across scene boundaries; use owned child references, unique nodes, exports, or explicit binding.

22. Avoid get_tree().get_first_node_in_group() as service location by default.  Groups are discovery tools, not a replacement for explicit ownership.

23. No abstraction without reuse.  Do not build a generic action language until multiple real systems need that composition.

24. Atomic actions are optional.  Use small data-driven action/condition objects only where designer composition produces real value.

25. Save IDs and state, not scene graphs.  Reconstruct from definition + PackedScene and reapply mutable state.

26. Game-specific content stays outside the addon.  The reusable framework knows CharacterDefinition, not a named hero, island or mission.

27. Typed GDScript is the framework default.  Public APIs, signals, exported Resources and major state should use explicit types.

28. Static utility functions beat global managers for stateless helpers.  Use class_name + static func where no persistent state is needed.

29. Measure before optimizing architecture.  Keep signals, Resources and Nodes simple until profiling identifies a real performance problem.

30. The SceneTree is part of the architecture.  Ownership, lifetime and process mode should be intentionally represented by where Nodes live.

## 23. Decision Guide

| Question | Use |
| --- | --- |
| Does this describe what something is? | Custom Resource definition |
| Is it reusable configuration shared by definitions? | Profile Resource |
| Is it reusable stateful behavior attached to an entity? | Component Node |
| Is it a reusable assembled entity? | PackedScene |
| Is mutable state local to one entity? | Node / runtime object |
| Did local state change? | Signal |
| Did a cross-feature fact occur? | EventBus signal/event |
| Must I command a known capability? | Typed method call |
| Do I need runtime discovery/classification? | Group |
| Do I need semantic identity in data? | StringName constant / array |
| Must it survive scene changes and has broad scope? | Autoload |
| Is it a stateless helper? | class_name + static func |
| Is it purely presentation? | Animation/UI/Audio/VFX layer |
| Is it specific to one game? | game/ content layer |

## 24. Naming Guide

```
Scripts / classes
CharacterDefinition
VehicleDefinition
VendorDefinition
HealthComponent
InventoryComponent
CommerceService
FrameworkCore

Files
character_definition.gd
health_component.gd
vendor_definition.gd
framework_core.gd

Resources
character_marine.tres
vehicle_jeep.tres
vendor_blacksmith.tres
ai_guard.tres

Scenes
character.tscn
vehicle_car.tscn
world_object.tscn

Groups
interactable
damageable
saveable

Semantic StringNames
state.dead
state.movement.sprinting
event.actor.died
event.commerce.purchased
faction.robots
role.vendor
```

## 25. Final Reference Architecture

```
                         GAME-SPECIFIC CONTENT
                                  │
                                  ▼
                              RESOURCES
                            DEFINITIONS
                                  │
          ┌───────────────────────┼───────────────────────┐
          ▼                       ▼                       ▼
      CHARACTERS               VEHICLES              WORLD OBJECTS
       PackedScene              PackedScene             PackedScene
          │                       │                       │
          └────────────── CAPABILITY NODES ──────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
                 COMBAT       INTERACTION    INVENTORY
                                  │
                              COMMERCE
                    │             │             │
                    └────── CROSS-FEATURE ──────┘
                              EVENT BUS
                                  │
                           FRAMEWORK CORE
                     registry / config / contracts
                                  │
                  ┌───────────────┼───────────────┐
                  ▼               ▼               ▼
                SAVE             AI           OBJECTIVES
                                  │
                         movement commands
                                  │
                         CharacterBody3D
                                  │
                       AnimationTree / visuals

Local communication: Signals
Runtime discovery: Groups
Semantic data vocabulary: StringName
Global lifetime: rare Autoload services
```

## 26. The Short Version

Make Godot scenes the composition boundary. Use typed Resource definitions and reusable Profile Resources for data. Attach stateful capabilities as child Nodes. Use direct calls for commands, signals for local changes, and a small EventBus for cross-feature facts. Use Groups for runtime discovery and StringName constants for semantic data vocabulary. Keep Autoloads scarce and broad-scoped. Keep FrameworkCore tiny, every feature removable, and game-specific content outside the reusable addon.

## 27. Godot 4.7 Basis

This architecture is designed around Godot 4.7's native scene/Node model, custom Resources, typed GDScript, signals, Groups, PackedScenes and Autoload behavior. It intentionally favors Godot's scene-tree composition model over importing manager-heavy patterns from other engines.
