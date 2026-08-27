class_name MissionsDebugCommands
extends DebugCommandPack
## The plan's "start mission" cheat, plus the two that make it useful.
##
## Starting a mission you cannot finish is a cheat that wastes the tester's
## time, so [code]complete[/code] is here too: the point of a debug console is
## to get to the state under test, and half a mission chain is not a state.

var _missions: MissionService = null


func _init(missions: MissionService = null) -> void:
	_missions = missions


func set_service(missions: MissionService) -> void:
	_missions = missions


func build_commands() -> Array[DebugCommand]:
	return [
		DebugCommand.create(
			&"mission", _start, "Start a mission by id.", "<mission_id>", true
		),
		DebugCommand.create(
			&"complete", _complete, "Complete an active mission's objective.",
			"<mission_id> [objective_id]", true
		),
		DebugCommand.create(
			&"missions", _list, "List active missions and their progress.", "", false
		),
	] as Array[DebugCommand]


func _start(arguments: PackedStringArray) -> FrameworkResult:
	if _missions == null:
		return refuse("No mission service set.")
	if arguments.is_empty():
		return refuse("Usage: mission <mission_id>")
	return _missions.start_by_id(StringName(arguments[0]))


func _complete(arguments: PackedStringArray) -> FrameworkResult:
	if _missions == null:
		return refuse("No mission service set.")
	if arguments.is_empty():
		return refuse("Usage: complete <mission_id> [objective_id]")

	var mission_id := StringName(arguments[0])
	var runtime := _missions.get_runtime(mission_id)
	if runtime == null:
		return refuse("Mission '%s' is not active." % mission_id)

	if arguments.size() > 1:
		return runtime.complete_objective(StringName(arguments[1]))

	# No objective named: finish whatever is currently active, which is what
	# somebody typing "complete" while staring at a stuck quest actually wants.
	var active := runtime.get_active_objectives()
	if active.is_empty():
		return runtime.complete()
	for objective in active:
		runtime.complete_objective(objective.get_id())
	return FrameworkResult.ok("Completed %d objective(s)." % active.size())


func _list(_arguments: PackedStringArray) -> FrameworkResult:
	if _missions == null:
		return refuse("No mission service set.")
	var lines: Array[String] = []
	for runtime in _missions.get_active():
		lines.append("%s  %.0f%%" % [runtime.get_id(), runtime.get_fraction() * 100.0])
	if lines.is_empty():
		return FrameworkResult.ok("No active missions.")
	return FrameworkResult.ok("\n".join(lines))
