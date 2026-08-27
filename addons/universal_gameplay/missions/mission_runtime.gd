class_name MissionRuntime
extends RefCounted
## One mission, in progress.
##
## Holds the objectives' state, the mission's own local variables, and who it
## is for. A plain object, so a whole mission can be driven through a sequence
## of events in a unit test with no scene, no NPC and no bus (rule 33).
##
## [b]It reads events, not systems.[/b] Everything that reaches it arrives as a
## [FrameworkEvent] someone else published. That is the M9 exit gate: a mission
## reacting to combat, inventory and dialogue while importing none of them.

signal state_changed(state: State)
signal objective_progressed(objective: ObjectiveRuntime)
signal objective_completed(objective: ObjectiveRuntime)
signal objective_failed(objective: ObjectiveRuntime)
## Emitted when the mission ends, either way.
signal finished(state: State)

enum State {
	## Built but not started.
	INACTIVE,
	ACTIVE,
	COMPLETED,
	FAILED,
	## Given up on. Distinct from failed: a mission abandoned can usually be
	## taken again, and a failed one usually cannot.
	ABANDONED,
}

var definition: MissionDefinition = null
var state: State = State.INACTIVE

## Who the mission is for. Matchers use it to turn "a bandit died" into "you
## killed a bandit".
var subject: Node = null

## Narrative state rewards write to and prerequisites read from.
var narrative: NarrativeStateService = null

## The framework core, for a reward that has to resolve a definition by id.
var core: Node = null

## Values scoped to this mission: which of three targets was chosen, where the
## courier was intercepted. Saved with it.
var locals: Dictionary[StringName, Variant] = {}

var _objectives: Array[ObjectiveRuntime] = []


static func create(
	p_definition: MissionDefinition,
	p_subject: Node = null,
	p_narrative: NarrativeStateService = null,
	p_core: Node = null
) -> MissionRuntime:
	var runtime := MissionRuntime.new()
	runtime.definition = p_definition
	runtime.subject = p_subject
	runtime.narrative = p_narrative
	runtime.core = p_core
	runtime._build()
	return runtime


func get_id() -> StringName:
	return definition.id if definition != null else &""


func is_active() -> bool:
	return state == State.ACTIVE


func is_finished() -> bool:
	return state == State.COMPLETED or state == State.FAILED or state == State.ABANDONED


func get_objectives() -> Array[ObjectiveRuntime]:
	return _objectives.duplicate()


## The objectives a tracker should show: active ones, and finished ones that
## were never hidden.
func get_visible_objectives() -> Array[ObjectiveRuntime]:
	return _objectives.filter(
		func(objective: ObjectiveRuntime) -> bool:
			if objective.definition != null and objective.definition.hidden:
				return objective.is_active() or objective.is_finished()
			return true
	)


## Objectives being counted right now. For a sequential mission that is one.
func get_active_objectives() -> Array[ObjectiveRuntime]:
	return _objectives.filter(func(o: ObjectiveRuntime) -> bool: return o.is_active())


func get_objective(objective_id: StringName) -> ObjectiveRuntime:
	for objective in _objectives:
		if objective.get_id() == objective_id:
			return objective
	return null


## Progress across every required objective, in 0..1.
func get_fraction() -> float:
	var required := _objectives.filter(
		func(o: ObjectiveRuntime) -> bool: return not o.is_optional()
	)
	if required.is_empty():
		return 1.0
	var total := 0.0
	for objective in required:
		total += objective.get_fraction()
	return total / float(required.size())


## The subject's bag, for an item reward. Null is a normal answer.
func get_subject_inventory() -> InventoryComponent:
	if subject == null:
		return null
	for component in DefinitionBinder.collect_components(subject):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null


# --- Driving --------------------------------------------------------------

## Starts the mission and activates whichever objectives are open first.
func start() -> FrameworkResult:
	if definition == null:
		return FrameworkResult.fail(&"mission.no_definition", "There is no mission.")
	if state == State.ACTIVE:
		return FrameworkResult.fail(
			&"mission.already_active", "This mission is already running."
		)
	if _objectives.is_empty():
		_build()
	_set_state(State.ACTIVE)
	_activate_next()
	# A mission whose objectives were all optional, or all already satisfied,
	# completes immediately rather than sitting active with nothing to do.
	_check_completion()
	return FrameworkResult.ok(self)


## Offers an event to every active objective.
##
## Returns true when something changed, so a service can tell a relevant event
## from a passing one without re-walking the mission.
func handle(event: FrameworkEvent) -> bool:
	if not is_active() or event == null:
		return false
	var changed := false
	for objective in get_active_objectives():
		if objective.handle(event, subject):
			changed = true
	if changed:
		_after_change()
	return changed


## Advances timed objectives.
func tick(delta: float) -> bool:
	if not is_active() or delta <= 0.0:
		return false
	var changed := false
	for objective in get_active_objectives():
		if objective.tick(delta):
			changed = true
	if changed:
		_after_change()
	return changed


## Completes one objective outright. What a cutscene or a debug command calls.
func complete_objective(objective_id: StringName) -> FrameworkResult:
	var objective := get_objective(objective_id)
	if objective == null:
		return FrameworkResult.fail(
			&"mission.no_such_objective", "No objective '%s' here." % objective_id
		)
	if not objective.is_active():
		return FrameworkResult.fail(
			&"mission.objective_not_active", "That objective is not being counted."
		)
	objective.complete()
	_after_change()
	return FrameworkResult.ok(objective)


func complete() -> FrameworkResult:
	if is_finished():
		return FrameworkResult.fail(&"mission.finished", "This mission is over.")
	for objective in get_active_objectives():
		if not objective.is_optional():
			objective.complete()
	_set_state(State.COMPLETED)
	finished.emit(state)
	return FrameworkResult.ok(self)


func fail() -> FrameworkResult:
	if is_finished():
		return FrameworkResult.fail(&"mission.finished", "This mission is over.")
	_set_state(State.FAILED)
	finished.emit(state)
	return FrameworkResult.ok(self)


## Gives up on it. Distinct from failing: an abandoned mission can usually be
## taken again, and the distinction is one a quest log shows.
func abandon() -> FrameworkResult:
	if is_finished():
		return FrameworkResult.fail(&"mission.finished", "This mission is over.")
	_set_state(State.ABANDONED)
	finished.emit(state)
	return FrameworkResult.ok(self)


# --- Persistence ----------------------------------------------------------

func capture_state() -> Dictionary:
	var objectives: Array = []
	for objective in _objectives:
		objectives.append(objective.capture_state())
	var saved_locals: Dictionary = {}
	for key in locals:
		saved_locals[String(key)] = locals[key]
	return {
		"id": String(get_id()),
		"state": int(state),
		"objectives": objectives,
		"locals": saved_locals,
	}


func restore_state(data: Dictionary) -> void:
	state = data.get("state", State.INACTIVE) as State
	locals.clear()
	for key in data.get("locals", {}):
		locals[StringName(key)] = data["locals"][key]
	# Matched by id rather than by index, so a mission whose objectives were
	# reordered or extended between versions restores what it can instead of
	# restoring the wrong progress onto the wrong objective.
	for saved in data.get("objectives", []):
		var objective := get_objective(StringName(saved.get("id", "")))
		if objective != null:
			objective.restore_state(saved)


# --- Internals ------------------------------------------------------------

func _build() -> void:
	_objectives.clear()
	if definition == null:
		return
	for objective_definition in definition.objectives:
		if objective_definition == null:
			continue
		var objective := ObjectiveRuntime.create(objective_definition)
		objective.progressed.connect(_on_progressed)
		objective.completed.connect(_on_completed)
		objective.failed.connect(_on_failed)
		_objectives.append(objective)


## Activates whatever should be counting now. All of them at once, or the next
## one in order for a sequential mission.
func _activate_next() -> void:
	if definition == null:
		return
	if not definition.sequential:
		for objective in _objectives:
			objective.activate()
		return
	for objective in _objectives:
		if objective.is_finished():
			continue
		objective.activate()
		return


func _after_change() -> void:
	if definition != null and definition.sequential:
		_activate_next()
	_check_failure()
	if not is_finished():
		_check_completion()


## A failed required objective fails the mission. An optional one does not,
## which is the whole meaning of optional.
func _check_failure() -> void:
	for objective in _objectives:
		if objective.is_failed() and not objective.is_optional():
			fail()
			return


func _check_completion() -> void:
	if definition == null or not definition.completes_automatically:
		return
	for objective in _objectives:
		if not objective.is_optional() and not objective.is_complete():
			return
	complete()


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(state)


func _on_progressed(objective: ObjectiveRuntime) -> void:
	objective_progressed.emit(objective)


func _on_completed(objective: ObjectiveRuntime) -> void:
	objective_completed.emit(objective)


func _on_failed(objective: ObjectiveRuntime) -> void:
	objective_failed.emit(objective)


func _to_string() -> String:
	return "MissionRuntime(%s %s %.0f%%)" % [
		get_id(), State.keys()[state], get_fraction() * 100.0
	]
