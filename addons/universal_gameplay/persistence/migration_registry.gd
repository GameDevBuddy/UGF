class_name MigrationRegistry
extends RefCounted
## The ladder a save climbs to reach the running build.
##
## Steps are registered by the version they upgrade from, and applied in order
## until the data is current. A gap in the ladder is an error at registration
## time rather than a corrupt world at load time — which is the whole reason
## this is a registry and not a match statement somewhere in the loader.

## Emitted per step applied. What a migration log records.
signal step_applied(from_version: int, to_version: int)

var _steps: Dictionary[int, SaveMigration] = {}


func register(migration: SaveMigration) -> FrameworkResult:
	if migration == null:
		return FrameworkResult.fail(&"migration.null", "There is no migration.")
	if not migration.is_step():
		return FrameworkResult.fail(
			&"migration.not_a_step",
			"A migration from %d to %d skips a version." % [
				migration.from_version, migration.to_version
			]
		)
	if _steps.has(migration.from_version):
		return FrameworkResult.fail(
			&"migration.duplicate",
			"Two migrations claim to upgrade from schema %d." % migration.from_version
		)
	_steps[migration.from_version] = migration
	return FrameworkResult.ok(migration)


func register_all(migrations: Array) -> ValidationResult:
	var result := ValidationResult.new()
	for migration in migrations:
		var registered := register(migration)
		if registered.is_err():
			result.add_error(registered.code, registered.message)
	return result


func has_step_from(version: int) -> bool:
	return _steps.has(version)


func get_step_from(version: int) -> SaveMigration:
	return _steps.get(version)


func get_step_count() -> int:
	return _steps.size()


func clear() -> void:
	_steps.clear()


## Whether a save at [param from_version] can reach [param target].
##
## Checked before anything is touched, so a save that cannot be fully migrated
## is refused whole rather than half-upgraded (rule 17 applied to files).
func can_migrate(from_version: int, target: int = FrameworkVersion.SAVE_SCHEMA) -> FrameworkResult:
	if from_version > target:
		return FrameworkResult.fail(
			&"migration.from_the_future",
			(
				"This save is schema %d and this build understands %d. It was "
				+ "written by a newer version."
			) % [from_version, target]
		)
	var version := from_version
	while version < target:
		if not has_step_from(version):
			return FrameworkResult.fail(
				&"migration.missing_step",
				"No migration upgrades schema %d, so the ladder stops there." % version
			)
		version += 1
	return FrameworkResult.ok(target)


## Climbs [param data] to [param target], one step at a time.
##
## Returns the upgraded data as the payload. The input is never mutated: a
## failed migration must leave the caller holding exactly what it had, or a
## retry after fixing the ladder would start from something half-converted.
func migrate(
	data: Dictionary, from_version: int, target: int = FrameworkVersion.SAVE_SCHEMA
) -> FrameworkResult:
	var possible := can_migrate(from_version, target)
	if possible.is_err():
		return possible

	var working := data.duplicate(true)
	var version := from_version
	while version < target:
		var step := get_step_from(version)
		working = step.migrate(working)
		if working == null:
			return FrameworkResult.fail(
				&"migration.step_failed",
				"The migration from schema %d returned nothing." % version
			)
		version = step.to_version
		working["schema_version"] = version
		step_applied.emit(step.from_version, step.to_version)
	return FrameworkResult.ok(working)


## Every registration problem in the ladder as it stands. What a project runs
## in CI so a missing step is a build failure rather than a support ticket.
func validate(target: int = FrameworkVersion.SAVE_SCHEMA) -> ValidationResult:
	var result := ValidationResult.new()
	for version in _steps:
		result.merge(_steps[version].validate())
	if _steps.is_empty():
		return result

	var lowest := target
	for version in _steps:
		lowest = mini(lowest, version)
	var reachable := can_migrate(lowest, target)
	if reachable.is_err():
		result.add_error(
			reachable.code,
			(
				"The oldest registered migration starts at schema %d but the "
				+ "ladder does not reach %d: %s"
			) % [lowest, target, reachable.message]
		)
	return result
