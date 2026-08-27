extends FrameworkTestCase
## The M5 exit gate: a door, a pickup, an NPC and a vehicle on one pipeline.
##
## What is being asserted is a negative -- that there is no Door path, no
## Pickup path and no Vehicle path. Every one of these is an
## [InteractionComponent] holding [InteractionDefinition] resources, used
## through the same [method InteractorComponent.begin], and the only thing that
## differs is the content and what listens to the completion signal.

var player: Node = null
var interactor: InteractorComponent = null
var arrow: ItemDefinition = null


func before_each() -> void:
	arrow = ItemFixtures.stackable(&"item.arrow", 20)
	player = add_test_node(InteractionFixtures.actor("Player", arrow))
	InteractionFixtures.assemble(player)
	interactor = InteractionFixtures.interactor_of(player)


func _target(interactions: Array, entity_name: String) -> InteractionComponent:
	var entity := add_test_node(InteractionFixtures.target(interactions, entity_name))
	InteractionFixtures.assemble(entity)
	return InteractionFixtures.interaction_of(entity)


# --- The four shapes ------------------------------------------------------

func test_a_door_opens() -> void:
	var door := _target([InteractionFixtures.door()], "Door")
	assert_ok(interactor.begin(door))
	assert_true(
		InteractionFixtures.state_of(door.get_entity_root()).has_state(GameplayNames.STATE_OPEN)
	)


func test_a_pickup_goes_into_the_bag() -> void:
	# The item end of the pipeline needs no action resource at all: something
	# connects to the completion signal, which is the plain signal rule 7 asks
	# for and the reason Interaction does not depend on Inventory.
	var take := InteractionFixtures.definition(&"interaction.take", GameplayNames.VERB_TAKE, "Take")
	var pickup := _target([take], "Arrows")

	var stack := ItemInstance.create(arrow, 5)
	pickup.interaction_completed.connect(
		func(context: InteractionContext, _r: FrameworkResult) -> void:
			var bag := context.get_interactor_inventory()
			if bag != null:
				bag.add(stack)
	)

	assert_ok(interactor.begin(pickup))
	assert_eq(InteractionFixtures.inventory_of(player).count(&"item.arrow"), 5)


func test_an_npc_can_be_talked_to() -> void:
	var talk := InteractionFixtures.definition(&"interaction.talk", GameplayNames.VERB_TALK, "Talk")
	var action := RecordingAction.new()
	talk.action = action
	var npc := _target([talk], "Vendor")

	assert_ok(interactor.begin(npc))
	assert_eq(action.executed, 1)
	assert_eq(action.last_interactor, player)
	assert_eq(action.last_verb, GameplayNames.VERB_TALK)


func test_a_vehicle_can_be_entered() -> void:
	var enter := InteractionFixtures.definition(
		&"interaction.enter", GameplayNames.VERB_ENTER, "Enter"
	)
	var action := RecordingAction.new()
	enter.action = action
	var car := _target([enter], "Car")

	assert_ok(interactor.begin(car))
	assert_eq(action.executed, 1)


func test_all_four_are_the_same_component_and_the_same_call() -> void:
	var door := _target([InteractionFixtures.door()], "Door")
	var pickup := _target(
		[InteractionFixtures.definition(&"interaction.take", GameplayNames.VERB_TAKE, "Take")],
		"Arrows"
	)
	var npc := _target(
		[InteractionFixtures.definition(&"interaction.talk", GameplayNames.VERB_TALK, "Talk")],
		"Vendor"
	)
	var car := _target(
		[InteractionFixtures.definition(&"interaction.enter", GameplayNames.VERB_ENTER, "Enter")],
		"Car"
	)

	for target in [door, pickup, npc, car]:
		assert_true(target is InteractionComponent)
		assert_ok(interactor.begin(target))


func test_one_target_can_offer_several_things() -> void:
	var enter := InteractionFixtures.definition(
		&"interaction.enter", GameplayNames.VERB_ENTER, "Enter"
	)
	enter.priority = 10
	var boot := InteractionFixtures.definition(
		&"interaction.boot", GameplayNames.VERB_OPEN, "Open Boot"
	)
	var car := _target([enter, boot], "Car")

	assert_size(car.get_available(player), 2)
	assert_eq(car.get_primary(player).id, &"interaction.enter")
	assert_ok(interactor.begin(car, boot))


# --- A locked door, end to end --------------------------------------------

func test_a_locked_door_needs_its_key_and_keeps_it() -> void:
	var keycard := ItemFixtures.unique(&"item.keycard")
	var open := InteractionFixtures.door()
	open.show_when_unavailable = true
	var requirements: Array[InteractionRequirement] = [InteractionFixtures.needs_item()]
	open.requirements = requirements
	var door := _target([open], "LockedDoor")

	interactor.set_focus(door)
	assert_eq(interactor.get_prompt(), "Requires a keycard")
	assert_err(interactor.interact(), &"requirement.missing_item")

	InteractionFixtures.inventory_of(player).add(ItemInstance.create(keycard, 1))
	assert_ok(interactor.interact())
	assert_true(
		InteractionFixtures.state_of(door.get_entity_root()).has_state(GameplayNames.STATE_OPEN)
	)
	assert_eq(InteractionFixtures.inventory_of(player).count(&"item.keycard"), 1)


func test_a_toll_gate_takes_the_coin() -> void:
	var coin := ItemFixtures.stackable(&"item.coin", 99)
	InteractionFixtures.inventory_of(player).add(ItemInstance.create(coin, 3))

	var pay := InteractionFixtures.door(&"interaction.toll")
	var requirements: Array[InteractionRequirement] = [
		InteractionFixtures.needs_item(&"item.coin", 2, true)
	]
	pay.requirements = requirements
	var gate := _target([pay], "TollGate")

	assert_ok(interactor.begin(gate))
	assert_eq(InteractionFixtures.inventory_of(player).count(&"item.coin"), 1)
	assert_err(interactor.begin(gate), &"requirement.missing_item")


# --- Definitions carry interactions ---------------------------------------

func test_a_character_definition_can_offer_interactions() -> void:
	var talk := InteractionFixtures.definition(&"interaction.talk", GameplayNames.VERB_TALK, "Talk")
	var definition := CharacterDefinition.new()
	definition.id = &"character.vendor"
	definition.display_name = "Vendor"
	var offered: Array[InteractionDefinition] = [talk]
	definition.interactions = offered

	var npc := add_test_node(InteractionFixtures.target([], "Vendor"))
	InteractionFixtures.assemble(npc, definition)

	var interaction := InteractionFixtures.interaction_of(npc)
	assert_size(interaction.get_interactions(), 1)
	assert_ok(interactor.begin(interaction))


func test_an_item_definition_can_offer_interactions() -> void:
	var examine := InteractionFixtures.definition(
		&"interaction.examine", GameplayNames.VERB_SEARCH, "Examine"
	)
	var offered: Array[InteractionDefinition] = [examine]
	arrow.interactions = offered

	var lying_there := add_test_node(InteractionFixtures.target([], "Arrows"))
	InteractionFixtures.assemble(lying_there, arrow)

	assert_size(InteractionFixtures.interaction_of(lying_there).get_interactions(), 1)


func test_an_interactor_profile_on_a_character_definition_sets_the_reach() -> void:
	var profile := InteractorProfile.new()
	profile.reach = 7.5
	profile.auto_focus = false
	var definition := CharacterDefinition.new()
	definition.id = &"character.gorilla"
	definition.interaction = profile

	var beast := add_test_node(InteractionFixtures.actor("Gorilla"))
	InteractionFixtures.assemble(beast, definition)
	assert_almost_eq(InteractionFixtures.interactor_of(beast).get_reach(), 7.5)
