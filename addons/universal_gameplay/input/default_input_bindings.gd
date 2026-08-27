class_name DefaultInputBindings
extends RefCounted
## Keyboard and gamepad defaults for the framework's semantic actions.
##
## The framework names actions ([code]move_forward[/code], [code]jump[/code],
## [code]sprint[/code]) and Godot's InputMap binds them. Without something to
## close that gap, a project that installs this addon gets a character which
## compiles, spawns, validates and cannot move -- and nothing reports why,
## because an unbound action is indistinguishable from an unpressed one at
## runtime.
##
## [b]Defaults only.[/b] [method install] never touches an action the project
## has already defined, so rebinding is a project decision that survives a
## framework update. A project that wants none of this simply does not call it;
## nothing at runtime depends on these bindings existing.
##
## Bindings are not content in the rule 29 sense. WASD and space are not a
## game's design, they are the floor every genre this platform targets starts
## from, and shipping them is the difference between an addon that works when
## enabled and one that requires a page of setup first.

## Deadzone applied to generated joypad events. Godot's own default.
const JOYPAD_DEADZONE: float = 0.5


## Every action the framework defines, mapped to its default events.
##
## Pure: it builds events and returns them, touching neither InputMap nor
## ProjectSettings, so what the defaults actually are can be asserted without
## mutating the editor's global state.
static func get_bindings() -> Dictionary[StringName, Array]:
	var bindings: Dictionary[StringName, Array] = {}
	bindings[GameplayNames.ACTION_MOVE_FORWARD] = [
		_key(KEY_W),
		_key(KEY_UP),
		_joy_axis(JOY_AXIS_LEFT_Y, -1.0),
	]
	bindings[GameplayNames.ACTION_MOVE_BACK] = [
		_key(KEY_S),
		_key(KEY_DOWN),
		_joy_axis(JOY_AXIS_LEFT_Y, 1.0),
	]
	bindings[GameplayNames.ACTION_MOVE_LEFT] = [
		_key(KEY_A),
		_key(KEY_LEFT),
		_joy_axis(JOY_AXIS_LEFT_X, -1.0),
	]
	bindings[GameplayNames.ACTION_MOVE_RIGHT] = [
		_key(KEY_D),
		_key(KEY_RIGHT),
		_joy_axis(JOY_AXIS_LEFT_X, 1.0),
	]
	bindings[GameplayNames.ACTION_JUMP] = [
		_key(KEY_SPACE),
		_joy_button(JOY_BUTTON_A),
	]
	bindings[GameplayNames.ACTION_SPRINT] = [
		_key(KEY_SHIFT),
		_joy_button(JOY_BUTTON_LEFT_STICK),
	]
	bindings[GameplayNames.ACTION_CROUCH] = [
		_key(KEY_CTRL),
		_joy_button(JOY_BUTTON_B),
	]
	bindings[GameplayNames.ACTION_INTERACT] = [
		_key(KEY_E),
		_joy_button(JOY_BUTTON_X),
	]
	return bindings


## Adds any missing action to the live [InputMap].
##
## Returns a report naming what was added and what was left alone, so an editor
## plugin or a setup script can say what it did rather than changing the
## project's input silently.
##
## [param overwrite] replaces a project's existing events for these actions.
## Off by default and deliberately awkward to reach for: quietly resetting a
## player's rebound controls on a framework update is not a bug anyone enjoys
## tracking down.
static func install(overwrite: bool = false) -> ValidationResult:
	var result := ValidationResult.new()
	for action in get_bindings():
		var events: Array = get_bindings()[action]
		if InputMap.has_action(action):
			if not overwrite:
				result.add_info(
					&"input.binding_already_defined",
					"Action '%s' is already bound; left as the project has it." % action
				)
				continue
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, JOYPAD_DEADZONE)
		for event in events:
			InputMap.action_add_event(action, event)
		result.add_info(
			&"input.binding_installed", "Bound default events for '%s'." % action
		)
	return result


## Writes any missing action into ProjectSettings, so it survives a restart.
##
## [method install] only reaches the live [InputMap], which is enough for a
## running game and forgotten the moment the editor closes. Persisting means
## writing [code]input/<action>[/code] settings, which is how Godot stores the
## InputMap in [code]project.godot[/code] -- this is the editor plugin's path.
##
## The caller saves: [method ProjectSettings.save] is a file write, and doing
## it once after a batch of settings beats doing it eight times.
static func write_project_settings(overwrite: bool = false) -> ValidationResult:
	var result := ValidationResult.new()
	var bindings := get_bindings()
	for action in bindings:
		var property := "input/%s" % action
		if ProjectSettings.has_setting(property) and not overwrite:
			result.add_info(
				&"input.binding_already_defined",
				"Action '%s' is already in project settings; left alone." % action
			)
			continue
		var events: Array[InputEvent] = []
		events.assign(bindings[action])
		ProjectSettings.set_setting(
			property, {"deadzone": JOYPAD_DEADZONE, "events": events}
		)
		result.add_info(
			&"input.binding_installed", "Wrote default binding for '%s'." % action
		)
	return result


## Removes the framework's actions from the live [InputMap].
##
## Only for an editor plugin being disabled, and for tests that installed
## bindings and should not leave them behind for the next suite.
static func uninstall() -> void:
	for action in get_bindings():
		if InputMap.has_action(action):
			InputMap.erase_action(action)


## Framework actions the live [InputMap] has no binding for.
##
## The same question [method InputRouter.validate_bindings] asks of a context
## stack, asked of the whole vocabulary instead -- useful in a setup check
## before any context has been pushed.
static func get_unbound_actions() -> Array[StringName]:
	var missing: Array[StringName] = []
	for action in get_bindings():
		if not InputMap.has_action(action):
			missing.append(action)
	return missing


# --- Event builders -------------------------------------------------------

static func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


static func _joy_button(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


## [param direction] is -1 or 1: which end of the axis this action reads.
static func _joy_axis(axis: JoyAxis, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	return event
