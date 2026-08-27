# Universal Gameplay Framework

A reusable, data-driven gameplay platform for **Godot 4.7**, built to support action RPG,
shooter, open-world sandbox, driving, survival, faction simulation, commerce and narrative
adventure games from one foundation — without any of those genres being baked into it.

Godot-native throughout: scenes compose entities, typed `Resource` definitions carry content,
signals handle local communication, and a narrow event bus carries cross-feature facts.

---

## Status: M0 – M18 complete ✅

M0 locks the architecture before any gameplay system is written. M1 builds the universal
runtime entity on top of it. M2 makes that entity a playable character. M3 gives it numbers
that other systems change, and a way to die. M4 gives it things to carry and wear. M5 gives
it a way to use the world. M6 gives it a way to fight. M7 lets it do all of that
without a player. M8 gives the world something to say and somewhere to remember
it. M9 gives the player a reason to do any of it. M10 gives the world sides to take. M11 gives it
an economy. M12 lets it be lived in. M13 gives it something to drive. M14 fills it with
people without making it slow. M15 gives it a law. M16 makes all of it
survive being switched off. M17 lets you see any of it. M18 lets a server
decide it. All nineteen are green.

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

### M6 — Combat + Weapons ✅

| M6 deliverable | Where |
| --- | --- |
| Hitscan / projectile | `combat/hitscan_delivery.gd`, `projectile_delivery.gd`, `projectile.gd` |
| Ammo / reload | `combat/ammo_profile.gd`, `weapon_component.gd` |
| Recoil / spread | `combat/recoil_profile.gd`, `combat_solver.gd` |
| Melee action windows | `combat/attack_definition.gd`, `melee_delivery.gd` |
| Targeting hooks | `CombatComponent.aim_at`, `set_hit_provider` |

**M6 exit gate:**

- *Ranged and melee share DamageContext* —
  `test_combat_component.gd::test_both_produce_the_same_damage_context`
- *AI and player use the same command API* —
  `test_combat_component.gd::test_an_npc_attacks_through_the_same_call_a_player_does`

### M7 — AI + NPC Roles ✅

| M7 deliverable | Where |
| --- | --- |
| AIControllerComponent | `ai/ai_controller_component.gd` |
| Perception | `ai/perception_component.gd`, `perception_profile.gd`, `perceivable.gd` |
| Memory | `ai/ai_memory.gd`, `memory_entry.gd` |
| BrainAdapter | `ai/ai_brain.gd`, `role_brain.gd` |
| NavigationAgent3D integration | `ai/navigation_adapter.gd` |
| Vendor / guard / civilian role profiles | `ai/npc_role_definition.gd` |

**M7 exit gate:**

- *Civilian, guard and combatant built from the same character base* —
  `test_npc_roles.gd::test_all_three_roles_are_the_same_composition` and
  `::test_and_do_three_different_things_about_it`

### M8 — Dialogue + Narrative State ✅

| M8 deliverable | Where |
| --- | --- |
| DialogueDefinition / runtime | `dialogue/dialogue_definition.gd`, `dialogue_runtime.gd` |
| Conditions | `dialogue/dialogue_condition.gd`, `narrative_condition.gd`, `item_condition.gd` |
| Actions | `dialogue/dialogue_action.gd`, `narrative_action.gd` |
| NarrativeStateService | `narrative/narrative_state_service.gd` |
| UI presenter | *the runtime presents nothing — see below* |

**M8 exit gate:**

- *Branching conversation, persistent flags, events emitted for choices* —
  `test_dialogue_component.gd::test_a_branching_conversation_with_persistent_flags_and_events`

### M9 — Missions + Objectives ✅

| M9 deliverable | Where |
| --- | --- |
| MissionDefinition | `missions/mission_definition.gd` |
| ObjectiveDefinition | `missions/objective_definition.gd`, `event_matcher.gd` |
| Runtime state | `missions/mission_runtime.gd`, `objective_runtime.gd`, `mission_service.gd` |
| Reward hooks | `missions/mission_reward.gd`, `narrative_reward.gd`, `item_reward.gd` |
| Failure hooks | `ObjectiveDefinition.failure_event_name` |

**M9 exit gate:**

- *Mission reacts to combat, inventory and dialogue without importing them* —
  `test_mission_service.gd::test_a_mission_reacts_to_combat_inventory_and_dialogue_without_importing_them`

### M10 — Factions + Reputation ✅

| M10 deliverable | Where |
| --- | --- |
| FactionDefinition | `factions/faction_definition.gd` |
| FactionService | `factions/faction_service.gd` |
| Reputation | `FactionService.get_reputation`, `propagate_reputation` |
| Attitude resolver | `factions/attitude_solver.gd` |
| Faction events | `factions/faction_event_adapter.gd` |

**M10 exit gate:**

- *AI hostility consumes faction results via an adapter* —
  `test_faction_adapters.gd::test_a_guard_charges_a_bandit_and_ignores_a_merchant`
- *Vendor pricing consumes faction results via an adapter* —
  `test_faction_adapters.gd::test_a_liked_customer_is_charged_less`

### M11 — Commerce + Vendors + Loot ✅

| M11 deliverable | Where |
| --- | --- |
| Wallet / currencies | `commerce/wallet_component.gd`, `currency_definition.gd` |
| VendorDefinition | `commerce/vendor_definition.gd`, `vendor_component.gd` |
| CommerceService | `commerce/commerce_service.gd` |
| Pricing / stock policies | `commerce/standard_pricing_policy.gd`, `stock_entry.gd` |
| Loot tables | `loot/loot_table_definition.gd`, `loot_entry.gd`, `loot_component.gd` |

**M11 exit gate:**

- *Atomic purchase and sale* —
  `test_commerce_service.gd::test_a_purchase_the_bag_cannot_hold_changes_nothing`
- *Restock* — `test_commerce_service.gd::test_a_shelf_refills_on_its_interval`
- *Reputation pricing adapter* —
  `test_commerce_service.gd::test_a_liked_customer_pays_less_and_is_paid_more`

Every trade is validate-then-mutate with no step in between that can fail: currency, stock,
capacity and restrictions are all checked first, and only once every one has passed does
anything change. A purchase that took the money and then found the bag full is the bug this
shape exists to make impossible, and there is a test for exactly it.

The gate is met by AI declaring the question and Factions answering it. `HostilityProvider`
lives in `ai/` and defaults to "everything is an enemy"; `FactionHostilityProvider` lives in
`factions/` and answers from standing; `FactionAIAdapter` hands one to the other. No file in
`ai/` mentions a faction and no file in `factions/` mentions a brain.

Pricing is the same shape, one milestone early: Commerce is M11, but what a pricing policy
needs from Factions is a single multiplier, and `FactionPriceAdapter` produces and tests it
now rather than waiting to be written twice.

One `ObjectiveDefinition` covers the fourteen baseline kinds Implementation Plan 19 lists,
because they differ in which bus event they count and what they require of it — and both
are data. A kill objective is `actor_died` with a matcher on the instigator; an acquire
objective is `item_acquired` with a matcher on the item id. The cost is that field names
are strings, so a typo is content that silently never matches rather than a compile error;
`EventMatcher` says so in its own doc comment.

M9 also added the three publishers that gave missions something to hear: an inventory
adapter, a narrative adapter and an area trigger. Each is deletable, and each is what keeps
its own module from learning what a mission is.

The plan lists a UI presenter as an M8 deliverable and this milestone ships none, on
purpose. `DialogueRuntime` says which line is current and which options are open, and
emits a signal when either changes; drawing them is a project's decision about its own
look. Shipping a Control here would be the framework owning presentation, which rule 21
forbids — and the first thing every project would delete. M17 is where UI framework
patterns belong.

Enabling the addon binds the framework's semantic actions to WASD, space, shift, ctrl, E and
the usual gamepad equivalents, for any action the project has not already defined. It never
overwrites: rebind `jump` and it stays rebound through every future version of the addon.
Without this the addon produces a character that compiles, spawns, validates and cannot move —
and an unbound action is indistinguishable from an unpressed one at runtime.

### M12 — Crafting + Survival + Gathering ✅

| M12 deliverable | Where |
| --- | --- |
| Needs / meters | `survival/need_definition.gd`, `needs_component.gd` |
| Temperature hooks | `survival/need_definition.gd` (`drains_towards`), `environment_zone.gd` |
| Consumables | `survival/consumable_profile.gd`, `consumer_component.gd` |
| RecipeDefinition | `crafting/recipe_definition.gd`, `recipe_ingredient.gd` |
| Crafting stations / queue | `crafting/crafting_station.gd`, `crafting_component.gd` |
| Resource nodes | `gathering/resource_node_definition.gd`, `resource_node.gd` |
| Durability degradation | `crafting/recipe_ingredient.gd`, `gathering/resource_node.gd` |

**M12 exit gate:**

- *Gather → craft → consume* — `test_survival_loop.gd::test_gather_craft_consume`
- *Needs save/load* — `test_survival_loop.gd::test_a_reloaded_survivor_is_still_hungry`
- *Every stage refuses without half-running* —
  `test_survival_loop.gd::test_the_loop_stalls_at_each_missing_step_rather_than_half_running`
- *Survival is deletable* —
  `test_survival_loop.gd::test_gathering_and_crafting_work_with_no_needs_at_all`

```
70 suite(s), 1684 test(s), 1684 passed, 0 failed, 4089 assertions
RESULT: PASS
```

**Hunger, thirst, fatigue, oxygen and body temperature are one class.** They differ in their
numbers and in which states they set, not in code. Temperature is the interesting case — it
drains towards a comfortable middle rather than towards empty — and that is a
`drains_towards` field, not a second mechanism. A cold zone is the same shape: it does not
drain warmth, it multiplies how fast warmth drains, which is what lets two zones overlap and
compose and what makes walking out of a cave restore exactly what walking in changed. A zone
that drained directly would leave drift behind every round trip.

**A tool is an ingredient that is not consumed.** Modelling it as a flag on `RecipeIngredient`
rather than a second list beside `ingredients` is what lets a recipe say "two planks and a
hammer" in one array, and what makes tool wear a property of the ingredient rather than a
special case next to it. A broken axe is not an axe, in crafting and in gathering both —
otherwise durability is decorative.

Ingredients are consumed when a timed craft *starts*, not when it finishes. Cancelling a smelt
does not un-melt the ore, and consuming up front is also what stops the same planks being spent
on two benches at once. Room for the output is checked before anything is taken, which is the
purchase-that-took-the-money bug from M11 wearing different clothes.

Resource nodes yield through M11's `LootTableDefinition` rather than a yield list of their own.
"A weighted table of items with guaranteed entries" is one idea, and two implementations of it
would drift apart (rule 23). The roll takes an injected `RandomNumberGenerator`, so a test gets
the same drop twice and a networked game can share the stream.

`HarvestAction` is an `InteractionAction`, so a tree is chopped through exactly the pipeline a
door is opened with and a timed harvest is an interaction *duration* rather than a second timer
beside it. It lives in `gathering/` rather than `interaction/`, which is the direction that
keeps both deletable.

M12 also added `test_module_manifests.gd`, which sweeps every `*_module.gd` in the addon and
checks that each dependency it declares names a module that actually ships. Twenty-four modules
naming each other in `StringName` literals is a graph that rots quietly: a module can require
`module.narrativee` and nothing complains — the registry simply never resolves it and the
feature goes missing in a way that reads like a content bug. Verified by deliberately adding a
bogus dependency and watching the suite name it.

### M13 — Vehicles ✅

| M13 deliverable | Where |
| --- | --- |
| VehicleDefinition | `vehicles/vehicle_definition.gd`, `handling_profile.gd` |
| Controller adapter | `vehicles/vehicle_controller_adapter.gd`, `vehicle_body_adapter.gd` |
| Seats | `vehicles/seat_definition.gd`, `seat_component.gd` |
| Enter / exit | `vehicles/enter_vehicle_action.gd` |
| Fuel | `vehicles/fuel_component.gd` |
| Damage | `health_damage/` — reused unchanged |
| Storage | `inventory/` — reused unchanged |
| Camera contexts | `camera/camera_profile.gd`, `input/input_contexts.gd` |
| Driving maths | `vehicles/vehicle_solver.gd` |
| Shipped scene | `vehicles/vehicle.tscn` |

**M13 exit gate:**

- *Player and AI drive through the same adapter* —
  `test_vehicle_possession.gd::test_a_player_and_an_ai_reach_the_same_adapter`
- *An AI drives somewhere* —
  `test_vehicle_possession.gd::test_an_ai_drives_a_vehicle_to_a_destination`
- *Vehicle persists* — `test_vehicle_component.gd::test_a_vehicle_survives_a_save`,
  `test_seat_component.gd::test_a_restored_occupant_is_put_back_in_their_own_seat`
- *Possession does not leak input contexts* —
  `test_vehicle_possession.gd::test_the_context_stack_does_not_grow_across_a_round_trip`

```
75 suite(s), 1835 test(s), 1835 passed, 0 failed, 4531 assertions
RESULT: PASS
```

**`VehicleControllerAdapter` is the whole milestone.** Implementation Plan 22 requires that the
framework own identity, seats, fuel, damage, storage, upgrades, cameras and possession while the
concrete motion implementation stays replaceable — so six calls (`set_throttle`, `set_brake`,
`set_steering`, `set_handbrake`, `get_speed`, `get_motion_state`) are the entire surface between
them. The base class is not abstract: it integrates the handling profile and moves nothing, which
is a complete and honest implementation for a headless server, a replay and a test.
`VehicleBodyAdapter` is the one file that touches the physics server, and a project wanting
`VehicleBody3D` writes one more like it and changes nothing else.

**Possession is a handover, not an identity change.** Nobody is reparented, nothing is hidden, no
entity is destroyed and rebuilt. The character's controller lets go of its input context and the
vehicle's takes one; the character's AI stops thinking and the vehicle's starts. Every step is
optional, so a plain `Node3D` with no controller and no brain gets in perfectly well (rule 31).
The order matters and is tested: the character releases *before* the vehicle takes, because two
controllers holding contexts for one player leaves the stack permanently one deep.

**Damage, storage and upgrades are borrowed whole.** A car is wrecked through the same
`DamageReceiverComponent` a person is shot through; its boot is an `InventoryComponent` with a
different `InventoryProfile`; a turbo is an item with an `EquipmentProfile` granting a stat. All
three are tested by using them, not by asserting they exist. `VehicleDefinition` names those
fields `inventory` and `loadout` rather than the plan's `storage` and `upgrades` — those are the
property names the existing components resolve by, and a field nothing ever reads is worse than
no field at all. That trap caught three fields in this milestone before the tests did.

`VehicleSolver` is static and node-free like `MovementSolver` before it, so "a car will not
pirouette while stationary", "braking never reverses you through the stop" and "reversing inverts
the steering" are unit tests that run in microseconds rather than things you find out by driving.

M13 also hardened the test runner. A test file that failed to compile was skipped **silently** and
the run still printed `RESULT: PASS` — see the findings below.

---

### M14 — Spawn + World State + Traffic ✅

| M14 deliverable | Where |
| --- | --- |
| SpawnService | `spawn/spawn_service.gd` |
| Encounter definitions | `spawn/encounter_definition.gd` |
| Population budgets | `world/region_definition.gd`, `world_state_service.gd` |
| World state | `world/world_state_service.gd`, `region_tracker.gd` |
| Spawn pools / anchors | `spawn/spawn_definition.gd`, `spawn_entry.gd`, `spawn_anchor.gd` |
| Despawn policies | `spawn/despawn_policy.gd` |
| Traffic hooks | a `SpawnDefinition` with a category — no traffic class, see below |

**M14 exit gate:**

- *Region population scales without global per-frame scans* —
  `test_world_scaling.gd::test_the_cost_of_a_tick_does_not_grow_with_the_world`
- *A tick examines only what is awake* —
  `test_world_scaling.gd::test_a_tick_examines_only_the_regions_that_are_awake`
- *Nothing scans the tree* —
  `test_world_scaling.gd::test_nothing_in_the_spawn_or_world_services_scans_the_scene_tree`
- *Entities report their own region* —
  `test_world_scaling.gd::test_an_entity_reports_its_own_region_rather_than_being_found`

```
79 suite(s), 1970 test(s), 1970 passed, 0 failed, 5625 assertions
RESULT: PASS
```

**This milestone's exit gate is a cost, not a behaviour**, and that changed how it was tested.
Everything here could work perfectly and M14 would still have failed if a tick got more
expensive as the world grew — which is not something you can see by watching a city look busy.
So `SpawnService` reports what it actually examined, and the suite asserts that number stays flat
while the world grows by two orders of magnitude: fifty regions and five thousand people cost
exactly what one region costs, because forty-nine of them are asleep. No timing is involved. A
timing test on CI is a coin flip; a count is a fact.

Three things make it true, and each is a design decision rather than an optimisation:

- **Nothing is discovered.** Anchors are registered into per-region buckets, pools match regions
  by tag. A test reads both service files and fails on `get_nodes_in_group`, `get_tree()`,
  `find_children` or `get_children(` — verified by adding a group scan and watching it go red.
- **Nothing is counted.** Population lives in `WorldStateService`, maintained on entry and exit.
  Asking how full a district is, is a dictionary lookup at any world size.
- **Entities report their own region.** The obvious design walks every entity each frame asking
  where it is, which is precisely the scan the gate forbids. Inverting it makes the cost
  proportional to movement between regions — and even that is skipped until an entity has moved a
  threshold distance, so a crowd at a bus stop costs nothing at all.

**`WorldStateService` holds no flags,** which is a deliberate deviation from the plan's wording.
`NarrativeStateService` already owns flags, variables and counters; a region flag is
`narrative.set_flag(&"region.docks.cleared")` — a semantic id in the store that already exists,
with no second store to keep in sync (rule 23, rule 32). What lives in World State is what is
genuinely not narrative: who is where, and how many of them.

**There is no traffic class,** and the plan does not need one. Traffic is a `SpawnDefinition`
whose entries are vehicles, whose anchors are lay-bys and whose despawn policy is aggressive —
the same machinery pedestrians use. Three tests prove it rather than a doc comment asserting it,
including one that fills a district with cars and pedestrians on independent budgets and sweeps
only the cars away.

Spawning goes through `EntityFactory`, the same load path saves use, so a spawned entity is built
exactly the way a loaded one is rather than by a second path that drifts.

---

### M15 — Crime + Heat ✅

| M15 deliverable | Where |
| --- | --- |
| Crime events | `crime_heat/crime_definition.gd`, `crime_context.gd` |
| Witness reporting | `crime_heat/witness_component.gd` |
| Wanted tiers | `crime_heat/wanted_tier.gd`, `heat_profile.gd`, `heat_service.gd` |
| Law response hooks | `crime_heat/wanted_hostility_provider.gd`, `crime_ai_adapter.gd` |
| Faction consequences | `crime_heat/crime_faction_adapter.gd` |
| Deaths become crimes | `crime_heat/combat_crime_adapter.gd` |

**M15 exit gate:**

- *No module Crime layers on mentions it* —
  `test_crime_dependencies.gd::test_no_module_crime_layers_on_top_of_mentions_it`
- *A killing becomes a crime without Combat knowing* —
  `test_crime_dependencies.gd::test_a_killing_becomes_a_crime_without_combat_knowing`
- *A wanted actor becomes an enemy of the law* —
  `test_crime_dependencies.gd::test_a_wanted_actor_becomes_an_enemy_of_the_law`
- *The whole milestone is deletable* —
  `test_crime_dependencies.gd::test_everything_still_works_with_no_crime_module_installed`

```
82 suite(s), 2051 test(s), 2051 passed, 0 failed, 6328 assertions
RESULT: PASS
```

**Combat needed no change at all for this milestone. Not one line.** That is the exit gate, and it
is asserted directly: a test reads every source file in `combat/`, `ai/`, `factions/` and
`health_damage/` and fails if any of them names a crime, a heat service or a wanted level. Verified
by adding one such mention to `CombatComponent` and watching the suite name the file.

The cycle being avoided is real and easy to walk into. The obvious design has `HealthComponent`
call a crime service on death — and then Combat depends on Crime, Crime depends on Factions,
Factions is consumed by AI, and AI issues the attacks. Instead:

- **A killing becomes murder** because `CombatCrimeAdapter` subscribes to `actor_died`, a fact
  Combat has published since M3 whether or not anybody is listening.
- **A guard attacks a fugitive** because `CrimeAIAdapter` hands it a `WantedHostilityProvider`
  through the `HostilityProvider` seam AI declared back in M7. That provider *wraps* whatever is
  already installed rather than replacing it, so adding a law system does not make every policeman
  forget who its enemies already were — and uninstalling it restores the politics rather than the
  framework default.
- **Standing moves** because `CrimeFactionAdapter` pushes it through `FactionService`'s existing
  public API.

All three adapters live in `crime_heat/` and all three are deletable.

**The only thing law AI ever sees is a semantic state.** A guard's brain asks whether somebody is
`state.wanted`; it never asks what their heat is, which faction is annoyed, or what they did. The
numbers can be retuned without touching a behaviour (rule 32).

**`HeatService` has no dependency on Factions at all.** Reputation is entirely
`CrimeFactionAdapter`'s, which means a project can have a wanted level with no social system behind
it. That split also fixed a double-charge: `FactionService.propagate_reputation` already applies the
direct cost *and* spreads it, so a service that also spent reputation itself billed the offender
twice for one crime.

A crime nobody witnessed is not a crime, and silencing a witness is deleting a component, blinding
it, or setting a state on it — none of which the law has to know about. That is the whole of a
stealth game's escape hatch, and it is one `silenced_by` array.

---

### M16 — Full Persistence ✅

| M16 deliverable | Where |
| --- | --- |
| Save slots | `persistence/save_slot.gd`, `save_service.gd` |
| Autosave | `persistence/autosave_policy.gd` |
| World / entity state | `entity/entity_record.gd`, `entity_serializer.gd` — from M1, unchanged |
| Mission / narrative / faction state | each service's own `capture_state()` — unchanged |
| Schema migration | `persistence/save_migration.gd`, `migration_registry.gd` |
| Storage seam | `persistence/save_backend.gd`, `file_save_backend.gd` |

**M16 exit gate:**

- *Full feature-stack round-trip* —
  `test_save_round_trip.gd::test_the_whole_feature_stack_survives_a_save`
- *Old save migration* — `test_save_round_trip.gd::test_an_old_save_migrates_forward`,
  `test_a_migrated_save_loads_into_the_live_world`
- *A save loads into a different world* —
  `test_save_round_trip.gd::test_a_second_world_can_be_loaded_into_from_the_same_save`
- *A missing module does not make a save unloadable* —
  `test_save_round_trip.gd::test_a_save_holding_state_for_a_missing_module_still_loads`

```
84 suite(s), 2110 test(s), 2110 passed, 0 failed, 6576 assertions
RESULT: PASS
```

**`SaveService` serialises nothing.** Every persistent component has owned `capture_state()` and
`restore_state()` since M1, and every persistent service owns the same pair; this walks what it
was given and aggregates. That is why fifteen milestones have added saved state and the save
platform has needed no change for any of them — a test asserts it directly, reading
`save_service.gd` and failing if it names `InventoryComponent`, `HeatService`, `SeatComponent` or
any of eight others.

The round-trip test is the one that gets harder as the framework grows, so it drives real
components rather than hand-made dictionaries: health, inventory, needs, semantic state and a
transform on an entity; narrative flags and counters, faction reputation, wanted level and region
population across four services. Save, wipe every one of them, load, assert all of it came back.
It passed on the first run, which is the strongest evidence the capture/restore discipline held.

**Migrations are steps, never jumps.** A save at schema 1 loading into a build at schema 4 runs
1→2, 2→3, 3→4. Writing a 1→4 migration instead looks simpler and is the thing that rots: every new
version would need a migration from every old one, and the count grows with the square of the
project's age. A gap in the ladder is a registration-time error rather than a corrupt world at
load time, and `MigrationRegistry.validate()` is meant to run in CI so a missing rung is a build
failure rather than a support ticket.

Three failure modes get their own answers rather than a shrug. A save **from the future** is
refused — a player who downgraded is told, not silently given a broken world. A save holding state
for a **module this build no longer has** is reported as information and left alone, because
removing an optional module must not make existing saves unloadable (rule 31). A save naming an
**entity that is not in the world** is likewise information, with `rebuild()` available for the
project to decide what to respawn and where — a save service that guessed would be one deciding
scene structure.

`FileSaveBackend` is the only file here that touches the filesystem, and it writes binary rather
than JSON: the records carry `Transform3D` and `Vector3` values, and a JSON encoder that had to
know every type a component might save is exactly the "serialise arbitrary nodes" approach the
plan rules out. Slot metadata is a separate small file, so a load menu renders six rows without
deserialising six worlds.

---

### M17 — UI Framework + Debug Tooling ✅

| M17 deliverable | Where |
| --- | --- |
| Presenters / view models | `ui/presenter.gd`, `view_model.gd` |
| HUD shell | `ui/hud_presenter.gd`, `hud_view_model.gd` |
| Inventory / dialogue / mission panels | `ui/inventory_presenter.gd`, `dialogue_presenter.gd`, `mission_presenter.gd` |
| Vitals panel | `ui/vitals_presenter.gd` — health, needs and effects in one snapshot |
| Event monitor | `debug/event_monitor.gd` |
| Entity inspector | `debug/entity_inspector.gd` — from M1, unchanged |
| Mission / faction / save / spawn inspectors | `debug/service_inspector.gd` |
| Console | `debug/debug_console.gd`, `debug_command.gd` |

**M17 exit gate:**

- *UI contains no domain authority* — `test_ui_authority.gd::test_no_presenter_can_change_the_world`,
  `test_a_view_model_holds_no_live_objects`
- *Nothing depends on the view* — `test_ui_authority.gd::test_no_module_depends_on_the_ui_module`
- *Event inspector operational* — `test_debug_tooling.gd::test_the_monitor_records_what_crosses_the_bus`
- *Entity inspector operational* — `test_debug_tooling.gd::test_the_entity_inspector_reports_what_an_entity_is`

```
86 suite(s), 2163 test(s), 2163 passed, 0 failed, 7876 assertions
RESULT: PASS
```

**Presenters and no widgets.** This is the milestone's one real decision and it is written up in the
decisions section below. What a health bar looks like is a project's decision about its own game
(rule 21, rule 29); what every project would otherwise write five slightly different times is the
discipline — observe, snapshot, emit.

That discipline is what makes the exit gate true rather than merely intended. A `ViewModel` carries
numbers and strings, never components, so a widget handed one physically cannot mutate what it
draws. The `InventoryViewModel` is the clearest case: it holds rows of plain data rather than
`ItemInstance`s, because an instance is live state and a bag panel that can destroy items is
exactly what rule 21 exists to prevent. A test reads every file in `ui/` and fails on any of thirty
mutating calls — verified by adding a `heal()` to `VitalsPresenter` and watching the suite name the
file.

`HudPresenter` exists so a HUD redraws **once**. Five presenters emitting independently means a
frame where health has updated and the mission tracker has not, and every project would otherwise
coalesce them slightly differently.

**The debug tooling asks generically.** The plan wants a mission inspector, a faction matrix, a
save inspector and a spawn debugger — four panels over four modules, and four files would make
`debug/` the one thing in the framework that cannot be deleted. `ServiceInspector` finds each
service by the methods it has rather than by its type, so it names no module and a project's own
service is described for free if it answers the same questions. A test asserts that too.

`DebugConsole` ships four read-only commands and no cheats. Spawn-item, set-stat and start-mission
would import five modules; a project registers its own, and the console knows only names and
callables. Commands **declare** whether they mutate, which is what lets a release build keep the
inspectors and drop the cheats.

The faction matrix prints both directions of every relation rather than folding them, because
relations are directional and a matrix that hid the asymmetry would hide exactly what somebody
opened the panel to find.

---

### M18 — Networking Adapter ✅

| M18 deliverable | Where |
| --- | --- |
| Authority facade | `networking/network_authority.gd`, `authority_policy.gd` |
| RPC validation | `networking/network_authority.gd` (validators), the adapters' own |
| Sync / transport adapters | `networking/network_transport.gd`, `multiplayer_transport.gd` |
| Network identity | `networking/network_identity.gd` |
| Inventory prototype | `networking/inventory_authority_adapter.gd` |
| Combat prototype | `networking/combat_authority_adapter.gd` |

**M18 exit gate:**

- *Offline mode unchanged* —
  `test_network_authority.gd::test_offline_a_command_runs_in_process_on_the_same_line`,
  `test_no_module_names_anything_in_networking`
- *Server-authoritative inventory* —
  `test_network_authority.gd::test_a_client_sends_a_request_rather_than_acting`,
  `test_a_peer_cannot_act_for_somebody_elses_entity`
- *Server-authoritative combat* —
  `test_network_authority.gd::test_shots_arriving_faster_than_the_weapon_can_fire_are_refused`
- *One file touches Godot's multiplayer API* —
  `test_network_authority.gd::test_only_one_file_touches_godots_multiplayer_api`

```
87 suite(s), 2203 test(s), 2203 passed, 0 failed, 8540 assertions
RESULT: PASS
```

**Not one line changed in Inventory or Combat for this milestone.** Seventeen milestones of
insisting every mutation be a method returning a `FrameworkResult` is what made that possible: the
adapters register handlers that call `InventoryComponent.add()` and `CombatComponent.attack()` and
add nothing of their own. Every module's mutation API turned out to be its networking API, which is
the payoff the plan was aiming at when it said "define mutation APIs so an authority adapter can
sit in front of them".

**Offline is not a special case, and that is the design rather than a discipline.** The default
transport is authoritative and the default policy owns nothing, so a command handed to
`execute()` offline runs in-process on the same line. There is no second branch to drift out of
step — which is why "offline mode unchanged" is asserted rather than re-verified each release. Two
tests hold the line: no module names anything in `networking/`, and exactly one file in the whole
addon touches `MultiplayerAPI`. Both verified by deliberately breaking them.

**The policy defaults to local, not authoritative.** Everything-unless-allowed is safer on paper
and wrong for a framework: a project installing networking would find every unlisted call silently
stop working — including presentation — and would conclude the module was broken rather than
strict. `AuthorityPolicy.standard()` ships the plan's list (inventory, commerce, combat, missions,
crime, crafting, equipment) as a starting point to argue with.

**A network id is not a save id.** Conflating them means either saves that break when somebody
reconnects, or network traffic shaped like a save file. `NetworkIdentity` sits alongside
`PersistentIdentity` and never replaces it.

What crosses the wire for combat is "I fired", not "I am aiming here": aiming is client-side and
must be, because a shooter where turning waits for a round trip is unplayable. What the server owns
is the *result*, which is the distinction the plan draws by calling combat **results**
authority-owned. The rate check reads the weapon's own `rate_per_second`, because the component's
local limit runs on the machine that was modified.

---

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

The Ontology Rulebook and the Implementation Plan agree on principles and disagree in a few
places in their reference code. Each is resolved here deliberately, and the last two are places
where the plan is internally consistent but following it literally would have duplicated
something the framework already had.

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

### 4. Four dialogue node types, not six

Implementation Plan 18 lists Line, Choice, Branch, Action, Jump and End. This framework
ships four: Action and Jump are fields on the `DialogueNode` base rather than types of
their own.

The reason is that both already exist there. Every node needs to be able to run actions on
entry and to name a successor, so `enter_actions` and `next` have to be on the base
regardless — and once they are, an Action node is a node with actions and no text, and a
Jump node is a node whose only content is where it goes. Two subclasses whose entire body
would be inherited is the abstraction rule 23 asks us not to add.

The consequence worth stating: a project porting a graph from a tool that has explicit
Action and Jump nodes maps both onto a bare `DialogueNode`. `DialogueFixtures.action_node`
in the test support shows the shape.

---

### 5. World State holds no flags

The plan lists "WorldStateService for persistent global/region flags". `NarrativeStateService`
already owns flags, variables, counters and relationships, and building a second store of them
would be the same idea twice (rule 23) — two things to save, two to migrate, and two that can
disagree about whether the docks are cleared.

So `WorldStateService` owns only what is genuinely not narrative: which regions exist, which are
awake, and who is in them. A region flag is `narrative.set_flag(&"region.docks.cleared")`, which
is a semantic id in the store that already exists (rule 32) and needs no new code at all.

The cost is that a project reading the plan literally will look for `world.set_region_flag()` and
not find it. That is worth one line of documentation; a duplicated store is not.

### 6. The UI module ships no widgets

The plan lists "HUD shells; inventory/shop/dialogue/mission widgets" as M17 deliverables. This
ships presenters and view models and not one `Control`.

A health bar is a look, and a look is a project's decision about its own game (rule 21, rule 29).
A framework that shipped one would ship the first thing every project deletes — and worse, a widget
holding a live `HealthComponent` can call `kill()` on it, which is the exact failure the exit gate
forbids. What every project *does* need, and would otherwise write five slightly different times,
is the discipline: a presenter observes, builds a plain-data snapshot, and emits it; a widget draws
the snapshot and holds nothing live.

So the framework owns *when* a panel should redraw and *what* it needs to know, and a project owns
what it looks like. The cost is that "inventory widget" is not a thing you can drop into a scene —
you write the `Control` and connect it to `InventoryPresenter.view_changed`, which is perhaps
twenty lines.

This is the same call M8 made in deferring a dialogue presenter, now made deliberately rather than
by omission: `DialoguePresenter` ships here, and still draws nothing.

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

**`load()` returns a `GDScript` even when it failed to compile.** A null check is not enough
to prove a script is sound — `test_script_compilation.gd` passed while `WalletComponent` had a
method shadowing `Object._set` with a different signature. `can_instantiate()` is false for a
script that did not compile, and asserting on it names the file. Verified by deliberately
breaking a script and watching the suite fail.

**`extends` must immediately follow `class_name`.** Anything between them — a `const`, a `var`, a
blank-line-and-comment — is a parse error, and the message points at the *next* line rather than
the intrusion. Worth knowing because it makes injecting a deliberate fault to test a guard
surprisingly easy to get wrong: two guard verifications during M18 reported hundreds of unrelated
failures because the injection itself did not compile, which looks exactly like "the guard did not
fire".

**`Dictionary.get()` returns a `Variant`, so arithmetic on it has no inferable type.**
`var since := Time.get_ticks_msec() - dict.get(key, 0)` fails to compile with "cannot infer the
type", pointing at the variable rather than at the dictionary. Type the intermediate.

**`@export var x: Object` is a parse error.** Export types must be built-in, a resource, a node or
an enum. A registry parameter that genuinely accepts any object — including a plain `RefCounted` —
has to be a plain `var` wired in code.

**`FactionService` relations are directional, and that is deliberate.** `set_relation(a, b, v)`
keys on `"a>b"`, so setting police→thieves leaves thieves→police untouched. A one-sided grudge is a
real thing and the framework models it, but the failure mode when you forget is quiet: the attitude
resolves to NEUTRAL and whatever depended on hostility simply does not fire. It cost an M15 test a
debugging session — the assertion read as a crime-system bug and was a fixture setting one
direction.

**A freed instance cannot even be *assigned* to a typed local.** `var node: Node = dict[key]`
throws `Trying to assign invalid previously freed instance` — before `is_instance_valid(node)` on
the next line can run. So the guard has to come first and the type second: read into a `Variant`,
check, then cast. Any registry holding nodes has this latent in it; it cost three files here
(`WorldStateService`, and `SeatComponent` and `EnvironmentZone` from earlier milestones where no
test had yet freed a tracked entity). Worth grepping for `is_instance_valid` preceded by a typed
assignment.

**A test file that fails to compile is skipped silently, and the run still says PASS.** The
runner checked `load(path) != null` before calling `script.new()` — but `load()` returns a
`GDScript` even when it did not compile, and calling `new()` on that is a *runtime* error, which
aborts `run_script()` before it can record the failure. So the suite vanished from the run and
`RESULT: PASS` printed anyway. `can_instantiate()` fixes it, the same way it fixed
`test_script_compilation.gd`. Verified by adding a deliberately broken test file and watching the
run go red and name it. **This is the same trap twice; assume it is everywhere `load()` is
followed by `new()`.**

**`get_move_vector()` returns forward as *negative* y.** It matches Godot's screen-space
convention so the value drops into a camera basis without a sign flip at every call site — which
is right for movement and wrong for anything that is not a basis. `VehicleControllerComponent`
took it raw and pressing W reversed the car. The tell is that the test failure reads
`Expected -1.0 but got 0.7`, which looks like a magnitude problem and is a sign problem.

**Re-initialising a controller that holds a pushed input context strands the old one.** Contexts
are removed by instance, not by id, because two players both on foot push contexts with the same
id. So a second `initialize()` that rebuilds `_input_context` leaves the pushed instance
unreachable: release removes the new object, misses, and the stack is one deeper forever. Both
`CharacterController` and `VehicleControllerComponent` now refuse to replace the context while
controlling. It surfaced as a stack that grew by exactly one across five round trips in and out
of a car.

**`"some_method" in some_object` is false even when the method exists.** The `in` operator tests
*properties*. `FuelComponent` used it to detect `get_starting_fuel()` on a definition and the
check was dead on the very class that declares it. `has_method()` for methods, `in` for
properties.

**A field the framework declares but nothing resolves is worse than no field.** `VehicleDefinition`
shipped `maximum_health`, `storage` and `upgrades`, all authored, all validated, none of them
read: `HealthComponent` takes its maximum from its own export, and `InventoryComponent` and
`EquipmentComponent` resolve by looking for properties called `inventory` and `loadout`. Content
authors would have set three numbers that did nothing. Two were fixed by renaming to the property
the consumer already looks for; the third needed the vehicle to carry it across, because
`HealthComponent` should not learn what a car is. Worth a grep every time a definition gains a
field.

**`_set` is a Godot virtual, and it is the most natural name in the world for a private
setter.** `Object._set(StringName, Variant) -> bool` exists on everything, and declaring
`func _set(need, value) -> void` is a *parse error* — "the function signature doesn't match the
parent" — not an override. It has now cost this project twice, `WalletComponent` in M11 and
`NeedsComponent` in M12, and the second time the compilation guard named the file in one run.
The same trap sits on `_get`, `_notification` and `_to_string`; `ItemInstance.get_stack_id()`
is named that way for the same reason. Use `_apply`, and expect the parse error to point at
the *dependent* script rather than the one you edited.

**`String.num(12.5, 2)` is `"12.5"`, not `"12.50"`.** It trims trailing zeros, which for money
is always wrong. `pad_decimals()` after it; a currency with no decimals pads to none and is
unaffected.

**A script nothing references is never parsed, so its errors are invisible.** Godot compiles
a `.gd` when something loads it. `AreaTrigger` shipped a call to a method that did not exist
and the suite stayed green, because no test had imported it yet and the CI gate greps the
run's output for `SCRIPT ERROR` — which never appears for a script that was never loaded.
`--import` does not catch it either. `test_script_compilation.gd` now walks the addon and
loads every script and scene, which is the cheapest possible guard against a class of
mistake that is otherwise invisible until someone opens the editor.

**`Object.has_method()` says nothing about arity.** Calling a one-argument method with no
arguments is a runtime error, not a miss. `EventMatcher` reads a named field off an event
and falls back to a zero-argument method — checking `has_method` alone turned a mistyped
field name from "this objective never progresses" into a crash. `get_method_list()` carries
the argument list; filter on it.

**A `RefCounted` cycle between two objects is never collected, and Godot only reports the
count.** `DialogueRuntime` holds its `DialogueContext` and the context pointed back at the
runtime — a two-object cycle that leaked 436 ObjectDB instances at exit, because everything
either one reached stayed alive with them. Godot reports `N instances were leaked` and
names nothing. The fix is to make one direction weak (`weakref`), and the tell is that the
count is large and round-ish: a leak of hundreds from a suite that creates dozens of
objects means a cycle rooted somewhere reaching a big graph.

**A lambda captures a value type by value, so a counter incremented inside one never
changes.** `var hits := 0` followed by `signal.connect(func(): hits += 1)` compiles, runs, and
asserts `hits == 0` forever — the lambda increments its own copy. It is the quietest way to
write a test that passes for no reason: the assertion that survives is usually
`assert_eq(count, 0)`, which is exactly what a test of "this does not fire" looks like. Count
into an `Array` instead; arrays are captured by reference and `append` reaches the enclosing
scope.

**A `Resource` that stores the context it was handed leaks the whole graph.** The CI gate fails
on `ObjectDB instances were leaked at exit`, and this is the easiest way to trip it. An
`InteractionContext` holds the `InteractionDefinition`, which holds the `InteractionAction` —
so an action that stashes `last_context` closes a `RefCounted` cycle that Godot's reference
counting cannot break, and every resource in it survives to exit. Godot reports the count, not
the culprit. Record the facts you need (`last_interactor`, `last_verb`), not the context.

**`Node.name` is a `StringName`, not a `String`.** `assert_eq(["in", node.name], ["in", "Door"])`
fails with `["in", &"Door"] != ["in", "Door"]` — the two compare equal on their own, but not
once they are inside containers being compared element-wise. Wrap it in `String()` at the
boundary rather than chasing the mismatch through a diff that looks identical apart from one
ampersand.

**A component that resolves a profile in `initialize()` resolves it once.**
`DamageReceiverComponent`, `NeedsComponent` and the rest cache their definition at
initialisation, which is the whole point — the resolution reads the entity definition by
property name and should not run per frame. The consequence for a test is that setting
`profile_override` *after* assembling the entity does nothing at all and looks like the
override being ignored. Set it before, the way a scene would.

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
│   ├── inventory_component.gd     one container. transfers are atomic
│   ├── inventory_event_adapter.gd the seam that announces an acquisition
│   └── item_acquired_event.gd     …as a cross-feature fact
├── equipment/
│   ├── equipment_profile.gd       where an item goes and what it grants
│   ├── equipment_slot_definition.gd  one place a thing can be worn
│   ├── loadout_profile.gd         which slots, and what is worn to start
│   └── equipment_component.gd     wearing things, sourced per instance
├── ai/
│   ├── perception_solver.gd       the geometry of noticing. static, no node
│   ├── perception_provider.gd     where perception asks the world
│   ├── physics_perception_provider.gd  the only AI file touching physics
│   ├── perception_profile.gd      what it can notice, and for how long
│   ├── perceivable.gd             this can be noticed, and how easily
│   ├── perception_component.gd    sight, hearing, and a memory that fades
│   ├── memory_entry.gd            what it knows about one other entity
│   ├── ai_memory.gd               everything it knows. it forgets on purpose
│   ├── ai_context.gd              everything a brain is given to think with
│   ├── ai_brain.gd                what to do next. a resource, no state
│   ├── hostility_provider.gd      is that an enemy? a seam, not a policy
│   ├── role_brain.gd              one brain, three stances: the exit gate
│   ├── npc_role_definition.gd     civilian, guard, combatant, vendor
│   ├── navigation_adapter.gd      a navmesh when there is one, straight when not
│   └── ai_controller_component.gd drives a character. same API the player uses
├── combat/
│   ├── combat_solver.gd           spread, recoil, falloff, arcs, attack phases
│   ├── hit_provider.gd            where combat asks the world what it hit
│   ├── physics_hit_provider.gd    the only place combat touches the physics server
│   ├── combat_hit.gd              one thing an attack connected with
│   ├── attack_definition.gd       one attack: cost, timing, reach, damage
│   ├── attack_context.gd          everything one swing or shot knows
│   ├── attack_delivery.gd         how an attack reaches what it is aimed at
│   ├── melee_delivery.gd          an arc, within reach
│   ├── hitscan_delivery.gd        a shot that arrives instantly. pellets, falloff
│   ├── projectile_delivery.gd     a shot that takes time to arrive
│   ├── projectile.gd / .tscn      in flight, sweeping rather than teleporting
│   ├── weapon_profile.gd          what makes an item a weapon
│   ├── ammo_profile.gd            magazine, reserve, reload, or none of it
│   ├── recoil_profile.gd          how aim degrades, and how it settles
│   ├── combat_profile.gd          how an entity fights with empty hands
│   ├── weapon_component.gd        ammunition, reloading, aim drift
│   └── combat_component.gd        the attack state machine. one command API
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
├── commerce/
│   ├── currency_definition.gd     money: symbol, precision, ceilings
│   ├── wallet_component.gd        balances. every mutation returns a result
│   ├── stock_entry.gd             one line on a shelf
│   ├── vendor_definition.gd       what a shop stocks, charges and refills
│   ├── vendor_component.gd        the live shelf. its own copy, never shared
│   ├── pricing_policy.gd          what something costs
│   ├── standard_pricing_policy.gd markup, markdown, and how much they like you
│   ├── trade_context.gd           one purchase or sale, start to finish
│   ├── commerce_service.gd        validate everything, then move everything
│   ├── commerce_event.gd          something changed hands
│   ├── trade_action.gd            press E on the shopkeeper. M5's pipeline
│   └── commerce_module.gd         the module manifest
├── loot/
│   ├── loot_entry.gd              one thing that might drop
│   ├── loot_table_definition.gd   weighted, guaranteed, nested. seeded rolls
│   ├── loot_component.gd          rolls once. a corpse is generous only once
│   └── loot_module.gd             the module manifest
├── survival/
│   ├── need_definition.gd         one meter. hunger, warmth, oxygen, sanity
│   ├── needs_component.gd         the values, the bands, and what empty costs
│   ├── consumable_profile.gd      what eating something does
│   ├── consumer_component.gd      eating it. validate, then mutate
│   ├── environment_zone.gd        a cave, a fire. it scales, it never drains
│   └── survival_module.gd         the module manifest
├── crafting/
│   ├── recipe_ingredient.gd       spent or held. a tool is the held kind
│   ├── recipe_definition.gd       what can be made from what, where, how long
│   ├── crafting_station.gd        a forge is a set of tags and nothing else
│   ├── crafting_component.gd      the queue. materials are spent up front
│   └── crafting_module.gd         the module manifest
├── gathering/
│   ├── resource_node_definition.gd  what a tree gives up, and how often
│   ├── resource_node.gd           charges, tool wear, respawn. yields via loot
│   ├── harvest_action.gd          press E on the tree. M5's pipeline, reused
│   └── gathering_module.gd        the module manifest
├── factions/
│   ├── attitude_solver.gd         standing to disposition. static, no node
│   ├── faction_definition.gd      a group with opinions and its bands
│   ├── faction_service.gd         relations, reputation, attitude
│   ├── faction_component.gd       which side an entity is on
│   ├── faction_hostility_provider.gd  answers the AI's question from standing
│   ├── faction_ai_adapter.gd      hands the provider to a brain. deletable
│   ├── faction_price_adapter.gd   standing to a price multiplier, for M11
│   ├── faction_event_adapter.gd   the seam that promotes a change of heart
│   ├── faction_event.gd           …as a cross-feature fact
│   └── factions_module.gd         the module manifest
├── missions/
│   ├── event_matcher.gd           one question asked of an event, by field name
│   ├── objective_definition.gd    one thing a mission asks for. fourteen kinds
│   ├── objective_runtime.gd       how far along one objective is
│   ├── mission_definition.gd      a whole mission, as content
│   ├── mission_runtime.gd         one mission in progress. reads events only
│   ├── mission_service.gd         every mission in flight. one bus subscription
│   ├── mission_reward.gd          what a mission gives back
│   ├── narrative_reward.gd        a flag, a counter, standing
│   ├── item_reward.gd             the sword, the purse
│   ├── area_trigger.gd            somebody reached this place
│   ├── area_event.gd              …as a cross-feature fact
│   └── mission_event.gd           started, finished, objective ticked off
├── narrative/
│   ├── narrative_state_service.gd flags, variables, counters, standing
│   ├── narrative_event_adapter.gd the seam that promotes a flag to the bus
│   ├── narrative_event.gd         a flag moved, or a counter did
│   └── narrative_module.gd        the module manifest
├── dialogue/
│   ├── dialogue_definition.gd     a whole conversation, as content
│   ├── dialogue_node.gd           one step. line, choice, branch or end
│   ├── line_node.gd               somebody says something and it waits
│   ├── choice_node.gd             the conversation stops and the player picks
│   ├── dialogue_choice.gd         one thing the player can say
│   ├── branch_node.gd             it decides for itself. first match wins
│   ├── end_node.gd                over, and how it ended
│   ├── dialogue_condition.gd      a question. never mutates
│   ├── narrative_condition.gd     flags, variables, counters, standing
│   ├── item_condition.gd          the quest item, the bribe
│   ├── dialogue_action.gd         something it does to the world
│   ├── narrative_action.gd        raise, set, bump, shift
│   ├── dialogue_context.gd        what one conversation knows
│   ├── dialogue_runtime.gd        the conversation itself. no scene needed
│   ├── dialogue_component.gd      hangs one off an NPC
│   ├── talk_action.gd             press E on the NPC. M5's pipeline, reused
│   └── dialogue_event_adapter.gd  the seam that promotes a choice to the bus
├── vehicles/
│   ├── vehicle_solver.gd          driving maths. static, no node, no body
│   ├── handling_profile.gd        speed, response, steering, thirst
│   ├── seat_definition.gd         one place somebody can be, and what they may do
│   ├── vehicle_definition.gd      scene, seats, handling, fuel, boot, upgrades
│   ├── vehicle_controller_adapter.gd  the six calls. the boundary, not a wrapper
│   ├── vehicle_body_adapter.gd    the only file here touching the physics server
│   ├── seat_component.gd          who is aboard. saved by id, never by path
│   ├── fuel_component.gd          what is in the tank
│   ├── vehicle_component.gd       engine, clock, and the one command API
│   ├── vehicle_controller_component.gd  the player driving. deletable
│   ├── vehicle_ai_driver.gd       traffic driving. same four calls
│   ├── enter_vehicle_action.gd    press E on the car. M5's pipeline, reused
│   ├── vehicle_event_adapter.gd   the seam that promotes a theft to the bus
│   ├── vehicle_event.gd           …as a cross-feature fact
│   ├── vehicle.tscn               the shipped composition
│   └── vehicles_module.gd         the module manifest
├── world/
│   ├── region_definition.gd       a district, and what it will hold
│   ├── world_state_service.gd     who is where. counted on entry, never scanned
│   ├── region_tracker.gd          an entity reporting itself, so nothing hunts
│   └── world_module.gd            the module manifest
├── spawn/
│   ├── spawn_entry.gd             one thing a pool can produce
│   ├── spawn_definition.gd        a pool, its density and its region tags
│   ├── encounter_definition.gd    a group that arrives together
│   ├── despawn_policy.gd          when ambient is allowed to vanish
│   ├── spawn_anchor.gd            a doorway, a lay-by. bucketed by region
│   ├── spawn_service.gd           tops up what is awake, and nothing else
│   └── spawn_module.gd            the module manifest
├── crime_heat/
│   ├── crime_definition.gd        what counts as a crime, and how bad
│   ├── crime_context.gd           one thing somebody did, and who saw it
│   ├── wanted_tier.gd             one rung. a semantic state, not a number
│   ├── heat_profile.gd            the ladder, and how quickly it cools
│   ├── heat_service.gd            heat and tiers. knows nothing of factions
│   ├── witness_component.gd       somebody who will tell. silence-able
│   ├── wanted_hostility_provider.gd  the law, through M7's own seam
│   ├── crime_ai_adapter.gd        hands it to a guard. wraps, never replaces
│   ├── combat_crime_adapter.gd    actor_died becomes murder. combat unchanged
│   ├── crime_faction_adapter.gd   every reputation consequence, in one place
│   ├── crime_event_adapter.gd     the seam that promotes a warrant to the bus
│   ├── crime_event.gd             …as a cross-feature fact
│   └── crime_module.gd            the module manifest
├── persistence/
│   ├── save_game.gd               one whole saved world, as plain data
│   ├── save_slot.gd               what a load menu shows without loading
│   ├── save_migration.gd          one rung. never a jump
│   ├── migration_registry.gd      the ladder, and a gap is a build failure
│   ├── save_backend.gd            where saves live. in-memory by default
│   ├── file_save_backend.gd       the only file here touching the disk
│   ├── autosave_policy.gd         when, how often, and how many to keep
│   ├── save_service.gd            aggregates. serialises nothing itself
│   └── persistence_module.gd      the module manifest
├── ui/
│   ├── view_model.gd              a snapshot. plain data, never components
│   ├── presenter.gd               observe, snapshot, emit. one-way by design
│   ├── vitals_presenter.gd        health, needs and effects, taken together
│   ├── inventory_presenter.gd     rows, not item instances
│   ├── dialogue_presenter.gd      the window M8 deliberately deferred
│   ├── mission_presenter.gd       the quest log
│   ├── hud_presenter.gd           so a HUD redraws once, not five times
│   └── ui_module.gd               the module manifest
├── networking/
│   ├── network_identity.gd        who owns this. never the save id
│   ├── network_intent.gd          one request. plain data, because it travels
│   ├── authority_policy.gd        what the server owns. defaults to little
│   ├── network_transport.gd       where intents go. offline by default
│   ├── multiplayer_transport.gd   the only file touching MultiplayerAPI
│   ├── network_authority.gd       the facade. a function call offline
│   ├── inventory_authority_adapter.gd  the server in front of the bag
│   ├── combat_authority_adapter.gd     the server in front of the trigger
│   └── networking_module.gd       the module manifest
├── debug/
│   ├── entity_inspector.gd        what is this entity, and would it persist?
│   ├── service_inspector.gd       missions, factions, saves, spawns. names none
│   ├── event_monitor.gd           a ring buffer of everything on the bus
│   ├── debug_command.gd           one command. declares whether it mutates
│   └── debug_console.gd           four read-only commands and no cheats
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

M0 through M18 are done. The build order follows dependency, not feature appeal.

| | Milestone | | | Milestone |
| --- | --- | --- | --- | --- |
| **M0** | **Foundation contract** ✅ | | **M10** | **Factions + reputation** ✅ |
| **M1** | **Entity + save identity** ✅ | | **M11** | **Commerce + vendors + loot** ✅ |
| **M2** | **Character + input + locomotion** ✅ | | **M12** | **Crafting + survival** ✅ |
| **M3** | **Stats + health + damage + effects** ✅ | | **M13** | **Vehicles** ✅ |
| **M4** | **Items + inventory + equipment** ✅ | | **M14** | **Spawn + world state + traffic** ✅ |
| **M5** | **Interaction platform** ✅ | | **M15** | **Crime / heat** ✅ |
| **M6** | **Combat + weapons** ✅ | | **M16** | **Full persistence** ✅ |
| **M7** | **AI + NPC roles** ✅ | | **M17** | **UI framework + debug tooling** ✅ |
| **M8** | **Dialogue + narrative state** ✅ | | **M18** | **Networking adapter** ✅ |
| **M9** | **Missions + objectives** ✅ | | M19 | Packaging + documentation |

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
