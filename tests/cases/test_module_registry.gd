extends FrameworkTestCase
## Covers ModuleRegistry -- and with it M0's exit gate, that a sample module
## can register and unregister without a sibling dependency.

const SampleModule := preload("res://tests/support/sample_module.gd")

var registry: ModuleRegistry = null


func before_each() -> void:
	registry = ModuleRegistry.new()


func _module(
	id: StringName, requires: Array[StringName] = [], optional: Array[StringName] = []
) -> SampleModule:
	var module := SampleModule.new()
	module.configure(id, requires, optional)
	return module


func test_register_module() -> void:
	var module := _module(&"module.inventory")
	assert_ok(registry.register(module))
	assert_true(registry.has_module(&"module.inventory"))
	assert_eq(registry.size(), 1)


func test_register_calls_initialize_once() -> void:
	var module := _module(&"module.inventory")
	registry.register(module)
	assert_eq(module.initialize_count, 1)
	assert_eq(module.shutdown_count, 0)


func test_core_is_injected_not_looked_up() -> void:
	var core := add_test_node(Node.new())
	var scoped := ModuleRegistry.new(core)
	var module := _module(&"module.inventory")
	scoped.register(module)
	assert_eq(module.last_core, core)


func test_null_module_rejected() -> void:
	assert_err(registry.register(null), &"module.null")


func test_module_without_id_rejected() -> void:
	assert_err(registry.register(_module(&"")), &"module.invalid_manifest")


func test_double_registration_rejected() -> void:
	registry.register(_module(&"module.inventory"))
	assert_err(
		registry.register(_module(&"module.inventory")),
		&"module.already_registered"
	)
	assert_eq(registry.size(), 1)


func test_unregister_calls_shutdown() -> void:
	var module := _module(&"module.inventory")
	registry.register(module)
	assert_ok(registry.unregister(&"module.inventory"))
	assert_eq(module.shutdown_count, 1)
	assert_false(registry.has_module(&"module.inventory"))


func test_unregister_unknown_module() -> void:
	assert_err(registry.unregister(&"module.ghost"), &"module.not_registered")


func test_module_can_be_registered_again_after_removal() -> void:
	var module := _module(&"module.inventory")
	registry.register(module)
	registry.unregister(&"module.inventory")
	assert_ok(registry.register(module))
	assert_eq(module.initialize_count, 2)


func test_missing_required_dependency_rejects_registration() -> void:
	var commerce := _module(&"module.commerce", [&"module.inventory"])
	assert_err(registry.register(commerce), &"module.missing_dependency")
	assert_false(registry.has_module(&"module.commerce"))
	assert_eq(commerce.initialize_count, 0, "A rejected module is never initialised")


func test_dependency_satisfied_allows_registration() -> void:
	registry.register(_module(&"module.inventory"))
	assert_ok(registry.register(_module(&"module.commerce", [&"module.inventory"])))
	assert_eq(registry.size(), 2)


func test_cannot_remove_a_module_others_depend_on() -> void:
	registry.register(_module(&"module.inventory"))
	registry.register(_module(&"module.commerce", [&"module.inventory"]))
	assert_err(registry.unregister(&"module.inventory"), &"module.has_dependents")
	assert_true(registry.has_module(&"module.inventory"), "The refused removal changed nothing")


func test_force_removes_despite_dependents() -> void:
	registry.register(_module(&"module.inventory"))
	registry.register(_module(&"module.commerce", [&"module.inventory"]))
	assert_ok(registry.unregister(&"module.inventory", true))
	assert_false(registry.has_module(&"module.inventory"))


func test_optional_dependencies_are_never_enforced() -> void:
	# Rule 31: a missing optional module is a valid state, not an error.
	var missions := _module(&"module.missions", [], [&"module.dialogue"])
	assert_ok(registry.register(missions))
	assert_ok(registry.unregister(&"module.missions"), "Optional deps do not block removal either")


func test_optional_dependent_does_not_block_removal() -> void:
	registry.register(_module(&"module.dialogue"))
	registry.register(_module(&"module.missions", [], [&"module.dialogue"]))
	assert_ok(registry.unregister(&"module.dialogue"))


func test_get_dependents() -> void:
	registry.register(_module(&"module.inventory"))
	registry.register(_module(&"module.commerce", [&"module.inventory"]))
	registry.register(_module(&"module.loot", [&"module.inventory"]))
	var dependents := registry.get_dependents(&"module.inventory")
	assert_size(dependents, 2)
	assert_has(dependents, &"module.commerce")
	assert_empty(registry.get_dependents(&"module.commerce"))


func test_self_dependency_rejected() -> void:
	assert_err(
		registry.register(_module(&"module.weird", [&"module.weird"])),
		&"module.invalid_manifest"
	)


func test_registration_signals() -> void:
	var seen: Array[StringName] = []
	registry.module_registered.connect(func(id: StringName) -> void: seen.append(id))
	registry.module_unregistered.connect(func(id: StringName) -> void: seen.append(id))
	registry.register(_module(&"module.inventory"))
	registry.unregister(&"module.inventory")
	assert_size(seen, 2)


func test_clear_removes_dependents_before_dependencies() -> void:
	# Each module must shut down while its own dependencies are still alive.
	var inventory := _module(&"module.inventory")
	var commerce := _module(&"module.commerce", [&"module.inventory"])
	registry.register(inventory)
	registry.register(commerce)

	var order: Array[StringName] = []
	registry.module_unregistered.connect(func(id: StringName) -> void: order.append(id))

	registry.clear()
	assert_eq(registry.size(), 0)
	assert_eq(order[0], &"module.commerce", "The dependent goes first")
	assert_eq(order[1], &"module.inventory")


func test_removing_one_module_leaves_unrelated_modules_working() -> void:
	# This is rule 10 stated as a test: deleting Commerce must not disturb
	# Combat. Neither declares the other, so removal is a non-event.
	var combat := _module(&"module.combat")
	var commerce := _module(&"module.commerce")
	registry.register(combat)
	registry.register(commerce)

	assert_ok(registry.unregister(&"module.commerce"))
	assert_true(registry.has_module(&"module.combat"))
	assert_eq(combat.shutdown_count, 0, "The surviving module was never touched")
	assert_eq(registry.size(), 1)
