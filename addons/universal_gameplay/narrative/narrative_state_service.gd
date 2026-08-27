class_name NarrativeStateService
extends FrameworkService
## Everything the story remembers: flags, variables, counters and standing.
##
## A service rather than a component, because narrative state is the one kind
## of state that genuinely outlives every entity holding it. The quest flag
## that says the mayor is dead has to survive the mayor (Ontology Rulebook,
## services layer).
##
## [b]Four kinds of state, not one dictionary.[/b] A flag is a fact that either
## happened or did not; a variable is a value; a counter is a tally; a
## relationship is how two named parties feel about each other. Collapsing them
## into one bag makes every consumer parse conventions out of key names, and
## makes "how many bandits has the player killed" and "is the gate open"
## indistinguishable to a save migration.
##
## [b]It knows nothing about dialogue.[/b] Missions, world state, crime and
## commerce all read and write here, and none of them should have to depend on
## Dialogue to do it (rule 9).

## Emitted when a flag is raised or cleared.
signal flag_changed(flag: StringName, value: bool)
## Emitted when a variable is set, with its previous value for undo and debug.
signal variable_changed(key: StringName, value: Variant, previous: Variant)
signal counter_changed(counter: StringName, value: int, previous: int)
signal relationship_changed(subject: StringName, other: StringName, value: float)
## Emitted when everything is cleared, so caches downstream can drop.
signal narrative_reset

## Lower bound on relationship values. Standing is a scale, not an integer, and
## clamping it here stops one enthusiastic action from putting a faction
## permanently out of reach.
@export var relationship_minimum: float = -100.0
@export var relationship_maximum: float = 100.0

var _flags: Dictionary[StringName, bool] = {}
var _variables: Dictionary[StringName, Variant] = {}
var _counters: Dictionary[StringName, int] = {}
var _relationships: Dictionary[StringName, float] = {}


func get_service_id() -> StringName:
	return GameplayNames.SERVICE_NARRATIVE


# --- Flags ----------------------------------------------------------------

## Whether [param flag] is raised. Unknown flags are false, which is what makes
## a save written before a flag existed load cleanly.
func get_flag(flag: StringName) -> bool:
	return _flags.get(flag, false)


## Returns true when the value actually changed.
func set_flag(flag: StringName, value: bool = true) -> bool:
	if flag == &"" or get_flag(flag) == value:
		return false
	if value:
		_flags[flag] = true
	else:
		_flags.erase(flag)
	flag_changed.emit(flag, value)
	return true


func clear_flag(flag: StringName) -> bool:
	return set_flag(flag, false)


func get_raised_flags() -> Array[StringName]:
	var raised: Array[StringName] = []
	raised.assign(_flags.keys())
	return raised


func has_all_flags(required: Array[StringName]) -> bool:
	for flag in required:
		if not get_flag(flag):
			return false
	return true


func has_any_flag(any_of: Array[StringName]) -> bool:
	for flag in any_of:
		if get_flag(flag):
			return true
	return false


# --- Variables ------------------------------------------------------------

## A named value. [param fallback] is returned for anything never set, so
## content can read a variable a previous playthrough never wrote.
func get_variable(key: StringName, fallback: Variant = null) -> Variant:
	return _variables.get(key, fallback)


func set_variable(key: StringName, value: Variant) -> void:
	if key == &"":
		return
	var previous: Variant = _variables.get(key)
	if previous != null and typeof(previous) == typeof(value) and previous == value:
		return
	_variables[key] = value
	variable_changed.emit(key, value, previous)


func has_variable(key: StringName) -> bool:
	return _variables.has(key)


func clear_variable(key: StringName) -> bool:
	if not _variables.has(key):
		return false
	var previous: Variant = _variables[key]
	_variables.erase(key)
	variable_changed.emit(key, null, previous)
	return true


func get_variable_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	keys.assign(_variables.keys())
	return keys


# --- Counters -------------------------------------------------------------

func get_counter(counter: StringName) -> int:
	return _counters.get(counter, 0)


## Adds to a counter and returns its new value. Negative amounts subtract; a
## counter is a tally, not a resource, so it is not clamped at zero.
func increment(counter: StringName, amount: int = 1) -> int:
	if counter == &"" or amount == 0:
		return get_counter(counter)
	var previous := get_counter(counter)
	var value := previous + amount
	_counters[counter] = value
	counter_changed.emit(counter, value, previous)
	return value


func set_counter(counter: StringName, value: int) -> void:
	if counter == &"":
		return
	var previous := get_counter(counter)
	if previous == value:
		return
	_counters[counter] = value
	counter_changed.emit(counter, value, previous)


func get_counter_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	keys.assign(_counters.keys())
	return keys


# --- Relationships --------------------------------------------------------
#
# Named parties rather than entity references, so standing survives the entity
# it describes: how the town guard feels about the player outlives every
# individual guard (rule 32).

## How [param subject] feels about [param other]. Zero is neutral and is the
## answer for any pair never set.
func get_relationship(subject: StringName, other: StringName) -> float:
	return _relationships.get(_pair(subject, other), 0.0)


func set_relationship(subject: StringName, other: StringName, value: float) -> void:
	if subject == &"" or other == &"":
		return
	var clamped := clampf(value, relationship_minimum, relationship_maximum)
	var key := _pair(subject, other)
	if is_equal_approx(_relationships.get(key, 0.0), clamped):
		return
	_relationships[key] = clamped
	relationship_changed.emit(subject, other, clamped)


## Adjusts standing and returns the new value.
func modify_relationship(subject: StringName, other: StringName, amount: float) -> float:
	set_relationship(subject, other, get_relationship(subject, other) + amount)
	return get_relationship(subject, other)


## Directional on purpose. A player may be loved by one faction and hunted by
## another for the same act, and a symmetric store cannot say that.
func _pair(subject: StringName, other: StringName) -> StringName:
	return StringName("%s>%s" % [subject, other])


# --- Bulk -----------------------------------------------------------------

func is_empty() -> bool:
	return (
		_flags.is_empty()
		and _variables.is_empty()
		and _counters.is_empty()
		and _relationships.is_empty()
	)


## Wipes everything. What starting a new game does.
func reset() -> void:
	_flags.clear()
	_variables.clear()
	_counters.clear()
	_relationships.clear()
	narrative_reset.emit()


# --- Persistence ----------------------------------------------------------
#
# All of it survives, and it is the part of a save a player would most notice
# losing. Keys are stored as plain strings so the record is readable and
# portable rather than depending on StringName serialisation.

func capture_state() -> Dictionary:
	return {
		"flags": get_raised_flags().map(func(f: StringName) -> String: return String(f)),
		"variables": _stringify(_variables),
		"counters": _stringify(_counters),
		"relationships": _stringify(_relationships),
	}


func restore_state(data: Dictionary) -> void:
	reset()
	for flag in data.get("flags", []):
		_flags[StringName(flag)] = true
	for key in data.get("variables", {}):
		_variables[StringName(key)] = data["variables"][key]
	for key in data.get("counters", {}):
		_counters[StringName(key)] = int(data["counters"][key])
	for key in data.get("relationships", {}):
		_relationships[StringName(key)] = float(data["relationships"][key])


func _stringify(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in source:
		out[String(key)] = source[key]
	return out
