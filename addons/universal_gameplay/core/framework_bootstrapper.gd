class_name FrameworkBootstrapper
extends RefCounted
## Turns a [FrameworkSettings] module list into registered modules.
##
## Eighteen milestones built a framework whose parts could be assembled; this
## is the part that assembles them. Before it, a project that ticked Inventory
## in its settings got [method FrameworkCore.is_module_enabled] returning true
## and [method FrameworkCore.has_feature] returning false forever, because
## nothing anywhere read the list. The gap was invisible precisely because both
## methods worked exactly as documented.
##
## Everything here is reporting, not repair. A settings file that asks for
## Combat without Items gets an error naming the modules to add -- it does not
## get Items registered on its behalf. Silently widening a project's module
## list would make its settings file stop describing its game, and the first
## time one of the uninvited modules misbehaved there would be nothing to point
## at (rule 36: every dependency explicit).

## Registers the modules [param settings] asks for, in dependency order.
##
## Returns every problem found. Nothing is registered if the list cannot be
## resolved, so a failed install leaves the core exactly as it was rather than
## half-built (rule 17).
static func install(core: Node, settings: FrameworkSettings) -> ValidationResult:
	var result := ValidationResult.new()
	if core == null:
		result.add_error(&"bootstrap.no_core", "Cannot install modules without a core.")
		return result
	if settings == null:
		return result

	var requested := settings.get_enabled_module_ids()
	if requested.is_empty():
		# Not a problem. A project may register its modules by hand, and one
		# that has not chosen any yet is at the start of its first day.
		return result

	var order := ModuleCatalog.resolve_order(requested)
	if order.is_err():
		result.add_error(&"bootstrap.unresolved", order.message, "", "enabled_modules")
		if order.failed_with(&"catalog.missing_dependency"):
			var implied := ModuleCatalog.get_implied_requirements(requested)
			if not implied.is_empty():
				result.add_info(
					&"bootstrap.add_these",
					"Enable these as well and the list resolves: %s." % str(implied),
					"",
					"enabled_modules"
				)
		return result

	var ordered: Array = order.payload
	for id in ordered:
		var module := ModuleCatalog.instantiate(id)
		if module == null:
			result.add_error(
				&"bootstrap.instantiation_failed",
				"Module '%s' could not be instantiated from %s."
				% [id, ModuleCatalog.get_script_path(id)],
				ModuleCatalog.get_script_path(id)
			)
			continue

		var registration: FrameworkResult = core.register_module(module)
		if registration.is_err():
			result.add_error(
				&"bootstrap.registration_failed",
				"Module '%s' was not registered: %s" % [id, registration.message],
				ModuleCatalog.get_script_path(id)
			)

	return result


## The modules that would be registered, in order, without registering any.
##
## For an editor panel or a build script that wants to show the plan before
## committing to it. Returns an empty array when the list does not resolve;
## [method install] is where the reasons come from.
static func preview(settings: FrameworkSettings) -> Array[StringName]:
	var empty: Array[StringName] = []
	if settings == null:
		return empty
	var order := ModuleCatalog.resolve_order(settings.get_enabled_module_ids())
	if order.is_err():
		return empty
	var ordered: Array[StringName] = []
	ordered.assign(order.payload)
	return ordered
