extends FrameworkTestCase
## End-to-end content loading: scanning folders for definitions, and resolving
## the settings resource named by project settings.
##
## Everything above this file works on objects built in memory. These tests
## exercise the parts that touch disk, which is where content pipelines
## actually break.

const CORE_SCRIPT := "res://addons/universal_gameplay/core/framework_core.gd"
const CONTENT_DIR := "res://tests/content"
const SETTINGS_PATH := "res://tests/content/test_settings.tres"

var registry: DefinitionRegistry = null


func before_each() -> void:
	registry = DefinitionRegistry.new()


# --- Scanning -------------------------------------------------------------

func test_scan_loads_definitions_recursively() -> void:
	var result := registry.scan_directory(CONTENT_DIR)
	assert_false(result.has_errors(), result.format_report())
	assert_true(registry.has_definition(&"content.sword"), "Found the top-level definition")
	assert_true(registry.has_definition(&"content.shield"), "...and the nested one")


func test_scan_reads_exported_fields() -> void:
	registry.scan_directory(CONTENT_DIR)
	var sword := registry.get_definition(&"content.sword")
	assert_not_null(sword)
	assert_eq(sword.display_name, "Iron Sword")
	assert_eq(sword.power, 5.0, "A subclass field survived the round trip")
	assert_true(sword.has_tag(&"item.weapon"))


func test_scan_skips_non_definition_resources() -> void:
	# Profiles, curves and other plain Resources live alongside definitions
	# legitimately. Skipping them is correct; erroring on them is not.
	var result := registry.scan_directory(CONTENT_DIR)
	assert_false(result.has_errors())
	assert_eq(registry.size(), 2, "Only the two definitions were registered")


func test_rescanning_the_same_folder_is_idempotent() -> void:
	# The resource cache hands back the same instances, so a second scan must
	# not trip the duplicate-id check.
	registry.scan_directory(CONTENT_DIR)
	var second := registry.scan_directory(CONTENT_DIR)
	assert_false(second.has_errors(), second.format_report())
	assert_eq(registry.size(), 2)


func test_scanned_content_validates() -> void:
	registry.scan_directory(CONTENT_DIR)
	assert_true(DefinitionValidator.validate_registry(registry).is_valid())


func test_scanned_content_is_queryable_by_tag() -> void:
	registry.scan_directory(CONTENT_DIR)
	assert_size(registry.get_by_tag(&"item.weapon"), 1)
	assert_size(registry.get_by_tag(&"item.armour"), 1)


# --- Bootstrap through settings ------------------------------------------

func test_bootstrap_scans_the_paths_in_settings() -> void:
	var core := make_autoload(CORE_SCRIPT, "CoreContentTest")
	var settings := FrameworkSettings.new()
	settings.definition_paths = [CONTENT_DIR]

	var result: ValidationResult = core.bootstrap(settings)
	assert_false(result.has_errors(), result.format_report())
	assert_true(core.has_definition(&"content.sword"))
	assert_eq(core.get_definition_registry().size(), 2)


func test_bootstrap_can_skip_scanning() -> void:
	var core := make_autoload(CORE_SCRIPT, "CoreNoScanTest")
	var settings := FrameworkSettings.new()
	settings.definition_paths = [CONTENT_DIR]
	settings.scan_definitions_on_bootstrap = false

	core.bootstrap(settings)
	assert_eq(core.get_definition_registry().size(), 0, "Nothing was scanned")


# --- The settings resource itself ----------------------------------------

func test_settings_resource_loads_from_disk() -> void:
	var settings: FrameworkSettings = load(SETTINGS_PATH)
	assert_not_null(settings)
	assert_has(settings.definition_paths, CONTENT_DIR)
	assert_true(settings.is_module_enabled(&"module.inventory"))
	assert_false(settings.is_module_enabled(&"module.vehicles"))


func test_core_resolves_the_settings_path_from_project_settings() -> void:
	# The auto-bootstrap path. Core reads this during _ready(), which the
	# harness cannot trigger, so the resolution step is exercised directly --
	# it is the half that touches disk and can actually fail.
	var core := make_autoload(CORE_SCRIPT, "CoreSettingsPathTest")
	var property: String = core.SETTINGS_PATH_PROPERTY
	var had_setting := ProjectSettings.has_setting(property)
	var previous: Variant = ProjectSettings.get_setting(property, "") if had_setting else ""

	ProjectSettings.set_setting(property, SETTINGS_PATH)
	var loaded: FrameworkSettings = core._load_configured_settings()

	if had_setting:
		ProjectSettings.set_setting(property, previous)
	else:
		ProjectSettings.clear(property)

	assert_not_null(loaded, "Core resolved the configured settings resource")
	assert_has(loaded.definition_paths, CONTENT_DIR)


func test_missing_settings_path_resolves_to_null() -> void:
	var core := make_autoload(CORE_SCRIPT, "CoreBadSettingsTest")
	var property: String = core.SETTINGS_PATH_PROPERTY
	var had_setting := ProjectSettings.has_setting(property)
	var previous: Variant = ProjectSettings.get_setting(property, "") if had_setting else ""

	ProjectSettings.set_setting(property, "res://nope/missing.tres")
	var loaded: FrameworkSettings = core._load_configured_settings()

	if had_setting:
		ProjectSettings.set_setting(property, previous)
	else:
		ProjectSettings.clear(property)

	assert_null(loaded, "A bad path warns and yields null rather than crashing")


func test_settings_validation_flags_a_missing_content_path() -> void:
	var settings := FrameworkSettings.new()
	settings.definition_paths = ["res://not/here"]
	var result := settings.validate()
	assert_true(result.has_warnings())
	assert_false(result.has_errors())


func test_settings_validation_flags_an_empty_module_id() -> void:
	var settings := FrameworkSettings.new()
	settings.set_module_enabled(&"", true)
	assert_true(settings.validate().has_errors())


func test_enabled_module_ids() -> void:
	var settings := FrameworkSettings.new()
	settings.set_module_enabled(&"module.a", true)
	settings.set_module_enabled(&"module.b", false)
	var enabled := settings.get_enabled_module_ids()
	assert_size(enabled, 1)
	assert_has(enabled, &"module.a")
