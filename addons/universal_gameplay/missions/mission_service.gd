class_name MissionService
extends FrameworkService
## Owns every mission in flight, and is the only thing listening to the bus.
##
## [b]One subscription, not one per objective.[/b] It listens to
## [signal EventBus.event_published] -- the firehose -- and offers each event
## to every active mission. Subscribing per event name would mean
## subscribing and unsubscribing as objectives activate, which is more moving
## parts and one more thing to leak.
##
## [b]It publishes mission facts itself.[/b] Elsewhere the framework puts bus
## publication in a deletable adapter on an entity, because "is this death
## worth telling the game about?" is per-entity data. A mission has no entity
## and the answer is always yes: a completed mission is precisely the kind of
## cross-feature fact the bus exists for (rule 6). The adapters stay where
## there is an entity to hang a decision on.

signal mission_started(runtime: MissionRuntime)
signal mission_completed(runtime: MissionRuntime)
signal mission_failed(runtime: MissionRuntime)
signal mission_abandoned(runtime: MissionRuntime)
signal objective_completed(runtime: MissionRuntime, objective: ObjectiveRuntime)
signal objective_progressed(runtime: MissionRuntime, objective: ObjectiveRuntime)

const CompletedEvent := preload(
	"res://addons/universal_gameplay/missions/mission_event.gd"
)

## Who missions are for by default. Set once when the player spawns rather
## than passed to every call.
var default_subject: Node = null

var _bus: Node = null
var _narrative: NarrativeStateService = null
var _core: Node = null
var _active: Array[MissionRuntime] = []
var _completed: Dictionary[StringName, bool] = {}
var _failed: Dictionary[StringName, bool] = {}


func get_service_id() -> StringName:
	return GameplayNames.SERVICE_OBJECTIVE


## Wires the service to the rest of the framework. Everything it needs arrives
## here rather than being looked up (rule 20).
func configure(
	core: Node = null,
	bus: Node = null,
	narrative: NarrativeStateService = null
) -> void:
	_core = core
	_narrative = narrative
	set_bus(bus)


func set_bus(bus: Node) -> void:
	if _bus == bus:
		return
	if _bus != null and _bus.has_signal("event_published"):
		if _bus.is_connected("event_published", _on_event):
			_bus.disconnect("event_published", _on_event)
	_bus = bus
	if _bus == null:
		return
	if _bus.has_signal("event_published") and not _bus.is_connected("event_published", _on_event):
		_bus.connect("event_published", _on_event)
	if _bus.has_method("register_event"):
		_bus.call("register_event", GameplayNames.EVENT_MISSION_STARTED)
		_bus.call("register_event", GameplayNames.EVENT_MISSION_COMPLETED)
		_bus.call("register_event", GameplayNames.EVENT_MISSION_FAILED)
		_bus.call("register_event", GameplayNames.EVENT_OBJECTIVE_COMPLETED)


func set_narrative(narrative: NarrativeStateService) -> void:
	_narrative = narrative


func get_bus() -> Node:
	return _bus


func service_stopped() -> void:
	set_bus(null)


# --- Queries --------------------------------------------------------------

func get_active() -> Array[MissionRuntime]:
	return _active.duplicate()


func get_runtime(mission_id: StringName) -> MissionRuntime:
	for runtime in _active:
		if runtime.get_id() == mission_id:
			return runtime
	return null


func is_active(mission_id: StringName) -> bool:
	return get_runtime(mission_id) != null


func has_completed(mission_id: StringName) -> bool:
	return _completed.get(mission_id, false)


func has_failed(mission_id: StringName) -> bool:
	return _failed.get(mission_id, false)


func get_completed_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_completed.keys())
	return ids


## Whether [param definition] could be started right now.
func can_start(definition: MissionDefinition) -> FrameworkResult:
	if definition == null:
		return FrameworkResult.fail(&"mission.no_definition", "There is no mission.")
	if is_active(definition.id):
		return FrameworkResult.fail(
			&"mission.already_active", "That mission is already under way."
		)
	if has_completed(definition.id) and not definition.repeatable:
		return FrameworkResult.fail(
			&"mission.already_completed", "That mission has already been done."
		)
	if not definition.is_available(_narrative, get_completed_ids()):
		return FrameworkResult.fail(
			&"mission.unavailable", "Its prerequisites are not met."
		)
	return FrameworkResult.ok(definition)


# --- Driving --------------------------------------------------------------

## Starts a mission for [param subject], or for the default subject.
func start(
	definition: MissionDefinition, subject: Node = null
) -> FrameworkResult:
	var allowed := can_start(definition)
	if allowed.is_err():
		return allowed

	var runtime := MissionRuntime.create(
		definition, subject if subject != null else default_subject, _narrative, _core
	)
	runtime.objective_completed.connect(_on_objective_completed.bind(runtime))
	runtime.objective_progressed.connect(_on_objective_progressed.bind(runtime))
	runtime.finished.connect(_on_finished.bind(runtime))
	_active.append(runtime)

	var started := runtime.start()
	if started.is_err():
		_active.erase(runtime)
		return started

	mission_started.emit(runtime)
	_publish(GameplayNames.EVENT_MISSION_STARTED, runtime, null)
	return FrameworkResult.ok(runtime)


## Starts a mission by id, resolving it through the definition registry.
func start_by_id(mission_id: StringName, subject: Node = null) -> FrameworkResult:
	if _core == null or not _core.has_method("get_definition"):
		return FrameworkResult.fail(
			&"mission.no_registry", "There is no definition registry to look in."
		)
	var definition := _core.call("get_definition", mission_id) as MissionDefinition
	if definition == null:
		return FrameworkResult.fail(
			&"mission.unknown", "No mission is registered as '%s'." % mission_id
		)
	return start(definition, subject)


func abandon(mission_id: StringName) -> FrameworkResult:
	var runtime := get_runtime(mission_id)
	if runtime == null:
		return FrameworkResult.fail(
			&"mission.not_active", "That mission is not under way."
		)
	return runtime.abandon()


## Advances timed objectives across every active mission. Called from a
## project's own tick, or from a [SceneTree] timer -- the service does not
## process on its own, because most frames have nothing timed running
## (rule 26).
func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	for runtime in get_active():
		runtime.tick(delta)


## Offers an event to every active mission. Called by the bus subscription;
## public so a project driving its own event flow can push one in.
func handle(event: FrameworkEvent) -> void:
	if event == null:
		return
	for runtime in get_active():
		runtime.handle(event)


# --- Persistence ----------------------------------------------------------
#
# Everything: what is under way, how far along, and what has already been
# done. A quest log that forgot itself across a save is the single most
# noticeable thing a save can get wrong.

func capture_state() -> Dictionary:
	var missions: Array = []
	for runtime in _active:
		missions.append(runtime.capture_state())
	return {
		"active": missions,
		"completed": _completed.keys().map(func(k: StringName) -> String: return String(k)),
		"failed": _failed.keys().map(func(k: StringName) -> String: return String(k)),
	}


## Restores from a save. Definitions are re-resolved by id through the
## registry, so a mission record outlives the resource being moved on disk.
func restore_state(data: Dictionary) -> void:
	_active.clear()
	_completed.clear()
	_failed.clear()
	for key in data.get("completed", []):
		_completed[StringName(key)] = true
	for key in data.get("failed", []):
		_failed[StringName(key)] = true

	for saved in data.get("active", []):
		var mission_id := StringName(saved.get("id", ""))
		if _core == null or not _core.has_method("get_definition"):
			continue
		var definition := _core.call("get_definition", mission_id) as MissionDefinition
		if definition == null:
			# Content that no longer exists. Dropping the record beats
			# restoring a mission with no objectives that can never complete.
			push_warning(
				"MissionService: save names mission '%s', which is not registered." % mission_id
			)
			continue
		var runtime := MissionRuntime.create(definition, default_subject, _narrative, _core)
		runtime.restore_state(saved)
		runtime.objective_completed.connect(_on_objective_completed.bind(runtime))
		runtime.objective_progressed.connect(_on_objective_progressed.bind(runtime))
		runtime.finished.connect(_on_finished.bind(runtime))
		_active.append(runtime)


# --- Internals ------------------------------------------------------------

func _on_event(event: FrameworkEvent) -> void:
	handle(event)


func _on_objective_progressed(
	objective: ObjectiveRuntime, runtime: MissionRuntime
) -> void:
	objective_progressed.emit(runtime, objective)


func _on_objective_completed(
	objective: ObjectiveRuntime, runtime: MissionRuntime
) -> void:
	objective_completed.emit(runtime, objective)
	_publish(GameplayNames.EVENT_OBJECTIVE_COMPLETED, runtime, objective)


func _on_finished(state: MissionRuntime.State, runtime: MissionRuntime) -> void:
	_active.erase(runtime)
	match state:
		MissionRuntime.State.COMPLETED:
			_completed[runtime.get_id()] = true
			MissionReward.grant_all(runtime.definition.rewards, runtime)
			mission_completed.emit(runtime)
			_publish(GameplayNames.EVENT_MISSION_COMPLETED, runtime, null)
		MissionRuntime.State.FAILED:
			_failed[runtime.get_id()] = true
			mission_failed.emit(runtime)
			_publish(GameplayNames.EVENT_MISSION_FAILED, runtime, null)
		MissionRuntime.State.ABANDONED:
			mission_abandoned.emit(runtime)


func _publish(
	event_name: StringName, runtime: MissionRuntime, objective: ObjectiveRuntime
) -> void:
	if _bus == null or not _bus.has_method("publish"):
		return
	_bus.call(
		"publish",
		CompletedEvent.create(
			event_name,
			runtime.get_id(),
			objective.get_id() if objective != null else &"",
			runtime.subject
		)
	)
