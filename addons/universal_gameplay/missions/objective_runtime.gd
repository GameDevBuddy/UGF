class_name ObjectiveRuntime
extends RefCounted
## One objective, in progress.
##
## A plain object rather than a node: a whole mission can be driven through a
## sequence of events in a unit test with no scene (rule 33). The definition
## says what is asked; this holds how far along it is.

## Emitted when progress changes without completing.
signal progressed(objective: ObjectiveRuntime)
signal completed(objective: ObjectiveRuntime)
signal failed(objective: ObjectiveRuntime)

enum Status {
	## Not yet started. A sequential mission's later objectives sit here.
	INACTIVE,
	## Counting.
	ACTIVE,
	COMPLETED,
	FAILED,
}

var definition: ObjectiveDefinition = null
var status: Status = Status.INACTIVE

## Occurrences counted, or seconds elapsed for a timed objective.
var progress: float = 0.0


static func create(p_definition: ObjectiveDefinition) -> ObjectiveRuntime:
	var runtime := ObjectiveRuntime.new()
	runtime.definition = p_definition
	return runtime


func get_id() -> StringName:
	return definition.id if definition != null else &""


func is_active() -> bool:
	return status == Status.ACTIVE


func is_complete() -> bool:
	return status == Status.COMPLETED


func is_failed() -> bool:
	return status == Status.FAILED


func is_finished() -> bool:
	return status == Status.COMPLETED or status == Status.FAILED


func is_optional() -> bool:
	return definition != null and definition.optional


## What is still needed: occurrences remaining, or seconds remaining.
func get_remaining() -> float:
	return maxf(0.0, get_target() - progress)


func get_target() -> float:
	if definition == null:
		return 0.0
	return definition.duration if definition.is_timed() else float(definition.required_count)


## Progress in 0..1, for a tracker bar.
func get_fraction() -> float:
	var target := get_target()
	if target <= 0.0:
		return 1.0 if is_complete() else 0.0
	return clampf(progress / target, 0.0, 1.0)


## Player-facing line with its count: "Kill bandits (3/5)".
func describe() -> String:
	if definition == null:
		return ""
	var text := definition.get_description()
	if definition.is_timed():
		return "%s (%.0fs)" % [text, get_remaining()]
	if definition.required_count > 1:
		return "%s (%d/%d)" % [text, int(progress), definition.required_count]
	return text


# --- Driving --------------------------------------------------------------

func activate() -> void:
	if status != Status.INACTIVE:
		return
	status = Status.ACTIVE


## Offers an event. Returns true when it changed anything, so a mission can
## tell a relevant event from a passing one without re-checking.
##
## Failure is checked first: an event that both counts and fails is a
## contradiction in content, and failing is the safer reading.
func handle(event: FrameworkEvent, subject: Node = null) -> bool:
	if not is_active() or definition == null:
		return false
	if definition.matches_failure(event, subject):
		fail()
		return true
	if definition.is_timed() or not definition.matches(event, subject):
		return false
	return advance(float(definition.get_count_for(event)))


## Advances a timed objective. Ignored by counted ones.
func tick(delta: float) -> bool:
	if not is_active() or definition == null or not definition.is_timed():
		return false
	return advance(delta)


## Adds to progress directly. What a scripted objective a cutscene completes
## calls, and what every other path here funnels through.
func advance(amount: float = 1.0) -> bool:
	if not is_active() or amount <= 0.0:
		return false
	progress += amount
	if progress >= get_target():
		progress = get_target()
		status = Status.COMPLETED
		completed.emit(self)
		return true
	progressed.emit(self)
	return true


func complete() -> void:
	if is_finished():
		return
	status = Status.COMPLETED
	progress = get_target()
	completed.emit(self)


func fail() -> void:
	if is_finished():
		return
	status = Status.FAILED
	failed.emit(self)


func reset() -> void:
	status = Status.INACTIVE
	progress = 0.0


# --- Persistence ----------------------------------------------------------

func capture_state() -> Dictionary:
	return {"id": String(get_id()), "status": int(status), "progress": progress}


func restore_state(data: Dictionary) -> void:
	status = data.get("status", Status.INACTIVE) as Status
	progress = float(data.get("progress", 0.0))


func _to_string() -> String:
	return "ObjectiveRuntime(%s %s %.0f/%.0f)" % [
		get_id(), Status.keys()[status], progress, get_target()
	]
