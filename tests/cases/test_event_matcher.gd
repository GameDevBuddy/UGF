extends FrameworkTestCase
## Covers EventMatcher: the field-name indirection that lets a mission react
## to a module it does not import.

const AcquiredEvent := preload(
	"res://addons/universal_gameplay/inventory/item_acquired_event.gd"
)

var player: Node3D = null
var victim: Node3D = null


func before_each() -> void:
	player = add_test_node(Node3D.new()) as Node3D
	player.name = "Player"
	victim = add_test_node(Node3D.new()) as Node3D
	victim.name = "Bandit"


func _death(instigator: Node = null) -> ActorDiedEvent:
	var damage := DamageContext.create(10.0, instigator, instigator)
	return ActorDiedEvent.create(victim, damage)


# --- Reading fields -------------------------------------------------------

func test_a_property_is_read_by_name() -> void:
	assert_true(MissionFixtures.matcher(&"actor", victim).matches(_death()))


func test_a_zero_argument_method_is_read_by_name() -> void:
	# get_instigator is a method, not a field, and "who killed it" is the
	# commonest thing a kill objective asks.
	var check := MissionFixtures.matcher(&"get_instigator", player)
	assert_true(check.matches(_death(player)))


func test_an_unknown_field_never_matches() -> void:
	# The honest cost of naming fields with strings: a typo is content that
	# silently does nothing, not a compile error.
	assert_false(MissionFixtures.matcher(&"nonexistent", victim).matches(_death()))


func test_a_matcher_with_no_field_never_matches() -> void:
	assert_false(EventMatcher.new().matches(_death()))


func test_a_null_event_never_matches() -> void:
	assert_false(MissionFixtures.matcher(&"actor", victim).matches(null))


# --- Modes ----------------------------------------------------------------

func test_equality_crosses_string_and_stringname() -> void:
	# Content authored as "item.plank" and an event carrying &"item.plank"
	# mean the same thing.
	var event := AcquiredEvent.create(null, _plank(2), 2)
	assert_true(MissionFixtures.matcher(&"item_id", "item.plank").matches(event))
	assert_true(MissionFixtures.matcher(&"item_id", &"item.plank").matches(event))


func test_equality_crosses_int_and_float() -> void:
	var event := AcquiredEvent.create(null, _plank(3), 3)
	assert_true(MissionFixtures.matcher(&"quantity", 3.0).matches(event))


func test_not_equals() -> void:
	var event := AcquiredEvent.create(null, _plank(1), 1)
	var check := MissionFixtures.matcher(
		&"item_id", &"item.stone", EventMatcher.Mode.NOT_EQUALS
	)
	assert_true(check.matches(event))


func test_ordered_comparisons() -> void:
	var event := AcquiredEvent.create(null, _plank(5), 5)
	assert_true(
		MissionFixtures.matcher(
			&"quantity", 3, EventMatcher.Mode.GREATER_OR_EQUAL
		).matches(event)
	)
	assert_false(
		MissionFixtures.matcher(
			&"quantity", 3, EventMatcher.Mode.LESS_OR_EQUAL
		).matches(event)
	)


func test_group_membership() -> void:
	victim.add_to_group(&"enemies")
	var check := MissionFixtures.matcher(&"actor", &"enemies", EventMatcher.Mode.IN_GROUP)
	assert_true(check.matches(_death()))
	victim.remove_from_group(&"enemies")
	assert_false(check.matches(_death()))


func test_a_tag_is_found_when_the_field_is_the_tag_list() -> void:
	# "Collect any quest item" without naming one: the event carries the
	# definition's tags, and the matcher reads them directly.
	var event := AcquiredEvent.create(null, _plank(1, [&"item.quest"]), 1)
	assert_true(MissionFixtures.tagged(&"tags", &"item.quest").matches(event))
	assert_false(MissionFixtures.tagged(&"tags", &"item.junk").matches(event))


func test_a_method_that_takes_arguments_is_not_called_as_a_field() -> void:
	# has_method() says nothing about arity. Calling a one-argument method
	# with none would crash on a mistyped field rather than simply not match.
	var event := AcquiredEvent.create(null, _plank(1), 1)
	assert_false(MissionFixtures.matcher(&"has_tag", true).matches(event))


func test_a_tag_is_found_on_an_entitys_components() -> void:
	# "Kill a bandit" without the mission knowing what marks one: the tag
	# lives on a component, and the matcher walks the entity to find it.
	var mark := Perceivable.new()
	mark.name = "Perceivable"
	var tags: Array[StringName] = [&"actor.bandit"]
	mark.tags = tags
	victim.add_child(mark)
	assert_true(MissionFixtures.tagged(&"actor", &"actor.bandit").matches(_death()))
	assert_false(MissionFixtures.tagged(&"actor", &"actor.guard").matches(_death()))


func test_is_subject_matches_the_mission_owner() -> void:
	var check := MissionFixtures.by_subject(&"get_instigator")
	assert_true(check.matches(_death(player), player))
	assert_false(check.matches(_death(victim), player))
	assert_false(check.matches(_death(player), null), "no subject, no match")


func test_is_present_asks_only_whether_there_was_one() -> void:
	var check := MissionFixtures.matcher(
		&"get_instigator", null, EventMatcher.Mode.IS_PRESENT
	)
	assert_true(check.matches(_death(player)))
	assert_false(check.matches(_death(null)))


# --- Combining ------------------------------------------------------------

func test_all_matchers_must_hold() -> void:
	var matchers: Array[EventMatcher] = [
		MissionFixtures.by_subject(&"get_instigator"),
		MissionFixtures.matcher(&"actor", victim),
	]
	assert_true(EventMatcher.all_match(matchers, _death(player), player))
	assert_false(EventMatcher.all_match(matchers, _death(victim), player))


func test_empty_slots_are_skipped_rather_than_stalling_an_objective() -> void:
	var matchers: Array[EventMatcher] = [null, MissionFixtures.matcher(&"actor", victim)]
	assert_true(EventMatcher.all_match(matchers, _death(), player))


func test_no_matchers_means_any_event_of_that_name() -> void:
	var matchers: Array[EventMatcher] = []
	assert_true(EventMatcher.all_match(matchers, _death(), player))


# --- Validation and description -------------------------------------------

func test_a_matcher_with_no_field_is_a_content_error() -> void:
	assert_false(EventMatcher.new().validate().is_valid())


func test_comparing_against_nothing_is_flagged() -> void:
	assert_true(MissionFixtures.matcher(&"actor").validate().has_warnings())


func test_subject_and_presence_modes_need_no_value() -> void:
	assert_false(MissionFixtures.by_subject(&"get_instigator").validate().has_warnings())


func test_matchers_describe_themselves() -> void:
	assert_has(MissionFixtures.matcher(&"item_id", &"item.plank").describe(), "item.plank")
	assert_has(MissionFixtures.by_subject(&"get_instigator").describe(), "subject")
	assert_has(MissionFixtures.tagged(&"actor", &"actor.bandit").describe(), "actor.bandit")


func _plank(quantity: int, tags: Array = []) -> ItemInstance:
	var definition := ItemFixtures.stackable(&"item.plank", 99)
	var typed: Array[StringName] = []
	typed.assign(tags)
	definition.tags = typed
	return ItemInstance.create(definition, quantity)
