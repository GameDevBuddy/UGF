extends FrameworkTestCase
## Covers DefinitionBinder, including M1's exit gate: an entity can bind a
## definition and its capabilities come up configured.

const CORE_SCRIPT := "res://addons/universal_gameplay/core/framework_core.gd"
const ENTITY_SCENE := "res://tests/entities/test_entity.tscn"
const NESTED_SCENE := "res://tests/entities/nested_entity.tscn"
const SampleComponent := preload("res://tests/support/sample_component.gd")

var entity: Node = null
var binder: DefinitionBinder = null


func before_each() -> void:
	entity = (load(ENTITY_SCENE) as PackedScene).instantiate()
	add_test_node(entity)
	binder = entity.get_node("DefinitionBinder")


func _definition(id: StringName, tags: Array[StringName] = []) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.tags = tags.duplicate()
	return definition


# --- Exit gate ------------------------------------------------------------

func test_entity_binds_a_definition() -> void:
	binder.definition = _definition(&"character.guard")
	assert_ok(binder.bind())
	assert_true(binder.is_bound())
	assert_eq(binder.get_definition().id, &"character.guard")


func test_binding_initialises_every_capability() -> void:
	binder.definition = _definition(&"character.guard")
	binder.bind()
	for component in DefinitionBinder.collect_components(entity):
		assert_true(component.is_initialized(), "%s was initialised" % component.name)


func test_capabilities_are_configured_from_definition_data() -> void:
	# The whole point of the data layer: an "elite" variant is a different
	# .tres, not a different class.
	binder.definition = _definition(&"character.elite", [&"sample.boosted"])
	binder.bind()
	assert_eq(entity.get_node("SampleComponent").value, 100)


func test_plain_definition_leaves_defaults() -> void:
	binder.definition = _definition(&"character.plain")
	binder.bind()
	assert_eq(entity.get_node("SampleComponent").value, 0)


# --- Context --------------------------------------------------------------

func test_context_carries_entity_definition_and_id() -> void:
	binder.definition = _definition(&"character.guard")
	binder.bind()
	var context := binder.get_context()
	assert_eq(context.entity, entity)
	assert_eq(context.definition.id, &"character.guard")
	assert_ne(context.persistent_id, &"", "The id was resolved back into the context")


func test_components_share_one_context() -> void:
	binder.definition = _definition(&"character.guard")
	binder.bind()
	var sample := entity.get_node("SampleComponent")
	assert_eq(sample.get_context(), binder.get_context())
	assert_eq(sample.get_entity(), entity)


func test_context_persistent_id_matches_the_identity_component() -> void:
	# The two-step context build has to end with these agreeing.
	binder.bind()
	var identity: PersistentIdentity = entity.get_node("PersistentIdentity")
	assert_eq(binder.get_context().persistent_id, identity.get_persistent_id())


# --- Resolution -----------------------------------------------------------

func test_definition_resolves_by_id_from_the_registry() -> void:
	# The normal case for spawned content: the scene carries an id, not a hard
	# resource reference.
	var core := make_autoload(CORE_SCRIPT, "CoreBinderTest")
	core.bootstrap()
	core.register_definition(_definition(&"character.guard"))

	binder.definition_id = &"character.guard"
	assert_ok(binder.bind(core))
	assert_eq(binder.get_definition().id, &"character.guard")


func test_unresolved_definition_id_fails_without_binding() -> void:
	var core := make_autoload(CORE_SCRIPT, "CoreBinderMissTest")
	core.bootstrap()
	binder.definition_id = &"character.ghost"
	assert_err(binder.bind(core), &"binder.unresolved_definition")
	assert_false(binder.is_bound(), "A failed bind leaves the entity unbound")


func test_binder_falls_back_to_the_core_autoload() -> void:
	# The single place the framework reaches for a global, and it has to work:
	# authored content dropped into a level is not handed a core by hand. The
	# unresolved-definition failure proves it found the autoload and asked it.
	binder.definition_id = &"character.ghost"
	assert_err(binder.bind(), &"binder.unresolved_definition")


func test_definition_id_without_any_core_fails_clearly() -> void:
	# Outside the tree there is no autoload to fall back to, so the binder has
	# to say so rather than quietly binding a null definition.
	var detached := Node.new()
	var detached_binder := DefinitionBinder.new()
	detached_binder.bind_on_ready = false
	detached.add_child(detached_binder)
	detached_binder.definition_id = &"character.guard"

	assert_err(detached_binder.bind(), &"binder.no_registry")
	assert_false(detached_binder.is_bound())
	detached.free()


func test_an_entity_needs_no_definition() -> void:
	# A scene-authored prop configured in the inspector has no content behind
	# it, and that is a legitimate entity.
	assert_ok(binder.bind())
	assert_true(binder.is_bound())
	assert_null(binder.get_definition())


func test_explicit_definition_beats_definition_id() -> void:
	binder.definition = _definition(&"character.explicit")
	binder.definition_id = &"character.ignored"
	binder.bind()
	assert_eq(binder.get_definition().id, &"character.explicit")


func test_binding_twice_is_refused() -> void:
	binder.bind()
	assert_err(binder.bind(), &"binder.already_bound")


func test_binder_without_a_parent_fails() -> void:
	# Never parented, so there is nothing for it to bind.
	var orphan := DefinitionBinder.new()
	orphan.bind_on_ready = false
	assert_err(orphan.bind(), &"binder.no_entity_root")
	orphan.free()


func test_bound_signal_carries_the_context() -> void:
	var seen: Array = []
	binder.bound.connect(func(context: EntityContext) -> void: seen.append(context))
	binder.bind()
	assert_size(seen, 1)
	assert_eq(seen[0], binder.get_context())


# --- Nested entities ------------------------------------------------------

func test_collect_stops_at_a_nested_entity() -> void:
	# A character seated in a vehicle binds its own components. Descending into
	# it would initialise them with the wrong entity's context.
	var outer := (load(NESTED_SCENE) as PackedScene).instantiate()
	add_test_node(outer)

	var names: Array[String] = []
	for component in DefinitionBinder.collect_components(outer):
		names.append(component.name)

	assert_has(names, "OuterComponent")
	assert_has_not(names, "InnerComponent", "The nested entity's component was left alone")


func test_nested_entity_binds_independently() -> void:
	var outer := (load(NESTED_SCENE) as PackedScene).instantiate()
	add_test_node(outer)
	var inner := outer.get_node("InnerEntity")

	outer.get_node("DefinitionBinder").bind()

	assert_true(outer.get_node("OuterComponent").is_initialized())
	assert_false(
		inner.get_node("InnerComponent").is_initialized(),
		"The inner entity is still waiting for its own binder"
	)

	inner.get_node("DefinitionBinder").bind()
	assert_true(inner.get_node("InnerComponent").is_initialized())


func test_is_entity_root() -> void:
	assert_true(DefinitionBinder.is_entity_root(entity))
	assert_false(DefinitionBinder.is_entity_root(entity.get_node("SampleComponent")))


func test_binder_finds_the_identity_component() -> void:
	assert_not_null(binder.get_persistent_identity())
