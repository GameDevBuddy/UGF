extends FrameworkTestCase
## Covers EntitySerializer and EntityFactory -- M1's other exit gate: entity
## state survives a round trip through a record.

const CORE_SCRIPT := "res://addons/universal_gameplay/core/framework_core.gd"
const ENTITY_SCENE := "res://tests/entities/test_entity.tscn"
const ENTITY_DIR := "res://tests/entities"

var core: Node = null
var entity: Node = null
var binder: DefinitionBinder = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "CorePersistenceTest")
	var settings := FrameworkSettings.new()
	settings.definition_paths = [ENTITY_DIR]
	core.bootstrap(settings)

	entity = (load(ENTITY_SCENE) as PackedScene).instantiate()
	add_test_node(entity)
	binder = entity.get_node("DefinitionBinder")


func _bind(id: StringName = &"entity.test_dummy") -> void:
	binder.definition_id = id
	binder.bind(core)


# --- Exit gate: round trip -----------------------------------------------

func test_entity_state_round_trips() -> void:
	_bind()
	entity.get_node("SampleComponent").set_value(77)
	entity.get_node("SemanticState").add_state(GameplayNames.STATE_CROUCHING)
	entity.global_transform = Transform3D(Basis.IDENTITY, Vector3(3, 4, 5))

	var record := EntitySerializer.capture(entity)

	var result := EntityFactory.spawn_from_record(core, record, entity.get_parent())
	assert_ok(result)
	var rebuilt: Node = result.payload["entity"]

	assert_eq(rebuilt.get_node("SampleComponent").value, 77, "Component state survived")
	assert_true(
		rebuilt.get_node("SemanticState").has_state(GameplayNames.STATE_CROUCHING),
		"Semantic state survived"
	)
	assert_eq(rebuilt.global_transform.origin, Vector3(3, 4, 5), "Transform survived")
	assert_eq(
		EntitySerializer.find_identity(rebuilt).get_persistent_id(),
		record.persistent_id,
		"Identity survived, so the entity is still the same entity"
	)


func test_record_survives_a_dictionary_round_trip() -> void:
	# The form that actually reaches a save file.
	_bind()
	entity.get_node("SampleComponent").set_value(42)
	var record := EntitySerializer.capture(entity)

	var revived := EntityRecord.from_dictionary(record.to_dictionary())

	assert_eq(revived.persistent_id, record.persistent_id)
	assert_eq(revived.definition_id, &"entity.test_dummy")
	assert_eq(revived.get_component_state(&"SampleComponent")["value"], 42)
	assert_true(revived.has_transform)
	assert_eq(revived.schema_version, FrameworkVersion.SAVE_SCHEMA)


# --- Capture --------------------------------------------------------------

func test_capture_records_the_definition_id() -> void:
	_bind()
	assert_eq(EntitySerializer.capture(entity).definition_id, &"entity.test_dummy")


func test_capture_records_the_persistent_id() -> void:
	_bind()
	assert_ne(EntitySerializer.capture(entity).persistent_id, &"")


func test_capture_includes_only_persistent_components() -> void:
	_bind()
	var record := EntitySerializer.capture(entity)
	assert_true(record.has_component_state(&"SampleComponent"))
	assert_true(record.has_component_state(&"SemanticState"))
	assert_false(
		record.has_component_state(&"PersistentIdentity"),
		"The id lives on the record, not in component state"
	)


func test_capture_of_a_null_entity_reports_rather_than_crashes() -> void:
	var issues := ValidationResult.new()
	EntitySerializer.capture(null, issues)
	assert_true(issues.has_errors())


func test_duplicate_state_keys_are_reported() -> void:
	# Two components filing under one key would clobber each other, and the
	# loss would only surface on load.
	_bind()
	var duplicate := SemanticState.new()
	duplicate.name = "SemanticState2"
	entity.add_child(duplicate)
	duplicate.state_key_override = &"SemanticState"

	var issues := ValidationResult.new()
	EntitySerializer.capture(entity, issues)
	assert_true(issues.has_errors())
	assert_eq(issues.get_errors()[0].code, &"serializer.duplicate_state_key")


func test_non_spatial_entity_records_no_transform() -> void:
	var plain := add_test_node(Node.new())
	var plain_binder := DefinitionBinder.new()
	plain_binder.bind_on_ready = false
	plain.add_child(plain_binder)
	plain_binder.bind(core)

	assert_false(EntitySerializer.capture(plain).has_transform)


# --- Restore --------------------------------------------------------------

func test_restore_into_a_live_entity() -> void:
	_bind()
	var record := EntitySerializer.capture(entity)
	record.component_state[&"SampleComponent"] = {"value": 123}

	assert_true(EntitySerializer.restore(entity, record).is_valid())
	assert_eq(entity.get_node("SampleComponent").value, 123)


func test_restore_tolerates_a_component_added_since_the_save() -> void:
	# A component that did not exist when the save was written keeps its
	# defaults. This is the normal case during development and must never be a
	# load failure.
	_bind()
	var record := EntitySerializer.capture(entity)
	record.component_state.erase(&"SampleComponent")

	var result := EntitySerializer.restore(entity, record)
	assert_true(result.is_valid(), "Missing state is not an error")
	assert_false(result.has_warnings())


func test_restore_warns_about_state_with_no_component() -> void:
	# Usually a renamed or removed component. Worth reporting, never worth
	# failing the load over.
	_bind()
	var record := EntitySerializer.capture(entity)
	record.component_state[&"ComponentThatLeft"] = {"value": 1}

	var result := EntitySerializer.restore(entity, record)
	assert_true(result.has_warnings())
	assert_false(result.has_errors())
	assert_eq(result.get_warnings()[0].code, &"serializer.orphan_state")


func test_restore_rejects_nulls() -> void:
	assert_true(EntitySerializer.restore(null, EntityRecord.new()).has_errors())
	assert_true(EntitySerializer.restore(entity, null).has_errors())


func test_is_saveable() -> void:
	_bind()
	assert_true(EntitySerializer.is_saveable(entity))
	EntitySerializer.find_identity(entity).saveable = false
	assert_false(EntitySerializer.is_saveable(entity))


func test_entity_without_identity_is_not_saveable() -> void:
	var plain := add_test_node(Node.new())
	assert_false(EntitySerializer.is_saveable(plain))


# --- Factory --------------------------------------------------------------

func test_spawn_from_a_definition_id() -> void:
	var result := EntityFactory.spawn(core, &"entity.test_dummy", entity.get_parent())
	assert_ok(result)
	var spawned: Node = result.payload
	assert_true(EntitySerializer.find_binder(spawned).is_bound())
	assert_true(spawned.get_node("SampleComponent").is_initialized())


func test_spawned_entity_gets_a_prefixed_id() -> void:
	var result := EntityFactory.spawn(core, &"entity.test_dummy", entity.get_parent())
	var spawned: Node = result.payload
	var id := EntitySerializer.find_identity(spawned).get_persistent_id()
	assert_true(str(id).begins_with("dummy."), "The definition's id_prefix was used")


func test_spawn_rejects_an_unknown_definition() -> void:
	assert_err(
		EntityFactory.spawn(core, &"entity.ghost", entity.get_parent()),
		&"factory.unresolved_definition"
	)


func test_spawn_rejects_a_non_entity_definition() -> void:
	var plain := FrameworkDefinition.new()
	plain.id = &"not.an.entity"
	plain.display_name = "Not An Entity"
	core.register_definition(plain)
	assert_err(
		EntityFactory.spawn(core, &"not.an.entity", entity.get_parent()),
		&"factory.not_an_entity"
	)


func test_spawn_rejects_a_scene_without_a_binder() -> void:
	assert_err(
		EntityFactory.spawn(core, &"entity.bare", entity.get_parent()),
		&"factory.no_binder"
	)


func test_spawn_requires_a_core() -> void:
	assert_err(EntityFactory.spawn(null, &"entity.test_dummy"), &"factory.no_core")


func test_spawn_from_record_requires_a_definition_id() -> void:
	assert_err(
		EntityFactory.spawn_from_record(core, EntityRecord.new()),
		&"factory.record_without_definition"
	)


func test_spawn_from_null_record() -> void:
	assert_err(EntityFactory.spawn_from_record(core, null), &"factory.null_record")


func test_state_key_defaults_to_the_node_name() -> void:
	var component := SemanticState.new()
	component.name = "Statuses"
	add_test_node(component)
	assert_eq(component.get_state_key(), &"Statuses")


func test_state_key_override_survives_a_rename() -> void:
	# The point of the override: the save key stops depending on the node name.
	var component := SemanticState.new()
	component.name = "Statuses"
	component.state_key_override = &"semantic_state"
	add_test_node(component)
	component.name = "RenamedLater"
	assert_eq(component.get_state_key(), &"semantic_state")
