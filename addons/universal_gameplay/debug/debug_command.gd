class_name DebugCommand
extends RefCounted
## One thing a console can do.
##
## [b]Commands are registered, not hard-coded.[/b] The plan's console list —
## spawn item, set stat, start mission, change faction, enter vehicle — is five
## modules' worth of cheats, and a console that implemented them would import
## all five and be undeletable. Instead each module's own project code
## registers what it wants, and the console knows only names and callables
## (rule 9, rule 10).

## What the player types.
var name: StringName = &""

## One line of help.
var summary: String = ""

## Argument shape for the help text: [code]"<item_id> [count]"[/code]. Free
## text, because a console that validated argument grammar would be a parser
## nobody asked for.
var usage: String = ""

## What it does. Takes the parsed arguments as a [PackedStringArray] and
## returns a [FrameworkResult] whose payload is what to print.
var handler: Callable = Callable()

## Whether this command changes the world.
##
## [b]Declared, not inferred.[/b] A console is the one place in the framework
## where mutation is the point, and marking which commands mutate is what lets
## a project ship the console in a release build with the cheats switched off
## and the inspectors left on.
var mutates: bool = false


static func create(
	p_name: StringName,
	p_handler: Callable,
	p_summary: String = "",
	p_usage: String = "",
	p_mutates: bool = false
) -> DebugCommand:
	var command := DebugCommand.new()
	command.name = p_name
	command.handler = p_handler
	command.summary = p_summary
	command.usage = p_usage
	command.mutates = p_mutates
	return command


func is_valid() -> bool:
	return name != &"" and handler.is_valid()


func run(arguments: PackedStringArray) -> FrameworkResult:
	if not handler.is_valid():
		return FrameworkResult.fail(
			&"console.no_handler", "'%s' has nothing behind it." % name
		)
	var answer: Variant = handler.call(arguments)
	if answer is FrameworkResult:
		return answer
	# A handler that returned something plain is a handler that succeeded and
	# had something to say. Requiring every cheat to wrap its answer would
	# make the easy case the verbose one.
	return FrameworkResult.ok(answer)


func describe() -> String:
	var line := String(name)
	if not usage.is_empty():
		line += " " + usage
	if not summary.is_empty():
		line += "  -- " + summary
	return line
