extends FrameworkTestCase
## Covers PersistentIdentity.

var entity: Node = null
var identity: PersistentIdentity = null


func before_each() -> void:
	entity = add_test_node(Node.new())
	identity = PersistentIdentity.new()
	entity.add_child(identity)


func test_authored_id_is_left_alone() -> void:
	# An entity placed in a level keeps the id the designer gave it, for every
	# save that level ever produces.
	identity.persistent_id = &"npc.town.blacksmith"
	assert_eq(identity.get_persistent_id(), &"npc.town.blacksmith")


func test_id_is_generated_on_first_use() -> void:
	assert_false(identity.has_persistent_id())
	var generated := identity.get_persistent_id()
	assert_ne(generated, &"")
	assert_true(identity.has_persistent_id())


func test_generated_id_is_stable_across_calls() -> void:
	assert_eq(identity.get_persistent_id(), identity.get_persistent_id())


func test_generated_ids_are_unique() -> void:
	var second := PersistentIdentity.new()
	entity.add_child(second)
	assert_ne(identity.get_persistent_id(), second.get_persistent_id())


func test_many_ids_in_one_tick_do_not_collide() -> void:
	# The microsecond clock alone is not enough; the sequence counter is what
	# makes this hold.
	var seen: Dictionary = {}
	for i in 200:
		var component := PersistentIdentity.new()
		entity.add_child(component)
		seen[component.get_persistent_id()] = true
	assert_size(seen, 200)


func test_generation_can_be_refused() -> void:
	identity.generate_if_missing = false
	assert_eq(identity.get_persistent_id(), &"")


func test_explicit_prefix_is_used() -> void:
	identity.id_prefix = "guard"
	assert_true(str(identity.get_persistent_id()).begins_with("guard."))


func test_prefix_falls_back_to_the_entity_definition() -> void:
	var definition := EntityDefinition.new()
	definition.id = &"character.guard"
	definition.id_prefix = "guard"
	identity.initialize(EntityContext.create(entity, definition))
	assert_true(str(identity.get_persistent_id()).begins_with("guard."))


func test_prefix_falls_back_to_the_definition_id() -> void:
	var definition := EntityDefinition.new()
	definition.id = &"character.guard"
	identity.initialize(EntityContext.create(entity, definition))
	assert_true(str(identity.get_persistent_id()).begins_with("character.guard."))


func test_prefix_falls_back_to_entity_with_no_definition() -> void:
	assert_true(str(identity.get_persistent_id()).begins_with("entity."))


func test_id_can_be_overwritten_on_load() -> void:
	identity.get_persistent_id()
	identity.set_persistent_id(&"restored.id")
	assert_eq(identity.get_persistent_id(), &"restored.id")


func test_saveable_by_default() -> void:
	assert_true(identity.is_saveable())


func test_ambient_entities_can_opt_out_of_saving() -> void:
	# Traffic and crowd NPCs are regenerated from definitions, not persisted.
	identity.saveable = false
	assert_false(identity.is_saveable())


func test_identity_does_not_serialise_itself() -> void:
	# The id lives on the record, not inside component state.
	assert_false(identity.is_persistent())
