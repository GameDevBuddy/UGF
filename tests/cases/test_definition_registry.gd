extends FrameworkTestCase
## Covers DefinitionRegistry.

const SampleDefinition := preload("res://tests/support/sample_definition.gd")

var registry: DefinitionRegistry = null


func before_each() -> void:
	registry = DefinitionRegistry.new()


func _make(id: StringName, tags: Array[StringName] = []) -> FrameworkDefinition:
	var definition := SampleDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.tags = tags.duplicate()
	return definition


func test_register_and_resolve() -> void:
	assert_ok(registry.register(_make(&"item.sword")))
	assert_true(registry.has_definition(&"item.sword"))
	assert_eq(registry.get_definition(&"item.sword").id, &"item.sword")
	assert_eq(registry.size(), 1)


func test_unknown_id_resolves_to_null() -> void:
	assert_null(registry.get_definition(&"item.nope"))
	assert_false(registry.has_definition(&"item.nope"))


func test_null_definition_rejected() -> void:
	assert_err(registry.register(null), &"definition.null")


func test_definition_without_id_rejected() -> void:
	assert_err(registry.register(SampleDefinition.new()), &"definition.missing_id")


func test_duplicate_id_rejected() -> void:
	# Two definitions claiming one id is a content bug that would otherwise
	# surface much later as the wrong thing spawning.
	assert_ok(registry.register(_make(&"item.sword")))
	var second := registry.register(_make(&"item.sword"))
	assert_err(second, &"definition.duplicate_id")
	assert_eq(registry.size(), 1, "The colliding definition is not stored")


func test_duplicate_id_allowed_with_overwrite() -> void:
	var first := _make(&"item.sword")
	var second := _make(&"item.sword")
	assert_ok(registry.register(first))
	assert_ok(registry.register(second, true))
	assert_eq(registry.get_definition(&"item.sword"), second)


func test_reregistering_same_instance_is_a_noop() -> void:
	# A folder scan overlapping an explicit registration must not fail.
	var definition := _make(&"item.sword")
	assert_ok(registry.register(definition))
	assert_ok(registry.register(definition))
	assert_eq(registry.size(), 1)


func test_unregister() -> void:
	registry.register(_make(&"item.sword"))
	assert_true(registry.unregister(&"item.sword"))
	assert_false(registry.has_definition(&"item.sword"))
	assert_false(registry.unregister(&"item.sword"), "Unregistering twice reports false")


func test_get_by_tag() -> void:
	registry.register(_make(&"npc.smith", [&"role.vendor", &"character.human"]))
	registry.register(_make(&"npc.guard", [&"role.guard", &"character.human"]))
	registry.register(_make(&"item.sword", [&"item.weapon"]))

	assert_size(registry.get_by_tag(&"character.human"), 2)
	assert_size(registry.get_by_tag(&"role.vendor"), 1)
	assert_empty(registry.get_by_tag(&"role.nonexistent"))


func test_get_by_script_matches_subclasses() -> void:
	# Lets a module ask for "all VehicleDefinitions" without Core knowing that
	# type exists.
	registry.register(_make(&"item.sword"))
	registry.register(_make(&"item.axe"))
	assert_size(registry.get_by_script(SampleDefinition), 2)
	assert_size(registry.get_by_script(FrameworkDefinition), 2, "Base class matches subclasses")
	assert_empty(registry.get_by_script(null))


func test_get_ids_and_clear() -> void:
	registry.register(_make(&"a"))
	registry.register(_make(&"b"))
	var ids := registry.get_ids()
	assert_size(ids, 2)
	assert_has(ids, &"a")
	registry.clear()
	assert_eq(registry.size(), 0)


func test_scan_missing_directory_warns_without_failing() -> void:
	var result := registry.scan_directory("res://definitely/not/here")
	assert_false(result.has_errors(), "A missing content folder is a warning, not an error")
	assert_true(result.has_warnings())
