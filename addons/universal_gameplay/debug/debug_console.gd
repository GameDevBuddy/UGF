class_name DebugConsole
extends Node
## Runs typed commands. No window, no text box, no font.
##
## [b]The console is a command registry and a parser.[/b] Drawing it is a
## project's decision about its own look, exactly as a health bar is — and a
## console the framework drew would be the second thing every project replaced.
## What the framework can own is the part every project writes the same way:
## splitting a line, finding the command, running it, and reporting what
## happened.
##
## It ships four commands and no cheats. [code]help[/code], [code]commands[/code],
## [code]inspect[/code] and [code]events[/code] are read-only and depend on
## nothing; spawn-item and set-stat and start-mission are a project's to
## register, because a console that implemented them would import five modules
## and be undeletable (rule 10).

## Emitted per line run, so a project's own view can echo it.
signal command_run(line: String, result: FrameworkResult)

## Emitted when a line named nothing.
signal command_unknown(name: StringName)

## Whether commands marked [member DebugCommand.mutates] may run. Off is a
## release build with the inspectors kept and the cheats gone.
@export var allow_mutation: bool = true

## The monitor [code]events[/code] reads. Optional.
@export var monitor: EventMonitor

## What [code]inspect[/code] describes when given no argument.
@export var inspect_target: Node

var _commands: Dictionary[StringName, DebugCommand] = {}
var _history: PackedStringArray = PackedStringArray()


func _ready() -> void:
	register_builtins()


# --- Registration ---------------------------------------------------------

func register(command: DebugCommand) -> FrameworkResult:
	if command == null or not command.is_valid():
		return FrameworkResult.fail(
			&"console.invalid_command", "A command needs a name and a handler."
		)
	if _commands.has(command.name):
		return FrameworkResult.fail(
			&"console.duplicate", "There is already a command called '%s'." % command.name
		)
	_commands[command.name] = command
	return FrameworkResult.ok(command)


## Registers a handler without building the resource by hand. What a project's
## own cheat registration actually calls.
func add(
	name: StringName,
	handler: Callable,
	summary: String = "",
	usage: String = "",
	mutates: bool = false
) -> FrameworkResult:
	return register(DebugCommand.create(name, handler, summary, usage, mutates))


func unregister(name: StringName) -> bool:
	return _commands.erase(name)


func has_command(name: StringName) -> bool:
	return _commands.has(name)


func get_command(name: StringName) -> DebugCommand:
	return _commands.get(name)


func get_command_names() -> Array[StringName]:
	var names: Array[StringName] = []
	names.assign(_commands.keys())
	names.sort()
	return names


func get_command_count() -> int:
	return _commands.size()


# --- Running --------------------------------------------------------------

## Splits a line and runs it.
##
## Quoted arguments are honoured, because "start mission" is one argument and
## a console that could not say so would be one nobody used twice.
func run(line: String) -> FrameworkResult:
	var trimmed := line.strip_edges()
	if trimmed.is_empty():
		return FrameworkResult.fail(&"console.empty", "Nothing to run.")
	_history.append(trimmed)

	var parts := parse(trimmed)
	var name := StringName(parts[0])
	var command := get_command(name)
	if command == null:
		command_unknown.emit(name)
		var answer := FrameworkResult.fail(
			&"console.unknown", "There is no command called '%s'." % name
		)
		command_run.emit(trimmed, answer)
		return answer
	if command.mutates and not allow_mutation:
		var refused := FrameworkResult.fail(
			&"console.mutation_disabled",
			"'%s' changes the world, and that is switched off." % name
		)
		command_run.emit(trimmed, refused)
		return refused

	var result := command.run(parts.slice(1))
	command_run.emit(trimmed, result)
	return result


## Splits a line into a command and its arguments, honouring double quotes.
##
## Static and public because it is the one piece of this file worth reusing,
## and because a parser is far easier to trust when you can test it directly.
static func parse(line: String) -> PackedStringArray:
	var parts := PackedStringArray()
	var current := ""
	var quoted := false
	for index in line.length():
		var character := line[index]
		if character == '"':
			quoted = not quoted
			continue
		if character == " " and not quoted:
			if not current.is_empty():
				parts.append(current)
				current = ""
			continue
		current += character
	if not current.is_empty():
		parts.append(current)
	if parts.is_empty():
		parts.append("")
	return parts


func get_history() -> PackedStringArray:
	return _history.duplicate()


func clear_history() -> void:
	_history.clear()


# --- Built-ins ------------------------------------------------------------
#
# Read-only, every one. A console that shipped cheats would import the modules
# they cheat at, and a debug tool that cannot be deleted is not a debug tool.

func register_builtins() -> void:
	add(&"help", _help, "Lists commands, or explains one.", "[command]")
	add(&"commands", _list, "Lists command names only.")
	add(&"inspect", _inspect, "Describes an entity.", "[node_path]")
	add(&"events", _events, "Shows recent bus traffic.", "[count]")


func _help(arguments: PackedStringArray) -> FrameworkResult:
	if not arguments.is_empty():
		var command := get_command(StringName(arguments[0]))
		if command == null:
			return FrameworkResult.fail(
				&"console.unknown", "There is no command called '%s'." % arguments[0]
			)
		return FrameworkResult.ok(command.describe())
	var lines := PackedStringArray()
	for name in get_command_names():
		lines.append("  " + _commands[name].describe())
	return FrameworkResult.ok("\n".join(lines))


func _list(_arguments: PackedStringArray) -> FrameworkResult:
	var names := PackedStringArray()
	for name in get_command_names():
		names.append(String(name))
	return FrameworkResult.ok(" ".join(names))


func _inspect(arguments: PackedStringArray) -> FrameworkResult:
	var target := inspect_target
	if not arguments.is_empty():
		target = get_node_or_null(NodePath(arguments[0]))
		if target == null:
			return FrameworkResult.fail(
				&"console.no_such_node", "There is no node at '%s'." % arguments[0]
			)
	if target == null:
		return FrameworkResult.fail(
			&"console.no_target", "Nothing to inspect, and no target is set."
		)
	return FrameworkResult.ok(EntityInspector.describe(target))


func _events(arguments: PackedStringArray) -> FrameworkResult:
	if monitor == null:
		return FrameworkResult.fail(
			&"console.no_monitor", "No event monitor is wired to this console."
		)
	var count := int(arguments[0]) if not arguments.is_empty() else 20
	return FrameworkResult.ok(monitor.describe(count))
