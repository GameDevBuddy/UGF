extends FrameworkTestCase
## M19: the addon is installable, and installing it is one list of module ids.
##
## The exit gate for this milestone is "a new project integrates Core plus
## chosen modules without copying game-specific code". These tests are what
## that sentence means in practice: the catalog knows every module the addon
## ships, the bootstrapper turns a settings list into registrations in the
## right order, and nothing under [code]addons/[/code] reaches outside itself.

const ADDON_ROOT: String = "res://addons/universal_gameplay"
const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const PLUGIN_CFG: String = "res://addons/universal_gameplay/plugin.cfg"

## The base contract, which lives under core/contracts and is not a module.
const MODULE_CONTRACT: String = (
	"res://addons/universal_gameplay/core/contracts/framework_module.gd"
)


# --- The catalog matches the addon ---------------------------------------

func test_catalog_lists_every_module_script_on_disk() -> void:
	# ModuleCatalog.MODULES is written out by hand because a scan would find
	# nothing in an exported build. Written-out tables drift; this is the
	# check that stops them.
	var on_disk := _find_module_scripts(ADDON_ROOT)
	var catalogued: Array[String] = []
	for id in ModuleCatalog.get_ids():
		catalogued.append(ModuleCatalog.get_script_path(id))
	on_disk.sort()
	catalogued.sort()

	for path in on_disk:
		assert_has(
			catalogued,
			path,
			"%s is a module the catalog does not list. Add it to ModuleCatalog.MODULES." % path
		)
	for path in catalogued:
		assert_has(
			on_disk,
			path,
			"ModuleCatalog lists %s, which is not a module script on disk." % path
		)


func test_every_catalogued_id_matches_its_manifest() -> void:
	# The key in the table and the id the module declares have to agree, or a
	# project enabling "module.combat" gets whatever combat_module.gd calls
	# itself and the registry ends up keyed by something else entirely.
	for id in ModuleCatalog.get_ids():
		var manifest := ModuleCatalog.get_manifest(id)
		assert_not_null(manifest, "%s produced no manifest" % id)
		if manifest != null:
			assert_eq(manifest.id, id, "Catalog key and manifest id disagree for %s" % id)


func test_every_declared_dependency_is_a_module_the_addon_ships() -> void:
	# A manifest naming a module that does not exist is a dependency nothing
	# can ever satisfy: the registry would refuse the module forever and the
	# error would name an id no file defines.
	for id in ModuleCatalog.get_ids():
		var manifest := ModuleCatalog.get_manifest(id)
		for dependency in manifest.requires:
			assert_true(
				ModuleCatalog.has(dependency),
				"%s requires '%s', which the addon does not ship." % [id, dependency]
			)
		for dependency in manifest.optional:
			assert_true(
				ModuleCatalog.has(dependency),
				"%s lists optional '%s', which the addon does not ship." % [id, dependency]
			)


func test_instantiate_returns_a_fresh_module_each_time() -> void:
	# Two cores must never share one module instance: a module owns whatever
	# its initialize() registered, and sharing it would give two cores one set
	# of services (rule 2).
	var first := ModuleCatalog.instantiate(&"module.entity")
	var second := ModuleCatalog.instantiate(&"module.entity")
	assert_not_null(first)
	assert_not_null(second)
	assert_true(first != second, "instantiate() handed back the same object twice")


func test_an_unknown_id_yields_nothing_rather_than_erroring() -> void:
	assert_false(ModuleCatalog.has(&"module.telepathy"))
	assert_null(ModuleCatalog.instantiate(&"module.telepathy"))
	assert_null(ModuleCatalog.get_manifest(&"module.telepathy"))
	assert_eq(ModuleCatalog.get_script_path(&"module.telepathy"), "")


# --- Ordering -------------------------------------------------------------

func test_the_whole_catalog_resolves_into_a_registration_order() -> void:
	# Also the standing check that no two shipped modules require each other.
	# resolve_order's cycle branch exists for the day somebody adds one; that
	# it never fires here is the property worth asserting.
	var result := ModuleCatalog.resolve_order(ModuleCatalog.get_ids())
	assert_ok(result, "The shipped modules do not form a resolvable graph")
	var ordered: Array = result.payload
	assert_size(ordered, ModuleCatalog.get_ids().size())


func test_dependencies_come_before_the_modules_that_require_them() -> void:
	var result := ModuleCatalog.resolve_order(ModuleCatalog.get_ids())
	var ordered: Array = result.payload

	var seen: Array[StringName] = []
	for id in ordered:
		var manifest := ModuleCatalog.get_manifest(id)
		for dependency in manifest.requires:
			assert_has(
				seen,
				dependency,
				"%s was ordered before its requirement %s" % [id, dependency]
			)
		seen.append(id)


func test_the_order_is_the_same_every_run() -> void:
	# An unstable registration order turns a dependency bug into an
	# intermittent one, which is the most expensive kind to find.
	var first: Array = ModuleCatalog.resolve_order(ModuleCatalog.get_ids()).payload
	var second: Array = ModuleCatalog.resolve_order(ModuleCatalog.get_ids()).payload
	assert_eq(first, second)


func test_optional_dependencies_do_not_constrain_the_order() -> void:
	# World lists Entity as optional. Asking for World alone must succeed --
	# ordering by an optional dependency would report a missing module for a
	# relationship that is explicitly allowed to be absent (rule 31).
	var ids: Array[StringName] = [&"module.world_state"]
	var result := ModuleCatalog.resolve_order(ids)
	assert_ok(result)
	assert_eq(result.payload, ids)


func test_an_unknown_module_is_named_rather_than_skipped() -> void:
	var ids: Array[StringName] = [&"module.entity", &"module.telepathy"]
	var result := ModuleCatalog.resolve_order(ids)
	assert_err(result, &"catalog.unknown_module")
	assert_true(
		result.message.contains("module.telepathy"), "The message names the bad id"
	)


func test_a_missing_dependency_names_both_ends() -> void:
	var ids: Array[StringName] = [&"module.inventory"]
	var result := ModuleCatalog.resolve_order(ids)
	assert_err(result, &"catalog.missing_dependency")
	assert_true(result.message.contains("module.inventory"))
	assert_true(result.message.contains("module.items"))


func test_implied_requirements_are_the_transitive_closure() -> void:
	# Inventory requires Items, Items requires Entity. Asking for Inventory
	# has to surface both, not just the one it names directly.
	var ids: Array[StringName] = [&"module.inventory"]
	var implied := ModuleCatalog.get_implied_requirements(ids)
	assert_has(implied, &"module.items")
	assert_has(implied, &"module.entity")
	assert_has_not(implied, &"module.inventory", "What was asked for is not implied")


func test_nothing_is_implied_when_the_list_is_already_complete() -> void:
	var ids: Array[StringName] = [&"module.entity", &"module.items", &"module.inventory"]
	assert_empty(ModuleCatalog.get_implied_requirements(ids))


# --- Installing -----------------------------------------------------------

func test_settings_alone_bring_up_the_modules_they_ask_for() -> void:
	# The exit gate in one test: a project names modules and gets modules. No
	# script, no scene, no copied code.
	var core := make_autoload(CORE_SCRIPT, "PackagingInstallCore")
	var settings := _settings([&"module.entity", &"module.items", &"module.inventory"])

	var result: ValidationResult = core.bootstrap(settings)

	assert_false(result.has_errors(), result.format_report())
	assert_true(core.has_feature(&"module.entity"))
	assert_true(core.has_feature(&"module.items"))
	assert_true(core.has_feature(&"module.inventory"))


func test_installing_registers_in_dependency_order() -> void:
	# Proven through the registry rather than by inspecting the plan: the
	# module registry refuses a module whose requirements are absent, so
	# three successful registrations *are* the ordering.
	var core := make_autoload(CORE_SCRIPT, "PackagingOrderCore")
	var settings := _settings([&"module.inventory", &"module.items", &"module.entity"])

	core.bootstrap(settings)

	assert_size(core.get_module_ids(), 3, "One of them was refused for a missing dependency")


func test_the_entire_framework_installs_at_once() -> void:
	# Thirty-one modules, one settings resource. If any pair of them cannot
	# coexist, this is where it shows.
	var core := make_autoload(CORE_SCRIPT, "PackagingFullCore")
	var settings := _settings(ModuleCatalog.get_ids())

	var result: ValidationResult = core.bootstrap(settings)

	assert_false(result.has_errors(), result.format_report())
	assert_size(core.get_module_ids(), ModuleCatalog.get_ids().size())


func test_an_incomplete_list_registers_nothing_at_all() -> void:
	# Rule 17. Registering the half that resolves would leave a project with
	# Items but no Inventory and an error it probably did not read.
	var core := make_autoload(CORE_SCRIPT, "PackagingPartialCore")
	var settings := _settings([&"module.entity", &"module.inventory"])

	var result: ValidationResult = core.bootstrap(settings)

	assert_true(result.has_errors())
	assert_empty(core.get_module_ids(), "Entity registered despite the list failing")


func test_an_incomplete_list_says_what_to_add() -> void:
	var core := make_autoload(CORE_SCRIPT, "PackagingAdviceCore")
	var settings := _settings([&"module.inventory"])

	var result: ValidationResult = core.bootstrap(settings)
	var report := result.format_report()

	assert_true(report.contains("module.items"), report)
	assert_true(report.contains("module.entity"), report)


func test_module_registration_can_be_turned_off() -> void:
	# For a project substituting its own implementation of a shipped module,
	# or registering one the addon does not ship.
	var core := make_autoload(CORE_SCRIPT, "PackagingManualCore")
	var settings := _settings([&"module.entity"])
	settings.register_enabled_modules = false

	core.bootstrap(settings)

	assert_true(core.is_module_enabled(&"module.entity"), "Still what the project asked for")
	assert_empty(core.get_module_ids(), "But nothing was installed on its behalf")


func test_a_module_switched_off_is_not_installed() -> void:
	var core := make_autoload(CORE_SCRIPT, "PackagingDisabledCore")
	var settings := _settings([&"module.entity"])
	settings.set_module_enabled(&"module.items", false)

	core.bootstrap(settings)

	assert_true(core.has_feature(&"module.entity"))
	assert_false(core.has_feature(&"module.items"))


func test_shutdown_removes_everything_that_was_installed() -> void:
	var core := make_autoload(CORE_SCRIPT, "PackagingShutdownCore")
	core.bootstrap(_settings([&"module.entity", &"module.items"]))
	assert_size(core.get_module_ids(), 2)

	core.shutdown()

	assert_empty(core.get_module_ids())
	assert_false(core.is_bootstrapped())


func test_a_project_with_no_modules_chosen_is_not_an_error() -> void:
	var core := make_autoload(CORE_SCRIPT, "PackagingEmptyCore")
	var result: ValidationResult = core.bootstrap(FrameworkSettings.new())
	assert_false(result.has_errors(), result.format_report())


func test_preview_reports_the_plan_without_installing_it() -> void:
	var settings := _settings([&"module.inventory", &"module.items", &"module.entity"])
	var plan := FrameworkBootstrapper.preview(settings)
	assert_size(plan, 3)
	assert_eq(plan[0], &"module.entity", "Entity has no requirements, so it is first")


func test_preview_of_an_unresolvable_list_is_empty() -> void:
	assert_empty(FrameworkBootstrapper.preview(_settings([&"module.inventory"])))


func test_installing_without_a_core_is_refused_rather_than_crashing() -> void:
	var result := FrameworkBootstrapper.install(null, _settings([&"module.entity"]))
	assert_true(result.has_errors())


# --- The addon stands alone ----------------------------------------------

func test_no_addon_file_reaches_outside_the_addon() -> void:
	# What "packaged" means. An addon script that loads res://tests/ or a
	# project's own folder works perfectly in this repository and breaks the
	# moment somebody copies addons/ into their game -- which is the only way
	# anyone will ever install it.
	var offenders: Array[String] = []
	for path in _find_scripts(ADDON_ROOT):
		var source := _read_without_comments(path)
		for forbidden in ["res://tests/", "res://examples/", "res://game/"]:
			if source.contains(forbidden):
				offenders.append("%s references %s" % [path, forbidden])
	assert_empty(offenders, "\n".join(offenders))


func test_the_addon_ships_no_content_definitions() -> void:
	# Rule 29. A .tres under addons/ is game content living in the framework,
	# and every project that installs the addon inherits it.
	var resources := _find_by_extension(ADDON_ROOT, "tres")
	assert_empty(resources, "Content resources under addons/: %s" % str(resources))


func test_the_plugin_version_matches_the_framework_version() -> void:
	# Two places state the version. They are read by different audiences --
	# the editor's plugin list and the framework's own migration code -- and
	# a mismatch means one of those audiences is being told a lie.
	var config := ConfigFile.new()
	assert_eq(config.load(PLUGIN_CFG), OK, "plugin.cfg could not be read")
	assert_eq(
		str(config.get_value("plugin", "version", "")),
		FrameworkVersion.get_version_string()
	)


func test_the_plugin_declares_a_script_that_exists() -> void:
	var config := ConfigFile.new()
	config.load(PLUGIN_CFG)
	var script_name := str(config.get_value("plugin", "script", ""))
	assert_false(script_name.is_empty(), "plugin.cfg names no script")
	assert_true(
		ResourceLoader.exists(ADDON_ROOT.path_join(script_name)),
		"plugin.cfg points at %s, which does not exist" % script_name
	)


# --- Helpers --------------------------------------------------------------

func _settings(ids: Array[StringName]) -> FrameworkSettings:
	var settings := FrameworkSettings.new()
	for id in ids:
		settings.set_module_enabled(id, true)
	# Nothing to scan and nothing to validate: these tests are about modules.
	settings.scan_definitions_on_bootstrap = false
	settings.validate_on_bootstrap = false
	return settings


func _find_module_scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	for path in _find_scripts(directory):
		if path.get_file().ends_with("_module.gd") and path != MODULE_CONTRACT:
			found.append(path)
	return found


func _find_scripts(directory: String) -> Array[String]:
	return _find_by_extension(directory, "gd")


func _find_by_extension(directory: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full_path := directory.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_find_by_extension(full_path, extension))
			elif entry.get_extension() == extension:
				found.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Source with comment lines removed, so a doc comment mentioning a path is
## not mistaken for code that loads it.
func _read_without_comments(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var kept: Array[String] = []
	while not file.eof_reached():
		var line := file.get_line()
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	file.close()
	return "\n".join(kept)
