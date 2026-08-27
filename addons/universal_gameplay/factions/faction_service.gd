class_name FactionService
extends FrameworkService
## Who feels what about whom, and what that means.
##
## Two distinct questions live here and it is worth keeping them apart:
## [b]relation[/b] is how one faction feels about another, and
## [b]reputation[/b] is how a faction feels about one particular actor. A
## bandit clan's opinion of the town watch is a relation; its opinion of the
## player who has been robbing it is a reputation, and the two move
## independently.
##
## [b]Everything is named, never referenced.[/b] Factions and actors are
## [StringName] ids, so standing survives the entity it describes: how the town
## watch feels about the player outlives every individual guard (rule 32).

## Emitted when one faction's view of another changes.
signal relation_changed(subject: StringName, other: StringName, value: float)
## Emitted when a faction's view of one actor changes.
signal reputation_changed(faction: StringName, actor: StringName, value: float)
## Emitted when a change crosses a band boundary -- neutral to hostile, wary to
## friendly. What an adapter listens to rather than re-resolving every frame.
signal attitude_changed(
	faction: StringName, other: StringName, attitude: AttitudeSolver.Attitude
)

@export var minimum: float = -100.0
@export var maximum: float = 100.0

var _definitions: Dictionary[StringName, FactionDefinition] = {}
var _relations: Dictionary[StringName, float] = {}
var _reputations: Dictionary[StringName, float] = {}


func get_service_id() -> StringName:
	return GameplayNames.SERVICE_FACTION


# --- Definitions ----------------------------------------------------------

## Registers a faction so its thresholds and authored relations can be read.
##
## Kept here rather than read from the definition registry on every query: an
## attitude is resolved often enough that a dictionary lookup beats a registry
## round trip, and a project that never registers one still gets neutral
## answers rather than errors (rule 31).
func register(definition: FactionDefinition) -> FrameworkResult:
	if definition == null or definition.id == &"":
		return FrameworkResult.fail(
			&"faction.invalid", "A faction needs an id to be registered."
		)
	_definitions[definition.id] = definition
	return FrameworkResult.ok(definition)


func register_all(definitions: Array) -> void:
	for definition in definitions:
		if definition is FactionDefinition:
			register(definition as FactionDefinition)


func get_definition(faction: StringName) -> FactionDefinition:
	return _definitions.get(faction)


func has_faction(faction: StringName) -> bool:
	return _definitions.has(faction)


func get_faction_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_definitions.keys())
	return ids


# --- Relations ------------------------------------------------------------

## How [param subject] feels about [param other]. Falls back to the authored
## default, then to neutral.
func get_relation(subject: StringName, other: StringName) -> float:
	var key := _pair(subject, other)
	if _relations.has(key):
		return _relations[key]
	var definition := get_definition(subject)
	return definition.get_default_relation(other) if definition != null else 0.0


func set_relation(subject: StringName, other: StringName, value: float) -> void:
	if subject == &"" or other == &"":
		return
	var before := resolve_attitude(subject, other)
	var clamped := clampf(value, minimum, maximum)
	if is_equal_approx(get_relation(subject, other), clamped):
		return
	_relations[_pair(subject, other)] = clamped
	relation_changed.emit(subject, other, clamped)
	_announce_attitude(subject, other, before)


## Adjusts a relation and returns the new value.
func modify_relation(subject: StringName, other: StringName, amount: float) -> float:
	set_relation(subject, other, get_relation(subject, other) + amount)
	return get_relation(subject, other)


# --- Reputation -----------------------------------------------------------

## How [param faction] feels about one actor. Starts from the faction's
## default standing.
func get_reputation(faction: StringName, actor: StringName) -> float:
	var key := _pair(faction, actor)
	if _reputations.has(key):
		return _reputations[key]
	var definition := get_definition(faction)
	return definition.default_standing if definition != null else 0.0


func set_reputation(faction: StringName, actor: StringName, value: float) -> void:
	if faction == &"" or actor == &"":
		return
	var before := resolve_attitude(faction, actor)
	var clamped := clampf(value, minimum, maximum)
	if is_equal_approx(get_reputation(faction, actor), clamped):
		return
	_reputations[_pair(faction, actor)] = clamped
	reputation_changed.emit(faction, actor, clamped)
	_announce_attitude(faction, actor, before)


## Whether a reputation has actually been recorded for this pair, as opposed
## to being answered from the faction's default standing.
##
## The distinction matters: a faction whose default standing is non-zero would
## otherwise make every actor in the world look personally known, and personal
## history is supposed to outrank group politics only when there is some.
func has_reputation(faction: StringName, actor: StringName) -> bool:
	return _reputations.has(_pair(faction, actor))


func has_relation(subject: StringName, other: StringName) -> bool:
	return _relations.has(_pair(subject, other))


func modify_reputation(faction: StringName, actor: StringName, amount: float) -> float:
	set_reputation(faction, actor, get_reputation(faction, actor) + amount)
	return get_reputation(faction, actor)


## Applies a change to every faction that cares about the one wronged.
##
## Robbing the watch should cost you with the watch's allies too, and having a
## project write that fan-out by hand is how one faction ends up forgotten.
## Spread is proportional to how much each faction likes the wronged one, so a
## faction that is indifferent shrugs.
func propagate_reputation(
	faction: StringName, actor: StringName, amount: float, spread: float = 0.5
) -> void:
	modify_reputation(faction, actor, amount)
	if spread <= 0.0:
		return
	for other in get_faction_ids():
		if other == faction:
			continue
		var sympathy := get_relation(other, faction) / maxf(1.0, maximum)
		if is_zero_approx(sympathy):
			continue
		modify_reputation(other, actor, amount * sympathy * spread)


# --- Attitude -------------------------------------------------------------

## How [param subject] behaves towards [param other], whether [param other] is
## a faction or an actor.
##
## One call for both because the caller usually does not know: an AI asking
## about the thing it just noticed does not care whether the answer came from
## a faction relation or from a personal grudge.
func resolve_attitude(
	subject: StringName, other: StringName
) -> AttitudeSolver.Attitude:
	var definition := get_definition(subject)
	if definition == null:
		return AttitudeSolver.Attitude.NEUTRAL
	return definition.resolve_attitude(get_standing(subject, other))


## The number behind an attitude: a reputation when one has been recorded, and
## the faction relation otherwise.
##
## Personal history wins over group politics. A bandit clan that hates the
## watch still tolerates the one guard who has been paying them.
func get_standing(subject: StringName, other: StringName) -> float:
	if _reputations.has(_pair(subject, other)):
		return _reputations[_pair(subject, other)]
	if _relations.has(_pair(subject, other)) or has_faction(other):
		return get_relation(subject, other)
	return get_reputation(subject, other)


func is_hostile(subject: StringName, other: StringName) -> bool:
	return AttitudeSolver.is_hostile(resolve_attitude(subject, other))


func is_friendly(subject: StringName, other: StringName) -> bool:
	return AttitudeSolver.is_friendly(resolve_attitude(subject, other))


# --- Bulk -----------------------------------------------------------------

func reset() -> void:
	_relations.clear()
	_reputations.clear()


## Forgets registered factions as well. What unloading the module does.
func clear() -> void:
	reset()
	_definitions.clear()


# --- Persistence ----------------------------------------------------------
#
# Live standing survives; the definitions do not, because they are content
# reloaded from disk rather than state.

func capture_state() -> Dictionary:
	return {
		"relations": _stringify(_relations),
		"reputations": _stringify(_reputations),
	}


func restore_state(data: Dictionary) -> void:
	reset()
	for key in data.get("relations", {}):
		_relations[StringName(key)] = float(data["relations"][key])
	for key in data.get("reputations", {}):
		_reputations[StringName(key)] = float(data["reputations"][key])


# --- Internals ------------------------------------------------------------

## Directional on purpose. The watch hating bandits does not make bandits hate
## the watch by the same amount.
func _pair(subject: StringName, other: StringName) -> StringName:
	return StringName("%s>%s" % [subject, other])


## Announces only band crossings, so an adapter re-evaluates when behaviour
## would change rather than on every point of standing.
func _announce_attitude(
	subject: StringName, other: StringName, before: AttitudeSolver.Attitude
) -> void:
	var after := resolve_attitude(subject, other)
	if after != before:
		attitude_changed.emit(subject, other, after)


func _stringify(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in source:
		out[String(key)] = source[key]
	return out
