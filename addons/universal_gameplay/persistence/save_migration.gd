class_name SaveMigration
extends Resource
## One step up the schema ladder.
##
## [b]Migrations are steps, not jumps.[/b] A save from schema 1 loading into a
## build at schema 4 runs 1→2, 2→3, 3→4 in order. Writing a 1→4 migration
## instead looks simpler and is the thing that rots: every new schema version
## would need a new migration from every old one, and the count grows with the
## square of the project's age.
##
## A migration receives and returns plain data — the dictionary form of a
## [SaveGame], before anything has been turned into objects. That is what lets
## it rename a field the current code no longer knows about.

## The version this upgrades from.
@export var from_version: int = 0

## The version it produces. Always [member from_version] plus one; the
## registry refuses anything else, because a step that skips a version leaves
## a hole nothing can cross.
@export var to_version: int = 0

## What it does, for a migration log and for a project auditing its own ladder.
@export_multiline var description: String = ""


func is_step() -> bool:
	return to_version == from_version + 1


## Upgrades one save's plain data. The base does nothing, which is a valid
## migration: a schema bump that only adds an optional field needs no work,
## and saying so explicitly is better than a gap in the ladder.
func migrate(data: Dictionary) -> Dictionary:
	return data


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if not is_step():
		result.add_error(
			&"migration.not_a_step",
			(
				"A migration from %d to %d skips a version, leaving a hole "
				+ "nothing can cross."
			) % [from_version, to_version],
			resource_path,
			"to_version"
		)
	if from_version < 0:
		result.add_error(
			&"migration.negative_version",
			"A migration cannot come from a negative schema version.",
			resource_path,
			"from_version"
		)
	if description.is_empty():
		result.add_info(
			&"migration.undocumented",
			(
				"This migration says nothing about what it does, which is the "
				+ "one comment anybody reading a save bug will want."
			),
			resource_path,
			"description"
		)
	return result
