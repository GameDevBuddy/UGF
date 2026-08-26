extends FrameworkTestCase
## Covers FrameworkComponent, including the save capture/restore contract and
## the deliberate absence of any EventBus dependency.

const SampleComponent := preload("res://tests/support/sample_component.gd")
const SampleDefinition := preload("res://tests/support/sample_definition.gd")

var entity: Node = null
var component: FrameworkComponent = null


func before_each() -> void:
	entity = add_test_node(Node.new())
	component = SampleComponent.new()
	entity.add_child(component)


func test_uninitialised_component_is_inert() -> void:
	assert_false(component.is_initialized())
	assert_null(component.get_context())
	assert_null(component.get_entity())
	assert_null(component.get_definition())


func test_initialize_binds_the_context() -> void:
	component.initialize(EntityContext.create(entity))
	assert_true(component.is_initialized())
	assert_eq(component.get_entity(), entity)


func test_initialize_emits() -> void:
	var fired := [false]
	component.initialized.connect(func() -> void: fired[0] = true)
	component.initialize(EntityContext.create(entity))
	assert_true(fired[0])


func test_component_reads_its_definition() -> void:
	# Configuration comes from data, not from a subclass per variant.
	var definition := SampleDefinition.new()
	definition.id = &"character.elite"
	definition.tags = [&"sample.boosted"]
	component.initialize(EntityContext.create(entity, definition))

	assert_eq(component.value, 100)
	assert_eq(component.get_definition().id, &"character.elite")


func test_component_without_a_definition_uses_defaults() -> void:
	component.initialize(EntityContext.create(entity))
	assert_eq(component.value, 0)


func test_local_signal_on_state_change() -> void:
	# Rule 7: local changes are local signals. Promoting one to a cross-feature
	# fact is a decision made above the component, not inside it.
	var seen: Array[int] = []
	component.value_changed.connect(func(v: int) -> void: seen.append(v))
	component.set_value(5)
	assert_eq(seen, [5] as Array[int])


func test_no_signal_when_value_is_unchanged() -> void:
	component.set_value(5)
	var seen: Array[int] = []
	component.value_changed.connect(func(v: int) -> void: seen.append(v))
	component.set_value(5)
	assert_empty(seen)


func test_component_publishes_nothing_to_the_event_bus() -> void:
	# The testability half of the argument for keeping the bus out of
	# components, stated as a test: a component doing its whole job must not
	# put anything on the bus. Promoting a local change to a cross-feature
	# fact is a decision for the entity root or an adapter to make.
	var bus := make_autoload(
		"res://addons/universal_gameplay/core/event_bus.gd", "BusUnderTest"
	)
	var published: Array = []
	bus.event_published.connect(func(event: FrameworkEvent) -> void: published.append(event))

	component.initialize(EntityContext.create(entity))
	component.set_value(42)
	component.capture_state()
	component.restore_state({"value": 9})

	assert_eq(component.value, 9, "The component did its job")
	assert_empty(published, "...and told the bus nothing")


func test_component_works_with_no_event_bus_at_all() -> void:
	# The same point from the other side: nothing here requires the singleton
	# to exist, which is what lets components be unit-tested.
	component.initialize(EntityContext.create(entity))
	component.set_value(42)
	assert_eq(component.value, 42)


func test_capture_and_restore_round_trip() -> void:
	component.set_value(7)
	var state := component.capture_state()
	assert_eq(state["value"], 7)

	var restored := SampleComponent.new()
	entity.add_child(restored)
	restored.restore_state(state)
	assert_eq(restored.value, 7)


func test_restore_tolerates_a_missing_key() -> void:
	# A save written before a field existed is a normal case, not corruption.
	component.restore_state({})
	assert_eq(component.value, 0)


func test_base_component_is_not_persistent_by_default() -> void:
	var plain := FrameworkComponent.new()
	entity.add_child(plain)
	assert_false(plain.is_persistent())
	assert_empty(plain.capture_state())
	plain.restore_state({"anything": 1})


func test_stateful_component_opts_into_persistence() -> void:
	assert_true(component.is_persistent())
