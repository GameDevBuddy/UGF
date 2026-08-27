class_name MissionAction
extends DialogueAction
## Starts, completes or abandons a mission from a conversation.
##
## The quest-giver verb. Implementation Plan 18 lists mission hooks as one of
## the pieces a quest giver is made of, and a conversation that could only set
## a flag left every project writing the same flag-watching adapter.
##
## [b]It names a service, not a mission runtime.[/b] The service is found
## through the framework's own registry and duck-typed, so Dialogue compiles
## and runs in a project with Missions deleted -- the action simply reports
## that there is nothing to start (rule 10, rule 31).

enum Operation {
	START,
	COMPLETE,
	ABANDON,
}

@export var operation: Operation = Operation.START

@export var mission_id: StringName = &""


func execute(context: DialogueContext) -> FrameworkResult:
	if mission_id == &"":
		return FrameworkResult.fail(
			&"dialogue.no_mission", "This action names no mission."
		)
	var service := _missions(context)
	if service == null:
		return FrameworkResult.fail(
			&"dialogue.no_mission_service",
			"No mission service is registered; nothing can be started."
		)

	match operation:
		Operation.START:
			# The listener is the subject: a quest giver starts a mission for
			# whoever it is talking to, never for itself.
			return service.call("start_by_id", mission_id, context.listener)
		Operation.COMPLETE:
			var runtime: Object = service.call("get_runtime", mission_id)
			if runtime == null:
				return FrameworkResult.fail(
					&"dialogue.mission_not_active",
					"Mission '%s' is not active." % mission_id
				)
			return runtime.call("complete")
		Operation.ABANDON:
			return service.call("abandon", mission_id)
	return FrameworkResult.ok(null)


func describe() -> String:
	var verb: String = ["starts", "completes", "abandons"][int(operation)]
	return "%s %s" % [verb, mission_id]


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if mission_id == &"":
		result.add_error(
			&"dialogue.action_no_mission",
			"A mission action names no mission.",
			resource_path,
			"mission_id"
		)
	return result


## Duck-typed off the service registry, so this file names no mission type.
func _missions(context: DialogueContext) -> Object:
	var core: Variant = context.extras.get("core")
	if core == null and context.listener != null and context.listener.is_inside_tree():
		core = context.listener.get_tree().root.get_node_or_null("FrameworkCore")
	if core == null or not core.has_method("get_service"):
		return null
	var service: Object = core.call("get_service", GameplayNames.SERVICE_OBJECTIVE)
	if service == null or not service.has_method("start_by_id"):
		return null
	return service
