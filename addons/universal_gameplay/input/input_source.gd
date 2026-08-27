class_name InputSource
extends RefCounted
## Where the router reads raw action state from.
##
## This exists so [InputRouter] never calls Godot's [Input] singleton directly.
## A global that reports what a physical device is doing right now cannot be
## driven from a test, and an input layer that can only be exercised by a human
## holding a key is an input layer nobody tests (rule 33).
##
## The default implementation is [EngineInputSource], which reads the real
## [Input]. Tests substitute a fake and drive the same router.
##
## Bindings are not this class's business. Godot's InputMap remains the
## engine-level binding source (Implementation Plan 24); this only reports
## whether a semantic action is active.


## True while the action is held.
func is_pressed(_action: StringName) -> bool:
	return false


## True only on the frame the action went down.
func was_just_pressed(_action: StringName) -> bool:
	return false


## True only on the frame the action came up.
func was_just_released(_action: StringName) -> bool:
	return false


## Analogue strength in 0..1. Digital sources report 0 or 1.
func get_strength(action: StringName) -> float:
	return 1.0 if is_pressed(action) else 0.0


## Signed axis built from two opposing actions.
func get_axis(negative: StringName, positive: StringName) -> float:
	return get_strength(positive) - get_strength(negative)


## Two-axis vector built from four actions, clamped to unit length so a
## diagonal is not faster than a straight line.
func get_vector(
	negative_x: StringName,
	positive_x: StringName,
	negative_y: StringName,
	positive_y: StringName
) -> Vector2:
	var vector := Vector2(
		get_axis(negative_x, positive_x), get_axis(negative_y, positive_y)
	)
	return vector.limit_length(1.0)


## Whether this source can report on [param action] at all.
##
## A source that knows an action is unbound lets the router say so during
## validation rather than silently reporting "not pressed" forever.
func has_action(_action: StringName) -> bool:
	return true
