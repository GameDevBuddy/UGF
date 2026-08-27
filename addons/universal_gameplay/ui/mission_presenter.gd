class_name MissionPresenter
extends Presenter
## Publishes active missions and their objectives as rows.
##
## A [FrameworkComponent] like every other presenter, even though what it
## watches is a service rather than a sibling. That keeps the family one shape:
## a HUD holds a handful of presenters and treats them identically, and none of
## them has a different lifecycle to remember.

## Live missions. Resolved from the core's registry when not wired.
@export var service: MissionService

## Whether to include objectives a mission has marked hidden. Off is the usual
## case: a hidden objective is hidden because showing it spoils something.
@export var include_hidden: bool = false


func observe() -> void:
	if service == null:
		service = _resolve_service()
	for signal_name in [
		&"mission_started", &"mission_completed", &"mission_failed",
		&"mission_abandoned",
	]:
		_watch(service, signal_name, _on_mission)
	for signal_name in [&"objective_completed", &"objective_progressed"]:
		_watch(service, signal_name, _on_objective)


func stop_observing() -> void:
	for signal_name in [
		&"mission_started", &"mission_completed", &"mission_failed",
		&"mission_abandoned",
	]:
		_unwatch(service, signal_name, _on_mission)
	for signal_name in [&"objective_completed", &"objective_progressed"]:
		_unwatch(service, signal_name, _on_objective)


func build() -> ViewModel:
	var model := MissionViewModel.new()
	if service == null:
		return model
	model.present = true
	model.completed = service.get_completed_ids()

	for runtime in service.get_active():
		var definition := runtime.definition
		model.missions.append({
			"mission_id": runtime.get_id(),
			"display_name": definition.display_name if definition != null else String(runtime.get_id()),
			"fraction": runtime.get_fraction(),
			"objectives": _build_objectives(runtime),
		})
	return model


# --- Internals ------------------------------------------------------------

func _build_objectives(runtime: MissionRuntime) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var objectives := (
		runtime.get_objectives() if include_hidden else runtime.get_visible_objectives()
	)
	for objective in objectives:
		rows.append({
			"objective_id": objective.get_id(),
			"text": objective.describe(),
			"progress": objective.progress,
			"target": objective.get_target(),
			"fraction": objective.get_fraction(),
			"complete": objective.is_complete(),
			"failed": objective.is_failed(),
			"optional": objective.is_optional(),
		})
	return rows


func _on_mission(_runtime: MissionRuntime) -> void:
	refresh()


func _on_objective(_runtime: MissionRuntime, _objective: ObjectiveRuntime) -> void:
	refresh()


func _resolve_service() -> MissionService:
	var context := get_context()
	var core := context.core if context != null else null
	if core == null or not core.has_method("get_service"):
		return null
	return core.get_service(GameplayNames.SERVICE_OBJECTIVE) as MissionService
