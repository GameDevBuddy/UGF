class_name DebugCommandPack
extends RefCounted
## A module's own console cheats, registered by the project that wants them.
##
## [b]This is the resolution of a real tension.[/b] Implementation Plan 29
## lists five console cheats -- spawn item, set stat, start mission, change
## faction, enter vehicle -- as a deliverable. M17 shipped a console that
## implements none of them, with the reasoning written down: a console
## implementing those five would import Items, Stats, Missions, Factions and
## Vehicles, and become the one file in the framework that cannot be deleted.
##
## That reasoning holds. So the cheats ship, but not in the console. Each pack
## lives in the module folder it cheats at, knows only that module, and is
## registered by the project that wants it:
## [codeblock]
## InventoryDebugCommands.new(inventory, core).register_into(console)
## [/codeblock]
##
## The console still imports nothing. Deleting a module deletes its cheats
## along with it, because they were never anywhere else (rule 10).

## Registers this pack's commands into [param console].
##
## Returns the number registered, so a project wiring several packs can assert
## it got what it expected rather than discovering a silent no-op later.
func register_into(console: DebugConsole) -> int:
	if console == null:
		return 0
	# The console keeps the pack alive. Without this every command registered
	# from an inline pack points at a freed object the moment the caller's
	# statement ends -- see DebugConsole.retain.
	console.retain(self)
	var added := 0
	for command in build_commands():
		if console.register(command).is_ok():
			added += 1
	return added


## Overridden by every pack. Returns the commands it contributes.
func build_commands() -> Array[DebugCommand]:
	return []


## Convenience for a pack reporting a refusal in the shape the console prints.
static func refuse(message: String) -> FrameworkResult:
	return FrameworkResult.fail(&"debug.refused", message)
