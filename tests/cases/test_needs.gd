extends FrameworkTestCase
## Covers NeedDefinition and NeedsComponent: meters that drain, the bands they
## cross on the way down, what an empty one costs, and the save/load half of
## the M12 exit gate.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var entity: Node3D = null
var needs: NeedsComponent = null
var hunger: NeedDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	hunger = SurvivalFixtures.need(&"need.hunger", 1.0)
	entity = SurvivalFixtures.survivor("Survivor", [hunger])
	add_test_node(entity)
	SurvivalFixtures.assemble(entity, core)
	needs = SurvivalFixtures.find(entity, NeedsComponent) as NeedsComponent


# --- Definition ------------------------------------------------------------

func test_a_need_reports_its_fraction() -> void:
	assert_almost_eq(hunger.get_fraction(50.0), 0.5)
	assert_almost_eq(hunger.get_fraction(-10.0), 0.0, 0.001, "clamped below")
	assert_almost_eq(hunger.get_fraction(500.0), 1.0, 0.001, "clamped above")


func test_decay_walks_downwards_towards_empty() -> void:
	assert_almost_eq(hunger.decay(100.0, 10.0), 90.0)


func test_decay_never_overshoots_its_target() -> void:
	# A long frame after a pause must not push a meter through the floor and
	# out the other side.
	assert_almost_eq(hunger.decay(5.0, 1000.0), 0.0)


func test_a_temperature_need_climbs_as_readily_as_it_falls() -> void:
	# The reason temperature is a field rather than a second class: warming up
	# is decay towards a middle, not a separate mechanism.
	var warmth := SurvivalFixtures.temperature(&"need.warmth", 50.0)
	assert_almost_eq(warmth.decay(80.0, 10.0), 70.0, 0.001, "cools towards the middle")
	assert_almost_eq(warmth.decay(20.0, 10.0), 30.0, 0.001, "warms towards the middle")
	assert_almost_eq(warmth.decay(50.0, 10.0), 50.0, 0.001, "settles there")


func test_a_temperature_need_never_overshoots_the_middle() -> void:
	var warmth := SurvivalFixtures.temperature(&"need.warmth", 50.0)
	assert_almost_eq(warmth.decay(80.0, 1000.0), 50.0)
	assert_almost_eq(warmth.decay(20.0, 1000.0), 50.0)


func test_a_need_that_is_critical_before_it_is_low_is_an_error() -> void:
	var broken := SurvivalFixtures.need(&"need.broken")
	broken.low_fraction = 0.1
	broken.critical_fraction = 0.5
	assert_true(broken.validate().has_errors())


func test_untagged_damage_is_a_warning() -> void:
	var meter := SurvivalFixtures.need(&"need.air")
	meter.damage_per_second = 5.0
	assert_true(meter.validate().has_warnings())


# --- Starting values -------------------------------------------------------

func test_needs_start_at_their_starting_value() -> void:
	assert_almost_eq(needs.get_value(&"need.hunger"), 100.0)
	assert_true(needs.has_need(&"need.hunger"))


func test_needs_come_from_the_entity_definition_when_not_overridden() -> void:
	var character := CharacterDefinition.new()
	character.id = &"character.survivor"
	var meters: Array[NeedDefinition] = [SurvivalFixtures.need(&"need.thirst")]
	character.needs = meters

	var other := Node3D.new()
	other.name = "Other"
	other.add_child(SurvivalFixtures.needs_component())
	add_test_node(other)
	SurvivalFixtures.assemble(other, core, character)

	var component := SurvivalFixtures.find(other, NeedsComponent) as NeedsComponent
	assert_true(component.has_need(&"need.thirst"))


func test_an_unknown_need_is_simply_absent() -> void:
	assert_false(needs.has_need(&"need.nonsense"))
	assert_almost_eq(needs.get_value(&"need.nonsense"), 0.0)
	needs.restore(&"need.nonsense", 50.0)
	assert_almost_eq(needs.get_value(&"need.nonsense"), 0.0)


# --- Draining --------------------------------------------------------------

func test_ticking_drains_a_need() -> void:
	needs.tick(10.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 90.0)


func test_a_need_never_drains_below_empty() -> void:
	needs.tick(1000.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 0.0)
	assert_true(needs.is_empty(&"need.hunger"))


func test_restoring_tops_a_need_up() -> void:
	needs.tick(50.0)
	needs.restore(&"need.hunger", 20.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 70.0)


func test_restoring_never_exceeds_the_maximum() -> void:
	needs.restore(&"need.hunger", 500.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 100.0)


func test_draining_is_restoring_backwards() -> void:
	needs.drain(&"need.hunger", 25.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 75.0)


func test_a_change_is_announced() -> void:
	# Counted into an Array rather than an int: a lambda captures a value type
	# by value, so an int counter would still read zero here.
	var seen: Array = []
	needs.need_changed.connect(
		func(need: StringName, value: float, _previous: float) -> void:
			seen.append([need, value])
	)
	needs.drain(&"need.hunger", 10.0)
	assert_size(seen, 1)
	assert_eq(seen[0][0], &"need.hunger")
	assert_almost_eq(seen[0][1], 90.0)


func test_a_change_that_changes_nothing_is_not_announced() -> void:
	var seen: Array = []
	needs.need_changed.connect(func(_n: StringName, _v: float, _p: float) -> void: seen.append(1))
	needs.restore(&"need.hunger", 50.0)
	assert_empty(seen, "already full")


# --- Bands -----------------------------------------------------------------

func test_crossing_into_the_low_band_is_announced_once() -> void:
	var crossings: Array = []
	needs.need_low.connect(
		func(need: StringName, low: bool) -> void: crossings.append([need, low])
	)
	needs.set_value(&"need.hunger", 25.0)
	needs.set_value(&"need.hunger", 20.0)
	assert_size(crossings, 1, "one crossing, not one per change")
	assert_true(crossings[0][1])
	assert_true(needs.is_low(&"need.hunger"))


func test_climbing_back_out_of_the_low_band_is_announced() -> void:
	needs.set_value(&"need.hunger", 20.0)
	var crossings: Array = []
	needs.need_low.connect(func(_n: StringName, low: bool) -> void: crossings.append(low))
	needs.refill(&"need.hunger")
	assert_eq(crossings, [false])
	assert_false(needs.is_low(&"need.hunger"))


func test_the_critical_band_is_separate_from_the_low_one() -> void:
	needs.set_value(&"need.hunger", 20.0)
	assert_true(needs.is_low(&"need.hunger"))
	assert_false(needs.is_critical(&"need.hunger"), "low is not yet critical")
	needs.set_value(&"need.hunger", 5.0)
	assert_true(needs.is_critical(&"need.hunger"))
	assert_has(needs.get_critical_needs(), &"need.hunger")


func test_the_bands_are_mirrored_onto_semantic_state() -> void:
	var state := SurvivalFixtures.find(entity, SemanticState) as SemanticState
	needs.set_value(&"need.hunger", 5.0)
	assert_true(state.has_state(hunger.low_state))
	assert_true(state.has_state(hunger.critical_state))
	needs.refill(&"need.hunger")
	assert_false(state.has_state(hunger.low_state))
	assert_false(state.has_state(hunger.critical_state))


func test_emptying_is_announced() -> void:
	var emptied: Array = []
	needs.need_emptied.connect(func(need: StringName) -> void: emptied.append(need))
	needs.set_value(&"need.hunger", 0.0)
	assert_eq(emptied, [&"need.hunger"])


func test_a_need_that_is_already_empty_is_not_emptied_again() -> void:
	needs.set_value(&"need.hunger", 0.0)
	var emptied: Array = []
	needs.need_emptied.connect(func(need: StringName) -> void: emptied.append(need))
	needs.tick(10.0)
	assert_empty(emptied)


# --- Consequences ----------------------------------------------------------

func test_an_empty_need_hurts_through_the_damage_pipeline() -> void:
	var oxygen := SurvivalFixtures.lethal_need(&"need.oxygen", 10.0)
	var diver := SurvivalFixtures.survivor("Diver", [oxygen])
	add_test_node(diver)
	SurvivalFixtures.assemble(diver, core)

	var meters := SurvivalFixtures.find(diver, NeedsComponent) as NeedsComponent
	var health := SurvivalFixtures.find(diver, HealthComponent) as HealthComponent
	meters.set_value(&"need.oxygen", 0.0)
	meters.tick(2.0)
	assert_almost_eq(health.get_current(), 80.0)


func test_a_need_with_no_damage_never_hurts() -> void:
	needs.set_value(&"need.hunger", 0.0)
	needs.tick(5.0)
	var health := SurvivalFixtures.find(entity, HealthComponent) as HealthComponent
	assert_almost_eq(health.get_current(), 100.0, 0.001, "a comfort meter is not lethal")


func test_empty_need_damage_passes_through_immunity() -> void:
	# It goes through the receiver rather than straight to health, so a
	# rebreather is a resistance profile and not a special case in Survival.
	var oxygen := SurvivalFixtures.lethal_need(&"need.oxygen", 10.0)
	var diver := SurvivalFixtures.survivor("Diver", [oxygen])
	# Set before assembling: the receiver resolves its profile once, at
	# initialize, and a rebreather bolted on afterwards is not one.
	var receiver := (
		SurvivalFixtures.find(diver, DamageReceiverComponent) as DamageReceiverComponent
	)
	var profile := ResistanceProfile.new()
	var immunities: Array[StringName] = [&"damage.suffocation"]
	profile.immunities = immunities
	receiver.profile_override = profile

	add_test_node(diver)
	SurvivalFixtures.assemble(diver, core)

	var meters := SurvivalFixtures.find(diver, NeedsComponent) as NeedsComponent
	var health := SurvivalFixtures.find(diver, HealthComponent) as HealthComponent
	meters.set_value(&"need.oxygen", 0.0)
	meters.tick(2.0)
	assert_almost_eq(health.get_current(), 100.0)


# --- Environment -----------------------------------------------------------

func test_a_decay_modifier_scales_the_rate() -> void:
	needs.set_decay_modifier(&"need.hunger", &"zone.cold", 2.0)
	needs.tick(10.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 80.0)


func test_two_modifiers_compose() -> void:
	needs.set_decay_modifier(&"need.hunger", &"zone.cold", 2.0)
	needs.set_decay_modifier(&"need.hunger", &"zone.wind", 3.0)
	assert_almost_eq(needs.get_decay_scale(&"need.hunger"), 6.0)


func test_the_same_source_replaces_rather_than_stacks() -> void:
	needs.set_decay_modifier(&"need.hunger", &"zone.cold", 2.0)
	needs.set_decay_modifier(&"need.hunger", &"zone.cold", 4.0)
	assert_almost_eq(needs.get_decay_scale(&"need.hunger"), 4.0)


func test_clearing_one_modifier_leaves_the_other() -> void:
	needs.set_decay_modifier(&"need.hunger", &"zone.cold", 2.0)
	needs.set_decay_modifier(&"need.hunger", &"zone.wind", 3.0)
	needs.clear_decay_modifier(&"need.hunger", &"zone.cold")
	assert_almost_eq(needs.get_decay_scale(&"need.hunger"), 3.0)


func test_the_component_scale_multiplies_the_environment() -> void:
	needs.decay_scale = 0.5
	needs.set_decay_modifier(&"need.hunger", &"zone.cold", 4.0)
	assert_almost_eq(needs.get_decay_scale(&"need.hunger"), 2.0)


func test_a_zero_scale_suspends_decay_entirely() -> void:
	needs.decay_scale = 0.0
	needs.tick(100.0)
	assert_almost_eq(needs.get_value(&"need.hunger"), 100.0)


# --- Persistence -----------------------------------------------------------

func test_needs_survive_a_save() -> void:
	needs.tick(40.0)
	var saved := needs.capture_state()

	var loaded := SurvivalFixtures.survivor("Loaded", [hunger])
	add_test_node(loaded)
	SurvivalFixtures.assemble(loaded, core)
	var restored := SurvivalFixtures.find(loaded, NeedsComponent) as NeedsComponent
	restored.restore_state(saved)

	assert_true(needs.is_persistent())
	assert_almost_eq(restored.get_value(&"need.hunger"), 60.0)


func test_a_restored_entity_is_not_topped_up_by_a_second_initialize() -> void:
	# The free-meal bug: re-initializing a loaded save would re-seed every
	# meter to full, so reloading would be the cheapest way to eat.
	needs.set_value(&"need.hunger", 12.0)
	var saved := needs.capture_state()

	var loaded := SurvivalFixtures.survivor("Loaded", [hunger])
	add_test_node(loaded)
	SurvivalFixtures.assemble(loaded, core)
	var restored := SurvivalFixtures.find(loaded, NeedsComponent) as NeedsComponent
	restored.restore_state(saved)
	SurvivalFixtures.assemble(loaded, core)

	assert_almost_eq(restored.get_value(&"need.hunger"), 12.0)


func test_restoring_a_need_the_entity_does_not_have_is_ignored() -> void:
	needs.restore_state({"needs": {"need.sanity": 3.0}})
	assert_false(needs.has_need(&"need.sanity"))
	assert_almost_eq(needs.get_value(&"need.hunger"), 100.0)


func test_a_restored_low_need_is_low_again() -> void:
	# Restoring must run the bands, or a save loaded at 5% hunger would come
	# back with no starving state and no HUD warning.
	needs.restore_state({"needs": {"need.hunger": 5.0}})
	assert_true(needs.is_critical(&"need.hunger"))
	var state := SurvivalFixtures.find(entity, SemanticState) as SemanticState
	assert_true(state.has_state(hunger.critical_state))
