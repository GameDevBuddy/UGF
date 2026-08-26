extends FrameworkTestCase
## Covers the Core context and result types.

const SampleDefinition := preload("res://tests/support/sample_definition.gd")


func test_result_ok_carries_payload() -> void:
	var result := FrameworkResult.ok("payload")
	assert_true(result.is_ok())
	assert_false(result.is_err())
	assert_eq(result.payload, "payload")
	assert_eq(result.code, &"")


func test_result_fail_carries_code() -> void:
	var result := FrameworkResult.fail(&"thing.broken", "It broke.")
	assert_true(result.is_err())
	assert_true(result.failed_with(&"thing.broken"))
	assert_false(result.failed_with(&"other.code"))


func test_ok_result_never_matches_a_failure_code() -> void:
	assert_false(FrameworkResult.ok().failed_with(&""))


func test_damage_context_clamps_negative_amounts() -> void:
	# Healing is its own operation, not negative damage.
	var context := DamageContext.create(-50.0)
	assert_eq(context.amount, 0.0)
	assert_eq(context.final_amount, 0.0)
	assert_false(context.is_effective())


func test_damage_context_seeds_final_amount() -> void:
	var context := DamageContext.create(25.0)
	assert_eq(context.final_amount, 25.0, "final_amount starts at the requested amount")
	assert_true(context.is_effective())


func test_damage_context_tags() -> void:
	var tags: Array[StringName] = [&"damage.fire", &"damage.magical"]
	var context := DamageContext.create(10.0, null, null, tags)
	assert_true(context.has_tag(&"damage.fire"))
	assert_false(context.has_tag(&"damage.ice"))
	assert_true(context.has_any_tag([&"damage.ice", &"damage.magical"]))
	assert_false(context.has_any_tag([&"damage.ice"]))


func test_damage_context_copies_tag_array() -> void:
	# A caller reusing one tag array must not be able to mutate a context
	# that was already built from it.
	var tags: Array[StringName] = [&"damage.fire"]
	var context := DamageContext.create(10.0, null, null, tags)
	tags.append(&"damage.ice")
	assert_false(context.has_tag(&"damage.ice"))


func test_fully_absorbed_damage_is_not_effective() -> void:
	var context := DamageContext.create(30.0)
	context.final_amount = 0.0
	assert_false(context.is_effective(), "Armour absorbing everything is a real, zero-damage hit")


func test_entity_context_exposes_definition() -> void:
	var entity := add_test_node(Node.new())
	var definition := SampleDefinition.new()
	definition.id = &"sample.thing"
	var context := EntityContext.create(entity, definition)
	assert_true(context.has_definition())
	assert_eq(context.entity, entity)
	assert_eq(context.definition.id, &"sample.thing")


func test_entity_context_without_definition() -> void:
	var context := EntityContext.create(add_test_node(Node.new()))
	assert_false(context.has_definition())


func test_entity_context_has_feature_is_safe_without_core() -> void:
	# An entity assembled outside a bootstrapped framework must not crash on
	# a feature check; it simply has no features.
	var context := EntityContext.create(add_test_node(Node.new()))
	assert_false(context.has_feature(&"module.anything"))
