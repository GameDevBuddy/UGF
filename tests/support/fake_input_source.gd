extends InputSource
## Scriptable input, so the routing layer can be tested without a device.
##
## This fixture is the payoff for [InputRouter] reading through an
## [InputSource] rather than calling [Input] directly. Holding sprint, tapping
## jump and letting go are three method calls here, and the assertions that
## follow run in microseconds with no window open.

var _pressed: Dictionary[StringName, float] = {}
var _just_pressed: Dictionary[StringName, bool] = {}
var _just_released: Dictionary[StringName, bool] = {}
## Actions this source claims not to know, for exercising unbound-action
## validation.
var unbound: Array[StringName] = []


## Holds an action down, optionally at partial strength for an analogue stick.
func press(action: StringName, strength: float = 1.0) -> void:
	_pressed[action] = strength
	_just_pressed[action] = true
	_just_released.erase(action)


func release(action: StringName) -> void:
	_pressed.erase(action)
	_just_pressed.erase(action)
	_just_released[action] = true


## Presses and immediately stops being "just" pressed, for a tap that has
## already been consumed by a previous frame.
func hold(action: StringName, strength: float = 1.0) -> void:
	_pressed[action] = strength
	_just_pressed.erase(action)


## Clears the one-frame flags, as the engine does between frames. Anything
## held stays held.
func advance_frame() -> void:
	_just_pressed.clear()
	_just_released.clear()


func clear() -> void:
	_pressed.clear()
	_just_pressed.clear()
	_just_released.clear()


func is_pressed(action: StringName) -> bool:
	return _pressed.has(action)


func was_just_pressed(action: StringName) -> bool:
	return _just_pressed.get(action, false)


func was_just_released(action: StringName) -> bool:
	return _just_released.get(action, false)


func get_strength(action: StringName) -> float:
	return _pressed.get(action, 0.0)


func has_action(action: StringName) -> bool:
	return not unbound.has(action)
