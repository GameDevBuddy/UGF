class_name GameplayNames
extends RefCounted
## Shared semantic vocabulary for the framework.
##
## Two distinct mechanisms live here, and the distinction matters
## (Ontology Rulebook 12, rule 10):
##
## [b]Groups[/b] are SceneTree membership, used for runtime discovery and
## fan-out. Only register a group when tree membership genuinely matters.
##
## [b]Semantic StringNames[/b] are data vocabulary. They describe meaning on
## Resources and in tags, and require no SceneTree presence at all.
##
## Nothing game-specific belongs in this file (rule 29). A faction of robots,
## a named city or a story flag is game content, not framework vocabulary.

# --- SceneTree groups: runtime discovery ---------------------------------

const GROUP_INTERACTABLE: StringName = &"interactable"
const GROUP_DAMAGEABLE: StringName = &"damageable"
const GROUP_SAVEABLE: StringName = &"saveable"
const GROUP_ENTITY: StringName = &"framework_entity"

## Something an NPC's senses can pick up. Membership is a decision the
## entity's composition makes, through [Perceivable] -- a destructible crate
## is not something a guard stares at, and a possessed vehicle is.
const GROUP_PERCEIVABLE: StringName = &"perceivable"

# --- Semantic state vocabulary -------------------------------------------

const STATE_DEAD: StringName = &"state.dead"
const STATE_DOWNED: StringName = &"state.downed"
const STATE_SPRINTING: StringName = &"state.movement.sprinting"
const STATE_CROUCHING: StringName = &"state.movement.crouching"
const STATE_AIRBORNE: StringName = &"state.movement.airborne"
const STATE_MOVING: StringName = &"state.movement.moving"
const STATE_INTERACTING: StringName = &"state.interacting"
const STATE_ATTACKING: StringName = &"state.attacking"
const STATE_RELOADING: StringName = &"state.reloading"
const STATE_AIMING: StringName = &"state.aiming"
const STATE_ALERTED: StringName = &"state.alerted"
const STATE_FLEEING: StringName = &"state.fleeing"

## Set by [ToggleStateAction] on anything that opens: a door, a chest, a hatch.
## Generic enough to be framework vocabulary; a game's own states are not
## (rule 29).
const STATE_OPEN: StringName = &"state.open"
const STATE_LOCKED: StringName = &"state.locked"

# --- Semantic interaction verbs ------------------------------------------
#
# What an interaction is, independent of the prose shown for it. Presentation
# picks an icon from the verb; the prompt string stays free to be localised.

const VERB_USE: StringName = &"verb.use"
const VERB_OPEN: StringName = &"verb.open"
const VERB_CLOSE: StringName = &"verb.close"
const VERB_TAKE: StringName = &"verb.take"
const VERB_TALK: StringName = &"verb.talk"
const VERB_ENTER: StringName = &"verb.enter"
const VERB_EXIT: StringName = &"verb.exit"
const VERB_SEARCH: StringName = &"verb.search"

# --- Semantic input actions ----------------------------------------------
#
# Gameplay asks for these, never for a key or a button (Implementation Plan
# 24). Godot's InputMap still owns the bindings behind them; what the router
# decides is which context is allowed to hear them.

const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_MOVE_FORWARD: StringName = &"move_forward"
const ACTION_MOVE_BACK: StringName = &"move_back"
const ACTION_JUMP: StringName = &"jump"
const ACTION_SPRINT: StringName = &"sprint"
const ACTION_CROUCH: StringName = &"crouch"
const ACTION_INTERACT: StringName = &"interact"
const ACTION_ATTACK: StringName = &"attack"
const ACTION_ATTACK_SECONDARY: StringName = &"attack_secondary"
const ACTION_RELOAD: StringName = &"reload"
const ACTION_AIM: StringName = &"aim"

# --- Input context identifiers -------------------------------------------

const INPUT_CONTEXT_ON_FOOT: StringName = &"input.on_foot"
const INPUT_CONTEXT_VEHICLE_DRIVER: StringName = &"input.vehicle_driver"
const INPUT_CONTEXT_VEHICLE_PASSENGER: StringName = &"input.vehicle_passenger"
const INPUT_CONTEXT_UI: StringName = &"input.ui"
const INPUT_CONTEXT_DIALOGUE: StringName = &"input.dialogue"
const INPUT_CONTEXT_DISABLED: StringName = &"input.disabled"

# --- Semantic damage vocabulary ------------------------------------------
#
# Resistances and status effects match on these rather than on an enum Core
# would have to own. A project is free to invent its own; these are the ones
# every genre this platform targets ends up needing.

const DAMAGE_PHYSICAL: StringName = &"damage.physical"
const DAMAGE_BALLISTIC: StringName = &"damage.ballistic"
const DAMAGE_EXPLOSIVE: StringName = &"damage.explosive"
const DAMAGE_FIRE: StringName = &"damage.fire"
const DAMAGE_COLD: StringName = &"damage.cold"
const DAMAGE_POISON: StringName = &"damage.poison"
const DAMAGE_FALL: StringName = &"damage.fall"
const DAMAGE_TRUE: StringName = &"damage.true"

# --- Core stat identifiers -----------------------------------------------
#
# Health's maximum is here because Health is a Core-adjacent concern every
# genre shares. Strength, agility and the rest are game content and are not.

const STAT_HEALTH_MAX: StringName = &"stat.health.max"
const STAT_STAMINA: StringName = &"stat.stamina"
const STAT_RESISTANCE: StringName = &"stat.resistance"

# --- Cross-feature event names -------------------------------------------
# These match the EventBus signal names one-for-one. FrameworkEvent
# subclasses return one of these from get_event_name().

const EVENT_ACTOR_DIED: StringName = &"actor_died"
const EVENT_DIALOGUE_COMPLETED: StringName = &"dialogue_completed"
const EVENT_DIALOGUE_CHOICE: StringName = &"dialogue_choice"
const EVENT_ITEM_ACQUIRED: StringName = &"item_acquired"
const EVENT_NARRATIVE_FLAG: StringName = &"narrative_flag_changed"
const EVENT_NARRATIVE_COUNTER: StringName = &"narrative_counter_changed"
const EVENT_AREA_ENTERED: StringName = &"area_entered"
const EVENT_MISSION_STARTED: StringName = &"mission_started"
const EVENT_MISSION_COMPLETED: StringName = &"mission_completed"
const EVENT_MISSION_FAILED: StringName = &"mission_failed"
const EVENT_OBJECTIVE_COMPLETED: StringName = &"objective_completed"
const EVENT_ATTITUDE_CHANGED: StringName = &"attitude_changed"

# --- AI activity names ---------------------------------------------------
#
# What a brain reports it is doing. Vocabulary rather than an enum, so a
# project's own brain can invent states the framework never heard of without
# Core having to grow a case for them (rule 32).

const AI_STATE_IDLE: StringName = &"ai.idle"
const AI_STATE_WANDER: StringName = &"ai.wander"
const AI_STATE_INVESTIGATE: StringName = &"ai.investigate"
const AI_STATE_ENGAGE: StringName = &"ai.engage"
const AI_STATE_FLEE: StringName = &"ai.flee"
const AI_STATE_DEAD: StringName = &"ai.dead"

# --- Objective kinds -----------------------------------------------------
#
# What an objective is asking for, for presentation: an icon, a sort order, a
# tracker line. Vocabulary rather than an enum, because Implementation Plan 19
# lists fourteen baseline kinds and a project will invent a fifteenth.

const OBJECTIVE_KILL: StringName = &"objective.kill"
const OBJECTIVE_ACQUIRE: StringName = &"objective.acquire"
const OBJECTIVE_DELIVER: StringName = &"objective.deliver"
const OBJECTIVE_TALK: StringName = &"objective.talk"
const OBJECTIVE_REACH: StringName = &"objective.reach"
const OBJECTIVE_INTERACT: StringName = &"objective.interact"
const OBJECTIVE_SURVIVE: StringName = &"objective.survive"
const OBJECTIVE_CUSTOM: StringName = &"objective.custom"

# --- Core service identifiers --------------------------------------------

const SERVICE_SAVE: StringName = &"service.save"
const SERVICE_SCENE_FLOW: StringName = &"service.scene_flow"
const SERVICE_WORLD_STATE: StringName = &"service.world_state"
const SERVICE_SPAWN: StringName = &"service.spawn"
const SERVICE_OBJECTIVE: StringName = &"service.objective"
const SERVICE_INPUT: StringName = &"service.input"
const SERVICE_NARRATIVE: StringName = &"service.narrative"
const SERVICE_FACTION: StringName = &"service.faction"

# --- Core module identifiers ---------------------------------------------
# Feature modules declare these in their manifest. Core is not listed: it is
# not a module, it is the contract layer every module is allowed to know.

const MODULE_ENTITY: StringName = &"module.entity"
const MODULE_CHARACTER: StringName = &"module.character"
const MODULE_LOCOMOTION: StringName = &"module.locomotion"
const MODULE_INPUT: StringName = &"module.input"
const MODULE_CAMERA: StringName = &"module.camera"
const MODULE_ANIMATION: StringName = &"module.animation"
const MODULE_STATUS_EFFECTS: StringName = &"module.status_effects"
const MODULE_STATS: StringName = &"module.stats"
const MODULE_HEALTH: StringName = &"module.health"
const MODULE_ITEMS: StringName = &"module.items"
const MODULE_INVENTORY: StringName = &"module.inventory"
const MODULE_EQUIPMENT: StringName = &"module.equipment"
const MODULE_INTERACTION: StringName = &"module.interaction"
const MODULE_COMBAT: StringName = &"module.combat"
const MODULE_AI: StringName = &"module.ai"
const MODULE_DIALOGUE: StringName = &"module.dialogue"
const MODULE_NARRATIVE: StringName = &"module.narrative"
const MODULE_MISSIONS: StringName = &"module.missions"
const MODULE_FACTIONS: StringName = &"module.factions"
const MODULE_COMMERCE: StringName = &"module.commerce"
const MODULE_CRAFTING: StringName = &"module.crafting"
const MODULE_SURVIVAL: StringName = &"module.survival"
const MODULE_VEHICLES: StringName = &"module.vehicles"
const MODULE_SAVE: StringName = &"module.save"
const MODULE_UI: StringName = &"module.ui"
const MODULE_NETWORKING: StringName = &"module.networking"
