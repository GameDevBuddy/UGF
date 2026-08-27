extends FrameworkTestCase
## Vertical Slice C: gather -> craft -> consume -> needs and status ->
## persistence, driven end to end through the components a game would use.
##
## The M12 exit gate already proves the survival loop runs. What it does not
## prove is that the loop is legible to anything outside Survival, and that is
## where the interesting failure lives. Gathering yields through Loot and has
## never heard of recipes; Crafting reads a bag and has never heard of resource
## nodes; Survival restores meters and has never heard of either; Missions
## watches a bus and has never heard of any of the three. The only things
## joining them are the inventory they all reach through and the events the
## adapters promote -- so this suite drives the whole run through the
## interaction pipeline, the real recipe, the real consumable and a real save,
## and asserts every join.
##
## [b]It is also why [CraftEventAdapter] exists.[/b] Crafting puts its output
## in a bag, so a craft already fires [code]item_acquired[/code]. An objective
## counting acquisitions therefore completes whether the player made the thing,
## looted it or bought it, which quietly turns "craft two rations" into "obtain
## two rations". Only the craft carries a recipe id, and until this slice
## nothing put it on the bus. The later tests here are the ones that would have
## caught that: a craft objective must refuse an item that arrived by any other
## route, while an acquire objective must still accept one that was made.

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"
const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var bus: Node = null
var core: Node = null
var saves: SaveService = null
var missions: MissionService = null
var published: Array[FrameworkEvent] = []

var fibre: ItemDefinition = null
var ration: ItemDefinition = null
var hunger: NeedDefinition = null
var ration_recipe: RecipeDefinition = null

var survivor: Node3D = null
var inventory: InventoryComponent = null
var needs: NeedsComponent = null
var crafting: CraftingComponent = null
var consumer: ConsumerComponent = null
var interactor: InteractorComponent = null
var state: SemanticState = null


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")

	published = []
	bus.event_published.connect(
		func(event: FrameworkEvent) -> void: published.append(event)
	)

	fibre = ItemFixtures.stackable(&"item.fibre", 99, 0.1)
	ration = SurvivalFixtures.meal(&"item.ration", [&"need.hunger"], [60.0])
	for definition in [fibre, ration]:
		core.get_definition_registry().register(definition)
	core.get_definition_registry().register(
		CommerceFixtures.loot_table(
			&"loot.thicket",
			[CommerceFixtures.loot_entry(&"item.fibre", 4, 4, 0.0, true)],
			0
		)
	)

	# Eight fibre in, two rations out. Instant, so the craft is one call and
	# the timing of a queued craft stays the crafting suite's problem.
	ration_recipe = SurvivalFixtures.recipe(
		&"recipe.ration",
		[SurvivalFixtures.ingredient(&"item.fibre", 8)],
		&"item.ration",
		2,
		0.0
	)

	hunger = SurvivalFixtures.need(&"need.hunger", 1.0)

	saves = SaveService.new()
	saves.name = "SaveService"
	add_test_node(saves)
	saves.configure(SaveBackend.new(), core)

	missions = MissionService.new()
	missions.name = "MissionService"
	add_test_node(missions)
	missions.configure(core, bus)

	survivor = _survivor("Survivor", &"survivor")
	missions.default_subject = survivor
	inventory = SurvivalFixtures.find(survivor, InventoryComponent) as InventoryComponent
	needs = SurvivalFixtures.find(survivor, NeedsComponent) as NeedsComponent
	crafting = SurvivalFixtures.find(survivor, CraftingComponent) as CraftingComponent
	consumer = SurvivalFixtures.find(survivor, ConsumerComponent) as ConsumerComponent
	interactor = (
		SurvivalFixtures.find(survivor, InteractorComponent) as InteractorComponent
	)
	state = SurvivalFixtures.find(survivor, SemanticState) as SemanticState


# --- Composition ----------------------------------------------------------

## A survivor who can reach the world, work it, cook, eat, starve and be saved.
##
## The two adapters are the whole reason this is not just
## [method SurvivalFixtures.survivor]: without them the entity is complete and
## silent, and nothing outside it learns that anything happened.
func _survivor(entity_name: String, persistent_id: StringName) -> Node3D:
	var entity := SurvivalFixtures.survivor(entity_name, [hunger])

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = persistent_id
	entity.add_child(identity)

	var reach := InteractorComponent.new()
	reach.name = "InteractorComponent"
	reach.auto_tick = false
	entity.add_child(reach)

	# The bus is injected rather than found: make_autoload parents it under the
	# test's scratch root, not under the scene root the adapters look in.
	var acquisitions := InventoryEventAdapter.new()
	acquisitions.name = "InventoryEventAdapter"
	acquisitions.event_bus = bus
	entity.add_child(acquisitions)

	var crafts := CraftEventAdapter.new()
	crafts.name = "CraftEventAdapter"
	crafts.event_bus = bus
	entity.add_child(crafts)

	add_test_node(entity)
	SurvivalFixtures.assemble(entity, core)
	return entity


## A thicket that is worked through the interaction pipeline, exactly as a door
## is opened: the harvest is an [InteractionAction], not a second path beside
## the first.
func _thicket(
	charges: int = 2,
	persistent_id: StringName = &"thicket",
	entity_name: String = "Thicket"
) -> ResourceNode:
	var definition := SurvivalFixtures.resource_definition(
		&"node.thicket", &"loot.thicket", &"", charges
	)
	definition.respawn_time = 60.0

	var entity := SurvivalFixtures.resource_node(definition)
	entity.name = entity_name

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = persistent_id
	entity.add_child(identity)

	var cut := InteractionFixtures.definition(&"interaction.cut", &"verb.cut", "Cut")
	cut.action = HarvestAction.new()
	var offered: Array[InteractionDefinition] = [cut]
	var interaction := InteractionComponent.new()
	interaction.name = "InteractionComponent"
	interaction.interactions_override = offered
	interaction.auto_tick = false
	entity.add_child(interaction)

	add_test_node(entity)
	SurvivalFixtures.assemble(entity, core)

	var node := SurvivalFixtures.find(entity, ResourceNode) as ResourceNode
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	node.set_rng(rng)
	return node


## Presses the interact key on a thicket. Nothing here calls
## [method ResourceNode.harvest] directly: the point of the first link is that
## the player's route into gathering is the interaction pipeline.
func _cut(node: ResourceNode) -> FrameworkResult:
	return interactor.begin(
		SurvivalFixtures.find(node.get_entity(), InteractionComponent)
	)


func _events(event_name: StringName) -> Array[FrameworkEvent]:
	return published.filter(
		func(event: FrameworkEvent) -> bool: return event.get_event_name() == event_name
	)


## "Craft two rations." A [constant GameplayNames.OBJECTIVE_CRAFT] objective is
## the acquire objective with a different event name, which is rule 11 and the
## reason a fifteenth objective kind is content rather than a class.
func _craft_objective(count: int = 2) -> ObjectiveDefinition:
	var definition := MissionFixtures.objective(
		&"objective.make_rations",
		GameplayNames.EVENT_ITEM_CRAFTED,
		[MissionFixtures.matcher(&"item_id", &"item.ration")],
		count
	)
	definition.kind = GameplayNames.OBJECTIVE_CRAFT
	definition.count_field = &"quantity"
	return definition


# --- The slice ------------------------------------------------------------

func test_the_survival_slice_runs_from_the_thicket_to_the_save_file() -> void:
	var thicket := _thicket(2)
	var quest := MissionFixtures.mission(&"mission.rations", [_craft_objective(2)])
	assert_ok(missions.start(quest), "the mission watching the chain is running")
	assert_ok(saves.register_entity(survivor), "the survivor can be saved")
	assert_ok(saves.register_entity(thicket.get_entity()), "and so can the thicket")

	# --- 1. Gather ---------------------------------------------------------
	# InteractorComponent -> InteractionComponent -> HarvestAction ->
	# ResourceNode -> LootTableDefinition -> InventoryComponent. Six components
	# for one button press, and none of them names the next but one.
	assert_ok(_cut(thicket), "an interaction on the thicket is accepted")
	assert_eq(
		inventory.count(&"item.fibre"), 4,
		"the loot table's yield reached the bag through the interaction pipeline"
	)
	assert_ok(_cut(thicket), "the thicket still had a charge")
	assert_eq(
		inventory.count(&"item.fibre"), 8,
		"and a second harvest stacked rather than replacing"
	)
	assert_true(thicket.is_depleted(), "two charges is all the thicket had")
	assert_err(
		_cut(thicket), &"node.depleted",
		"a spent node refuses through the pipeline, not only through harvest()"
	)

	# --- 2. Craft ----------------------------------------------------------
	assert_ok(
		crafting.craft(ration_recipe),
		"the gathered fibre satisfies a recipe Crafting never heard gathering describe"
	)
	assert_eq(
		inventory.count(&"item.fibre"), 0,
		"the ingredients were spent out of the same bag gathering filled"
	)
	assert_eq(
		inventory.count(&"item.ration"), 2, "and the recipe's output arrived in it"
	)

	var crafted := _events(GameplayNames.EVENT_ITEM_CRAFTED)
	assert_size(crafted, 1, "CraftEventAdapter promoted the craft to the bus")
	assert_eq(crafted[0].recipe_id, &"recipe.ration", "the event names the recipe used")
	assert_eq(crafted[0].item_id, &"item.ration", "and what came out of it")
	assert_eq(crafted[0].quantity, 2, "and how many, so an objective can count them")
	assert_eq(
		crafted[0].category, &"item.consumable",
		"and the category, so an objective can ask for any consumable"
	)
	assert_true(
		missions.has_completed(&"mission.rations"),
		"which is all a craft objective needs, with no module knowing a mission exists"
	)

	# --- 3 and 4. Needs, status and eating ---------------------------------
	needs.tick(75.0)
	assert_almost_eq(
		needs.get_value(&"need.hunger"), 25.0, 0.001,
		"seventy-five seconds of decay at one a second"
	)
	assert_true(needs.is_low(&"need.hunger"), "which is under the need's low threshold")
	assert_true(
		state.has_state(hunger.low_state),
		"and NeedsComponent mirrored the threshold onto SemanticState"
	)

	assert_ok(
		consumer.consume_by_id(&"item.ration"),
		"the crafted item is eaten out of the bag it was crafted into"
	)
	assert_almost_eq(
		needs.get_value(&"need.hunger"), 85.0, 0.001,
		"the consumable's profile restored the need it names"
	)
	assert_eq(inventory.count(&"item.ration"), 1, "and one ration was used up doing it")
	assert_false(
		needs.is_low(&"need.hunger"), "the need is back above its low threshold"
	)
	assert_false(
		state.has_state(hunger.low_state),
		"and the semantic state came off again, which is the half that rots quietly"
	)

	# --- 5. Persistence ----------------------------------------------------
	assert_ok(saves.save(&"slot_slice_c"), "the run is written to a slot")

	# Loaded into a world that was never gathered from, rather than back over
	# the objects that produced it: restoring onto live state can pass while
	# reading nothing off the disk at all.
	saves.unregister_entity(survivor)
	saves.unregister_entity(thicket.get_entity())
	var rebuilt := _survivor("Rebuilt", &"survivor")
	var regrown := _thicket(2, &"thicket", "Regrown")
	assert_ok(saves.register_entity(rebuilt))
	assert_ok(saves.register_entity(regrown.get_entity()))

	var rebuilt_needs := SurvivalFixtures.find(rebuilt, NeedsComponent) as NeedsComponent
	var rebuilt_bag := (
		SurvivalFixtures.find(rebuilt, InventoryComponent) as InventoryComponent
	)
	var rebuilt_state := SurvivalFixtures.find(rebuilt, SemanticState) as SemanticState
	assert_almost_eq(
		rebuilt_needs.get_value(&"need.hunger"), 100.0, 0.001,
		"the second world starts well fed, so nothing below can be a leftover"
	)
	assert_true(rebuilt_bag.is_empty(), "and empty handed")
	assert_eq(regrown.get_charges(), 2, "and its thicket is untouched")

	assert_ok(saves.load_slot(&"slot_slice_c"), "the slot loads")

	assert_almost_eq(
		rebuilt_needs.get_value(&"need.hunger"), 85.0, 0.001,
		"needs came back at the value eating left them at"
	)
	assert_eq(
		rebuilt_bag.count(&"item.ration"), 1, "the uneaten ration came back with them"
	)
	assert_eq(
		rebuilt_bag.count(&"item.fibre"), 0,
		"and the fibre the craft consumed stayed consumed"
	)
	assert_false(
		rebuilt_state.has_state(hunger.low_state),
		"a survivor restored above the threshold is not flagged hungry"
	)
	assert_eq(regrown.get_charges(), 0, "the worked thicket came back worked")
	assert_true(regrown.is_depleted(), "and still spent")
	assert_almost_eq(
		regrown.get_time_until_respawn(), 60.0, 0.001,
		"with its respawn timer where the save left it"
	)


# --- Craft is not acquire -------------------------------------------------

func test_a_craft_objective_is_not_satisfied_by_getting_the_item_another_way() -> void:
	# The distinction the adapter exists for. Both events name the same item
	# and the same bag; only one of them says a recipe was used.
	var quest := MissionFixtures.mission(&"mission.rations", [_craft_objective(2)])
	assert_ok(missions.start(quest))

	assert_ok(
		inventory.add(ItemInstance.create(ration, 2)),
		"two rations arrive by some other route: looted, bought or handed over"
	)
	assert_size(
		_events(GameplayNames.EVENT_ITEM_ACQUIRED), 1,
		"the bag announced the acquisition"
	)
	assert_empty(
		_events(GameplayNames.EVENT_ITEM_CRAFTED),
		"but nothing was crafted, so nothing said so"
	)

	var objective := missions.get_runtime(&"mission.rations").get_objective(
		&"objective.make_rations"
	)
	assert_almost_eq(
		objective.progress, 0.0, 0.001,
		"and a craft objective made no progress on an item that was merely obtained"
	)
	assert_false(
		missions.has_completed(&"mission.rations"), "so the mission is still open"
	)

	# Now actually make some, from material actually gathered.
	var thicket := _thicket(2)
	assert_ok(_cut(thicket))
	assert_ok(_cut(thicket))
	assert_ok(crafting.craft(ration_recipe))

	var crafted := _events(GameplayNames.EVENT_ITEM_CRAFTED)
	assert_size(crafted, 1, "this time a craft was announced")
	assert_eq(
		crafted[0].quantity, 2,
		(
			"and it counted the output even though the bag already held some, "
			+ "which is what an objective counting crafts depends on"
		)
	)
	assert_true(
		missions.has_completed(&"mission.rations"),
		"and the same objective completed on it"
	)


func test_crafting_also_announces_the_acquisition_it_causes() -> void:
	# The other side of the distinction, written down so it cannot be lost
	# while "fixing" the test above: a craft is more specific, not exclusive.
	# "Collect two rations" must still be satisfied by making them.
	var quest := MissionFixtures.mission(
		&"mission.collect", [MissionFixtures.acquire_objective(&"item.ration", 2)]
	)
	assert_ok(missions.start(quest))

	var thicket := _thicket(2)
	assert_ok(_cut(thicket))
	assert_ok(_cut(thicket))
	assert_ok(crafting.craft(ration_recipe))

	assert_size(_events(GameplayNames.EVENT_ITEM_CRAFTED), 1, "the craft was announced")
	assert_size(
		_events(GameplayNames.EVENT_ITEM_ACQUIRED), 3,
		"alongside two harvests and the output landing in the bag"
	)
	assert_true(
		missions.has_completed(&"mission.collect"),
		"so an acquire objective is satisfied by crafting the thing"
	)


func test_deleting_the_craft_adapter_costs_the_objective_and_nothing_else() -> void:
	# Rule 10, stated where it is cheapest to get wrong. The adapter is the one
	# thing that has to be installed for a craft objective to work, and taking
	# it off must leave the loop itself running.
	var adapter := SurvivalFixtures.find(survivor, CraftEventAdapter) as CraftEventAdapter
	assert_not_null(adapter, "the survivor was composed with one")
	adapter.get_parent().remove_child(adapter)
	adapter.queue_free()

	var quest := MissionFixtures.mission(&"mission.rations", [_craft_objective(2)])
	assert_ok(missions.start(quest))

	var thicket := _thicket(2)
	assert_ok(_cut(thicket))
	assert_ok(_cut(thicket))
	assert_ok(crafting.craft(ration_recipe), "crafting still works with no bus seam")
	assert_eq(inventory.count(&"item.ration"), 2, "and still produces")
	assert_empty(
		_events(GameplayNames.EVENT_ITEM_CRAFTED),
		"but nothing outside the entity heard about it"
	)
	assert_false(
		missions.has_completed(&"mission.rations"),
		"which is what a missing adapter should cost: the objective, not the loop"
	)
