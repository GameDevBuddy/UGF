extends FrameworkTestCase
## Covers InteractionDefinition: prompt fallbacks and the validation that
## catches content nobody could ever use.


func test_prompt_prefers_the_authored_line() -> void:
	var definition := InteractionFixtures.definition(&"interaction.open", &"verb.open", "Open Door")
	assert_eq(definition.get_prompt(), "Open Door")


func test_prompt_falls_back_to_display_name() -> void:
	var definition := InteractionDefinition.new()
	definition.id = &"interaction.open"
	definition.display_name = "Open"
	assert_eq(definition.get_prompt(), "Open")


func test_prompt_falls_back_to_the_verb() -> void:
	var definition := InteractionDefinition.new()
	definition.id = &"interaction.open"
	definition.verb = &"verb.open"
	assert_eq(definition.get_prompt(), "verb.open")


func test_instant_interactions_are_not_timed() -> void:
	var definition := InteractionFixtures.definition()
	assert_false(definition.is_timed())
	assert_false(definition.has_cooldown())


func test_a_duration_makes_it_timed() -> void:
	assert_true(InteractionFixtures.timed(2.0).is_timed())


func test_missing_prompt_is_a_warning_not_an_error() -> void:
	var definition := InteractionDefinition.new()
	definition.id = &"interaction.silent"
	var result := definition.validate()
	assert_true(result.is_valid())
	assert_true(result.has_warnings())


func test_negative_duration_is_an_error() -> void:
	var definition := InteractionFixtures.definition()
	definition.duration = -1.0
	assert_false(definition.validate().is_valid())


func test_negative_cooldown_is_an_error() -> void:
	var definition := InteractionFixtures.definition()
	definition.cooldown = -1.0
	assert_false(definition.validate().is_valid())


func test_a_cooldown_on_a_one_shot_is_flagged() -> void:
	var definition := InteractionFixtures.definition()
	definition.repeatable = false
	definition.cooldown = 5.0
	var result := definition.validate()
	assert_true(result.is_valid())
	assert_true(result.has_warnings())


func test_an_empty_requirement_slot_is_flagged() -> void:
	var definition := InteractionFixtures.definition()
	var requirements: Array[InteractionRequirement] = [null]
	definition.requirements = requirements
	assert_true(definition.validate().has_warnings())


func test_requirement_problems_surface_through_the_interaction() -> void:
	var definition := InteractionFixtures.definition()
	var broken := ItemRequirement.new()
	var requirements: Array[InteractionRequirement] = [broken]
	definition.requirements = requirements
	assert_false(definition.validate().is_valid())


func test_action_problems_surface_through_the_interaction() -> void:
	var definition := InteractionFixtures.definition()
	definition.action = ToggleStateAction.new()
	assert_false(definition.validate().is_valid())


func test_a_complete_interaction_validates_clean() -> void:
	var definition := InteractionFixtures.door()
	var result := definition.validate()
	assert_true(result.is_valid())
	assert_false(result.has_warnings())
