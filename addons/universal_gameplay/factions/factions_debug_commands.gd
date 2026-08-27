class_name FactionsDebugCommands
extends DebugCommandPack
## The plan's "change faction" cheat.
##
## Two different things get called "faction standing" and the console must not
## blur them: [code]reputation[/code] is how one faction feels about one actor,
## [code]relation[/code] is how two factions feel about each other. Setting the
## wrong one and watching nothing change is the confusion this split avoids.
##
## Relations are directional. Setting the guards against the thieves does not
## set the thieves against the guards, and the console says so rather than
## quietly doing both.

var _factions: FactionService = null


func _init(factions: FactionService = null) -> void:
	_factions = factions


func set_service(factions: FactionService) -> void:
	_factions = factions


func build_commands() -> Array[DebugCommand]:
	return [
		DebugCommand.create(
			&"rep", _reputation, "Set a faction's opinion of one actor.",
			"<faction_id> <actor_id> <value>", true
		),
		DebugCommand.create(
			&"relation", _relation, "Set how one faction regards another (directional).",
			"<subject_faction> <other_faction> <value>", true
		),
		DebugCommand.create(
			&"standing", _standing, "Show standing between two parties.",
			"<faction_id> <actor_or_faction_id>", false
		),
	] as Array[DebugCommand]


func _reputation(arguments: PackedStringArray) -> FrameworkResult:
	if _factions == null:
		return refuse("No faction service set.")
	if arguments.size() < 3:
		return refuse("Usage: rep <faction_id> <actor_id> <value>")

	var faction := StringName(arguments[0])
	if not _factions.has_faction(faction):
		return refuse("No faction '%s' is registered." % faction)

	var actor := StringName(arguments[1])
	var value := arguments[2].to_float()
	_factions.set_reputation(faction, actor, value)
	return FrameworkResult.ok(
		"%s now regards %s at %.2f." % [faction, actor, _factions.get_reputation(faction, actor)]
	)


func _relation(arguments: PackedStringArray) -> FrameworkResult:
	if _factions == null:
		return refuse("No faction service set.")
	if arguments.size() < 3:
		return refuse("Usage: relation <subject_faction> <other_faction> <value>")

	var subject := StringName(arguments[0])
	var other := StringName(arguments[1])
	for faction in [subject, other]:
		if not _factions.has_faction(faction):
			return refuse("No faction '%s' is registered." % faction)

	_factions.set_relation(subject, other, arguments[2].to_float())
	return FrameworkResult.ok(
		(
			"%s now regards %s at %.2f. The reverse is unchanged at %.2f."
			% [
				subject,
				other,
				_factions.get_relation(subject, other),
				_factions.get_relation(other, subject),
			]
		)
	)


func _standing(arguments: PackedStringArray) -> FrameworkResult:
	if _factions == null:
		return refuse("No faction service set.")
	if arguments.size() < 2:
		return refuse("Usage: standing <faction_id> <actor_or_faction_id>")
	var subject := StringName(arguments[0])
	var other := StringName(arguments[1])
	return FrameworkResult.ok(
		"%s -> %s: %.2f" % [subject, other, _factions.get_standing(subject, other)]
	)
