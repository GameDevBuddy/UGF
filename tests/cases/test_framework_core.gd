extends FrameworkTestCase
## Covers FrameworkCore, including M0's exit gate: the framework loads with
## zero game content.

const CORE_SCRIPT := "res://addons/universal_gameplay/core/framework_core.gd"
const SampleModule := preload("res://tests/support/sample_module.gd")
const SampleDefinition := preload("res://tests/support/sample_definition.gd")

var core: Node = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCoreUnderTest")


func _module(id: StringName) -> SampleModule:
	var module := SampleModule.new()
	module.configure(id)
	return module


func _definition(id: StringName) -> FrameworkDefinition:
	var definition := SampleDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	return definition


# --- Exit gate ------------------------------------------------------------

func test_framework_loads_with_zero_game_content() -> void:
	# M0's headline gate. No definitions, no modules, no settings resource --
	# the framework must still come up clean.
	var result: ValidationResult = core.bootstrap()
	assert_true(core.is_bootstrapped())
	assert_true(result.is_valid(), "Bootstrap with no content produces no errors")
	assert_eq(core.get_definition_registry().size(), 0)
	assert_empty(core.get_module_ids())


func test_sample_module_registers_and_unregisters() -> void:
	# The other half of the gate.
	core.bootstrap()
	var module := _module(&"module.sample")
	assert_ok(core.register_module(module))
	assert_true(core.has_feature(&"module.sample"))
	assert_ok(core.unregister_module(&"module.sample"))
	assert_false(core.has_feature(&"module.sample"))
	assert_eq(module.initialize_count, 1)
	assert_eq(module.shutdown_count, 1)


# --- Lifecycle ------------------------------------------------------------

func test_core_is_usable_before_ready_runs() -> void:
	# Godot defers _ready() to the first process frame, so an autoload is
	# reachable before its _ready() has run. Core must be fully wired on first
	# use, not one frame later -- this test runs entirely within _initialize(),
	# so _ready() has definitively not fired yet.
	# Deliberately not added to the tree, so _ready() has definitively not run.
	var fresh: Node = load(CORE_SCRIPT).new()

	var seen: Array[StringName] = []
	fresh.module_registered.connect(func(id: StringName) -> void: seen.append(id))

	assert_ok(fresh.register_module(_module(&"module.early")))
	assert_true(fresh.has_feature(&"module.early"))
	assert_eq(seen, [&"module.early"] as Array[StringName], "The relay was wired on first use")
	fresh.free()


func test_not_bootstrapped_until_asked() -> void:
	assert_false(core.is_bootstrapped(), "Without a configured settings path, Core waits")


func test_double_bootstrap_warns() -> void:
	core.bootstrap()
	var second: ValidationResult = core.bootstrap()
	assert_true(second.has_warnings())
	assert_true(second.is_valid(), "A second bootstrap is a warning, not an error")


func test_shutdown_returns_core_to_a_clean_state() -> void:
	core.bootstrap()
	core.register_service(&"service.test", RefCounted.new())
	core.register_definition(_definition(&"thing.a"))
	core.register_module(_module(&"module.sample"))

	core.shutdown()

	assert_false(core.is_bootstrapped())
	assert_false(core.has_service(&"service.test"))
	assert_false(core.has_definition(&"thing.a"))
	assert_false(core.has_feature(&"module.sample"))


func test_shutdown_before_bootstrap_is_safe() -> void:
	core.shutdown()
	assert_false(core.is_bootstrapped())


func test_can_bootstrap_again_after_shutdown() -> void:
	core.bootstrap()
	core.shutdown()
	assert_true(core.bootstrap().is_valid())
	assert_true(core.is_bootstrapped())


func test_shutdown_shuts_modules_down() -> void:
	core.bootstrap()
	var module := _module(&"module.sample")
	core.register_module(module)
	core.shutdown()
	assert_eq(module.shutdown_count, 1)


func test_lifecycle_signals() -> void:
	var seen: Array[String] = []
	core.bootstrapped.connect(func() -> void: seen.append("bootstrapped"))
	core.shutting_down.connect(func() -> void: seen.append("shutting_down"))
	core.bootstrap()
	core.shutdown()
	assert_eq(seen, ["bootstrapped", "shutting_down"] as Array[String])


func test_module_signals_are_relayed() -> void:
	core.bootstrap()
	var seen: Array[StringName] = []
	core.module_registered.connect(func(id: StringName) -> void: seen.append(id))
	core.module_unregistered.connect(func(id: StringName) -> void: seen.append(id))
	core.register_module(_module(&"module.sample"))
	core.unregister_module(&"module.sample")
	assert_eq(seen, [&"module.sample", &"module.sample"] as Array[StringName])


# --- Services -------------------------------------------------------------

func test_register_and_resolve_service() -> void:
	var service := RefCounted.new()
	assert_ok(core.register_service(&"service.save", service))
	assert_true(core.has_service(&"service.save"))
	assert_eq(core.get_service(&"service.save"), service)


func test_unknown_service_resolves_to_null() -> void:
	assert_null(core.get_service(&"service.nope"))
	assert_false(core.has_service(&"service.nope"))


func test_null_service_rejected() -> void:
	assert_err(core.register_service(&"service.save", null), &"service.null")


func test_service_id_cannot_be_empty() -> void:
	assert_err(core.register_service(&"", RefCounted.new()), &"service.invalid_id")


func test_replacing_a_service_is_reported() -> void:
	core.register_service(&"service.save", RefCounted.new())
	var second: FrameworkResult = core.register_service(&"service.save", RefCounted.new())
	assert_ok(second)
	assert_true(second.payload, "Payload reports the registration replaced an existing one")


func test_framework_service_lifecycle_hooks_fire() -> void:
	var service := FrameworkService.new()
	add_test_node(service)
	core.register_service(&"service.test", service)
	core.unregister_service(&"service.test")
	assert_false(core.has_service(&"service.test"))


func test_freed_service_is_not_reported_as_present() -> void:
	# A Node service can outlive its registration when a scene unloads.
	var service := Node.new()
	core.register_service(&"service.transient", service)
	assert_true(core.has_service(&"service.transient"))
	service.free()
	assert_false(core.has_service(&"service.transient"))
	assert_eq(core.get_service_registry().prune_invalid(), 1)


# --- Features -------------------------------------------------------------

func test_has_feature_reflects_registration_not_intent() -> void:
	# Settings say what the project asked for; has_feature says what actually
	# came up. Adapters must branch on the latter.
	var settings := FrameworkSettings.new()
	settings.set_module_enabled(&"module.vehicles", true)
	core.bootstrap(settings)

	assert_true(core.is_module_enabled(&"module.vehicles"), "The project asked for it")
	assert_false(core.has_feature(&"module.vehicles"), "But nothing registered it")

	core.register_module(_module(&"module.vehicles"))
	assert_true(core.has_feature(&"module.vehicles"))


func test_entity_context_reads_features_through_core() -> void:
	core.bootstrap()
	core.register_module(_module(&"module.inventory"))
	var context := EntityContext.create(add_test_node(Node.new()), null, core)
	assert_true(context.has_feature(&"module.inventory"))
	assert_false(context.has_feature(&"module.commerce"))


# --- Definitions ----------------------------------------------------------

func test_register_and_resolve_definition() -> void:
	core.bootstrap()
	assert_ok(core.register_definition(_definition(&"item.sword")))
	assert_true(core.has_definition(&"item.sword"))
	assert_eq(core.get_definition(&"item.sword").id, &"item.sword")


func test_bootstrap_validates_registered_definitions() -> void:
	var broken := SampleDefinition.new()
	broken.id = &"item.broken"
	broken.power = -1.0
	core.register_definition(broken)

	var result: ValidationResult = core.bootstrap()
	assert_true(result.has_errors(), "An invalid definition is reported at bootstrap")
	assert_eq(core.get_bootstrap_result(), result)


func test_validation_can_be_skipped() -> void:
	var broken := SampleDefinition.new()
	broken.id = &"item.broken"
	broken.power = -1.0
	core.register_definition(broken)

	var settings := FrameworkSettings.new()
	settings.validate_on_bootstrap = false
	assert_false(core.bootstrap(settings).has_errors())


func test_missing_content_path_warns_without_failing() -> void:
	var settings := FrameworkSettings.new()
	settings.definition_paths = ["res://content/does_not_exist"]
	var result: ValidationResult = core.bootstrap(settings)
	assert_true(result.has_warnings())
	assert_false(result.has_errors(), "A missing content folder must not stop the framework")
	assert_true(core.is_bootstrapped())
