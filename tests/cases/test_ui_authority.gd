extends FrameworkTestCase
## The M17 exit gate: UI contains no domain authority, and the debug
## inspectors work.
##
## [b]The structural half is the one that matters.[/b] A presenter that happens
## not to mutate today is a presenter that mutates the first time somebody adds
## a convenience method to it — and a health bar that can kill you is not a bug
## found in review, it is one found in a bug report six months later. So this
## reads every file in [code]ui/[/code] and fails on a call that would change
## the world.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"
const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"
const UI_ROOT: String = "res://addons/universal_gameplay/ui"

var core: Node = null


func before_each() -> void:
	core = make_artifact()


func make_artifact() -> Node:
	return make_autoload(CORE_SCRIPT, "FrameworkCore")


func _sources_in(directory: String) -> Dictionary:
	var found: Dictionary = {}
	var handle := DirAccess.open(directory)
	if handle == null:
		return found
	handle.list_dir_begin()
	var entry := handle.get_next()
	while entry != "":
		var path := directory.path_join(entry)
		if handle.current_is_dir():
			if not entry.begins_with("."):
				found.merge(_sources_in(path))
		elif entry.ends_with(".gd"):
			found[path] = _strip_comments(FileAccess.get_file_as_string(path))
		entry = handle.get_next()
	handle.list_dir_end()
	return found


## Comments stripped, so a doc comment explaining why a presenter must not call
## something does not fail the guard that enforces it.
func _strip_comments(source: String) -> String:
	var kept := PackedStringArray()
	for line in source.split("\n"):
		var trimmed := (line as String).strip_edges()
		if not trimmed.begins_with("#"):
			kept.append(line)
	return "\n".join(kept)


# --- No domain authority --------------------------------------------------

func test_no_presenter_can_change_the_world() -> void:
	# One entry per module that has a mutating verb. A presenter reaching for
	# any of them is a presenter with authority it must not have.
	var forbidden := [
		"apply_damage", ".kill(", ".heal(", ".revive(",
		".add(", ".remove(", ".take(", ".give(", ".transfer_to(",
		".equip(", ".unequip(",
		".craft(", ".consume(", ".harvest(",
		"set_flag", "set_counter", "set_variable", "increment(",
		"modify_reputation", "set_relation", "modify_relation",
		".report(", "add_heat", "set_heat", "clear_heat",
		".buy(", ".sell(", ".start(", ".abandon(", ".complete(",
		".choose(", ".advance(", ".stop(",
		"set_entity_region", "spawn_one", "spawn_encounter", ".despawn(",
		"restore_state", "set_throttle", "set_steering", "take_control",
	]
	var sources := _sources_in(UI_ROOT)
	assert_true(sources.size() >= 8, "expected the ui module to have sources")
	for path in sources:
		for verb in forbidden:
			assert_false(
				(sources[path] as String).contains(verb),
				"%s reaches for %s" % [(path as String).get_file(), verb]
			)


func test_a_view_model_holds_no_live_objects() -> void:
	# The type-level half of the claim: a widget handed a snapshot has nothing
	# to call. Every value in a model's dictionary form is plain data.
	var entity := _survivor()
	var presenter := _vitals(entity)
	var data := presenter.get_model().to_dictionary()
	for key in data:
		var value: Variant = data[key]
		assert_false(
			value is Object, "%s carries a live %s" % [key, type_string(typeof(value))]
		)


func test_an_inventory_model_carries_rows_rather_than_instances() -> void:
	# An ItemInstance is live state: a widget holding one can degrade it, split
	# it or change its quantity.
	var ration := SurvivalFixtures.meal(&"item.ration", [&"need.hunger"], [40.0])
	core.get_definition_registry().register(ration)

	var entity := _survivor()
	var inventory := _find(entity, InventoryComponent) as InventoryComponent
	assert_ok(inventory.add(ItemInstance.create(ration, 2)))

	var presenter := InventoryPresenter.new()
	presenter.name = "InventoryPresenter"
	presenter.inventory = inventory
	entity.add_child(presenter)
	_assemble(entity)

	var model := presenter.get_model() as InventoryViewModel
	assert_size(model.rows, 1)
	for row in model.rows:
		for key in row:
			assert_false(row[key] is Object, "row.%s carries a live object" % key
			)
	assert_eq(model.get_quantity(&"item.ration"), 2)


func test_the_ui_module_requires_nothing() -> void:
	var module: FrameworkModule = load(
		"res://addons/universal_gameplay/ui/ui_module.gd"
	).new()
	var manifest := module.get_manifest()
	assert_eq(manifest.id, GameplayNames.MODULE_UI)
	assert_empty(manifest.requires, "a presenter layer that requires nothing")


func test_no_module_depends_on_the_ui_module() -> void:
	# Presentation observes and is never observed. A module reaching for a
	# presenter would be domain code depending on a view.
	var forbidden := [
		"Presenter", "ViewModel", "HudPresenter", "VitalsPresenter",
		"InventoryPresenter", "DialoguePresenter", "MissionPresenter",
	]
	for directory in [
		"res://addons/universal_gameplay/health_damage",
		"res://addons/universal_gameplay/inventory",
		"res://addons/universal_gameplay/dialogue",
		"res://addons/universal_gameplay/missions",
		"res://addons/universal_gameplay/combat",
		"res://addons/universal_gameplay/ai",
	]:
		var sources := _sources_in(directory)
		for path in sources:
			for name in forbidden:
				assert_false(
					(sources[path] as String).contains(name),
					"%s names %s" % [(path as String).get_file(), name]
				)


# --- Presenters reflect, and only reflect ---------------------------------

func _survivor(entity_name: String = "Survivor") -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.maximum_health = 100.0
	entity.add_child(health)

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container(20)
	entity.add_child(inventory)

	entity.add_child(
		SurvivalFixtures.needs_component([SurvivalFixtures.need(&"need.hunger", 1.0)])
	)
	add_test_node(entity)
	_assemble(entity)
	return entity


func _assemble(entity: Node) -> void:
	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


func _find(entity: Node, type: Variant) -> FrameworkComponent:
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null


func _vitals(entity: Node) -> VitalsPresenter:
	var presenter := VitalsPresenter.new()
	presenter.name = "VitalsPresenter"
	entity.add_child(presenter)
	_assemble(entity)
	return presenter


func test_a_presenter_publishes_when_the_world_changes() -> void:
	var entity := _survivor()
	var presenter := _vitals(entity)
	var published: Array = []
	presenter.view_changed.connect(
		func(model: ViewModel) -> void:
			published.append((model as VitalsViewModel).health_fraction)
	)

	(_find(entity, HealthComponent) as HealthComponent).set_current(50.0)
	assert_size(published, 1)
	assert_almost_eq(published[0], 0.5)


func test_a_presenter_reflects_needs_and_health_together() -> void:
	# One model rather than two: a widget handed two snapshots taken a frame
	# apart draws a contradiction.
	var entity := _survivor()
	var presenter := _vitals(entity)
	(_find(entity, HealthComponent) as HealthComponent).set_current(25.0)
	(_find(entity, NeedsComponent) as NeedsComponent).set_value(&"need.hunger", 10.0)

	var model := presenter.get_model() as VitalsViewModel
	assert_almost_eq(model.health_fraction, 0.25)
	assert_almost_eq(model.get_need_fraction(&"need.hunger"), 0.1)
	assert_true(model.is_critical(&"need.hunger"))


func test_a_presenter_with_nothing_to_watch_says_so() -> void:
	# A HUD hides the panel rather than drawing zeroes (rule 31).
	var bare := Node3D.new()
	bare.name = "Bare"
	add_test_node(bare)
	var presenter := VitalsPresenter.new()
	presenter.name = "VitalsPresenter"
	bare.add_child(presenter)
	_assemble(bare)

	var model := presenter.get_model() as VitalsViewModel
	assert_false(model.present)
	assert_false(model.has_health)
	assert_false(model.has_needs())


func test_a_hud_redraws_once_rather_than_per_panel() -> void:
	var entity := _survivor()
	var vitals := _vitals(entity)
	var bag := InventoryPresenter.new()
	bag.name = "InventoryPresenter"
	entity.add_child(bag)

	var hud := HudPresenter.new()
	hud.name = "HudPresenter"
	var panels: Array[Presenter] = [vitals, bag]
	hud.presenters = panels
	entity.add_child(hud)
	_assemble(entity)

	var draws: Array = []
	hud.view_changed.connect(func(_model: ViewModel) -> void: draws.append(1))
	(_find(entity, HealthComponent) as HealthComponent).set_current(75.0)
	assert_size(draws, 1)

	var model := hud.get_model() as HudViewModel
	assert_eq(model.get_panel_count(), 2)
	assert_true(model.has_panel(&"VitalsPresenter"))
	assert_almost_eq(
		(model.get_panel(&"VitalsPresenter") as VitalsViewModel).health_fraction, 0.75
	)


func test_a_panel_can_be_added_and_removed_at_runtime() -> void:
	# What entering a vehicle or opening a shop does to a HUD that grows.
	var entity := _survivor()
	var hud := HudPresenter.new()
	hud.name = "HudPresenter"
	entity.add_child(hud)
	_assemble(entity)
	assert_eq((hud.get_model() as HudViewModel).get_panel_count(), 0)

	var vitals := _vitals(entity)
	assert_true(hud.add_presenter(vitals))
	assert_false(hud.add_presenter(vitals), "the same one twice")
	assert_eq((hud.get_model() as HudViewModel).get_panel_count(), 1)

	assert_true(hud.remove_presenter(vitals))
	assert_eq((hud.get_model() as HudViewModel).get_panel_count(), 0)


func test_an_inventory_panel_can_be_pointed_at_a_chest() -> void:
	var ration := SurvivalFixtures.meal(&"item.ration", [&"need.hunger"], [40.0])
	core.get_definition_registry().register(ration)

	var entity := _survivor()
	var presenter := InventoryPresenter.new()
	presenter.name = "InventoryPresenter"
	entity.add_child(presenter)
	_assemble(entity)

	var chest := Node3D.new()
	chest.name = "Chest"
	var container := InventoryComponent.new()
	container.name = "InventoryComponent"
	container.profile_override = ItemFixtures.container(5)
	chest.add_child(container)
	add_test_node(chest)
	_assemble(chest)
	assert_ok(container.add(ItemInstance.create(ration, 4)))

	presenter.show_container(container)
	assert_eq((presenter.get_model() as InventoryViewModel).get_quantity(&"item.ration"), 4)


func test_a_stale_model_can_be_recognised() -> void:
	var model := ViewModel.new()
	assert_false(model.is_stale(1000))
	model.captured_at_ms -= 5000
	assert_true(model.is_stale(1000))
