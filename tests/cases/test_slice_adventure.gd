extends FrameworkTestCase
## Vertical slice A (Implementation Plan 36): move, use, take, talk, track, save.
##
## Every other suite in this directory proves one module works on its own. This
## one proves six of them compose, by walking a character across a floor from a
## fake input source and following the thread all the way into a save file: the
## controller drives locomotion, locomotion carries the interactor into reach,
## the interactor runs an interaction on a crate, the crate's harvest action
## fills the bag, the bag's adapter publishes the acquisition, a conversation
## started through that same interaction pipeline publishes its ending, and a
## mission that has heard of none of those modules completes off the three bus
## events and pays out a narrative flag.
##
## [b]Nothing here is hand-fed.[/b] The test constructs no events, pokes no
## private state, and calls no service where a component would have done the
## calling. That is the whole value of the file: the chain can only run if the
## seams between the modules -- the adapters, the bus, the field names an
## objective matches on -- are all genuinely connected. Break one of them and
## this suite goes red while every module's own suite stays green, which is the
## failure a slice gate exists to catch.
##
## The mission is the load-bearing part. Its three objectives name an event and
## a few field names and nothing else: no InteractionComponent, no
## InventoryComponent, no DialogueComponent. If a module ever has to be
## imported to make an objective work, this is where it shows.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"

const FakeInputSource := preload("res://tests/support/fake_input_source.gd")

const RELIC: StringName = &"item.relic"
const CRATE_TABLE: StringName = &"loot.crate"
const CRATE_INTERACTION: StringName = &"interaction.crate"
const TALK_INTERACTION: StringName = &"interaction.foreman"
const CONTAINER_TAG: StringName = &"interaction.container"
const MISSION: StringName = &"mission.relic"
const OBJECTIVE_SEARCH: StringName = &"objective.search_the_crate"
const OBJECTIVE_TAKE: StringName = &"objective.take_the_relic"
const OBJECTIVE_REPORT: StringName = &"objective.report_back"
const REWARD_FLAG: StringName = &"flag.relic_recovered"

## One physics step. Only the acceleration curve reads it -- CharacterBody3D
## moves on the engine's own physics delta -- so the walk helpers below stop on
## distance rather than on a frame count.
const STEP: float = 1.0 / 60.0

var bus: Node = null
var core: Node = null
var narrative: NarrativeStateService = null
var missions: MissionService = null
var saves: SaveService = null
var source: RefCounted = null
var router: InputRouter = null

var player: CharacterBody3D = null
var movement: MovementComponent = null
var controller: CharacterController = null
var interactor: InteractorComponent = null
var inventory: InventoryComponent = null
var crate: Node3D = null
var foreman: Node3D = null
var dialogue: DialogueComponent = null

var published: Array[FrameworkEvent] = []


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	published = []
	bus.event_published.connect(
		func(event: FrameworkEvent) -> void: published.append(event)
	)

	_register_content()

	narrative = NarrativeStateService.new()
	narrative.name = "NarrativeStateService"
	add_test_node(narrative)

	missions = MissionService.new()
	missions.name = "MissionService"
	add_test_node(missions)
	missions.configure(core, bus, narrative)

	saves = SaveService.new()
	saves.name = "SaveService"
	add_test_node(saves)
	saves.configure(SaveBackend.new(), core)
	assert_ok(saves.register_service(GameplayNames.SERVICE_NARRATIVE, narrative))
	assert_ok(saves.register_service(GameplayNames.SERVICE_OBJECTIVE, missions))

	_build_ground()

	source = FakeInputSource.new()
	router = InputRouter.new(source)
	add_test_node(router)

	player = _build_player()
	movement = _find(player, MovementComponent) as MovementComponent
	controller = _find(player, CharacterController) as CharacterController
	interactor = _find(player, InteractorComponent) as InteractorComponent
	inventory = _find(player, InventoryComponent) as InventoryComponent
	controller.set_router(router)
	assert_ok(controller.take_control())

	crate = _build_crate()
	foreman = _build_foreman()
	dialogue = _find(foreman, DialogueComponent) as DialogueComponent

	missions.default_subject = player
	for entity in [player, crate, foreman]:
		assert_ok(saves.register_entity(entity))


# --- The world ------------------------------------------------------------

## Registers the content this slice is played out with. All of it is built
## here rather than loaded, because the addon ships no game content (rule 29).
func _register_content() -> void:
	var registry: DefinitionRegistry = core.get_definition_registry()
	registry.register(ItemFixtures.unique(RELIC, 0.5))
	registry.register(
		CommerceFixtures.loot_table(
			CRATE_TABLE,
			[CommerceFixtures.loot_entry(RELIC, 1, 1, 0.0, true)],
			0
		)
	)
	registry.register(_mission_definition())


## A floor to stand on. The character is a real [CharacterBody3D] driven by
## [method CharacterBody3D.move_and_slide], so without a collider under it the
## walk would be a fall.
func _build_ground() -> StaticBody3D:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	ground.add_child(shape)
	return add_test_node(ground) as StaticBody3D


func _build_player(entity_name: String = "Player") -> CharacterBody3D:
	var entity := CharacterBody3D.new()
	entity.name = entity_name

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 2.0
	capsule.radius = 0.4
	shape.shape = capsule
	entity.add_child(shape)

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = &"player"
	entity.add_child(identity)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var profile := MovementProfile.new()
	profile.walk_speed = 4.0
	profile.acceleration = 40.0
	profile.deceleration = 55.0

	var mover := MovementComponent.new()
	mover.name = "MovementComponent"
	mover.profile_override = profile
	mover.body = entity
	mover.semantic_state = state
	mover.auto_tick = false
	entity.add_child(mover)

	var bag := InventoryComponent.new()
	bag.name = "InventoryComponent"
	bag.profile_override = ItemFixtures.container(20)
	entity.add_child(bag)

	var bag_adapter := InventoryEventAdapter.new()
	bag_adapter.name = "InventoryEventAdapter"
	bag_adapter.inventory = bag
	bag_adapter.event_bus = bus
	entity.add_child(bag_adapter)

	var reach := InteractorProfile.new()
	reach.reach = 2.0
	reach.focus_interval = 0.05

	var hands := InteractorComponent.new()
	hands.name = "InteractorComponent"
	hands.profile_override = reach
	hands.inventory = bag
	hands.semantic_state = state
	hands.auto_tick = false
	entity.add_child(hands)

	var driver := CharacterController.new()
	driver.name = "CharacterController"
	driver.movement = mover
	driver.interactor = hands
	driver.mouse_look = false
	entity.add_child(driver)

	add_test_node(entity)
	entity.global_position = Vector3(0.0, 1.0, 0.0)
	_assemble(entity)
	return entity


## A crate that gives up one relic when it is searched, and announces it.
##
## The pickup is a [HarvestAction] on an ordinary [InteractionDefinition]: the
## same pipeline a door is opened with, which is what stops "picking things up"
## being a second code path beside "using things".
func _build_crate() -> Node3D:
	var entity := Node3D.new()
	entity.name = "Crate"

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = &"crate"
	entity.add_child(identity)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var node_definition := SurvivalFixtures.resource_definition(
		&"node.crate", CRATE_TABLE, &"", 1
	)
	var resource := ResourceNode.new()
	resource.name = "ResourceNode"
	resource.node_override = node_definition
	resource.auto_tick = false
	entity.add_child(resource)

	var offered: Array[InteractionDefinition] = [_crate_interaction()]
	var interaction := InteractionComponent.new()
	interaction.name = "InteractionComponent"
	interaction.interactions_override = offered
	interaction.semantic_state = state
	interaction.auto_tick = false
	entity.add_child(interaction)

	var adapter := InteractionEventAdapter.new()
	adapter.name = "InteractionEventAdapter"
	adapter.interaction = interaction
	adapter.event_bus = bus
	entity.add_child(adapter)

	add_test_node(entity)
	entity.global_position = Vector3(0.0, 1.0, -5.0)
	_assemble(entity)
	resource.set_rng(WorldFixtures.rng())
	return entity


## The foreman: an NPC whose only interaction starts a conversation.
func _build_foreman(
	entity_name: String = "Foreman", state_service: NarrativeStateService = null
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = &"foreman"
	entity.add_child(identity)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var talk := DialogueComponent.new()
	talk.name = "DialogueComponent"
	talk.dialogue_override = DialogueFixtures.branching()
	talk.narrative = state_service if state_service != null else narrative
	# No input context to push: this suite drives the controller by hand, and a
	# suppressed context would stop the walk rather than the conversation.
	talk.suppresses_control = false
	entity.add_child(talk)

	var adapter := DialogueEventAdapter.new()
	adapter.name = "DialogueEventAdapter"
	adapter.dialogue = talk
	adapter.event_bus = bus
	entity.add_child(adapter)

	var offered: Array[InteractionDefinition] = [_talk_interaction()]
	var interaction := InteractionComponent.new()
	interaction.name = "InteractionComponent"
	interaction.interactions_override = offered
	interaction.semantic_state = state
	interaction.auto_tick = false
	entity.add_child(interaction)

	add_test_node(entity)
	entity.global_position = Vector3(0.0, 1.0, -6.4)
	_assemble(entity)
	return entity


func _crate_interaction() -> InteractionDefinition:
	var definition := InteractionFixtures.definition(
		CRATE_INTERACTION, GameplayNames.VERB_SEARCH, "Search"
	)
	var tags: Array[StringName] = [CONTAINER_TAG]
	definition.tags = tags
	definition.action = HarvestAction.new()
	# A one-shot: once it is searched it stops being offered, which is what
	# hands focus on to the foreman without the test steering it.
	definition.repeatable = false
	return definition


func _talk_interaction() -> InteractionDefinition:
	var definition := InteractionFixtures.definition(
		TALK_INTERACTION, GameplayNames.VERB_TALK, "Talk"
	)
	definition.action = TalkAction.new()
	return definition


## The mission that watches all of it.
##
## Three objectives, three modules, and not one type name between them: an
## event name, some field names and some values. That is the claim this slice
## is really making.
func _mission_definition() -> MissionDefinition:
	var searched := MissionFixtures.objective(
		OBJECTIVE_SEARCH,
		GameplayNames.EVENT_INTERACTION_COMPLETED,
		[
			MissionFixtures.matcher(&"verb", GameplayNames.VERB_SEARCH),
			MissionFixtures.tagged(&"tags", CONTAINER_TAG),
			MissionFixtures.by_subject(&"interactor"),
		]
	)
	searched.kind = GameplayNames.OBJECTIVE_INTERACT

	var taken := MissionFixtures.acquire_objective(RELIC, 1)
	taken.id = OBJECTIVE_TAKE
	taken.matchers.append(MissionFixtures.by_subject(&"get_owner_entity"))

	var reported := MissionFixtures.objective(
		OBJECTIVE_REPORT,
		GameplayNames.EVENT_DIALOGUE_COMPLETED,
		[
			MissionFixtures.matcher(&"dialogue_id", &"dialogue.job"),
			MissionFixtures.matcher(&"outcome", &"outcome.accepted"),
			MissionFixtures.by_subject(&"listener"),
		]
	)
	reported.kind = GameplayNames.OBJECTIVE_TALK

	var definition := MissionFixtures.mission(MISSION, [searched, taken, reported])
	definition.rewards = MissionFixtures.rewards(
		[MissionFixtures.flag_reward(REWARD_FLAG)]
	)
	return definition


func _assemble(entity: Node) -> void:
	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


func _find(entity: Node, type: Variant) -> FrameworkComponent:
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null


# --- Driving the character ------------------------------------------------

## One frame of the game loop, in the order a running project has it: read
## input, move, then look around.
func _frame() -> void:
	controller.drive(STEP)
	movement.tick(STEP)
	interactor.tick(STEP)
	source.advance_frame()


## Holds forward until [param target] is inside [param stop_distance], then
## lets go. Returns the distance actually reached.
##
## Nothing here touches the character's transform: the input source is pressed,
## the controller reads it, and the body moves. Setting a position directly
## would make every assertion after this one meaningless.
func _walk_to(target: Node3D, stop_distance: float) -> float:
	source.press(GameplayNames.ACTION_MOVE_FORWARD)
	var guard := 0
	while _distance_to(target) > stop_distance and guard < 600:
		_frame()
		guard += 1
	source.release(GameplayNames.ACTION_MOVE_FORWARD)
	# A few frames standing still, so the focus scan runs on its own interval
	# rather than the test calling refresh_focus() for it.
	for _settle in 4:
		_frame()
	return _distance_to(target)


func _distance_to(target: Node3D) -> float:
	return player.global_position.distance_to(target.global_position)


## Taps the interact button for exactly one frame.
func _press_interact() -> void:
	source.press(GameplayNames.ACTION_INTERACT)
	_frame()
	source.release(GameplayNames.ACTION_INTERACT)
	_frame()


## Runs [param component]'s conversation through to its accepted ending.
func _accept_the_job(component: DialogueComponent) -> void:
	var runtime := component.get_runtime()
	if runtime == null:
		fail("There is no conversation running to advance.")
		return
	runtime.advance()
	runtime.choose_id(&"choice.accept")
	runtime.advance()


func _events_of(event_name: StringName) -> Array[FrameworkEvent]:
	return published.filter(
		func(event: FrameworkEvent) -> bool: return event.get_event_name() == event_name
	)


func _interaction_of(entity: Node) -> InteractionComponent:
	return InteractionComponent.find_on(entity)


# --- The chain ------------------------------------------------------------

func test_the_adventure_chain_runs_end_to_end() -> void:
	assert_ok(missions.start_by_id(MISSION, player), "the mission is under way")
	var origin := player.global_position

	# 1. MOVE. Input goes in one end, a transform changes at the other.
	var at_crate := _walk_to(crate, 1.5)
	assert_true(
		player.global_position.distance_to(origin) > 1.0,
		"holding forward on the input source moved the body over ticks"
	)
	assert_true(
		player.global_position.z < origin.z - 1.0,
		"and it moved the way forward points, not just somewhere"
	)
	assert_true(at_crate <= 1.5, "the walk ended inside the interactor's reach")
	assert_eq(
		interactor.get_focus(),
		_interaction_of(crate),
		"walking into reach is what put the crate in focus -- nothing set it"
	)

	# 2. INTERACT. The button reaches the target's pipeline, not a shortcut.
	_press_interact()
	var used := _events_of(GameplayNames.EVENT_INTERACTION_COMPLETED)
	assert_size(used, 1, "one interact press produced one interaction_completed")
	# Guarded so a missing event reads as one failed assertion rather than an
	# index error that aborts the rest of the chain.
	if used.size() == 1:
		assert_eq(used[0].interaction_id, CRATE_INTERACTION, "and it was the crate's")
		assert_eq(used[0].interactor, player, "published with who did it")
		assert_eq(used[0].target, crate, "and what it was done to")
		assert_eq(
			used[0].verb,
			GameplayNames.VERB_SEARCH,
			"and the verb the mission matches on"
		)

	# 3. PICKUP. The item is in the bag because the interaction put it there.
	assert_eq(inventory.count(RELIC), 1, "the interaction's action filled the bag")
	var acquired := _events_of(GameplayNames.EVENT_ITEM_ACQUIRED)
	assert_size(acquired, 1, "and the inventory adapter promoted it to the bus")
	if acquired.size() == 1:
		assert_eq(acquired[0].item_id, RELIC, "naming what arrived")
		assert_eq(acquired[0].get_owner_entity(), player, "and whose bag it arrived in")

	# The mission has heard two of the three facts and no more.
	var runtime := missions.get_runtime(MISSION)
	assert_not_null(runtime, "the mission is still in flight")
	if runtime != null:
		assert_true(
			runtime.get_objective(OBJECTIVE_SEARCH).is_complete(),
			"the interact objective advanced off the bus event"
		)
		assert_true(
			runtime.get_objective(OBJECTIVE_TAKE).is_complete(),
			"and so did the acquire objective"
		)
		assert_false(
			runtime.get_objective(OBJECTIVE_REPORT).is_complete(),
			"but nothing has been said to anybody yet"
		)

	# 4. DIALOGUE. Same walk, same button, a different kind of target.
	var at_foreman := _walk_to(foreman, 1.5)
	assert_true(at_foreman <= 1.5, "the character walked on to the foreman")
	assert_eq(
		interactor.get_focus(),
		_interaction_of(foreman),
		"the spent crate stopped being offered and focus moved on by itself"
	)
	_press_interact()
	assert_true(dialogue.is_talking(), "the interaction started the conversation")
	_accept_the_job(dialogue)
	assert_false(dialogue.is_talking(), "which then ran to its end")
	assert_true(
		narrative.get_flag(&"flag.job_accepted"),
		"the choice taken wrote the narrative state its action asked for"
	)
	var conversations := _events_of(GameplayNames.EVENT_DIALOGUE_COMPLETED)
	assert_size(conversations, 1, "the dialogue adapter promoted the ending")
	if conversations.size() == 1:
		assert_eq(
			conversations[0].outcome, &"outcome.accepted", "with the outcome reached"
		)
		assert_eq(conversations[0].listener, player, "and who it was reached with")

	# 5. MISSION. Three modules, three events, one completed mission.
	assert_true(
		missions.has_completed(MISSION),
		"the mission completed off bus events alone"
	)
	assert_false(missions.is_active(MISSION), "and is no longer in flight")
	assert_true(
		narrative.get_flag(REWARD_FLAG),
		"and paid its reward into narrative state"
	)


# --- Save -----------------------------------------------------------------

func test_the_finished_adventure_survives_a_save() -> void:
	_play_the_chain()
	assert_true(missions.has_completed(MISSION), "the chain ran before the save")
	var stood_at := player.global_position
	assert_ok(saves.save(&"slot_1"))

	# A second world, as a fresh launch is: new services, a character rebuilt
	# from scratch, and only the file in common. Nothing is carried over by
	# object identity, which is the only honest way to test a load.
	var second := _second_world()
	assert_ok(second.saves.load_slot(&"slot_1"))

	assert_true(
		second.missions.has_completed(MISSION),
		"the quest log came back knowing the mission was done"
	)
	assert_eq(
		second.inventory.count(RELIC), 1, "and the relic came back in the bag"
	)
	assert_true(
		second.narrative.get_flag(&"flag.job_accepted"),
		"and the flag the conversation raised"
	)
	assert_true(
		second.narrative.get_flag(REWARD_FLAG),
		"and the flag the mission paid out"
	)
	assert_almost_eq(
		second.player.global_position.z, stood_at.z, 0.001,
		"and the character is standing where the walk left them"
	)


func test_a_mission_still_in_flight_comes_back_able_to_finish() -> void:
	# The harder half of the save link. A completed mission is one boolean; a
	# mission two objectives into three has to come back knowing which two,
	# or the conversation below completes nothing.
	assert_ok(missions.start_by_id(MISSION, player))
	_walk_to(crate, 1.5)
	_press_interact()
	assert_eq(inventory.count(RELIC), 1, "the first half of the chain ran")
	assert_ok(saves.save(&"slot_midway"))

	var second := _second_world()
	assert_ok(second.saves.load_slot(&"slot_midway"))

	var runtime := second.missions.get_runtime(MISSION)
	assert_not_null(runtime, "the mission came back in flight")
	if runtime != null:
		assert_true(
			runtime.get_objective(OBJECTIVE_SEARCH).is_complete(),
			"remembering that the crate had been searched"
		)
		assert_true(
			runtime.get_objective(OBJECTIVE_TAKE).is_complete(),
			"and that the relic had been taken"
		)
		assert_false(
			runtime.get_objective(OBJECTIVE_REPORT).is_complete(), "but no more"
		)

	# Finish it in the rebuilt world. Only a restored mission can complete here.
	assert_ok(second.dialogue.talk(second.player))
	_accept_the_job(second.dialogue)
	assert_true(
		second.missions.has_completed(MISSION),
		"the last objective completed the mission the save restored"
	)
	assert_true(
		second.narrative.get_flag(REWARD_FLAG),
		"and the reward was paid in the world that loaded it"
	)


# --- The structural claim -------------------------------------------------

func test_the_mission_that_watched_all_this_names_no_module() -> void:
	# Everything above could be true and the design still wrong, if an
	# objective had to hold a component to work. It does not: the whole mission
	# is event names, field names and values.
	var definition := core.get_definition(MISSION) as MissionDefinition
	assert_not_null(definition, "the mission is registered content")
	for objective in definition.objectives:
		assert_ne(objective.event_name, &"", "%s counts a named event" % objective.id)
		for matcher in objective.matchers:
			assert_ne(matcher.field, &"", "a matcher on %s names a field" % objective.id)
			assert_false(
				matcher.value is Object,
				"a matcher on %s holds a live object rather than a value" % objective.id
			)

	# And the classes those objectives are made of import none of what this
	# slice pointed them at.
	for path in [
		"res://addons/universal_gameplay/missions/objective_definition.gd",
		"res://addons/universal_gameplay/missions/event_matcher.gd",
	]:
		var text := FileAccess.get_file_as_string(path)
		assert_true(text.length() > 0, "could not read %s" % path)
		for type_name in [
			"InteractionComponent", "InventoryComponent", "DialogueComponent",
			"ResourceNode", "HarvestAction", "TalkAction",
		]:
			assert_false(text.contains(type_name), "%s names %s" % [path, type_name])


# --- Helpers used by more than one test -----------------------------------

## The whole chain with no assertions, for the tests whose subject is what
## happens afterwards.
func _play_the_chain() -> void:
	assert_ok(missions.start_by_id(MISSION, player))
	_walk_to(crate, 1.5)
	_press_interact()
	_walk_to(foreman, 1.5)
	_press_interact()
	_accept_the_job(dialogue)


class SecondWorld:
	extends RefCounted
	var saves: SaveService = null
	var missions: MissionService = null
	var narrative: NarrativeStateService = null
	var player: Node3D = null
	var inventory: InventoryComponent = null
	var dialogue: DialogueComponent = null


## Builds a world that shares only the definition registry and the save
## backend with the one the chain was played in.
func _second_world() -> SecondWorld:
	# The first world's mission service stays subscribed to the bus otherwise,
	# and would react to the second world's conversation as well as its own.
	missions.set_bus(null)

	var world := SecondWorld.new()
	world.narrative = NarrativeStateService.new()
	world.narrative.name = "SecondNarrative"
	add_test_node(world.narrative)

	world.player = _build_player("RebuiltPlayer")
	world.inventory = _find(world.player, InventoryComponent) as InventoryComponent

	world.dialogue = _find(
		_build_foreman("RebuiltForeman", world.narrative), DialogueComponent
	) as DialogueComponent

	world.missions = MissionService.new()
	world.missions.name = "SecondMissionService"
	add_test_node(world.missions)
	world.missions.configure(core, bus, world.narrative)
	world.missions.default_subject = world.player

	world.saves = SaveService.new()
	world.saves.name = "SecondSaveService"
	add_test_node(world.saves)
	world.saves.configure(saves.backend, core)
	assert_ok(world.saves.register_service(GameplayNames.SERVICE_NARRATIVE, world.narrative))
	assert_ok(world.saves.register_service(GameplayNames.SERVICE_OBJECTIVE, world.missions))
	assert_ok(world.saves.register_entity(world.player))
	return world
