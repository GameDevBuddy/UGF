extends FrameworkTestCase
## Covers the two built-in requirements: what they refuse, what they consume,
## and the guarantee that checking one never changes anything.

var keycard: ItemDefinition = null


func before_each() -> void:
	keycard = ItemFixtures.unique(&"item.keycard")


func _context_with(actor: Node, target: Node) -> InteractionContext:
	var interaction := InteractionFixtures.interaction_of(target)
	return interaction.make_context(actor)


func _actor_with_keycard(quantity: int = 1) -> Node:
	var actor := add_test_node(InteractionFixtures.actor("Player", keycard))
	InteractionFixtures.assemble(actor)
	var inventory := InteractionFixtures.inventory_of(actor)
	inventory.add(ItemInstance.create(keycard, quantity))
	return actor


# --- ItemRequirement ------------------------------------------------------

func test_a_carried_item_meets_the_requirement() -> void:
	var actor := _actor_with_keycard()
	var target := add_test_node(InteractionFixtures.target([InteractionFixtures.door()]))
	InteractionFixtures.assemble(target)
	assert_ok(InteractionFixtures.needs_item().check(_context_with(actor, target)))


func test_an_empty_bag_fails_the_requirement() -> void:
	var actor := add_test_node(InteractionFixtures.actor("Player", keycard))
	InteractionFixtures.assemble(actor)
	var target := add_test_node(InteractionFixtures.target([InteractionFixtures.door()]))
	InteractionFixtures.assemble(target)
	assert_err(
		InteractionFixtures.needs_item().check(_context_with(actor, target)),
		&"requirement.missing_item"
	)


func test_no_inventory_at_all_is_an_unmet_requirement_not_a_crash() -> void:
	var actor := add_test_node(InteractionFixtures.actor("Beast"))
	InteractionFixtures.assemble(actor)
	var target := add_test_node(InteractionFixtures.target([InteractionFixtures.door()]))
	InteractionFixtures.assemble(target)
	assert_err(
		InteractionFixtures.needs_item().check(_context_with(actor, target)),
		&"requirement.no_inventory"
	)


func test_quantity_is_respected() -> void:
	var actor := _actor_with_keycard(1)
	var target := add_test_node(InteractionFixtures.target([InteractionFixtures.door()]))
	InteractionFixtures.assemble(target)
	assert_err(
		InteractionFixtures.needs_item(&"item.keycard", 2).check(_context_with(actor, target)),
		&"requirement.missing_item"
	)


func test_checking_never_consumes() -> void:
	var actor := _actor_with_keycard()
	var target := add_test_node(InteractionFixtures.target([InteractionFixtures.door()]))
	InteractionFixtures.assemble(target)
	var requirement := InteractionFixtures.needs_item(&"item.keycard", 1, true)
	var context := _context_with(actor, target)
	requirement.check(context)
	requirement.check(context)
	assert_eq(InteractionFixtures.inventory_of(actor).count(&"item.keycard"), 1)


func test_commit_consumes_only_when_asked() -> void:
	var actor := _actor_with_keycard()
	var target := add_test_node(InteractionFixtures.target([InteractionFixtures.door()]))
	InteractionFixtures.assemble(target)
	var context := _context_with(actor, target)

	assert_ok(InteractionFixtures.needs_item(&"item.keycard", 1, false).commit(context))
	assert_eq(InteractionFixtures.inventory_of(actor).count(&"item.keycard"), 1)

	assert_ok(InteractionFixtures.needs_item(&"item.keycard", 1, true).commit(context))
	assert_eq(InteractionFixtures.inventory_of(actor).count(&"item.keycard"), 0)


func test_an_item_requirement_with_no_id_can_never_be_met() -> void:
	var requirement := ItemRequirement.new()
	assert_false(requirement.validate().is_valid())
	assert_err(requirement.check(InteractionContext.new()), &"requirement.no_item_id")


func test_a_zero_quantity_requirement_is_an_error() -> void:
	var requirement := InteractionFixtures.needs_item()
	requirement.quantity = 0
	assert_false(requirement.validate().is_valid())


func test_describe_falls_back_when_no_text_is_authored() -> void:
	var requirement := ItemRequirement.new()
	requirement.item_id = &"item.keycard"
	assert_has(requirement.describe(), "item.keycard")
	requirement.quantity = 3
	assert_has(requirement.describe(), "3")


# --- StateRequirement -----------------------------------------------------

func test_a_required_state_on_the_target_is_checked() -> void:
	var actor := add_test_node(InteractionFixtures.actor())
	InteractionFixtures.assemble(actor)
	var target := add_test_node(InteractionFixtures.target([InteractionFixtures.door()]))
	InteractionFixtures.assemble(target)
	var requirement := InteractionFixtures.needs_state([GameplayNames.STATE_OPEN])
	var context := _context_with(actor, target)

	assert_err(requirement.check(context), &"requirement.missing_state")
	InteractionFixtures.state_of(target).add_state(GameplayNames.STATE_OPEN)
	assert_ok(requirement.check(context))


func test_a_forbidden_state_on_the_target_blocks() -> void:
	var actor := add_test_node(InteractionFixtures.actor())
	InteractionFixtures.assemble(actor)
	var target := add_test_node(InteractionFixtures.target([InteractionFixtures.door()]))
	InteractionFixtures.assemble(target)
	var requirement := InteractionFixtures.needs_state([], [GameplayNames.STATE_LOCKED])
	var context := _context_with(actor, target)

	assert_ok(requirement.check(context))
	InteractionFixtures.state_of(target).add_state(GameplayNames.STATE_LOCKED)
	assert_err(requirement.check(context), &"requirement.forbidden_state")


func test_the_interactor_can_be_the_subject() -> void:
	var actor := add_test_node(InteractionFixtures.actor())
	InteractionFixtures.assemble(actor)
	var target := add_test_node(InteractionFixtures.target([InteractionFixtures.door()]))
	InteractionFixtures.assemble(target)
	var requirement := InteractionFixtures.needs_state(
		[], [GameplayNames.STATE_DOWNED], StateRequirement.Subject.INTERACTOR
	)
	var context := _context_with(actor, target)

	assert_ok(requirement.check(context))
	InteractionFixtures.state_of(actor).add_state(GameplayNames.STATE_DOWNED)
	assert_err(requirement.check(context), &"requirement.forbidden_state")


func test_an_entity_with_no_state_component_cannot_meet_a_required_state() -> void:
	var requirement := InteractionFixtures.needs_state([GameplayNames.STATE_OPEN])
	var context := InteractionContext.create(null, Node.new())
	assert_err(requirement.check(context), &"requirement.no_semantic_state")
	context.target.free()


func test_an_entity_with_no_state_component_trivially_meets_a_forbidden_state() -> void:
	var requirement := InteractionFixtures.needs_state([], [GameplayNames.STATE_LOCKED])
	var context := InteractionContext.create(null, Node.new())
	assert_ok(requirement.check(context))
	context.target.free()


func test_an_empty_state_requirement_is_flagged_and_always_met() -> void:
	var requirement := StateRequirement.new()
	assert_true(requirement.validate().has_warnings())
	assert_ok(requirement.check(InteractionContext.new()))


func test_requiring_and_forbidding_the_same_state_is_an_error() -> void:
	var requirement := InteractionFixtures.needs_state(
		[GameplayNames.STATE_OPEN], [GameplayNames.STATE_OPEN]
	)
	assert_false(requirement.validate().is_valid())


func test_state_requirement_describes_itself() -> void:
	assert_has(
		InteractionFixtures.needs_state([GameplayNames.STATE_OPEN]).describe(), "state.open"
	)
	assert_has(
		InteractionFixtures.needs_state([], [GameplayNames.STATE_LOCKED]).describe(),
		"state.locked"
	)


# --- The base class -------------------------------------------------------

func test_the_base_requirement_is_always_met() -> void:
	var requirement := InteractionRequirement.new()
	assert_ok(requirement.check(InteractionContext.new()))
	assert_ok(requirement.commit(InteractionContext.new()))
	assert_eq(requirement.describe(), "")
	assert_true(requirement.validate().is_valid())
