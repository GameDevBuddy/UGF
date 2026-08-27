class_name EngineInputSource
extends InputSource
## Reads real device state through Godot's [Input] singleton.
##
## The only place in the framework that touches [Input]. Everything else asks
## an [InputRouter], which asks an [InputSource] -- so swapping in recorded
## input, a replay, or a network client's intent stream is a constructor
## argument rather than a rewrite (Implementation Plan 27).
##
## Actions absent from the project's InputMap are reported as unpressed rather
## than raising. A project that has not bound sprint yet should not crash on
## the frame something asks about it; [method has_action] is how a caller finds
## out, and [method InputRouter.validate_bindings] is where that gets reported.


func is_pressed(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	return Input.is_action_pressed(action)


func was_just_pressed(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	return Input.is_action_just_pressed(action)


func was_just_released(action: StringName) -> bool:
	if not InputMap.has_action(action):
		return false
	return Input.is_action_just_released(action)


func get_strength(action: StringName) -> float:
	if not InputMap.has_action(action):
		return 0.0
	return Input.get_action_strength(action)


func has_action(action: StringName) -> bool:
	return InputMap.has_action(action)
