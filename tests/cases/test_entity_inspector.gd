extends FrameworkTestCase
## Covers EntityInspector. Debug tooling is a deliverable, not a nicety, so it
## gets tested like everything else -- an inspector that lies is worse than
## none, because it is trusted while debugging something else.

const CORE_SCRIPT := "res://addons/universal_gameplay/core/framework_core.gd"
const ENTITY_SCENE := "res://tests/entities/test_entity.tscn"

var core: Node = null
var entity: Node = null
var binder: DefinitionBinder = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "CoreInspectorTest")
	var settings := FrameworkSettings.new()
	settings.definition_paths = ["res://tests/entities"]
	core.bootstrap(settings)

	entity = (load(ENTITY_SCENE) as PackedScene).instantiate()
	add_test_node(entity)
	binder = entity.get_node("DefinitionBinder")


func test_reports_identity_and_definition() -> void:
	binder.definition_id = &"entity.test_dummy"
	binder.bind(core)

	var data := EntityInspector.inspect(entity)
	assert_eq(data["definition_id"], &"entity.test_dummy")
	assert_true(data["bound"])
	assert_true(data["is_entity_root"])
	assert_has(data["definition_tags"], &"entity.test")


func test_lists_every_component() -> void:
	binder.bind(core)
	var names: Array[String] = []
	for component in data_components():
		names.append(component["name"])
	assert_has(names, "SampleComponent")
	assert_has(names, "SemanticState")
	assert_has(names, "PersistentIdentity")


func data_components() -> Array:
	return EntityInspector.inspect(entity)["components"]


func test_flags_uninitialised_components() -> void:
	# Before binding, every capability is inert. Saying so is the whole value.
	for component in data_components():
		assert_false(component["initialized"], "%s is not yet initialised" % component["name"])

	binder.bind(core)
	for component in data_components():
		assert_true(component["initialized"])


func test_reports_which_components_are_saved() -> void:
	binder.bind(core)
	var persistent: Array[String] = []
	for component in data_components():
		if component["persistent"]:
			persistent.append(component["name"])
	assert_has(persistent, "SemanticState")
	assert_has_not(persistent, "PersistentIdentity", "The id is on the record, not in state")


func test_inspecting_never_mints_an_id() -> void:
	# Reading debug state must not change the thing being debugged.
	var data := EntityInspector.inspect(entity)
	assert_eq(data["persistent_id"], &"", "The id was reported as absent, not generated")
	assert_false(
		EntitySerializer.find_identity(entity).has_persistent_id(),
		"...and the entity still has none"
	)


func test_reports_semantic_state() -> void:
	binder.bind(core)
	entity.get_node("SemanticState").add_state(GameplayNames.STATE_DEAD)
	assert_has(EntityInspector.inspect(entity)["states"], GameplayNames.STATE_DEAD)


func test_reports_groups() -> void:
	entity.add_to_group(GameplayNames.GROUP_DAMAGEABLE)
	assert_has(EntityInspector.inspect(entity)["groups"], GameplayNames.GROUP_DAMAGEABLE)


func test_null_entity_is_reported_not_crashed() -> void:
	assert_has(EntityInspector.inspect(null), "error")
	assert_has(EntityInspector.describe(null), "null entity")


func test_describe_is_readable() -> void:
	binder.definition_id = &"entity.test_dummy"
	binder.bind(core)
	entity.get_node("SemanticState").add_state(GameplayNames.STATE_DEAD)

	var text := EntityInspector.describe(entity)
	assert_has(text, "TestEntity")
	assert_has(text, "entity.test_dummy")
	assert_has(text, "SampleComponent")
	assert_has(text, "state.dead")


func test_describe_flags_an_unbound_entity() -> void:
	assert_has(EntityInspector.describe(entity), "NOT BOUND")


func test_describe_names_scripts_by_class() -> void:
	binder.bind(core)
	assert_has(EntityInspector.describe(entity), "SemanticState")


func test_preview_save_state_answers_why_it_is_not_persisting() -> void:
	binder.definition_id = &"entity.test_dummy"
	binder.bind(core)
	entity.get_node("SampleComponent").set_value(31)

	var preview := EntityInspector.preview_save_state(entity)
	assert_true(preview["saveable"])
	assert_eq(preview["record"]["component_state"]["SampleComponent"]["value"], 31)
	assert_has(preview["issues"], "No validation issues")


func test_preview_surfaces_a_duplicate_state_key() -> void:
	binder.bind(core)
	var duplicate := SemanticState.new()
	duplicate.name = "Second"
	duplicate.state_key_override = &"SemanticState"
	entity.add_child(duplicate)

	assert_has(EntityInspector.preview_save_state(entity)["issues"], "duplicate_state_key")


func test_preview_reports_an_unsaveable_entity() -> void:
	binder.bind(core)
	EntitySerializer.find_identity(entity).saveable = false
	assert_false(EntityInspector.preview_save_state(entity)["saveable"])
