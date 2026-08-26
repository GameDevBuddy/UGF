class_name SemanticState
extends FrameworkComponent
## Runtime semantic state tags for an entity.
##
## The vocabulary is [StringName] constants from [GameplayNames]:
## [code]state.dead[/code], [code]state.movement.sprinting[/code]. This is the
## data-side counterpart to a SceneTree group -- membership here means
## something is true about the entity, not that it is discoverable by a tree
## scan (Ontology Rulebook 12).
##
## What this is [b]not[/b] is an authority. A state tag mirrors a fact some
## component already owns: HealthComponent owns whether an entity is dead, and
## sets [code]state.dead[/code] to advertise it. Rule 4 still applies, and
## reading a tag is never a substitute for asking the owner.

signal state_added(state: StringName)
signal state_removed(state: StringName)

var _states: Dictionary[StringName, bool] = {}


## Returns true if the state was newly added.
func add_state(state: StringName) -> bool:
	if state == &"" or _states.has(state):
		return false
	_states[state] = true
	state_added.emit(state)
	return true


## Returns true if the state was present and removed.
func remove_state(state: StringName) -> bool:
	if not _states.erase(state):
		return false
	state_removed.emit(state)
	return true


## Adds or removes according to [param active]. Returns true if anything
## changed.
func set_state(state: StringName, active: bool) -> bool:
	return add_state(state) if active else remove_state(state)


func has_state(state: StringName) -> bool:
	return _states.has(state)


func has_all_states(required: Array[StringName]) -> bool:
	for state in required:
		if not _states.has(state):
			return false
	return true


func has_any_state(any_of: Array[StringName]) -> bool:
	for state in any_of:
		if _states.has(state):
			return true
	return false


func get_states() -> Array[StringName]:
	var states: Array[StringName] = []
	states.assign(_states.keys())
	return states


func clear_states() -> void:
	for state in get_states():
		remove_state(state)


func is_persistent() -> bool:
	return true


func capture_state() -> Dictionary:
	return {"states": get_states()}


func restore_state(data: Dictionary) -> void:
	clear_states()
	for state in data.get("states", []):
		add_state(StringName(state))
