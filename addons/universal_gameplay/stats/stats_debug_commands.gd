class_name StatsDebugCommands
extends DebugCommandPack
## The plan's "set stat" cheat.
##
## Sets the base rather than the computed value, because the computed value is
## not a thing anything can set: it is the base plus whatever modifiers happen
## to be applied, and writing to it would be undone by the next recompute.
## A console that appeared to work and silently reverted would be worse than
## one that refused.

var _stats: StatsComponent = null


func _init(stats: StatsComponent = null) -> void:
	_stats = stats


func set_target(stats: StatsComponent) -> void:
	_stats = stats


func build_commands() -> Array[DebugCommand]:
	return [
		DebugCommand.create(
			&"setstat", _set_stat, "Set a stat's base value.", "<stat_id> <value>", true
		),
		DebugCommand.create(
			&"getstat", _get_stat, "Show a stat's value and where it came from.", "<stat_id>", false
		),
		DebugCommand.create(
			&"refill", _refill, "Refill every depletable stat.", "", true
		),
	] as Array[DebugCommand]


func _set_stat(arguments: PackedStringArray) -> FrameworkResult:
	if _stats == null:
		return refuse("No stats target set.")
	if arguments.size() < 2:
		return refuse("Usage: setstat <stat_id> <value>")

	var stat := StringName(arguments[0])
	if not _stats.has_stat(stat):
		return refuse("This entity has no stat '%s'." % stat)

	var value := arguments[1].to_float()
	_stats.set_base(stat, value)
	return FrameworkResult.ok(
		"%s base is now %.2f (value %.2f)." % [stat, value, _stats.get_value(stat)]
	)


func _get_stat(arguments: PackedStringArray) -> FrameworkResult:
	if _stats == null:
		return refuse("No stats target set.")
	if arguments.is_empty():
		return refuse("Usage: getstat <stat_id>")

	var stat := StringName(arguments[0])
	if not _stats.has_stat(stat):
		return refuse("This entity has no stat '%s'." % stat)
	return FrameworkResult.ok(_stats.explain(stat))


func _refill(_arguments: PackedStringArray) -> FrameworkResult:
	if _stats == null:
		return refuse("No stats target set.")
	_stats.refill_all()
	return FrameworkResult.ok("Refilled.")
