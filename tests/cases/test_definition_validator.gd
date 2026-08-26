extends FrameworkTestCase
## Covers DefinitionValidator and FrameworkDefinition.validate().

const SampleDefinition := preload("res://tests/support/sample_definition.gd")

var registry: DefinitionRegistry = null


func before_each() -> void:
	registry = DefinitionRegistry.new()


func _make(id: StringName, display_name: String = "x") -> FrameworkDefinition:
	var definition := SampleDefinition.new()
	definition.id = id
	definition.display_name = display_name
	return definition


func test_valid_definition_passes() -> void:
	assert_true(DefinitionValidator.validate_definition(_make(&"item.sword")).is_valid())


func test_missing_id_is_an_error() -> void:
	var result := DefinitionValidator.validate_definition(SampleDefinition.new())
	assert_true(result.has_errors())
	assert_eq(result.get_errors()[0].code, &"definition.missing_id")


func test_missing_display_name_is_only_a_warning() -> void:
	var result := DefinitionValidator.validate_definition(_make(&"item.sword", ""))
	assert_false(result.has_errors())
	assert_true(result.has_warnings())


func test_empty_tag_warns() -> void:
	var definition := _make(&"item.sword")
	definition.tags = [&""]
	assert_true(DefinitionValidator.validate_definition(definition).has_warnings())


func test_subclass_rules_run_alongside_base_rules() -> void:
	# SampleDefinition.validate() calls super() then adds its own check.
	var definition := SampleDefinition.new()
	definition.power = -5.0
	var codes: Array[StringName] = []
	for issue in DefinitionValidator.validate_definition(definition).get_errors():
		codes.append(issue.code)
	assert_has(codes, &"definition.missing_id", "The base rule ran")
	assert_has(codes, &"sample.invalid_power", "The subclass rule ran too")


func test_null_definition_is_reported() -> void:
	assert_true(DefinitionValidator.validate_definition(null).has_errors())


func test_null_registry_is_reported() -> void:
	assert_true(DefinitionValidator.validate_registry(null).has_errors())


func test_validate_registry_covers_every_definition() -> void:
	registry.register(_make(&"item.a"))
	var broken := _make(&"item.b")
	broken.power = -1.0
	registry.register(broken)
	assert_size(DefinitionValidator.validate_registry(registry).get_errors(), 1)


func test_near_duplicate_ids_warn() -> void:
	# The registry rejects exact duplicates. These are the near-misses it
	# cannot, and they produce the hardest bug reports.
	registry.register(_make(&"Item.Sword"))
	registry.register(_make(&"item.sword"))
	var result := DefinitionValidator.check_id_collisions(registry)
	assert_true(result.has_warnings())
	assert_eq(result.get_warnings()[0].code, &"validator.near_duplicate_id")


func test_distinct_ids_do_not_warn() -> void:
	registry.register(_make(&"item.sword"))
	registry.register(_make(&"item.axe"))
	assert_true(DefinitionValidator.check_id_collisions(registry).is_empty())


func test_unresolved_reference_is_an_error() -> void:
	registry.register(_make(&"item.sword"))
	var result := DefinitionValidator.check_references(
		registry, [&"item.sword", &"item.ghost"], "res://loot.tres", "entries"
	)
	assert_size(result.get_errors(), 1)
	assert_eq(result.get_errors()[0].code, &"validator.unresolved_reference")
	assert_has(str(result.get_errors()[0]), "res://loot.tres")


func test_empty_reference_warns() -> void:
	var result := DefinitionValidator.check_references(registry, [&""])
	assert_true(result.has_warnings())
	assert_false(result.has_errors())


func test_resolved_references_pass() -> void:
	registry.register(_make(&"item.sword"))
	assert_true(DefinitionValidator.check_references(registry, [&"item.sword"]).is_valid())


func test_finds_a_direct_cycle() -> void:
	# Implementation Plan 28 calls out circular mission chains by name.
	var edges: Dictionary[StringName, Array] = {
		&"mission.a": [&"mission.b"],
		&"mission.b": [&"mission.a"],
	}
	assert_size(DefinitionValidator.find_cycles(edges), 1)


func test_finds_a_longer_cycle() -> void:
	var edges: Dictionary[StringName, Array] = {
		&"a": [&"b"],
		&"b": [&"c"],
		&"c": [&"a"],
	}
	var cycles := DefinitionValidator.find_cycles(edges)
	assert_size(cycles, 1)
	assert_size(cycles[0], 3)


func test_self_cycle_is_found() -> void:
	var edges: Dictionary[StringName, Array] = {&"a": [&"a"]}
	assert_size(DefinitionValidator.find_cycles(edges), 1)


func test_acyclic_chain_is_clean() -> void:
	var edges: Dictionary[StringName, Array] = {
		&"a": [&"b"],
		&"b": [&"c"],
		&"c": [],
	}
	assert_empty(DefinitionValidator.find_cycles(edges))


func test_diamond_is_not_a_cycle() -> void:
	# Two paths to one node is normal in a mission graph.
	var edges: Dictionary[StringName, Array] = {
		&"a": [&"b", &"c"],
		&"b": [&"d"],
		&"c": [&"d"],
		&"d": [],
	}
	assert_empty(DefinitionValidator.find_cycles(edges))


func test_empty_graph_is_clean() -> void:
	var edges: Dictionary[StringName, Array] = {}
	assert_empty(DefinitionValidator.find_cycles(edges))
