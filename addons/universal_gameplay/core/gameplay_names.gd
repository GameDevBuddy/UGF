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

# --- Semantic state vocabulary -------------------------------------------

const STATE_DEAD: StringName = &"state.dead"
const STATE_DOWNED: StringName = &"state.downed"
const STATE_SPRINTING: StringName = &"state.movement.sprinting"
const STATE_CROUCHING: StringName = &"state.movement.crouching"
const STATE_AIRBORNE: StringName = &"state.movement.airborne"

# --- Cross-feature event names -------------------------------------------
# These match the EventBus signal names one-for-one. FrameworkEvent
# subclasses return one of these from get_event_name().

const EVENT_ACTOR_DIED: StringName = &"actor_died"

# --- Core service identifiers --------------------------------------------

const SERVICE_SAVE: StringName = &"service.save"
const SERVICE_SCENE_FLOW: StringName = &"service.scene_flow"
const SERVICE_WORLD_STATE: StringName = &"service.world_state"
const SERVICE_SPAWN: StringName = &"service.spawn"
const SERVICE_OBJECTIVE: StringName = &"service.objective"

# --- Core module identifiers ---------------------------------------------
# Feature modules declare these in their manifest. Core is not listed: it is
# not a module, it is the contract layer every module is allowed to know.

const MODULE_ENTITY: StringName = &"module.entity"
const MODULE_CHARACTER: StringName = &"module.character"
const MODULE_LOCOMOTION: StringName = &"module.locomotion"
const MODULE_STATS: StringName = &"module.stats"
const MODULE_HEALTH: StringName = &"module.health"
const MODULE_INVENTORY: StringName = &"module.inventory"
const MODULE_EQUIPMENT: StringName = &"module.equipment"
const MODULE_INTERACTION: StringName = &"module.interaction"
const MODULE_COMBAT: StringName = &"module.combat"
const MODULE_AI: StringName = &"module.ai"
const MODULE_DIALOGUE: StringName = &"module.dialogue"
const MODULE_MISSIONS: StringName = &"module.missions"
const MODULE_FACTIONS: StringName = &"module.factions"
const MODULE_COMMERCE: StringName = &"module.commerce"
const MODULE_CRAFTING: StringName = &"module.crafting"
const MODULE_SURVIVAL: StringName = &"module.survival"
const MODULE_VEHICLES: StringName = &"module.vehicles"
const MODULE_SAVE: StringName = &"module.save"
const MODULE_UI: StringName = &"module.ui"
const MODULE_NETWORKING: StringName = &"module.networking"
