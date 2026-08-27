extends FrameworkTestCase
## Slice E of the vertical slice gates: the whole framework switched on at
## once, and nothing inside it quietly wired to anything else.
##
## The other four slices each follow one story through several modules. This
## one has no story. It asks three questions that only make sense about the
## framework as a whole.
##
## [b]Does all of it come up together?[/b] Every module in the catalog in one
## core, and a second core alongside it holding its own copy of the same set --
## a module keeping state in a static or an autoload would work perfectly right
## up until a project ran two worlds at once.
##
## [b]Is any of it wired to a sibling it never declared?[/b] This is the gate.
## Rule 9 says cross-feature integration lives in adapters and contracts; rule
## 36 says a dependency that exists is written down in the manifest. Neither is
## checkable by running the code: an undeclared reference compiles and works
## perfectly in this repository, where every module is on disk, and only breaks
## for the project that installed half of them. So the check is structural.
## Scan each module folder for the class names it mentions and for the addon
## paths it loads, look up which folder owns each, and require the manifest to
## admit the relationship. Both halves are needed: a scene composes an entity
## out of scripts named by [code]res://[/code] path and never spells a class,
## and a project that installed Character without Combat gets a broken
## [code]character.tscn[/code] rather than a compile error. Core is excluded,
## because every module may know Core.
##
## [b]Does one entity survive carrying all of it?[/b] Twelve modules' worth of
## components on one [Node3D], exercised against each other and then round
## tripped through a save. Interference is the failure this catches: damage
## that corrupts a bag, a buff that outlives the item granting it, a character
## that comes back from a save stronger than it went in.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"
const ADDON_ROOT: String = "res://addons/universal_gameplay"

var core: Node = null
var bus: Node = null
var factions: FactionService = null
var saves: SaveService = null

## Lazily built by [method _module_folders] and [method _class_folders]; the
## structural scan reads a couple of hundred files and several tests want the
## same answer.
var _folders: Dictionary = {}
var _classes: Dictionary = {}
var _patterns: Dictionary = {}
var _path_pattern: RegEx = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")

	# Bootstrapped, not merely constructed. make_autoload only puts the script
	# in the tree, so without this line the hybrid entity below is assembled
	# against a core reporting has_feature() == false for every module Part 1
	# just proved comes up -- and the two halves of this slice would be two
	# unrelated tests sharing a file rather than one chain.
	var installed: ValidationResult = core.bootstrap(_everything())
	assert_false(
		installed.has_errors(),
		"The core the hybrid entity is built against must come up clean: %s"
		% installed.format_report()
	)

	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false

	factions = FactionFixtures.service()
	factions.name = "FactionService"
	add_test_node(factions)

	saves = SaveService.new()
	saves.name = "SaveService"
	add_test_node(saves)
	saves.configure(SaveBackend.new(), core)


# --- Part 1: everything comes up together --------------------------------

func test_every_module_the_addon_ships_comes_up_in_one_core() -> void:
	var installed := make_autoload(CORE_SCRIPT, "HybridEverythingCore")

	var result: ValidationResult = installed.bootstrap(_everything())

	assert_false(
		result.has_errors(),
		"Enabling every shipped module at once must not error: %s" % result.format_report()
	)
	for id in ModuleCatalog.get_ids():
		assert_true(
			installed.has_feature(id),
			"%s is in the catalog but did not register when everything was enabled" % id
		)
	assert_size(
		installed.get_module_ids(),
		ModuleCatalog.get_ids().size(),
		"Every catalogued module should be registered exactly once"
	)


func test_every_requirement_of_every_registered_module_is_also_registered() -> void:
	# The runtime half of the manifest claim, asked against a graph that can
	# actually be open. Enabling everything makes closure a tautology:
	# resolve_order refuses any list with a requirement outside it, so a core
	# that bootstrapped at all has a closed graph by construction and the
	# question answers itself.
	#
	# Gathering alone is the case worth asking about. It requires Items,
	# Inventory and Loot, none of them enabled, and two of those need Entity
	# behind them -- so the repair the bootstrapper names has to be transitive
	# or the second installation below does not come up.
	var requested: Array[StringName] = [&"module.gathering"]

	var refused := make_autoload(CORE_SCRIPT, "HybridPartialCore")
	var refusal: ValidationResult = refused.bootstrap(_only(requested))

	assert_true(
		refusal.has_errors(),
		"A module list with a requirement left out must be refused, not repaired quietly"
	)
	assert_empty(
		refused.get_module_ids(),
		"An unresolvable list must register nothing rather than half of itself"
	)
	assert_false(
		refused.has_feature(&"module.gathering"),
		"Gathering came up without the modules it requires"
	)

	var implied := ModuleCatalog.get_implied_requirements(requested)

	assert_has(implied, &"module.loot", "Loot is a direct requirement of Gathering")
	assert_has(
		implied,
		&"module.entity",
		"Entity is required through Items and Inventory, so the closure has to be transitive"
	)

	var closed: Array[StringName] = requested.duplicate()
	closed.append_array(implied)
	var installed := make_autoload(CORE_SCRIPT, "HybridClosureCore")
	var result: ValidationResult = installed.bootstrap(_only(closed))

	assert_false(
		result.has_errors(),
		"Enabling exactly the modules the bootstrapper named must resolve: %s"
		% result.format_report()
	)
	assert_size(
		installed.get_module_ids(),
		closed.size(),
		"The bootstrapper registered something nobody asked for"
	)
	for id in closed:
		assert_true(installed.has_feature(id), "%s was asked for and did not register" % id)

	# The obvious follow-up -- looping the registered set and asserting each
	# module's requirements are also registered -- cannot fail and is not here.
	# resolve_order already refuses any list whose requirements are not all in
	# it, and the two assertions above pin the registered set to exactly the
	# list. Re-deriving that from the same static table proves the table is
	# self-consistent, which was never in doubt.
	#
	# These two are questions the registry can actually answer wrong.
	assert_empty(
		ModuleCatalog.get_implied_requirements(closed),
		"the chosen set is closed, so nothing is missing from it"
	)
	for id in closed:
		# Read off the running instance rather than the catalog. A module that
		# built one manifest for registration and reported another afterwards
		# would satisfy the bootstrapper and lie to everything downstream --
		# docs/modules.md included, which is generated from exactly this call.
		var running: FrameworkModule = installed.get_module(id)
		assert_not_null(running, "%s registered and then could not be fetched" % id)
		assert_eq(
			running.get_manifest().requires,
			ModuleCatalog.get_manifest(id).requires,
			"%s reports different requirements once it is running" % id
		)


func test_two_cores_hold_the_whole_catalog_at_the_same_time() -> void:
	# Beyond what test_packaging asks. One full installation proves the modules
	# coexist; two prove no module smuggled its state into a static or an
	# autoload, which is the failure that only shows up in a project running a
	# server world and a client world in one process (rule 2).
	var first := make_autoload(CORE_SCRIPT, "HybridFirstCore")
	var second := make_autoload(CORE_SCRIPT, "HybridSecondCore")

	var first_result: ValidationResult = first.bootstrap(_everything())
	var second_result: ValidationResult = second.bootstrap(_everything())

	assert_false(first_result.has_errors(), first_result.format_report())
	assert_false(
		second_result.has_errors(),
		"A second full installation alongside the first failed: %s"
		% second_result.format_report()
	)
	for id in ModuleCatalog.get_ids():
		assert_true(second.has_feature(id), "%s is missing from the second core" % id)

	# Input is the probe. Distinct module instances prove nothing about shared
	# state -- ModuleCatalog.instantiate news one per call, so two cores hold
	# different objects as arithmetic rather than as a discovered property, and
	# a module could keep everything in a static and still hand back two. What
	# tells the two apart is a module that actually owns something, and Input is
	# the only one in the catalog that does: initialize() builds an InputRouter,
	# parents it to the core it was handed, and registers it as that core's
	# service.
	var first_router := first.get_service(GameplayNames.SERVICE_INPUT) as InputRouter
	var second_router := second.get_service(GameplayNames.SERVICE_INPUT) as InputRouter

	assert_not_null(first_router, "The first core registered no input router to be isolated")
	assert_not_null(second_router, "The second core got no input router of its own")
	assert_true(first_router != second_router, "One router was handed to both cores")

	# State pushed on one core, invisible from the other. A router living in a
	# static or an autoload answers this question with the other world's stack.
	var driving := InputContext.new()
	driving.id = &"input.driving"
	driving.actions = [GameplayNames.ACTION_MOVE_FORWARD]
	assert_ok(first_router.push_context(driving))

	assert_eq(first_router.get_depth(), 1, "The first core's router did not take the context")
	assert_eq(
		second_router.get_depth(), 0, "The second core's router saw the first core's context"
	)
	assert_false(
		second_router.is_action_allowed(GameplayNames.ACTION_MOVE_FORWARD),
		"The second core answers input questions out of the first core's stack"
	)

	# The same failure from the other end: one world shutting down must not
	# release anything the other is still using.
	first.shutdown()

	assert_false(
		first.has_service(GameplayNames.SERVICE_INPUT),
		"The first core kept its input service through shutdown"
	)
	assert_true(
		second.has_service(GameplayNames.SERVICE_INPUT),
		"Shutting the first core down took the second core's input service with it"
	)
	assert_true(
		is_instance_valid(second_router),
		"Shutting the first core down freed the second core's router"
	)
	assert_eq(
		second.get_service(GameplayNames.SERVICE_INPUT),
		second_router,
		"The second core's input service is no longer the router it was given"
	)
	assert_size(
		second.get_module_ids(),
		ModuleCatalog.get_ids().size(),
		"Shutting the first core down unregistered the second core's modules"
	)


func test_the_whole_catalog_comes_down_and_goes_back_up() -> void:
	# Shutdown is where a module that registered something globally shows
	# itself: the second bootstrap fails on whatever the first left behind.
	var installed := make_autoload(CORE_SCRIPT, "HybridCycleCore")
	installed.bootstrap(_everything())
	assert_size(installed.get_module_ids(), ModuleCatalog.get_ids().size())

	installed.shutdown()

	assert_empty(installed.get_module_ids(), "Shutdown left modules registered")
	assert_false(installed.is_bootstrapped(), "Shutdown left the core marked as bootstrapped")

	var again: ValidationResult = installed.bootstrap(_everything())

	assert_false(
		again.has_errors(),
		"Bringing everything up a second time failed: %s" % again.format_report()
	)
	assert_size(
		installed.get_module_ids(),
		ModuleCatalog.get_ids().size(),
		"The second installation is not the same size as the first"
	)


# --- Part 2: no undeclared sibling dependencies --------------------------

func test_no_module_reaches_into_a_sibling_it_never_declared() -> void:
	# The gate. Every class name a module's sources mention that another module
	# declares, and every addon file a module's sources load by path, has to
	# appear in this module's manifest as required or optional. An undeclared
	# one is a hidden import (rule 9) and a dependency nobody wrote down
	# (rule 36) -- and it is invisible here, where the whole addon is on disk,
	# because it only breaks in a project that installed the one module and not
	# the other.
	var offenders := _undeclared_sibling_references()
	assert_empty(
		offenders,
		(
			"Modules referencing siblings their manifest does not declare:\n%s"
			% "\n".join(offenders)
		)
	)


func test_the_scan_behind_that_check_actually_read_the_addon() -> void:
	# A structural check that finds nothing passes, whether the framework is
	# clean or the scanner is broken. These are the assertions that tell those
	# two apart.
	var modules := _module_folders()
	var classes := _class_folders()

	assert_size(
		modules,
		ModuleCatalog.get_ids().size(),
		"The folder map should have one entry per catalogued module"
	)
	assert_true(
		classes.size() >= 150,
		"Only %d class_name declarations were found under a module folder; the scan is broken"
		% classes.size()
	)
	assert_eq(
		modules.get("commerce", &""),
		&"module.commerce",
		"The catalog's script paths should map the commerce folder to its module id"
	)
	assert_eq(
		classes.get("WalletComponent", ""),
		"commerce",
		"WalletComponent should be attributed to the folder that declares it"
	)

	for folder in modules:
		var declared := 0
		for owner_folder in classes.values():
			if owner_folder == folder:
				declared += 1
		assert_true(
			declared > 0,
			"No class_name was found anywhere in the %s module; the scan missed a folder"
			% folder
		)

	# And the same for the path half, which reads different files and would
	# otherwise be able to find nothing while looking busy.
	# Asserted against _sources(), not against _files(). The gate iterates the
	# composed list, so probing the helper would leave the .tscn line free to
	# be deleted: the self-check would stay green while the gate quietly
	# stopped reading scenes and reported no offenders forever -- exactly the
	# failure this whole section exists to rule out.
	var character := "%s/character/character.tscn" % ADDON_ROOT
	assert_has(
		_sources(),
		character,
		"the scanner's own file list does not include character.tscn"
	)
	assert_has(
		_referenced_folders(FileAccess.get_file_as_string(character)),
		"combat",
		"character.tscn attaches the combat module's scripts by path, and the scan must see it"
	)


func test_core_and_the_shared_folders_are_outside_the_check() -> void:
	# Core is excluded on purpose: every module may know Core. So are the
	# folders that hold no module -- attributing DefinitionValidator to a
	# module would invent a dependency that does not exist.
	var classes := _class_folders()
	for shared in ["EntityContext", "FrameworkResult", "GameplayNames", "DefinitionValidator"]:
		assert_eq(
			classes.get(shared, ""),
			"",
			"%s does not live in a module folder and must not be attributed to one" % shared
		)
	assert_eq(
		classes.get("FrameworkComponent", ""),
		"entity",
		"FrameworkComponent does live in a module folder, and Entity is that module"
	)


func test_the_check_names_a_reference_that_is_not_declared() -> void:
	# The proof that the check can fail. Missions declares Entity and three
	# optional modules and says nothing about Commerce, so a source file in
	# that folder touching a wallet is exactly the violation this gate exists
	# to catch.
	var offenders := _undeclared_references_in(
		"missions", "extends FrameworkComponent\nvar purse: WalletComponent = null\n"
	)

	assert_size(offenders, 1, "One undeclared reference should produce one report")
	assert_true(
		offenders[0].contains("WalletComponent"), "The report names the class: %s" % offenders[0]
	)
	assert_true(
		offenders[0].contains("module.commerce"),
		"The report names the module that owns it: %s" % offenders[0]
	)


func test_the_check_names_a_scene_that_attaches_an_undeclared_module_script() -> void:
	# The half a class-name scan cannot see. Nothing in this line spells
	# WalletComponent, and the path it does spell lives inside a string literal,
	# so both of the earlier filters would throw it away -- but a project that
	# enabled Missions without Commerce still gets a scene it cannot open.
	var scene := (
		'[ext_resource type="Script" path="%s/commerce/wallet_component.gd" id="1_wallet"]'
		% ADDON_ROOT
	)
	var offenders := _undeclared_references_in("missions", scene + "\n")

	assert_size(offenders, 1, "One undeclared path reference should produce one report")
	assert_true(
		offenders[0].contains("commerce"), "The report names the folder: %s" % offenders[0]
	)
	assert_true(
		offenders[0].contains("module.commerce"),
		"The report names the module that owns it: %s" % offenders[0]
	)


func test_a_scene_loading_core_or_its_own_folder_is_not_a_violation() -> void:
	# Core is outside the check for scenes exactly as it is for source, and a
	# module attaching its own scripts is what a module's scene is made of.
	var scene := (
		'[ext_resource path="%s/core/framework_core.gd" id="1_core"]' % ADDON_ROOT
		+ "\n"
		+ '[ext_resource path="%s/missions/area_trigger.gd" id="2_area"]' % ADDON_ROOT
	)
	var offenders := _undeclared_references_in("missions", scene + "\n")

	assert_empty(offenders, "Every module may know Core and its own folder")


func test_a_comment_naming_a_sibling_class_is_not_a_reference() -> void:
	# Doc comments cross-reference other modules constantly -- that is what
	# documentation is for. Scanning raw source would report every one of them
	# and the check would have to be switched off to get a green suite.
	var offenders := _undeclared_references_in(
		"missions",
		"## Rewards are paid through a WalletComponent when Commerce is present.\n"
		+ "# var purse: WalletComponent\n"
		+ "extends FrameworkComponent\n"
	)
	assert_empty(offenders, "A commented mention is documentation, not an import")


func test_a_class_named_inside_a_string_is_not_a_reference() -> void:
	# The other false positive: an error message or a test-facing name that
	# happens to spell a class. Nothing is imported by writing its name in a
	# message.
	var offenders := _undeclared_references_in(
		"missions", "extends FrameworkComponent\nvar note := \"needs WalletComponent\"\n"
	)
	assert_empty(offenders, "A class name inside a string literal is not a dependency")


func test_a_module_referencing_its_own_classes_is_not_a_violation() -> void:
	var offenders := _undeclared_references_in(
		"commerce", "var purse: WalletComponent = null\nvar shop: VendorComponent = null\n"
	)
	assert_empty(offenders, "A module is allowed to know its own folder")


func test_a_declared_reference_is_accepted() -> void:
	# Inventory requires Items, so an inventory file naming ItemInstance is
	# exactly the relationship the manifest describes.
	var offenders := _undeclared_references_in(
		"inventory", "func add(instance: ItemInstance) -> void:\n\tpass\n"
	)
	assert_empty(offenders, "A reference the manifest declares must pass")


# --- Part 3: one entity, twelve modules ----------------------------------

func test_one_entity_carries_every_capability_at_once() -> void:
	var polymath := _polymath()

	assert_size(
		_capability_types(polymath),
		17,
		"The hybrid character carries seventeen capability types drawn from twelve modules"
	)
	# The chain link between this half of the slice and the last one. These
	# components were initialised against the core before_each bootstrapped, so
	# the hybrid is carrying twelve modules' worth of capability on a core where
	# every module is actually running -- the state Part 1 establishes, and the
	# state EntityContext.has_feature exists to let a component branch on.
	var context := _stats(polymath).get_context()
	assert_not_null(context, "Stats was never handed a context")
	for id in ModuleCatalog.get_ids():
		assert_true(
			context.has_feature(id),
			"The hybrid was assembled against a core with no %s registered" % id
		)

	# Seventeen capabilities, and for each of them something initialisation
	# produced. Asserting the components are still children would only re-read
	# the fixture that added them twenty lines ago; every assertion below reads
	# state that exists because initialize() ran, and most of them name a
	# sibling that initialize() resolved -- which is the actual claim, that the
	# twelve modules are wired to each other rather than parked on one node.
	var state := _find(polymath, SemanticState) as SemanticState
	var receiver := _receiver(polymath)
	var effects := _effects(polymath)
	var inventory := _inventory(polymath)
	var equipment := _equipment(polymath)

	assert_ok(
		saves.register_entity(polymath),
		"Entity: Save found no persistent identity to file this character under"
	)
	assert_not_null(state, "Entity: the shared state vocabulary is missing")

	assert_almost_eq(
		_stats(polymath).get_value(&"stat.power"),
		10.0,
		0.001,
		"Stats came up on its profile with every other module beside it"
	)
	assert_almost_eq(
		_health(polymath).get_current(),
		100.0,
		0.001,
		"Health did not fill itself from its maximum, so its initialise never ran"
	)
	assert_true(
		polymath.is_in_group(GameplayNames.GROUP_DAMAGEABLE),
		"Health did not advertise the entity as damageable"
	)
	assert_eq(receiver.health, _health(polymath), "Damage: the receiver found no health to spend")
	assert_eq(
		(_find(polymath, HealthEventAdapter) as HealthEventAdapter).health,
		_health(polymath),
		"Health adapter: nothing to promote to the bus"
	)
	assert_eq(effects.stats, _stats(polymath), "Status effects: no Stats to write modifiers into")
	assert_eq(effects.damage_receiver, receiver, "Status effects: no receiver for damage effects")
	assert_eq(effects.semantic_state, state, "Status effects: no state to tag the entity with")

	assert_eq(inventory.get_free_slots(), 20, "Inventory: the container profile never resolved")
	assert_eq(
		(_find(polymath, InventoryEventAdapter) as InventoryEventAdapter).inventory,
		inventory,
		"Inventory adapter: no bag to publish acquisitions from"
	)
	assert_has(
		equipment.get_slot_ids(),
		&"slot.main_hand",
		"Equipment: the loadout never resolved, so there is nowhere to put a sword"
	)
	assert_eq(equipment.stats, _stats(polymath), "Equipment: nowhere to apply an item's modifier")
	assert_eq(equipment.inventory, inventory, "Equipment: no bag to take the item out of")

	assert_has(
		_needs(polymath).get_need_ids(), &"need.hunger", "Survival: no need definitions resolved"
	)
	assert_almost_eq(
		_needs(polymath).get_value(&"need.hunger"),
		100.0,
		0.001,
		"Survival: needs were never seeded to their starting values"
	)
	assert_eq(_consumer(polymath).needs, _needs(polymath), "Survival: the consumer feeds nothing")
	assert_eq(_consumer(polymath).inventory, inventory, "Survival: the consumer eats out of no bag")

	assert_not_null(
		_interactor(polymath).get_profile(), "Interaction: the interactor profile never resolved"
	)
	assert_eq(_interactor(polymath).semantic_state, state, "Interaction: no state to tag")

	assert_almost_eq(
		_wallet(polymath).get_balance(&"currency.gold"),
		120.0,
		0.001,
		"Commerce: the purse was never seeded from its starting amounts"
	)
	assert_eq(
		_faction(polymath).get_faction(),
		&"faction.watch",
		"Factions: the allegiance override never resolved"
	)
	assert_eq(_faction(polymath).service, factions, "Factions: no service to ask about standing")

	var weapon := _find(polymath, WeaponComponent) as WeaponComponent
	assert_eq(weapon.equipment, equipment, "Combat: the weapon watches no equipment slot")
	assert_eq(weapon.semantic_state, state, "Combat: the weapon tags no state")
	assert_not_null(_combat(polymath).get_profile(), "Combat: the combat profile never resolved")
	assert_eq(_combat(polymath).semantic_state, state, "Combat: the swing tags no state")

	# The maximum comes from Stats, not from the export. maximum_health is left
	# at a value nothing should ever read, so this number is only reachable
	# through stat.health.max -- a cross-module read rather than a getter.
	assert_almost_eq(
		_health(polymath).get_maximum(),
		100.0,
		0.001,
		"Health read its own export instead of the maximum Stats supplies"
	)


func test_taking_damage_moves_health_and_nothing_else() -> void:
	var polymath := _polymath()
	_carry(polymath, ItemFixtures.stackable(&"item.arrow", 20), 12)
	_wallet(polymath).set_balance(&"currency.gold", 120.0)
	_needs(polymath).set_value(&"need.hunger", 70.0)

	var taken := _receiver(polymath).receive_amount(30.0)

	assert_ok(taken, "A plain damage application on a fully loaded entity should succeed")
	assert_almost_eq(_health(polymath).get_current(), 70.0, 0.001, "Health took the damage")
	assert_eq(
		_inventory(polymath).count(&"item.arrow"), 12, "Damage did not disturb the inventory"
	)
	assert_almost_eq(
		_wallet(polymath).get_balance(&"currency.gold"), 120.0, 0.001,
		"Damage did not disturb the purse"
	)
	assert_almost_eq(
		_needs(polymath).get_value(&"need.hunger"), 70.0, 0.001, "Damage did not disturb needs"
	)
	assert_true(_health(polymath).is_alive(), "Thirty of a hundred is not fatal")


func test_equipping_raises_a_stat_without_touching_health_or_needs() -> void:
	var polymath := _polymath()
	_needs(polymath).set_value(&"need.hunger", 55.0)
	_health(polymath).set_current(80.0)
	var sword := _carry(polymath, ItemFixtures.weapon(&"item.sword", 5.0), 1)

	assert_ok(
		_equipment(polymath).equip(sword), "The sword should go into the main hand"
	)

	assert_almost_eq(
		_stats(polymath).get_value(&"stat.power"), 15.0, 0.001,
		"Equipment applied its modifier through Stats"
	)
	assert_true(
		_equipment(polymath).is_equipped(&"slot.main_hand"), "The slot holds the sword"
	)
	assert_eq(
		_inventory(polymath).count(&"item.sword"), 0,
		"Equipping took the sword out of the bag rather than duplicating it"
	)
	assert_almost_eq(
		_health(polymath).get_current(), 80.0, 0.001, "Equipping did not touch health"
	)
	assert_almost_eq(
		_needs(polymath).get_value(&"need.hunger"), 55.0, 0.001,
		"Equipping did not touch needs"
	)


func test_a_buff_and_a_worn_item_unwind_without_erasing_each_other() -> void:
	# Two modules writing modifiers into one Stats component. The failure this
	# catches is the common one: removing either source takes the other's
	# bonus with it, and the character silently drifts.
	var polymath := _polymath()
	var sword := _carry(polymath, ItemFixtures.weapon(&"item.sword", 5.0), 1)
	assert_ok(_equipment(polymath).equip(sword))

	assert_ok(_effects(polymath).apply(_rage()), "The buff should apply")
	assert_almost_eq(
		_stats(polymath).get_value(&"stat.power"), 22.0, 0.001,
		"Base ten, sword five, rage seven -- both sources are live"
	)

	assert_true(_effects(polymath).remove(&"effect.rage"), "The buff comes off")
	assert_almost_eq(
		_stats(polymath).get_value(&"stat.power"), 15.0, 0.001,
		"Removing the buff left the sword's bonus alone"
	)

	assert_ok(_equipment(polymath).unequip(&"slot.main_hand"))
	assert_almost_eq(
		_stats(polymath).get_value(&"stat.power"), 10.0, 0.001,
		"Removing the sword returned the stat to its base with nothing left over"
	)
	assert_eq(
		_inventory(polymath).count(&"item.sword"), 1, "And the sword went back in the bag"
	)


func test_growing_a_stat_does_not_reset_anything_else() -> void:
	# The framework has no levelling module, so raising a base stat is what
	# progression means here. It must not reach into needs, health or the bag.
	var polymath := _polymath()
	_carry(polymath, SurvivalFixtures.meal(&"item.ration", [&"need.hunger"], [40.0]), 2)
	_needs(polymath).set_value(&"need.hunger", 32.0)
	_health(polymath).set_current(64.0)

	_stats(polymath).set_base(&"stat.power", 25.0)

	assert_almost_eq(
		_stats(polymath).get_value(&"stat.power"), 25.0, 0.001, "The stat grew"
	)
	assert_almost_eq(
		_needs(polymath).get_value(&"need.hunger"), 32.0, 0.001,
		"Growing a stat did not refill needs"
	)
	assert_almost_eq(
		_health(polymath).get_current(), 64.0, 0.001, "Growing a stat did not heal"
	)
	assert_eq(
		_inventory(polymath).count(&"item.ration"), 2, "Growing a stat did not touch the bag"
	)


func test_eating_moves_needs_and_the_bag_and_nothing_else() -> void:
	var polymath := _polymath()
	var ration := SurvivalFixtures.meal(&"item.ration", [&"need.hunger"], [40.0])
	core.get_definition_registry().register(ration)
	_carry(polymath, ration, 3)
	_needs(polymath).set_value(&"need.hunger", 20.0)
	_health(polymath).set_current(72.0)

	assert_ok(_consumer(polymath).consume_by_id(&"item.ration"), "The ration is edible")

	assert_almost_eq(
		_needs(polymath).get_value(&"need.hunger"), 60.0, 0.001, "The meal restored hunger"
	)
	assert_eq(
		_inventory(polymath).count(&"item.ration"), 2, "And the bag is one ration lighter"
	)
	assert_almost_eq(
		_health(polymath).get_current(), 72.0, 0.001, "Eating a ration is not healing"
	)
	assert_almost_eq(
		_stats(polymath).get_value(&"stat.power"), 10.0, 0.001, "Nor is it a buff"
	)


func test_attacking_hurts_the_target_and_leaves_the_attacker_intact() -> void:
	var polymath := _polymath()
	_carry(polymath, ItemFixtures.stackable(&"item.arrow", 20), 5)
	_wallet(polymath).set_balance(&"currency.gold", 90.0)

	var dummy := add_test_node(CombatFixtures.dummy("Dummy", Vector3.FORWARD)) as Node3D
	CombatFixtures.assemble(dummy)
	var provider := FakeHitProvider.new()
	provider.wall = add_test_node(Node.new())
	provider.targets.append(dummy)
	_combat(polymath).set_hit_provider(provider)

	assert_ok(_combat(polymath).attack(), "An unarmed punch through the shared command API")

	assert_almost_eq(
		CombatFixtures.health_of(dummy).get_current(), 95.0, 0.001, "The dummy took the punch"
	)
	assert_almost_eq(
		_health(polymath).get_current(), 100.0, 0.001, "The attacker did not hurt itself"
	)
	assert_eq(_inventory(polymath).count(&"item.arrow"), 5, "Attacking did not spend the bag")
	assert_almost_eq(
		_wallet(polymath).get_balance(&"currency.gold"), 90.0, 0.001,
		"Attacking did not spend the purse"
	)


func test_interacting_changes_the_door_and_not_the_actor() -> void:
	var polymath := _polymath()
	_carry(polymath, ItemFixtures.stackable(&"item.arrow", 20), 4)
	var door := add_test_node(
		InteractionFixtures.target([InteractionFixtures.door()], "Door", true)
	)
	InteractionFixtures.assemble(door)

	var used := _interactor(polymath).begin(InteractionFixtures.interaction_of(door))

	assert_ok(used, "The door is in reach and takes one verb")
	assert_true(
		InteractionFixtures.state_of(door).has_state(GameplayNames.STATE_OPEN),
		"The door opened, which is the interaction's whole effect"
	)
	assert_false(
		_state(polymath).has_state(GameplayNames.STATE_OPEN),
		"The actor did not acquire the door's state"
	)
	assert_eq(
		_inventory(polymath).count(&"item.arrow"), 4, "Opening a door costs nothing from the bag"
	)


func test_faction_standing_is_unmoved_by_what_happened_to_the_body() -> void:
	var polymath := _polymath()
	var bandit := add_test_node(
		FactionFixtures.member("Bandit", &"faction.bandits", factions)
	) as Node3D
	FactionFixtures.assemble(bandit)

	assert_true(
		_faction(polymath).is_hostile_to(bandit),
		"The watch and the bandits start hostile, which is the standing under test"
	)

	_receiver(polymath).receive_amount(40.0)
	_stats(polymath).set_base(&"stat.power", 30.0)
	assert_ok(_effects(polymath).apply(_rage()))

	assert_eq(
		_faction(polymath).get_faction(), &"faction.watch",
		"Damage, growth and a buff do not change who somebody belongs to"
	)
	assert_true(
		_faction(polymath).is_hostile_to(bandit), "Nor do they change how the bandits feel"
	)


func test_the_bus_hears_the_capability_that_acted_and_only_that_one() -> void:
	# The sanctioned cross-module seam. Adapters promote local signals to bus
	# facts, so putting an item in a bag must produce an acquisition and not a
	# death, and dying must produce a death and not an acquisition.
	var polymath := _polymath()
	var acquisitions: Array[FrameworkEvent] = []
	var deaths: Array[FrameworkEvent] = []
	bus.subscribe(
		GameplayNames.EVENT_ITEM_ACQUIRED,
		func(event: FrameworkEvent) -> void: acquisitions.append(event)
	)
	bus.subscribe(
		GameplayNames.EVENT_ACTOR_DIED,
		func(event: FrameworkEvent) -> void: deaths.append(event)
	)

	_carry(polymath, ItemFixtures.stackable(&"item.arrow", 20), 6)

	assert_size(acquisitions, 1, "The inventory adapter published the acquisition")
	assert_empty(deaths, "Filling a bag is not a death")

	assert_ok(_health(polymath).kill())

	assert_size(deaths, 1, "The health adapter published the death")
	assert_size(acquisitions, 1, "And dying did not publish a second acquisition")


# --- Part 4: and all of it saves -----------------------------------------

func test_every_capability_on_the_hybrid_entity_survives_a_save() -> void:
	var ration := SurvivalFixtures.meal(&"item.ration", [&"need.hunger"], [40.0])
	var sword_definition := ItemFixtures.weapon(&"item.sword", 5.0)
	var registry: DefinitionRegistry = core.get_definition_registry()
	registry.register(ration)
	registry.register(sword_definition)
	registry.register(_rage())

	var polymath := _polymath()
	assert_ok(saves.register_entity(polymath))

	# Move every kind of state this entity owns.
	_carry(polymath, ration, 3)
	var sword := _carry(polymath, sword_definition, 1)
	assert_ok(_equipment(polymath).equip(sword))
	_health(polymath).set_current(58.0)
	_needs(polymath).set_value(&"need.hunger", 26.0)
	_stats(polymath).set_base(&"stat.power", 12.0)
	assert_ok(_effects(polymath).apply(_rage()))
	_wallet(polymath).set_balance(&"currency.gold", 73.0)
	_state(polymath).set_state(&"state.exhausted", true)
	_faction(polymath).set_faction(&"faction.merchants")
	polymath.global_position = Vector3(9.0, 0.0, -4.0)

	assert_ok(saves.save(&"slot_hybrid"))

	# Wipe it exactly as quitting the game would, and check every wipe took.
	#
	# An unasserted wipe makes the post-load assertion below conditional: if
	# refill_all() were a no-op, hunger would still read 26 from before the save
	# and the restore assertion would pass without load_slot having touched
	# needs at all. refill_all() and clear_states() are both loops over a
	# getter, so a getter returning nothing makes them silently do nothing --
	# which is exactly the shape of bug that would hide here.
	_equipment(polymath).unequip_all()
	_inventory(polymath).clear()
	_health(polymath).set_current(100.0)
	_needs(polymath).refill_all()
	_stats(polymath).set_base(&"stat.power", 10.0)
	_effects(polymath).clear()
	_wallet(polymath).set_balance(&"currency.gold", 0.0)
	_state(polymath).clear_states()
	_faction(polymath).set_faction(&"faction.watch")
	polymath.global_position = Vector3.ZERO

	assert_null(
		_equipment(polymath).get_equipped(&"slot.main_hand"), "The wipe: the sword came off"
	)
	assert_true(_inventory(polymath).is_empty(), "The wipe: the bag is empty")
	assert_almost_eq(
		_health(polymath).get_current(), 100.0, 0.001, "The wipe: health is back to full"
	)
	assert_almost_eq(
		_needs(polymath).get_value(&"need.hunger"), 100.0, 0.001, "The wipe: hunger is refilled"
	)
	assert_almost_eq(
		_stats(polymath).get_value(&"stat.power"),
		10.0,
		0.001,
		"The wipe: power is back to its base with no modifier left on it"
	)
	assert_false(_effects(polymath).has_effect(&"effect.rage"), "The wipe: the buff is gone")
	assert_almost_eq(
		_wallet(polymath).get_balance(&"currency.gold"), 0.0, 0.001, "The wipe: the purse is empty"
	)
	assert_false(
		_state(polymath).has_state(&"state.exhausted"), "The wipe: the state tag is cleared"
	)
	assert_eq(
		_faction(polymath).get_faction(), &"faction.watch", "The wipe: back to the starting faction"
	)
	assert_almost_eq(polymath.global_position.x, 0.0, 0.001, "The wipe: back at the origin")

	assert_ok(saves.load_slot(&"slot_hybrid"))

	assert_eq(_inventory(polymath).count(&"item.ration"), 3, "inventory")
	var worn := _equipment(polymath).get_equipped(&"slot.main_hand")
	assert_not_null(worn, "equipment: the sword is worn again")
	assert_eq(
		worn.get_definition_id() if worn != null else &"",
		&"item.sword",
		"equipment: and it is the same item, resolved by id"
	)
	assert_almost_eq(_health(polymath).get_current(), 58.0, 0.001, "health")
	assert_almost_eq(_needs(polymath).get_value(&"need.hunger"), 26.0, 0.001, "needs")
	assert_true(_effects(polymath).has_effect(&"effect.rage"), "status effects")
	assert_almost_eq(
		_stats(polymath).get_value(&"stat.power"), 24.0, 0.001,
		"stats: base twelve, plus the sword's five and rage's seven, each applied once"
	)
	assert_almost_eq(
		_wallet(polymath).get_balance(&"currency.gold"), 73.0, 0.001, "commerce: the purse"
	)
	assert_true(_state(polymath).has_state(&"state.exhausted"), "semantic state")
	assert_eq(_faction(polymath).get_faction(), &"faction.merchants", "factions")
	assert_almost_eq(polymath.global_position.x, 9.0, 0.001, "transform")


func test_the_round_trip_rebuilds_rather_than_reuses_the_entity() -> void:
	# Loading into a second world is the shape a real load has: the entity
	# that comes back is not the one that was saved. An entity whose restore
	# depended on object identity would pass the test above and fail here.
	var sword_definition := ItemFixtures.weapon(&"item.sword", 5.0)
	core.get_definition_registry().register(sword_definition)

	var original := _polymath()
	assert_ok(saves.register_entity(original))
	var sword := _carry(original, sword_definition, 1)
	assert_ok(_equipment(original).equip(sword))
	_health(original).set_current(41.0)
	_wallet(original).set_balance(&"currency.gold", 17.0)
	assert_ok(saves.save(&"slot_hybrid"))

	var elsewhere := SaveService.new()
	elsewhere.name = "OtherSaveService"
	add_test_node(elsewhere)
	elsewhere.configure(saves.backend, core)

	var rebuilt := _polymath()
	assert_ok(elsewhere.register_entity(rebuilt))

	assert_ok(elsewhere.load_slot(&"slot_hybrid"))

	assert_almost_eq(_health(rebuilt).get_current(), 41.0, 0.001, "health came back")
	assert_true(
		_equipment(rebuilt).is_equipped(&"slot.main_hand"), "and so did the worn sword"
	)
	assert_almost_eq(
		_stats(rebuilt).get_value(&"stat.power"), 15.0, 0.001,
		"and its modifier landed on a Stats component that never saw the original"
	)
	assert_almost_eq(
		_wallet(rebuilt).get_balance(&"currency.gold"), 17.0, 0.001, "and so did the purse"
	)


# --- The hybrid character -------------------------------------------------

## Settings enabling every module the addon ships.
##
## Nothing to scan and nothing to validate: what is under test is whether the
## modules coexist, not whether a content folder is well formed.
func _everything() -> FrameworkSettings:
	var settings := FrameworkSettings.new()
	for id in ModuleCatalog.get_ids():
		settings.set_module_enabled(id, true)
	settings.scan_definitions_on_bootstrap = false
	settings.validate_on_bootstrap = false
	return settings


## Settings enabling exactly [param ids] and nothing else.
func _only(ids: Array[StringName]) -> FrameworkSettings:
	var settings := FrameworkSettings.new()
	for id in ids:
		settings.set_module_enabled(id, true)
	settings.scan_definitions_on_bootstrap = false
	settings.validate_on_bootstrap = false
	return settings


## One character carrying capabilities from twelve modules, initialised and in
## the tree.
##
## Assembled by hand rather than from a definition because the point is the
## combination: an entity nobody designed as a whole, with every capability the
## framework offers hanging off one root.
func _polymath(person_name: String = "Polymath") -> Node3D:
	var entity := Node3D.new()
	entity.name = person_name

	# Entity: identity to save under, and the shared state vocabulary.
	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = StringName(person_name.to_lower())
	entity.add_child(identity)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	# Stats, Health and Status Effects.
	var stats := StatsComponent.new()
	stats.name = "StatsComponent"
	stats.profile_override = _stats_profile(10.0, 100.0)
	stats.auto_tick = false
	entity.add_child(stats)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	# Health takes its maximum from Stats, which is what a real character
	# definition produces. The export is left at a value nothing should ever
	# read, so a test asserting the maximum is asserting the cross-module link
	# rather than reading back the number the fixture just set.
	health.maximum_health = 1.0
	health.stats = stats
	entity.add_child(health)

	var receiver := DamageReceiverComponent.new()
	receiver.name = "DamageReceiverComponent"
	entity.add_child(receiver)

	var effects := StatusEffectComponent.new()
	effects.name = "StatusEffectComponent"
	effects.auto_tick = false
	entity.add_child(effects)

	# Items, Inventory and Equipment.
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container(20)
	entity.add_child(inventory)

	var equipment := EquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.loadout_override = ItemFixtures.loadout()
	entity.add_child(equipment)

	# Survival.
	entity.add_child(
		SurvivalFixtures.needs_component([SurvivalFixtures.need(&"need.hunger", 1.0)])
	)

	var consumer := ConsumerComponent.new()
	consumer.name = "ConsumerComponent"
	entity.add_child(consumer)

	# Interaction.
	var interactor := InteractorComponent.new()
	interactor.name = "InteractorComponent"
	interactor.auto_tick = false
	entity.add_child(interactor)

	# Commerce and Factions.
	entity.add_child(CommerceFixtures.wallet(120.0))

	var allegiance := FactionComponent.new()
	allegiance.name = "FactionComponent"
	allegiance.faction_override = &"faction.watch"
	allegiance.actor_id = StringName(person_name.to_lower())
	allegiance.service = factions
	entity.add_child(allegiance)

	# Combat.
	var weapon := WeaponComponent.new()
	weapon.name = "WeaponComponent"
	weapon.auto_tick = false
	entity.add_child(weapon)

	var combat := CombatComponent.new()
	combat.name = "CombatComponent"
	combat.profile_override = CombatFixtures.combat_profile()
	combat.weapon = weapon
	combat.auto_tick = false
	entity.add_child(combat)

	# The two adapters that promote local signals to bus facts. They are
	# separate components precisely so an entity can be built without them.
	var health_adapter := HealthEventAdapter.new()
	health_adapter.name = "HealthEventAdapter"
	health_adapter.event_bus = bus
	entity.add_child(health_adapter)

	var inventory_adapter := InventoryEventAdapter.new()
	inventory_adapter.name = "InventoryEventAdapter"
	inventory_adapter.event_bus = bus
	entity.add_child(inventory_adapter)

	add_test_node(entity)
	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)
	return entity


## The power stat every other module's modifiers land on, plus the maximum
## health stat [HealthComponent] reads.
##
## [ItemFixtures.stats_profile] carries power alone, which leaves Health and
## Stats unconnected -- and two components on one entity that never speak to
## each other are not the composition this slice claims to be exercising.
func _stats_profile(power: float, maximum_health: float) -> StatsProfile:
	var profile := ItemFixtures.stats_profile(power)
	var health_maximum := StatDefinition.new()
	health_maximum.id = &"stat.health.max"
	health_maximum.display_name = "Maximum Health"
	health_maximum.default_base = maximum_health
	health_maximum.minimum = 0.0
	profile.stats.append(health_maximum)
	return profile


## A buff, so two modules are writing modifiers into one Stats component.
func _rage() -> StatusEffectDefinition:
	var definition := StatusEffectDefinition.new()
	definition.id = &"effect.rage"
	definition.display_name = "Rage"
	definition.duration = 30.0
	definition.modifiers = [StatModifier.flat(&"stat.power", 7.0)]
	return definition


## Puts [param quantity] of [param definition] in the bag and hands back the
## stored instance.
func _carry(entity: Node, definition: ItemDefinition, quantity: int) -> ItemInstance:
	var instance := ItemInstance.create(definition, quantity)
	assert_ok(_inventory(entity).add(instance), "The bag should take %s" % definition.id)
	return _inventory(entity).find(definition.id)


func _capability_types(entity: Node) -> Array[String]:
	var types: Array[String] = []
	for component in DefinitionBinder.collect_components(entity):
		var script_name: String = component.get_script().get_global_name()
		if not types.has(script_name):
			types.append(script_name)
	return types


func _find(entity: Node, type: Variant) -> FrameworkComponent:
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component as FrameworkComponent
	return null


func _stats(entity: Node) -> StatsComponent:
	return _find(entity, StatsComponent) as StatsComponent


func _health(entity: Node) -> HealthComponent:
	return _find(entity, HealthComponent) as HealthComponent


func _receiver(entity: Node) -> DamageReceiverComponent:
	return _find(entity, DamageReceiverComponent) as DamageReceiverComponent


func _effects(entity: Node) -> StatusEffectComponent:
	return _find(entity, StatusEffectComponent) as StatusEffectComponent


func _inventory(entity: Node) -> InventoryComponent:
	return _find(entity, InventoryComponent) as InventoryComponent


func _equipment(entity: Node) -> EquipmentComponent:
	return _find(entity, EquipmentComponent) as EquipmentComponent


func _needs(entity: Node) -> NeedsComponent:
	return _find(entity, NeedsComponent) as NeedsComponent


func _consumer(entity: Node) -> ConsumerComponent:
	return _find(entity, ConsumerComponent) as ConsumerComponent


func _interactor(entity: Node) -> InteractorComponent:
	return _find(entity, InteractorComponent) as InteractorComponent


func _wallet(entity: Node) -> WalletComponent:
	return _find(entity, WalletComponent) as WalletComponent


func _faction(entity: Node) -> FactionComponent:
	return _find(entity, FactionComponent) as FactionComponent


func _combat(entity: Node) -> CombatComponent:
	return _find(entity, CombatComponent) as CombatComponent


func _state(entity: Node) -> SemanticState:
	return _find(entity, SemanticState) as SemanticState


# --- The structural check -------------------------------------------------

## Module folder name to the id of the module living in it.
##
## Derived from the catalog's script paths rather than from the folder listing,
## so a folder that holds no module -- [code]core[/code], [code]debug[/code],
## [code]definitions[/code], [code]validation[/code] -- is never treated as one.
func _module_folders() -> Dictionary:
	if not _folders.is_empty():
		return _folders
	for id in ModuleCatalog.get_ids():
		var path := ModuleCatalog.get_script_path(id)
		_folders[_folder_of(path)] = id
	return _folders


## Every [code]class_name[/code] declared inside a module folder, mapped to
## that folder. Classes declared outside one are deliberately absent: they
## belong to Core or to a shared folder, and every module may know those.
func _class_folders() -> Dictionary:
	if not _classes.is_empty():
		return _classes
	var modules := _module_folders()
	for path in _files(ADDON_ROOT, "gd"):
		var folder := _folder_of(path)
		if not modules.has(folder):
			continue
		var declared := _declared_class(_readable(path))
		if not declared.is_empty():
			_classes[declared] = folder
	return _classes


## Every reference from a module's sources to a sibling module that the
## referring module's manifest does not declare.
func _undeclared_sibling_references() -> Array[String]:
	var modules := _module_folders()
	var offenders: Array[String] = []
	for path in _sources():
		var folder := _folder_of(path)
		if not modules.has(folder):
			continue
		for offence in _undeclared_references_in(folder, FileAccess.get_file_as_string(path)):
			offenders.append("%s: %s" % [path, offence])
	offenders.sort()
	return offenders


## The same check applied to one piece of source attributed to one module
## folder. Separated out so the check itself can be tested.
##
## Two scans, because a module can reach a sibling two ways. A class name in
## GDScript is the obvious one. A [code]res://[/code] path is the other, and it
## is the one a scene uses for every script it attaches -- so the path scan is
## what stops a [code].tscn[/code] composing an entity out of five modules
## without the manifest saying a word.
func _undeclared_references_in(folder: String, source: String) -> Array[String]:
	var modules := _module_folders()
	var classes := _class_folders()
	var declared := _declared_dependencies(modules.get(folder, &""))
	var readable := _strip(source)

	var offenders: Array[String] = []
	for declared_class in classes:
		var owner_folder: String = classes[declared_class]
		if owner_folder == folder:
			continue
		if not _mentions(readable, declared_class):
			continue
		var dependency: StringName = modules[owner_folder]
		if declared.has(dependency):
			continue
		offenders.append(
			(
				"references %s, which belongs to %s, and %s declares no such dependency"
				% [declared_class, dependency, modules.get(folder, &"?")]
			)
		)
	for referenced in _referenced_folders(source):
		if referenced == folder or not modules.has(referenced):
			continue
		var dependency: StringName = modules[referenced]
		if declared.has(dependency):
			continue
		offenders.append(
			(
				"loads a file out of %s/, which is %s, and %s declares no such dependency"
				% [referenced, dependency, modules.get(folder, &"?")]
			)
		)
	offenders.sort()
	return offenders


## Addon folders [param source] names by path, in the order first seen.
##
## Read from the raw source rather than from [method _strip]'s output, because
## every one of these paths lives inside a string literal and stripping them is
## exactly what hid this half of the problem. Whole-line comments still go: a
## doc comment quoting a path is a cross-reference like any other.
func _referenced_folders(source: String) -> Array[String]:
	if _path_pattern == null:
		# Nothing in ADDON_ROOT is a regex metacharacter, so it goes in as-is.
		_path_pattern = RegEx.create_from_string("%s/([a-z_0-9]+)/" % ADDON_ROOT)
	var found: Array[String] = []
	for hit in _path_pattern.search_all(_uncommented(source)):
		var folder := hit.get_string(1)
		if not found.has(folder):
			found.append(folder)
	return found


## Requirements and optional dependencies together: rule 36 asks for the
## relationship to be written down, not for it to be mandatory.
func _declared_dependencies(id: StringName) -> Dictionary:
	var declared: Dictionary = {}
	if id == &"":
		return declared
	var manifest := ModuleCatalog.get_manifest(id)
	if manifest == null:
		return declared
	for required in manifest.requires:
		declared[required] = true
	for optional in manifest.optional:
		declared[optional] = true
	return declared


## Whether [param source] uses [param identifier] as a whole word.
##
## The cheap containment test first because it runs a couple of hundred times
## per file; the expression only has to adjudicate the handful that hit.
func _mentions(source: String, identifier: String) -> bool:
	if not source.contains(identifier):
		return false
	var pattern: RegEx = _patterns.get(identifier)
	if pattern == null:
		pattern = RegEx.create_from_string("\\b%s\\b" % identifier)
		_patterns[identifier] = pattern
	return pattern.search(source) != null


func _declared_class(source: String) -> String:
	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("class_name "):
			return trimmed.substr("class_name ".length()).strip_edges()
	return ""


func _readable(path: String) -> String:
	return _strip(FileAccess.get_file_as_string(path))


## Source with comment lines and string literals removed.
##
## Comments go because a doc comment naming another module's class is a
## cross-reference, not an import, and this addon's documentation is full of
## them -- test_packaging.gd strips them for the same reason. String literals
## go because a class name inside an error message imports nothing either.
func _strip(source: String) -> String:
	var quoted := RegEx.create_from_string('"[^"\\n]*"')
	var kept: Array[String] = []
	for line in _uncommented(source).split("\n"):
		kept.append(quoted.sub(line, " ", true))
	return "\n".join(kept)


## Source with whole-line comments removed and string literals left alone.
##
## What the path scan reads. The class scan needs both gone; the path scan
## needs the literals kept, because a path is only ever written inside one.
func _uncommented(source: String) -> String:
	var kept: Array[String] = []
	for line in source.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		kept.append(line)
	return "\n".join(kept)


func _folder_of(path: String) -> String:
	return path.trim_prefix(ADDON_ROOT + "/").get_slice("/", 0)


## Every file the gate reads. GDScript carries the class-name references;
## scenes and resources carry the paths, and are where a module composes an
## entity out of siblings without naming one of them.
func _sources() -> Array[String]:
	var found: Array[String] = _files(ADDON_ROOT, "gd")
	found.append_array(_files(ADDON_ROOT, "tscn"))
	found.append_array(_files(ADDON_ROOT, "tres"))
	return found


func _files(directory: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	var handle := DirAccess.open(directory)
	if handle == null:
		return found
	handle.list_dir_begin()
	var entry := handle.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var path := directory.path_join(entry)
			if handle.current_is_dir():
				found.append_array(_files(path, extension))
			elif entry.get_extension() == extension:
				found.append(path)
		entry = handle.get_next()
	handle.list_dir_end()
	return found
