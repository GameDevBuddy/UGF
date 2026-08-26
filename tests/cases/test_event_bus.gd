extends FrameworkTestCase
## Covers the EventBus.

const BUS_SCRIPT := "res://addons/universal_gameplay/core/event_bus.gd"
const SampleEvent := preload("res://tests/support/sample_event.gd")
const UnnamedEvent := preload("res://tests/support/unnamed_event.gd")

var bus: Node = null
var received: Array = []


func before_each() -> void:
	# A fresh bus per test. This is what autoload scripts having no class_name
	# buys: no shared global whose subscriptions bleed across tests.
	bus = make_autoload(BUS_SCRIPT, "EventBusUnderTest")
	bus.warn_on_unregistered = false
	received = []


func _record(event: FrameworkEvent) -> void:
	received.append(event)


func _event(p_source: Node = null, p_detail: String = "") -> SampleEvent:
	var event := SampleEvent.new()
	event.configure(p_source, p_detail)
	return event


func test_core_signal_is_declared_up_front() -> void:
	assert_true(bus.has_event(&"actor_died"))


func test_publish_reaches_a_core_signal_subscriber() -> void:
	bus.actor_died.connect(_record)
	var actor := add_test_node(Node.new())
	var result: FrameworkResult = bus.publish(ActorDiedEvent.create(actor))
	assert_ok(result)
	assert_true(result.payload, "Payload reports the event was delivered")
	assert_size(received, 1)
	assert_eq(received[0].actor, actor)


func test_every_event_reaches_the_firehose() -> void:
	# The debug event monitor watches the whole bus through this one signal,
	# without knowing which modules are installed.
	bus.event_published.connect(_record)
	bus.publish(ActorDiedEvent.create(null))
	bus.register_event(SampleEvent.EVENT_NAME)
	bus.publish(_event(null, "hello"))
	assert_size(received, 2)


func test_publish_null_is_rejected() -> void:
	assert_err(bus.publish(null), &"event.null")


func test_event_without_a_name_is_rejected_but_still_seen() -> void:
	bus.event_published.connect(_record)
	assert_err(bus.publish(UnnamedEvent.new()), &"event.unnamed")
	assert_size(received, 1, "A malformed event still reaches the monitor")


func test_module_registers_its_own_event() -> void:
	assert_false(bus.has_event(SampleEvent.EVENT_NAME))
	var result: FrameworkResult = bus.register_event(SampleEvent.EVENT_NAME)
	assert_ok(result)
	assert_true(result.payload, "Payload reports the signal was newly added")
	assert_true(bus.has_event(SampleEvent.EVENT_NAME))
	assert_has(bus.get_registered_event_names(), SampleEvent.EVENT_NAME)


func test_registering_an_event_twice_is_idempotent() -> void:
	bus.register_event(SampleEvent.EVENT_NAME)
	var second: FrameworkResult = bus.register_event(SampleEvent.EVENT_NAME)
	assert_ok(second)
	assert_false(second.payload, "Payload reports nothing new was added")


func test_empty_event_name_rejected() -> void:
	assert_err(bus.register_event(&""), &"event.invalid_name")


func test_subscribe_delivers() -> void:
	bus.register_event(SampleEvent.EVENT_NAME)
	assert_ok(bus.subscribe(SampleEvent.EVENT_NAME, _record))
	bus.publish(_event(null, "payload"))
	assert_size(received, 1)
	assert_eq(received[0].detail, "payload")


func test_subscribe_before_the_producing_module_loads() -> void:
	# Load order is not guaranteed, so binding early must work.
	assert_false(bus.has_event(SampleEvent.EVENT_NAME))
	assert_ok(bus.subscribe(SampleEvent.EVENT_NAME, _record))
	assert_true(bus.has_event(SampleEvent.EVENT_NAME))
	bus.publish(_event(null, "late"))
	assert_size(received, 1)


func test_double_subscribe_connects_once() -> void:
	bus.subscribe(SampleEvent.EVENT_NAME, _record)
	var second: FrameworkResult = bus.subscribe(SampleEvent.EVENT_NAME, _record)
	assert_ok(second)
	assert_false(second.payload, "Payload reports no new connection was made")
	bus.publish(_event())
	assert_size(received, 1, "Delivered once, not twice")


func test_invalid_handler_rejected() -> void:
	assert_err(bus.subscribe(SampleEvent.EVENT_NAME, Callable()), &"event.invalid_handler")


func test_unsubscribe() -> void:
	bus.subscribe(SampleEvent.EVENT_NAME, _record)
	assert_true(bus.unsubscribe(SampleEvent.EVENT_NAME, _record))
	bus.publish(_event())
	assert_empty(received)
	assert_false(bus.unsubscribe(SampleEvent.EVENT_NAME, _record), "Unsubscribing twice is false")


func test_publishing_an_unregistered_event_degrades_gracefully() -> void:
	# Rule 31: a module unregistering mid-flight means nobody hears the fact,
	# not that publishing errors.
	bus.event_published.connect(_record)
	var result: FrameworkResult = bus.publish(_event())
	assert_ok(result)
	assert_false(result.payload, "Payload reports it reached no named signal")
	assert_size(received, 1, "It still reached the firehose")


func test_unregister_event_drops_handlers() -> void:
	bus.subscribe(SampleEvent.EVENT_NAME, _record)
	assert_true(bus.unregister_event(SampleEvent.EVENT_NAME))
	bus.publish(_event())
	assert_empty(received)
	assert_has_not(bus.get_registered_event_names(), SampleEvent.EVENT_NAME)


func test_unregister_unknown_event() -> void:
	assert_false(bus.unregister_event(&"never.registered"))


func test_reset_module_events_leaves_core_signals_intact() -> void:
	bus.register_event(SampleEvent.EVENT_NAME)
	bus.actor_died.connect(_record)
	bus.reset_module_events()

	assert_empty(bus.get_registered_event_names())
	bus.publish(ActorDiedEvent.create(null))
	assert_size(received, 1, "The Core signal and its listener survived")


func test_actor_died_carries_its_instigator() -> void:
	var victim := add_test_node(Node.new())
	var killer := add_test_node(Node.new())
	killer.name = "Killer"
	var context := DamageContext.create(50.0, killer)
	var event := ActorDiedEvent.create(victim, context)

	assert_eq(event.get_instigator(), killer)
	assert_eq(event.get_event_name(), GameplayNames.EVENT_ACTOR_DIED)
	assert_has(event.describe(), "Killer")


func test_actor_died_without_damage_has_no_instigator() -> void:
	# A scripted death, or a survival need bottoming out.
	var event := ActorDiedEvent.create(add_test_node(Node.new()))
	assert_null(event.get_instigator())


func test_events_are_timestamped() -> void:
	assert_true(ActorDiedEvent.create(null).timestamp_ms >= 0)
