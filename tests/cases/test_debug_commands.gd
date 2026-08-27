extends FrameworkTestCase
## The plan's five console cheats, and the AI debug panel.
##
## [b]The cheats do not live in the console.[/b] M17 shipped a console with no
## cheats and wrote down why: a console implementing spawn item, set stat,
## start mission, change faction and enter vehicle would import five modules
## and become the one file in the framework that cannot be deleted. That
## reasoning still holds, so each cheat ships as a [DebugCommandPack] in the
## module folder it cheats at, registered by the project that wants it. The
## console still imports nothing.

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"
const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var console: DebugConsole = null
var core: Node = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	console = DebugConsole.new()
	console.name = "DebugConsole"
	add_test_node(console)


# --- The pack contract ----------------------------------------------------

func test_a_pack_registers_its_commands_and_says_how_many() -> void:
	var pack := StatsDebugCommands.new()
	var added := pack.register_into(console)
	assert_true(added > 0, "The pack registered nothing")
	assert_true(console.has_command(&"setstat"))


func test_registering_into_nothing_is_refused_rather_than_crashing() -> void:
	assert_eq(StatsDebugCommands.new().register_into(null), 0)


func test_the_console_itself_names_no_module() -> void:
	# The reason the packs exist. If this ever fails, the console has grown a
	# dependency on a feature module and rule 10 is gone.
	var source := _read_without_comments(
		"res://addons/universal_gameplay/debug/debug_console.gd"
	)
	for forbidden in [
		"InventoryComponent", "StatsComponent", "MissionService",
		"FactionService", "SeatComponent", "ItemDefinition",
	]:
		assert_false(
			source.contains(forbidden),
			"debug_console.gd names %s. The cheats belong in a pack." % forbidden
		)


func test_every_cheat_declares_that_it_mutates() -> void:
	# What lets a project ship the console in a release build with the cheats
	# off and the inspectors on.
	var packs: Array[DebugCommandPack] = [
		InventoryDebugCommands.new(),
		StatsDebugCommands.new(),
		MissionsDebugCommands.new(),
		FactionsDebugCommands.new(),
		VehiclesDebugCommands.new(),
	]
	var mutating := 0
	for pack in packs:
		for command in pack.build_commands():
			if command.mutates:
				mutating += 1
	assert_true(mutating >= 5, "Only %d commands declare mutation" % mutating)


# --- spawn item -----------------------------------------------------------

func _bag() -> InventoryComponent:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Player"
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	var profile := InventoryProfile.new()
	profile.slot_count = 20
	inventory.profile_override = profile
	entity.add_child(inventory)
	inventory.initialize(EntityContext.create(entity, null, core))
	return inventory


func _register_rock() -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.id = &"item.rock"
	definition.display_name = "Rock"
	definition.category = &"item.material"
	definition.max_stack = 99
	core.register_definition(definition)
	return definition


func test_give_puts_a_registered_item_in_the_bag() -> void:
	_register_rock()
	var inventory := _bag()
	InventoryDebugCommands.new(inventory, core).register_into(console)

	assert_ok(console.run("give item.rock 5"))

	assert_eq(inventory.count(&"item.rock"), 5)


func test_give_refuses_an_item_nobody_registered() -> void:
	# Rather than inventing one. A typo that silently creates an item existing
	# nowhere else in the game is a debug console causing the next bug.
	var inventory := _bag()
	InventoryDebugCommands.new(inventory, core).register_into(console)

	assert_err(console.run("give item.nonsense"))
	assert_true(inventory.is_empty())


func test_take_removes_what_give_added() -> void:
	_register_rock()
	var inventory := _bag()
	InventoryDebugCommands.new(inventory, core).register_into(console)

	console.run("give item.rock 5")
	assert_ok(console.run("take item.rock 2"))

	assert_eq(inventory.count(&"item.rock"), 3)


# --- set stat -------------------------------------------------------------

func _numbers() -> StatsComponent:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Fighter"
	var stats := StatsComponent.new()
	stats.name = "StatsComponent"
	stats.profile_override = ProgressionFixtures.stats_profile(&"stat.power", 10.0)
	stats.auto_tick = false
	entity.add_child(stats)
	stats.initialize(EntityContext.create(entity, null, core))
	return stats


func test_setstat_changes_the_base() -> void:
	var stats := _numbers()
	StatsDebugCommands.new(stats).register_into(console)

	assert_ok(console.run("setstat stat.power 42"))

	assert_eq(stats.get_base(&"stat.power"), 42.0)


func test_setstat_refuses_a_stat_this_entity_does_not_have() -> void:
	var stats := _numbers()
	StatsDebugCommands.new(stats).register_into(console)
	assert_err(console.run("setstat stat.charisma 5"))


func test_a_pack_with_no_target_refuses_rather_than_crashing() -> void:
	StatsDebugCommands.new().register_into(console)
	assert_err(console.run("setstat stat.power 1"))


# --- change faction -------------------------------------------------------

func test_rep_and_relation_are_kept_apart() -> void:
	# Two different things get called "faction standing" and setting the wrong
	# one and watching nothing change is the confusion this split avoids.
	var factions := FactionFixtures.service()
	add_test_node(factions)
	FactionsDebugCommands.new(factions).register_into(console)
	var ids := factions.get_faction_ids()
	assert_true(ids.size() >= 2, "The fixture needs two factions to compare")

	assert_ok(console.run("rep %s actor.player -50" % ids[0]))
	assert_eq(factions.get_reputation(ids[0], &"actor.player"), -50.0)

	assert_ok(console.run("relation %s %s -80" % [ids[0], ids[1]]))
	assert_eq(factions.get_relation(ids[0], ids[1]), -80.0)


func test_setting_a_relation_does_not_secretly_set_the_reverse() -> void:
	# Relations are directional and the console must not quietly do both.
	var factions := FactionFixtures.service()
	add_test_node(factions)
	FactionsDebugCommands.new(factions).register_into(console)
	var ids := factions.get_faction_ids()

	var before := factions.get_relation(ids[1], ids[0])
	console.run("relation %s %s -80" % [ids[0], ids[1]])

	assert_eq(factions.get_relation(ids[1], ids[0]), before, "The reverse moved")


# --- enter vehicle --------------------------------------------------------

func test_enter_goes_through_the_real_seat_path() -> void:
	# A cheat that placed the character in the seat directly would produce
	# somebody who is seated by every query and can never get out.
	var vehicle := VehicleFixtures.vehicle()
	add_test_node(vehicle)
	VehicleFixtures.assemble(vehicle)
	var seats := VehicleFixtures.seats_of(vehicle)

	var driver := add_test_node(Node3D.new()) as Node3D
	driver.name = "Driver"

	VehiclesDebugCommands.new(seats, driver).register_into(console)

	assert_ok(console.run("enter"))
	assert_true(seats.contains(driver))

	assert_ok(console.run("exit"))
	assert_false(seats.contains(driver))


# --- the AI panel ---------------------------------------------------------

func _npc() -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Guard"
	var perception := PerceptionComponent.new()
	perception.name = "PerceptionComponent"
	perception.auto_tick = false
	entity.add_child(perception)
	perception.initialize(EntityContext.create(entity, null, core))
	return entity


func _perception_of(entity: Node) -> PerceptionComponent:
	for child in entity.get_children():
		if child is PerceptionComponent:
			return child as PerceptionComponent
	return null


func test_the_panel_reports_an_entity_with_no_ai_rather_than_erroring() -> void:
	var plain := add_test_node(Node3D.new()) as Node3D
	plain.name = "Rock"
	var data := AIInspector.inspect(plain)
	assert_false(data["has_ai"])
	assert_true(AIInspector.format(plain).contains("no AI controller"))


func test_the_panel_survives_a_null_entity() -> void:
	assert_false(AIInspector.inspect(null)["has_ai"])


func test_perception_facts_are_listed() -> void:
	var guard := _npc()
	var thief := add_test_node(Node3D.new()) as Node3D
	thief.name = "Thief"
	_perception_of(guard).get_memory().hear(thief, Vector3(3.0, 0.0, 0.0))

	var facts := AIInspector.describe_facts(_perception_of(guard))

	assert_size(facts, 1)
	assert_eq(facts[0]["target"], "Thief")
	assert_true(facts[0]["heard"])


func test_an_attacker_is_listed_before_anything_merely_seen() -> void:
	# The whole value of the panel is the glance, and insertion order tells
	# you nothing at a glance.
	var guard := _npc()
	var bystander := add_test_node(Node3D.new()) as Node3D
	bystander.name = "Bystander"
	var sniper := add_test_node(Node3D.new()) as Node3D
	sniper.name = "Sniper"

	var memory := _perception_of(guard).get_memory()
	memory.see(bystander, Vector3(2.0, 0.0, 0.0), 1.0, 0.1)
	memory.damaged_by(sniper, Vector3(40.0, 0.0, 0.0), 25.0)

	var facts := AIInspector.describe_facts(_perception_of(guard))

	assert_eq(facts[0]["target"], "Sniper", "The one shooting at us comes first")
	assert_true(facts[0]["attacked_us"])


func test_the_panel_reads_and_never_writes() -> void:
	# Rule 21. A panel that could set an NPC's target would be a second owner
	# of that state, and the bug would move whenever you looked at it.
	var source := _read_without_comments(
		"res://addons/universal_gameplay/debug/ai_inspector.gd"
	)
	for forbidden in ["set_", ".add_state(", "= true", "queue_free"]:
		assert_false(
			source.contains(forbidden),
			"ai_inspector.gd contains '%s', which reads like a write." % forbidden
		)


func _read_without_comments(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var kept: Array[String] = []
	while not file.eof_reached():
		var line := file.get_line()
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	file.close()
	return "\n".join(kept)
