extends FrameworkTestCase
## The other half of the M17 exit gate: debug event and entity inspectors
## operational.
##
## Debugability is architecture (Implementation Plan 28). A framework whose
## modules deliberately do not know about each other is one where "why did
## nothing happen when I killed him?" is genuinely hard to answer — the answer
## is always a fact that was or was not published, and these are the tools that
## show it.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"

var core: Node = null
var bus: Node = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	bus = make_autoload(BUS_SCRIPT, "EventBus")


func _monitor(capacity: int = 100) -> EventMonitor:
	var monitor := EventMonitor.new()
	monitor.name = "EventMonitor"
	monitor.event_bus = bus
	monitor.capacity = capacity
	add_test_node(monitor)
	return monitor


## Publishes a real crime event through the module's own factory, rather than
## poking a hand-built one. The monitor is being tested on what the game
## actually puts on the bus.
func _publish_crime(actor: StringName = &"thief") -> void:
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var context := CrimeContext.new()
	context.actor_id = actor
	context.definition = CrimeFixtures.crime(&"crime.theft", 20.0, 5.0)
	context.law_faction = &"faction.police"
	var event: FrameworkEvent = CrimeEventAdapter.CrimeEvent.witnessed(context)
	bus.publish(event)


# --- The event monitor ----------------------------------------------------

func test_the_monitor_records_what_crosses_the_bus() -> void:
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var monitor := _monitor()
	monitor.rescan()

	_publish_crime()
	assert_eq(monitor.get_entry_count(), 1)
	assert_true(monitor.has_seen(GameplayNames.EVENT_CRIME_WITNESSED))
	assert_eq(monitor.get_last()["event"], GameplayNames.EVENT_CRIME_WITNESSED)


func test_the_monitor_summarises_an_event_without_knowing_its_type() -> void:
	# A monitor that knew what a CrimeEvent was would need editing every time
	# a module added a fact.
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var monitor := _monitor()
	monitor.rescan()
	_publish_crime(&"burglar")

	var summary: String = monitor.get_last()["summary"]
	assert_true(summary.contains("burglar"), "got '%s'" % summary)
	assert_true(summary.contains("crime.theft"), "got '%s'" % summary)


func test_the_summary_skips_fields_nobody_set() -> void:
	# An event with twelve fields and two set should print two.
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var monitor := _monitor()
	monitor.rescan()
	_publish_crime()

	var summary: String = monitor.get_last()["summary"]
	assert_false(summary.contains("wanted_state"), "blank fields are noise")
	assert_false(summary.contains("witness_count"), "and so are zeroes")


func test_the_monitor_counts_by_event_name() -> void:
	# The first thing worth looking at: a fact published a thousand times and
	# one published never are two very different bugs.
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var monitor := _monitor()
	monitor.rescan()
	for index in 3:
		_publish_crime()

	assert_eq(monitor.get_count(GameplayNames.EVENT_CRIME_WITNESSED), 3)
	assert_eq(monitor.get_count(GameplayNames.EVENT_ACTOR_DIED), 0)
	assert_false(monitor.has_seen(GameplayNames.EVENT_ACTOR_DIED))


func test_the_ring_buffer_keeps_the_newest() -> void:
	# Leaving it running costs a fixed amount of memory, not an increasing one.
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var monitor := _monitor(3)
	monitor.rescan()
	for index in 10:
		_publish_crime(StringName("thief_%d" % index))

	assert_eq(monitor.get_entry_count(), 3)
	assert_true((monitor.get_last()["summary"] as String).contains("thief_9"))
	assert_eq(
		monitor.get_count(GameplayNames.EVENT_CRIME_WITNESSED), 10,
		"and the counts remember everything the buffer dropped"
	)


func test_a_capacity_of_one_keeps_the_newest_rather_than_refusing_it() -> void:
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var monitor := _monitor(1)
	monitor.rescan()
	_publish_crime(&"first")
	_publish_crime(&"second")
	assert_eq(monitor.get_entry_count(), 1)
	assert_true((monitor.get_last()["summary"] as String).contains("second"))


func test_the_monitor_can_be_filtered() -> void:
	# What silences a chatty event while watching for something rare.
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	bus.register_event(GameplayNames.EVENT_ITEM_ACQUIRED)
	var monitor := _monitor()
	var ignored: Array[StringName] = [GameplayNames.EVENT_CRIME_WITNESSED]
	monitor.ignore_events = ignored
	monitor.rescan()

	_publish_crime()
	assert_eq(monitor.get_entry_count(), 0)
	assert_has_not(monitor.get_watched_events(), GameplayNames.EVENT_CRIME_WITNESSED)


func test_recording_can_be_paused() -> void:
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var monitor := _monitor()
	monitor.rescan()
	monitor.recording = false
	_publish_crime()
	assert_eq(monitor.get_entry_count(), 0)

	monitor.recording = true
	_publish_crime()
	assert_eq(monitor.get_entry_count(), 1)


func test_rescanning_picks_up_events_registered_later() -> void:
	# A module installed after the monitor registers its own event names, and
	# without a rescan the monitor would silently never see them.
	var monitor := _monitor()
	assert_empty(monitor.get_watched_events())

	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	monitor.rescan()
	assert_has(monitor.get_watched_events(), GameplayNames.EVENT_CRIME_WITNESSED)
	_publish_crime()
	assert_eq(monitor.get_entry_count(), 1)


func test_the_feed_can_be_searched_and_cleared() -> void:
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	bus.register_event(GameplayNames.EVENT_ITEM_ACQUIRED)
	var monitor := _monitor()
	monitor.rescan()
	_publish_crime()

	assert_size(monitor.find_entries(GameplayNames.EVENT_CRIME_WITNESSED), 1)
	assert_empty(monitor.find_entries(GameplayNames.EVENT_ITEM_ACQUIRED))
	monitor.clear()
	assert_eq(monitor.get_entry_count(), 0)


func test_the_feed_renders_as_text() -> void:
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var monitor := _monitor()
	monitor.rescan()
	_publish_crime()
	assert_true(monitor.describe().contains("crime_witnessed"))


func test_an_unloaded_monitor_stops_listening() -> void:
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var monitor := _monitor()
	monitor.rescan()
	monitor.get_parent().remove_child(monitor)
	monitor.free()
	_publish_crime()
	assert_true(true, "publishing after the monitor is gone does not crash")


# --- The entity inspector -------------------------------------------------

func _survivor() -> Node3D:
	var entity := Node3D.new()
	entity.name = "Survivor"

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = &"survivor"
	entity.add_child(identity)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	entity.add_child(health)

	add_test_node(entity)
	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)
	return entity


func test_the_entity_inspector_reports_what_an_entity_is() -> void:
	var entity := _survivor()
	var data := EntityInspector.inspect(entity)
	assert_eq(data["name"], "Survivor")
	assert_eq(data["persistent_id"], &"survivor")
	assert_true(data.has("components"))


func test_the_entity_inspector_renders_as_text() -> void:
	var described := EntityInspector.describe(_survivor())
	assert_true(described.contains("Survivor"))
	assert_true(described.length() > 0)


func test_inspecting_nothing_is_answered_rather_than_crashing() -> void:
	assert_true(EntityInspector.inspect(null).has("error"))


func test_inspecting_never_mints_an_id_the_entity_did_not_have() -> void:
	# Observing must not change what is observed, and get_persistent_id()
	# generates one lazily.
	var entity := Node3D.new()
	entity.name = "Anonymous"
	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	entity.add_child(identity)
	add_test_node(entity)

	EntityInspector.inspect(entity)
	assert_eq(identity.persistent_id, &"", "the stored value is untouched")


# --- The service inspector ------------------------------------------------

func test_the_service_inspector_reports_factions_directionally() -> void:
	# A matrix that folded the two directions would hide exactly the asymmetry
	# somebody opened the panel to find.
	var factions := CrimeFixtures.factions()
	add_test_node(factions)
	factions.set_relation(&"faction.police", &"faction.thieves", -80.0)

	var data := ServiceInspector.factions(factions)
	var matrix: Dictionary = data["relations"]
	assert_almost_eq(matrix["faction.police"]["faction.thieves"], -80.0)
	assert_almost_eq(
		matrix["faction.thieves"]["faction.police"], 0.0,
		0.001, "and the other direction is its own number"
	)


func test_the_service_inspector_reports_wanted_actors() -> void:
	var heat := CrimeFixtures.heat_service()
	add_test_node(heat)
	heat.add_heat(&"thief", &"faction.police", 60.0)

	var data := ServiceInspector.heat(heat)
	assert_size(data["tracked"], 1)
	assert_eq(data["tracked"][0]["actor"], &"thief")
	assert_has(data["tracked"][0]["wanted_by"], &"faction.police")


func test_the_service_inspector_reports_region_budgets() -> void:
	var world := WorldFixtures.world([
		WorldFixtures.region(&"region.docks", [&"region.urban"], {&"population.ambient": 5})
	])
	add_test_node(world)
	var body := Node3D.new()
	body.name = "Pedestrian"
	add_test_node(body)
	world.set_entity_region(body, &"region.docks", &"population.ambient")

	var data := ServiceInspector.world(world)
	assert_size(data["regions"], 1)
	var region: Dictionary = data["regions"][0]
	assert_eq(region["population"], 1)
	assert_eq(region["budgets"]["population.ambient"]["used"], 1)
	assert_eq(region["budgets"]["population.ambient"]["limit"], 5)


func test_the_service_inspector_reports_save_slots() -> void:
	var saves := SaveService.new()
	saves.name = "SaveService"
	add_test_node(saves)
	saves.configure(SaveBackend.new(), core)
	assert_ok(saves.save(&"slot_1", "First"))

	var data := ServiceInspector.saves(saves)
	assert_size(data["slots"], 1)
	assert_eq(data["slots"][0]["label"], "First")


func test_a_missing_service_is_answered_rather_than_crashing() -> void:
	for answer in [
		ServiceInspector.missions(null),
		ServiceInspector.factions(null),
		ServiceInspector.heat(null),
		ServiceInspector.world(null),
		ServiceInspector.spawning(null),
		ServiceInspector.saves(null),
	]:
		assert_true(answer.has("error"))


func test_inspecting_a_core_reports_only_what_is_installed() -> void:
	# A core with two modules reports two sections rather than six errors.
	var factions := CrimeFixtures.factions()
	add_test_node(factions)
	core.register_service(GameplayNames.SERVICE_FACTION, factions)

	var data := ServiceInspector.inspect_core(core)
	assert_true(data.has("factions"))
	assert_false(data.has("missions"), "not installed, so not reported")
	assert_true(ServiceInspector.describe_core(core).contains("factions"))


func test_inspecting_no_core_is_answered() -> void:
	assert_true(ServiceInspector.inspect_core(null).has("error"))


func test_the_debug_tools_name_no_module() -> void:
	# Four panels over four modules would make debug/ the one thing in the
	# framework that cannot be deleted.
	var forbidden := [
		"MissionService", "FactionService", "HeatService", "WorldStateService",
		"SpawnService", "SaveService", "InventoryComponent",
	]
	var handle := DirAccess.open("res://addons/universal_gameplay/debug")
	assert_not_null(handle)
	handle.list_dir_begin()
	var entry := handle.get_next()
	var checked := 0
	while entry != "":
		if entry.ends_with(".gd"):
			checked += 1
			# Comments stripped: this is about what the code does, and a doc
			# comment saying "works with a MissionService and equally with a
			# project's own" is the explanation, not a dependency.
			var code := _strip_comments(
				FileAccess.get_file_as_string(
					"res://addons/universal_gameplay/debug".path_join(entry)
				)
			)
			for name in forbidden:
				assert_false(code.contains(name), "%s names %s" % [entry, name])
		entry = handle.get_next()
	handle.list_dir_end()
	assert_true(checked >= 4, "expected the debug tools to have sources")


# --- The console ----------------------------------------------------------

func _console() -> DebugConsole:
	var console := DebugConsole.new()
	console.name = "DebugConsole"
	add_test_node(console)
	return console


func test_the_console_ships_read_only_commands() -> void:
	var console := _console()
	for name in [&"help", &"commands", &"inspect", &"events"]:
		assert_true(console.has_command(name))
		assert_false(
			console.get_command(name).mutates, "%s should not change the world" % name
		)


func test_the_console_runs_a_command() -> void:
	var console := _console()
	var answer := console.run("commands")
	assert_ok(answer)
	assert_true((answer.payload as String).contains("help"))


func test_an_unknown_command_is_refused_and_announced() -> void:
	var console := _console()
	var unknown: Array = []
	console.command_unknown.connect(func(name: StringName) -> void: unknown.append(name))
	assert_err(console.run("nonsense"), &"console.unknown")
	assert_eq(unknown, [&"nonsense"])


func test_an_empty_line_runs_nothing() -> void:
	assert_err(_console().run("   "), &"console.empty")


func test_a_project_registers_its_own_commands() -> void:
	# The console knows names and callables; the cheats are a project's.
	var console := _console()
	var called: Array = []
	assert_ok(
		console.add(
			&"give",
			func(arguments: PackedStringArray) -> FrameworkResult:
				called.append(arguments)
				return FrameworkResult.ok("gave %s" % arguments[0]),
			"Gives an item.", "<item_id>", true
		)
	)
	var answer := console.run("give item.sword")
	assert_ok(answer)
	assert_eq(answer.payload, "gave item.sword")
	assert_eq(called[0][0], "item.sword")


func test_a_duplicate_command_is_refused() -> void:
	var console := _console()
	assert_err(
		console.add(&"help", func(_a: PackedStringArray) -> void: pass),
		&"console.duplicate"
	)


func test_a_command_with_no_handler_is_refused() -> void:
	assert_err(_console().register(DebugCommand.new()), &"console.invalid_command")


func test_mutating_commands_can_be_switched_off_for_a_release_build() -> void:
	# The inspectors stay, the cheats go. That is why mutation is declared
	# rather than inferred.
	var console := _console()
	console.add(
		&"give", func(_a: PackedStringArray) -> FrameworkResult:
			return FrameworkResult.ok("gave"),
		"", "", true
	)
	console.allow_mutation = false
	assert_err(console.run("give item.sword"), &"console.mutation_disabled")
	assert_ok(console.run("commands"), "and the read-only ones still work")


func test_quoted_arguments_survive_the_parser() -> void:
	# "start mission" is one argument, and a console that could not say so
	# would be one nobody used twice.
	var parts := DebugConsole.parse('say "hello there" world')
	assert_eq(parts.size(), 3)
	assert_eq(parts[1], "hello there")
	assert_eq(parts[2], "world")


func test_the_parser_collapses_extra_spaces() -> void:
	var parts := DebugConsole.parse("  give   item.sword   2  ")
	assert_eq(parts.size(), 3)
	assert_eq(parts[0], "give")
	assert_eq(parts[2], "2")


func test_help_explains_one_command() -> void:
	var console := _console()
	var answer := console.run("help inspect")
	assert_ok(answer)
	assert_true((answer.payload as String).contains("inspect"))
	assert_err(console.run("help nonsense"), &"console.unknown")


func test_the_console_inspects_an_entity() -> void:
	var console := _console()
	console.inspect_target = _survivor()
	var answer := console.run("inspect")
	assert_ok(answer)
	assert_true((answer.payload as String).contains("Survivor"))


func test_inspecting_with_no_target_is_refused() -> void:
	assert_err(_console().run("inspect"), &"console.no_target")


func test_the_console_reads_the_event_feed() -> void:
	bus.register_event(GameplayNames.EVENT_CRIME_WITNESSED)
	var monitor := _monitor()
	monitor.rescan()
	_publish_crime()

	var console := _console()
	console.monitor = monitor
	var answer := console.run("events 5")
	assert_ok(answer)
	assert_true((answer.payload as String).contains("crime_witnessed"))


func test_reading_the_feed_with_no_monitor_is_refused() -> void:
	assert_err(_console().run("events"), &"console.no_monitor")


func test_the_console_keeps_a_history() -> void:
	var console := _console()
	console.run("commands")
	console.run("nonsense")
	assert_eq(console.get_history().size(), 2)
	console.clear_history()
	assert_eq(console.get_history().size(), 0)


func test_every_run_is_announced_with_its_result() -> void:
	var console := _console()
	var runs: Array = []
	console.command_run.connect(
		func(line: String, result: FrameworkResult) -> void:
			runs.append([line, result.is_ok()])
	)
	console.run("commands")
	console.run("nonsense")
	assert_eq(runs, [["commands", true], ["nonsense", false]])


func _strip_comments(source: String) -> String:
	var kept := PackedStringArray()
	for line in source.split("\n"):
		var trimmed := (line as String).strip_edges()
		if not trimmed.begins_with("#"):
			kept.append(line)
	return "\n".join(kept)
