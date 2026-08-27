extends FrameworkTestCase
## The registry-wide content checks: broken references and dependency cycles.
##
## [b]Both primitives shipped in M0 and nothing ever called them.[/b]
## [method DefinitionValidator.check_references] and
## [method DefinitionValidator.find_cycles] existed, were correct, were tested
## in isolation, and were unreachable from [method
## DefinitionValidator.validate_registry] -- so a project running validation on
## its content got a clean report because nothing had looked. That is worse
## than having no check at all, because a clean report is believed.
##
## Core cannot know that a recipe's ingredients are item ids, so it asks:
## [method FrameworkDefinition.get_referenced_ids] and
## [method FrameworkDefinition.get_dependency_ids] are the question, and each
## definition type answers for itself (rule 1).

var registry: DefinitionRegistry = null


func before_each() -> void:
	registry = DefinitionRegistry.new()


func _item(id: StringName) -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.category = &"item.material"
	definition.scene = load("res://addons/universal_gameplay/items/item_pickup.tscn")
	return definition


func _recipe(id: StringName, ingredient: StringName, output: StringName) -> RecipeDefinition:
	var entry := RecipeIngredient.new()
	entry.item_id = ingredient
	entry.quantity = 1

	var definition := RecipeDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	var list: Array[RecipeIngredient] = [entry]
	definition.ingredients = list
	definition.output_id = output
	return definition


func _mission(id: StringName, requires: Array[StringName]) -> MissionDefinition:
	var definition := MissionDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.required_missions = requires
	return definition


func _errors_of(result: ValidationResult, code: StringName) -> int:
	var count := 0
	for issue in result.get_errors():
		if issue.code == code:
			count += 1
	return count


# --- Broken references ----------------------------------------------------

func test_a_recipe_naming_an_item_nobody_registered_is_an_error() -> void:
	registry.register(_item(&"item.plank"))
	registry.register(_recipe(&"recipe.chair", &"item.plank", &"item.chair"))

	var result := DefinitionValidator.validate_registry(registry)

	assert_eq(
		_errors_of(result, &"validator.unresolved_reference"),
		1,
		"The output item was never registered: %s" % result.format_report()
	)
	assert_true(result.format_report().contains("item.chair"))


func test_a_recipe_whose_references_all_resolve_is_clean() -> void:
	registry.register(_item(&"item.plank"))
	registry.register(_item(&"item.chair"))
	registry.register(_recipe(&"recipe.chair", &"item.plank", &"item.chair"))

	assert_eq(_errors_of(DefinitionValidator.validate_registry(registry), &"validator.unresolved_reference"), 0)


func test_a_loot_table_naming_a_renamed_item_is_an_error() -> void:
	# The failure this exists for: a corpse that drops nothing, with no error
	# anywhere, because the item was renamed three commits ago.
	registry.register(_item(&"item.coin"))
	var entry := LootEntry.new()
	entry.item_id = &"item.old_name"
	entry.minimum = 1
	entry.maximum = 1

	var table := LootTableDefinition.new()
	table.id = &"loot.bandit"
	table.display_name = "Bandit"
	var entries: Array[LootEntry] = [entry]
	table.entries = entries
	registry.register(table)

	var result := DefinitionValidator.validate_registry(registry)
	assert_eq(_errors_of(result, &"validator.unresolved_reference"), 1, result.format_report())


func test_a_crime_reporting_to_an_unregistered_faction_is_an_error() -> void:
	# The plan's "invalid faction references". Heat that accrues to a faction
	# nobody registered is heat no NPC will ever act on.
	var crime := CrimeDefinition.new()
	crime.id = &"crime.theft"
	crime.display_name = "Theft"
	crime.law_faction = &"faction.nobody"
	registry.register(crime)

	var result := DefinitionValidator.validate_registry(registry)
	assert_eq(_errors_of(result, &"validator.unresolved_reference"), 1, result.format_report())


func test_a_vendor_selling_something_that_does_not_exist_is_an_error() -> void:
	var entry := StockEntry.new()
	entry.item_id = &"item.ghost"
	entry.quantity = 1
	entry.maximum = 1

	var vendor := VendorDefinition.new()
	vendor.id = &"vendor.smith"
	vendor.display_name = "Smith"
	var stock: Array[StockEntry] = [entry]
	vendor.stock = stock
	vendor.currency = &"currency.gold"
	registry.register(vendor)

	var result := DefinitionValidator.validate_registry(registry)
	assert_true(result.format_report().contains("item.ghost"), result.format_report())


func test_a_definition_with_no_cross_references_is_asked_and_says_nothing() -> void:
	# Most definitions reference nothing, and the base returning an empty array
	# is what keeps this from being every type's problem.
	assert_empty(_item(&"item.rock").get_referenced_ids())
	assert_empty(_item(&"item.rock").get_dependency_ids())


# --- Dependency cycles ----------------------------------------------------

func test_a_mission_chain_that_loops_is_an_error() -> void:
	# Implementation Plan 28 names circular mission chains specifically. Three
	# missions each requiring the next is three missions no player can start.
	var first: Array[StringName] = [&"mission.c"]
	var second: Array[StringName] = [&"mission.a"]
	var third: Array[StringName] = [&"mission.b"]
	registry.register(_mission(&"mission.a", first))
	registry.register(_mission(&"mission.b", second))
	registry.register(_mission(&"mission.c", third))

	var result := DefinitionValidator.validate_registry(registry)

	assert_true(
		_errors_of(result, &"validator.dependency_cycle") > 0,
		"No cycle reported: %s" % result.format_report()
	)


func test_a_mission_chain_that_does_not_loop_is_clean() -> void:
	var none: Array[StringName] = []
	var after_a: Array[StringName] = [&"mission.a"]
	var after_b: Array[StringName] = [&"mission.b"]
	registry.register(_mission(&"mission.a", none))
	registry.register(_mission(&"mission.b", after_a))
	registry.register(_mission(&"mission.c", after_b))

	var result := DefinitionValidator.validate_registry(registry)
	assert_eq(_errors_of(result, &"validator.dependency_cycle"), 0, result.format_report())


func test_a_loot_table_that_rolls_itself_is_an_error() -> void:
	var table := LootTableDefinition.new()
	table.id = &"loot.recursive"
	table.display_name = "Recursive"
	var subs: Array[StringName] = [&"loot.recursive"]
	table.sub_tables = subs
	registry.register(table)

	var result := DefinitionValidator.validate_registry(registry)
	assert_true(_errors_of(result, &"validator.dependency_cycle") > 0, result.format_report())


func test_a_dependency_on_something_unregistered_is_reported_once() -> void:
	# It is a broken reference, not a cycle. Counting it as both would report
	# one content bug twice under two different names.
	var missing: Array[StringName] = [&"mission.gone"]
	registry.register(_mission(&"mission.a", missing))

	var result := DefinitionValidator.validate_registry(registry)

	assert_eq(_errors_of(result, &"validator.dependency_cycle"), 0)


func test_a_skill_prerequisite_loop_is_an_error() -> void:
	var first := SkillDefinition.new()
	first.id = &"skill.a"
	first.display_name = "A"
	first.track_id = &"track.x"
	var needs_b: Array[StringName] = [&"skill.b"]
	first.requires_skills = needs_b

	var second := SkillDefinition.new()
	second.id = &"skill.b"
	second.display_name = "B"
	second.track_id = &"track.x"
	var needs_a: Array[StringName] = [&"skill.a"]
	second.requires_skills = needs_a

	registry.register(first)
	registry.register(second)

	var result := DefinitionValidator.validate_registry(registry)
	assert_true(_errors_of(result, &"validator.dependency_cycle") > 0, result.format_report())
