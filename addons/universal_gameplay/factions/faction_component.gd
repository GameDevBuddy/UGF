class_name FactionComponent
extends FrameworkComponent
## Which group an entity belongs to, and what it thinks of what it sees.
##
## Membership is a [StringName] rather than a definition reference, so a
## faction and the hundreds of NPCs in it do not have to load each other, and
## so an entity's save record is a name (rule 32).

## Emitted when this entity changes sides.
signal faction_changed(faction: StringName)

## Group this entity belongs to. Takes precedence over the definition's.
@export var faction_override: StringName = &""

## Stable id this entity is known by for reputation: the player is
## [code]actor.player[/code]. Blank falls back to the persistent identity, and
## then to nothing -- an NPC nobody keeps a grudge against is the normal case.
@export var actor_id: StringName = &""

## Live standing service. Resolved from the core's registry when not wired.
@export var service: FactionService

var _faction: StringName = &""


func initialize(context: EntityContext) -> void:
	super(context)
	_faction = _resolve_faction()
	if service == null:
		service = _resolve_service()


func get_faction() -> StringName:
	return _faction


func has_faction() -> bool:
	return _faction != &""


## Changes sides at runtime. What a defection, a disguise or a promotion does.
func set_faction(faction: StringName) -> void:
	if faction == _faction:
		return
	_faction = faction
	faction_changed.emit(_faction)


## The name this entity is known by personally. Falls back to its save id, so
## a named NPC accumulates a reputation without anyone authoring one.
func get_actor_id() -> StringName:
	if actor_id != &"":
		return actor_id
	var entity := get_entity()
	if entity == null:
		return &""
	for component in DefinitionBinder.collect_components(entity):
		if component is PersistentIdentity:
			return (component as PersistentIdentity).get_persistent_id()
	return &""


# --- Asking about others --------------------------------------------------

## How this entity behaves towards [param other].
##
## Personal standing first, then group politics: an entity's own reputation
## with a faction outranks that faction's opinion of its side.
func get_attitude_to(other: Node) -> AttitudeSolver.Attitude:
	if service == null or not has_faction() or other == null:
		return AttitudeSolver.Attitude.NEUTRAL
	var mark := find_on(other)
	if mark == null:
		return AttitudeSolver.Attitude.NEUTRAL

	# Recorded history only. Asking whether the standing is non-zero would
	# treat a faction's default standing as a personal opinion about everyone
	# who has never met it.
	var personal := mark.get_actor_id()
	if personal != &"" and service.has_reputation(_faction, personal):
		return service.resolve_attitude(_faction, personal)
	if mark.has_faction():
		return service.resolve_attitude(_faction, mark.get_faction())
	return AttitudeSolver.Attitude.NEUTRAL


func is_hostile_to(other: Node) -> bool:
	return AttitudeSolver.is_hostile(get_attitude_to(other))


func is_friendly_to(other: Node) -> bool:
	return AttitudeSolver.is_friendly(get_attitude_to(other))


## Records that [param actor] did something this entity's faction cares about.
## What a crime witness or a favour calls.
func report(actor_name: StringName, amount: float, spread: float = 0.5) -> void:
	if service == null or not has_faction() or actor_name == &"":
		return
	service.propagate_reputation(_faction, actor_name, amount, spread)


# --- Discovery ------------------------------------------------------------

static func find_on(node: Node) -> FactionComponent:
	if node == null:
		return null
	if node is FactionComponent:
		return node as FactionComponent
	for component in DefinitionBinder.collect_components(node):
		if component is FactionComponent:
			return component as FactionComponent
	return null


# --- Persistence ----------------------------------------------------------

func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	return {"faction": String(_faction)}


func restore_state(data: Dictionary) -> void:
	set_faction(StringName(data.get("faction", "")))


# --- Internals ------------------------------------------------------------

## Read by property name rather than by casting, so a vehicle or a turret with
## its own definition type can belong to a faction (rule 9). Accepts either a
## name or a whole definition, because content does both.
func _resolve_faction() -> StringName:
	if faction_override != &"":
		return faction_override
	var definition := get_definition()
	if definition == null or not "faction" in definition:
		return &""
	var candidate: Variant = definition.get("faction")
	if candidate is FactionDefinition:
		return (candidate as FactionDefinition).id
	if candidate is StringName or candidate is String:
		return StringName(candidate)
	return &""


func _resolve_service() -> FactionService:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_service"):
		return null
	return core.get_service(GameplayNames.SERVICE_FACTION) as FactionService
