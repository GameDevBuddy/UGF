extends FrameworkTestCase
## M19 exit gate: a project integrates Core plus chosen modules without
## copying game-specific code.
##
## The two example projects under [code]examples/[/code] are the evidence.
## Each is one [FrameworkSettings] resource naming the modules it wants and
## the folder its content lives in -- no scripts, no scenes, no framework code
## copied anywhere. These tests bootstrap them exactly as a game would and
## then play a slice of each with real components, because content that loads
## and then does nothing is not an integration.

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"
const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

const EXAMPLES_ROOT: String = "res://examples"
const ADVENTURE_SETTINGS: String = "res://examples/adventure/settings.tres"
const SURVIVAL_SETTINGS: String = "res://examples/survival/settings.tres"

var bus: Node = null


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false


# --- Installing an example -----------------------------------------------

func test_the_adventure_example_installs_from_its_settings_alone() -> void:
	var core := _boot(ADVENTURE_SETTINGS, "AdventureCore")
	var result: ValidationResult = core.get_bootstrap_result()

	assert_false(result.has_errors(), result.format_report())
	assert_true(core.has_feature(&"module.missions"))
	assert_true(core.has_feature(&"module.dialogue"))
	assert_true(core.has_feature(&"module.inventory"))


func test_the_survival_example_installs_from_its_settings_alone() -> void:
	var core := _boot(SURVIVAL_SETTINGS, "SurvivalCore")
	var result: ValidationResult = core.get_bootstrap_result()

	assert_false(result.has_errors(), result.format_report())
	assert_true(core.has_feature(&"module.crafting"))
	assert_true(core.has_feature(&"module.survival"))


func test_example_content_is_registered_by_id() -> void:
	# Rule 32: the mission is found by what it is called, not by where the
	# file happens to sit.
	var core := _boot(ADVENTURE_SETTINGS, "AdventureIdCore")
	assert_true(core.has_definition(&"example.mission.light_the_cellar"))
	assert_true(core.has_definition(&"example.dialogue.gatekeeper"))
	assert_true(core.has_definition(&"example.item.lantern"))
	assert_true(core.has_definition(&"example.item.cellar_key"))


func test_example_content_passes_the_frameworks_own_validation() -> void:
	# Bootstrap validates every definition it scanned. Warnings included:
	# example content that trips a warning is example content teaching a
	# reader to trip it too.
	for path in [ADVENTURE_SETTINGS, SURVIVAL_SETTINGS]:
		var core := _boot(path, "ValidatingCore_%s" % path.get_file())
		var result: ValidationResult = core.get_bootstrap_result()
		assert_false(result.has_warnings(), "%s:\n%s" % [path, result.format_report()])
		assert_false(result.has_errors(), "%s:\n%s" % [path, result.format_report()])


func test_the_examples_contain_no_gdscript_at_all() -> void:
	# The claim the exit gate actually makes. If an example needed a script to
	# work, "integrates without copying game-specific code" would be false and
	# this whole milestone would be a wish.
	var scripts := _find_by_extension(EXAMPLES_ROOT, "gd")
	assert_empty(scripts, "Scripts under examples/: %s" % str(scripts))


func test_the_examples_reference_only_the_addon() -> void:
	# An example pointing at res://tests/ would work here and break for a
	# reader who copied examples/ into their own project.
	var offenders: Array[String] = []
	for path in _find_by_extension(EXAMPLES_ROOT, "tres"):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var text := file.get_as_text()
		file.close()
		for reference in _external_references(text):
			if not reference.begins_with("res://addons/universal_gameplay/"):
				offenders.append("%s loads %s" % [path, reference])
	assert_empty(offenders, "\n".join(offenders))


# --- Slice A: adventure ---------------------------------------------------

func test_the_adventure_slice_runs_end_to_end() -> void:
	# Talk to the gatekeeper, pick up the lantern, mission completes, flag
	# set. Every step is a real component publishing a real event; the
	# mission never touches Dialogue or Inventory (rule 9).
	var core := _boot(ADVENTURE_SETTINGS, "AdventureSliceCore")

	var narrative := NarrativeStateService.new()
	add_test_node(narrative)
	var missions := MissionService.new()
	add_test_node(missions)
	missions.configure(core, bus, narrative)

	var player := _player(core)
	missions.default_subject = player

	var mission: MissionDefinition = core.get_definition(&"example.mission.light_the_cellar")
	assert_not_null(mission, "The example mission was not in the registry")
	assert_ok(missions.start(mission))

	_talk_to_the_gatekeeper(core)
	assert_true(
		missions.is_active(&"example.mission.light_the_cellar"),
		"One objective of two should not finish the mission"
	)

	_give(core, player, &"example.item.lantern")

	assert_true(missions.has_completed(&"example.mission.light_the_cellar"))
	assert_true(
		narrative.get_flag(&"example.flag.ready_for_the_cellar"),
		"The mission's reward did not land"
	)


func test_the_adventure_mission_is_sequential_as_authored() -> void:
	# Picking the lantern up before asking must not credit the second
	# objective, because the .tres says sequential = true. This is the test
	# that proves the file's fields are being read rather than defaulted.
	var core := _boot(ADVENTURE_SETTINGS, "AdventureOrderCore")
	var narrative := NarrativeStateService.new()
	add_test_node(narrative)
	var missions := MissionService.new()
	add_test_node(missions)
	missions.configure(core, bus, narrative)

	var player := _player(core)
	missions.default_subject = player
	missions.start(core.get_definition(&"example.mission.light_the_cellar"))

	_give(core, player, &"example.item.lantern")

	# Asserted on the objective, not on the mission. The mission is unfinished
	# either way while the first objective is outstanding, so asking whether
	# it completed would pass with sequential switched off and prove nothing.
	var runtime: MissionRuntime = missions.get_runtime(&"example.mission.light_the_cellar")
	var lantern := runtime.get_objective(&"example.objective.find_a_lantern")
	assert_false(
		lantern.is_active(), "The second objective was live before the first was done"
	)
	assert_eq(lantern.progress, 0.0, "It counted the lantern out of turn")


# --- Slice C: survival ----------------------------------------------------

func test_the_survival_slice_crafts_from_authored_content() -> void:
	# Two ingredients in, one torch out, entirely from .tres.
	var core := _boot(SURVIVAL_SETTINGS, "SurvivalCraftCore")
	var player := _player(core)
	var inventory := _inventory_of(player)

	_give(core, player, &"example.item.kindling", 2)
	_give(core, player, &"example.item.pine_resin", 1)

	var crafting := CraftingComponent.new()
	crafting.name = "CraftingComponent"
	crafting.inventory = inventory
	crafting.auto_tick = false
	player.add_child(crafting)
	crafting.initialize(EntityContext.create(player, null, core))

	var recipe: RecipeDefinition = core.get_definition(&"example.recipe.torch")
	assert_not_null(recipe)
	assert_ok(crafting.craft(recipe))

	assert_eq(inventory.count(&"example.item.torch"), 1)
	assert_eq(inventory.count(&"example.item.kindling"), 0, "Ingredients were consumed")
	assert_eq(inventory.count(&"example.item.pine_resin"), 0)


func test_the_survival_slice_refuses_a_craft_without_the_ingredients() -> void:
	var core := _boot(SURVIVAL_SETTINGS, "SurvivalRefuseCore")
	var player := _player(core)
	var inventory := _inventory_of(player)

	_give(core, player, &"example.item.kindling", 1)

	var crafting := CraftingComponent.new()
	crafting.name = "CraftingComponent"
	crafting.inventory = inventory
	crafting.auto_tick = false
	player.add_child(crafting)
	crafting.initialize(EntityContext.create(player, null, core))

	assert_err(crafting.craft(core.get_definition(&"example.recipe.torch")))
	assert_eq(inventory.count(&"example.item.kindling"), 1, "Nothing was consumed")


func test_the_survival_slice_feeds_a_hungry_character() -> void:
	# The need, the food and how much it restores are all authored data.
	var core := _boot(SURVIVAL_SETTINGS, "SurvivalNeedsCore")
	var player := _player(core)

	var need: NeedDefinition = core.get_definition(&"example.need.hunger")
	assert_not_null(need)

	var needs := NeedsComponent.new()
	needs.name = "NeedsComponent"
	var needs_list: Array[NeedDefinition] = [need]
	needs.needs_override = needs_list
	needs.auto_tick = false
	player.add_child(needs)
	needs.initialize(EntityContext.create(player, null, core))

	needs.tick(120.0)
	var hungry := needs.get_value(&"example.need.hunger")
	assert_true(hungry < 100.0, "Hunger did not decay")

	var berries: ItemDefinition = core.get_definition(&"example.item.dried_berries")
	needs.restore(&"example.need.hunger", berries.consumable.restore_amounts[0])

	assert_true(needs.get_value(&"example.need.hunger") > hungry, "Eating changed nothing")


# --- Helpers --------------------------------------------------------------

## Boots a throwaway core against an example's settings resource, exactly as
## the [code]FrameworkCore[/code] autoload would from Project Settings.
func _boot(settings_path: String, core_name: String) -> Node:
	var core := make_autoload(CORE_SCRIPT, core_name)
	var settings: FrameworkSettings = load(settings_path)
	core.bootstrap(settings)
	return core


## A character with a bag and an adapter that announces what goes into it.
func _player(core: Node) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Player"

	var profile := InventoryProfile.new()
	profile.slot_count = 20

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = profile
	entity.add_child(inventory)

	var adapter := InventoryEventAdapter.new()
	adapter.name = "InventoryEventAdapter"
	adapter.inventory = inventory
	adapter.event_bus = bus
	entity.add_child(adapter)

	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)
	return entity


func _give(core: Node, entity: Node, item_id: StringName, quantity: int = 1) -> void:
	var definition: ItemDefinition = core.get_definition(item_id)
	var inventory := _inventory_of(entity)
	inventory.add(ItemInstance.create(definition, quantity))


## Runs the gatekeeper conversation to its end on a throwaway NPC, so the
## completion reaches the bus the way it would in a game.
func _talk_to_the_gatekeeper(core: Node) -> void:
	var npc := add_test_node(Node3D.new()) as Node3D
	npc.name = "Gatekeeper"

	var dialogue := DialogueComponent.new()
	dialogue.name = "DialogueComponent"
	dialogue.dialogue_override = core.get_definition(&"example.dialogue.gatekeeper")
	npc.add_child(dialogue)

	var adapter := DialogueEventAdapter.new()
	adapter.name = "DialogueEventAdapter"
	adapter.dialogue = dialogue
	adapter.event_bus = bus
	npc.add_child(adapter)

	var context := EntityContext.create(npc, null, core)
	for component in DefinitionBinder.collect_components(npc):
		component.initialize(context)

	dialogue.talk()
	while dialogue.is_talking():
		dialogue.get_runtime().advance()


## The [code]res://[/code] paths a resource file loads, from its ext_resource
## lines. Anything outside the addon makes the example uncopyable.
func _external_references(text: String) -> Array[String]:
	var found: Array[String] = []
	for line in text.split("\n"):
		if not line.begins_with("[ext_resource"):
			continue
		var start := line.find('path="')
		if start < 0:
			continue
		start += 6
		var end := line.find('"', start)
		if end > start:
			found.append(line.substr(start, end - start))
	return found


func _inventory_of(entity: Node) -> InventoryComponent:
	for component in DefinitionBinder.collect_components(entity):
		if component is InventoryComponent:
			return component as InventoryComponent
	return null


func _find_by_extension(directory: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full_path := directory.path_join(entry)
			if dir.current_is_dir():
				found.append_array(_find_by_extension(full_path, extension))
			elif entry.get_extension() == extension:
				found.append(full_path)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
