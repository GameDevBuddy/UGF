extends FrameworkTestCase
## Covers the three adapters M9 added so a mission has something to react to:
## the area trigger, the inventory adapter and the narrative adapter.
##
## Each is deletable, and each is the seam that keeps its own module from
## learning what a mission is (rule 10).

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"

var bus: Node = null
var received: Array[FrameworkEvent] = []


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false
	received = []
	bus.event_published.connect(func(event: FrameworkEvent) -> void: received.append(event))


func _of(event_name: StringName) -> Array[FrameworkEvent]:
	return received.filter(
		func(event: FrameworkEvent) -> bool: return event.get_event_name() == event_name
	)


# --- AreaTrigger ----------------------------------------------------------

func _trigger(area_id: StringName = &"area.docks") -> AreaTrigger:
	var entity := add_test_node(Node3D.new())
	var trigger := AreaTrigger.new()
	trigger.name = "AreaTrigger"
	trigger.area_id = area_id
	trigger.event_bus = bus
	entity.add_child(trigger)
	trigger.initialize(EntityContext.create(entity))
	return trigger


func test_entering_a_named_place_is_published() -> void:
	var trigger := _trigger()
	var player := add_test_node(Node3D.new())

	assert_true(trigger.enter(player))
	var events := _of(GameplayNames.EVENT_AREA_ENTERED)
	assert_size(events, 1)
	assert_eq(events[0].area_id, &"area.docks")
	assert_eq(events[0].body, player)
	assert_true(events[0].entered)


func test_re_entering_while_already_inside_is_ignored() -> void:
	# A body brushing the edge of a volume fires several times a second, and
	# an objective counting arrivals would complete on one careless step.
	var trigger := _trigger()
	var player := add_test_node(Node3D.new())
	trigger.enter(player)
	assert_false(trigger.enter(player))
	assert_size(_of(GameplayNames.EVENT_AREA_ENTERED), 1)


func test_leaving_and_re_entering_counts_again() -> void:
	var trigger := _trigger()
	var player := add_test_node(Node3D.new())
	trigger.enter(player)
	trigger.exit(player)
	assert_true(trigger.enter(player))
	assert_size(_of(GameplayNames.EVENT_AREA_ENTERED), 2)


func test_occupants_are_tracked() -> void:
	var trigger := _trigger()
	var first := add_test_node(Node3D.new())
	var second := add_test_node(Node3D.new())
	trigger.enter(first)
	trigger.enter(second)
	assert_eq(trigger.get_occupant_count(), 2)
	assert_true(trigger.contains(first))
	trigger.exit(first)
	assert_false(trigger.contains(first))


func test_departures_are_silent_unless_asked_for() -> void:
	var trigger := _trigger()
	var player := add_test_node(Node3D.new())
	trigger.enter(player)
	trigger.exit(player)
	assert_size(_of(GameplayNames.EVENT_AREA_ENTERED), 1)

	trigger.publish_exits = true
	trigger.enter(player)
	trigger.exit(player)
	var events := _of(GameplayNames.EVENT_AREA_ENTERED)
	assert_size(events, 3)
	assert_false(events[2].entered)


func test_a_group_filter_narrows_what_is_announced() -> void:
	# A busy area with no filter is a lot of events.
	var trigger := _trigger()
	trigger.only_group = &"player"
	var player := add_test_node(Node3D.new())
	var pigeon := add_test_node(Node3D.new())
	player.add_to_group(&"player")

	assert_true(trigger.enter(player))
	assert_false(trigger.enter(pigeon))
	assert_size(_of(GameplayNames.EVENT_AREA_ENTERED), 1)


func test_an_unnamed_area_publishes_nothing() -> void:
	var trigger := _trigger(&"")
	trigger.enter(add_test_node(Node3D.new()))
	assert_empty(_of(GameplayNames.EVENT_AREA_ENTERED))


func test_local_signals_fire_whether_or_not_anything_is_published() -> void:
	var trigger := _trigger(&"")
	var arrivals: Array[Node] = []
	trigger.entered.connect(func(body: Node) -> void: arrivals.append(body))
	trigger.enter(add_test_node(Node3D.new()))
	assert_size(arrivals, 1)


func test_tags_travel_with_the_event() -> void:
	var trigger := _trigger()
	var tags: Array[StringName] = [&"area.restricted"]
	trigger.tags = tags
	trigger.enter(add_test_node(Node3D.new()))
	assert_true(_of(GameplayNames.EVENT_AREA_ENTERED)[0].has_tag(&"area.restricted"))


# --- InventoryEventAdapter ------------------------------------------------

func _bag() -> Array:
	var entity := add_test_node(Node3D.new())
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container()
	entity.add_child(inventory)

	var adapter := InventoryEventAdapter.new()
	adapter.name = "InventoryEventAdapter"
	adapter.inventory = inventory
	adapter.event_bus = bus
	entity.add_child(adapter)

	var context := EntityContext.create(entity)
	inventory.initialize(context)
	adapter.initialize(context)
	return [inventory, adapter, entity]


func test_acquiring_something_is_published() -> void:
	var parts := _bag()
	var inventory: InventoryComponent = parts[0]
	inventory.add(ItemInstance.create(ItemFixtures.stackable(&"item.plank", 99), 4))

	var events := _of(GameplayNames.EVENT_ITEM_ACQUIRED)
	assert_size(events, 1)
	assert_eq(events[0].item_id, &"item.plank")
	assert_eq(events[0].quantity, 4)
	assert_eq(events[0].category, &"item.ammo")


func test_an_items_tags_travel_with_the_acquisition() -> void:
	var parts := _bag()
	var inventory: InventoryComponent = parts[0]
	var definition := ItemFixtures.unique(&"item.amulet")
	var tags: Array[StringName] = [&"item.quest"]
	definition.tags = tags
	inventory.add(ItemInstance.create(definition, 1))

	assert_true(_of(GameplayNames.EVENT_ITEM_ACQUIRED)[0].has_tag(&"item.quest"))


func test_the_event_names_whose_bag_it_was() -> void:
	var parts := _bag()
	var inventory: InventoryComponent = parts[0]
	var entity: Node = parts[2]
	inventory.add(ItemInstance.create(ItemFixtures.stackable(&"item.plank", 99), 1))
	assert_eq(_of(GameplayNames.EVENT_ITEM_ACQUIRED)[0].get_owner_entity(), entity)


func test_publication_can_be_turned_off_per_container() -> void:
	# Every crate and vendor stall has an inventory; announcing every restock
	# to the whole game would be noise.
	var parts := _bag()
	var inventory: InventoryComponent = parts[0]
	var adapter: InventoryEventAdapter = parts[1]
	adapter.publish_acquisitions = false
	inventory.add(ItemInstance.create(ItemFixtures.stackable(&"item.plank", 99), 1))
	assert_empty(_of(GameplayNames.EVENT_ITEM_ACQUIRED))


func test_the_container_works_with_the_adapter_deleted() -> void:
	var parts := _bag()
	var inventory: InventoryComponent = parts[0]
	var adapter: InventoryEventAdapter = parts[1]
	adapter.free()
	assert_ok(inventory.add(ItemInstance.create(ItemFixtures.stackable(&"item.plank", 99), 1)))
	assert_eq(inventory.count(&"item.plank"), 1)


# --- NarrativeEventAdapter ------------------------------------------------

func _narrative() -> Array:
	var narrative := NarrativeStateService.new()
	add_test_node(narrative)
	var adapter := NarrativeEventAdapter.new()
	adapter.name = "NarrativeEventAdapter"
	adapter.event_bus = bus
	adapter.narrative = narrative
	add_test_node(adapter)
	adapter.set_bus(bus)
	adapter.watch(narrative)
	return [narrative, adapter]


func test_a_raised_flag_is_published() -> void:
	var parts := _narrative()
	var narrative: NarrativeStateService = parts[0]
	narrative.set_flag(&"flag.alarm")

	var events := _of(GameplayNames.EVENT_NARRATIVE_FLAG)
	assert_size(events, 1)
	assert_eq(events[0].key, &"flag.alarm")
	assert_eq(events[0].value, true)


func test_a_counter_is_published_with_its_previous_value() -> void:
	var parts := _narrative()
	var narrative: NarrativeStateService = parts[0]
	narrative.increment(&"counter.crimes", 2)
	narrative.increment(&"counter.crimes", 3)

	var events := _of(GameplayNames.EVENT_NARRATIVE_COUNTER)
	assert_size(events, 2)
	assert_eq(events[1].value, 5)
	assert_eq(events[1].previous, 2)


func test_publication_can_be_narrowed_to_one_kind() -> void:
	var parts := _narrative()
	var narrative: NarrativeStateService = parts[0]
	var adapter: NarrativeEventAdapter = parts[1]
	adapter.publish_counters = false

	narrative.set_flag(&"flag.a")
	narrative.increment(&"counter.n")
	assert_size(_of(GameplayNames.EVENT_NARRATIVE_FLAG), 1)
	assert_empty(_of(GameplayNames.EVENT_NARRATIVE_COUNTER))


func test_the_adapter_can_be_pointed_at_a_different_service() -> void:
	var parts := _narrative()
	var adapter: NarrativeEventAdapter = parts[1]
	var second := NarrativeStateService.new()
	add_test_node(second)
	adapter.watch(second)

	(parts[0] as NarrativeStateService).set_flag(&"flag.old")
	assert_empty(_of(GameplayNames.EVENT_NARRATIVE_FLAG))
	second.set_flag(&"flag.new")
	assert_size(_of(GameplayNames.EVENT_NARRATIVE_FLAG), 1)


func test_the_store_works_with_the_adapter_deleted() -> void:
	var parts := _narrative()
	var narrative: NarrativeStateService = parts[0]
	(parts[1] as NarrativeEventAdapter).free()
	narrative.set_flag(&"flag.a")
	assert_true(narrative.get_flag(&"flag.a"))
	assert_empty(_of(GameplayNames.EVENT_NARRATIVE_FLAG))
