extends FrameworkTestCase
## The two perception facts the plan lists and M7 never built:
## [code]damaged_by[/code] and the interaction stimulus (plan lines 569-571).
##
## Both arrive through deletable adapters rather than through Perception
## learning what damage or an interaction is, because Perception knowing either
## would make AI depend on Health and Interaction (rule 9).

const BUS_SCRIPT: String = "res://addons/universal_gameplay/core/event_bus.gd"

var bus: Node = null


func before_each() -> void:
	bus = make_autoload(BUS_SCRIPT, "EventBus")
	bus.warn_on_unregistered = false


# --- damaged_by -----------------------------------------------------------

func _guard(position: Vector3 = Vector3.ZERO) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Guard"
	entity.global_position = position

	var health := HealthComponent.new()
	health.name = "HealthComponent"
	health.maximum_health = 100.0
	entity.add_child(health)

	var receiver := DamageReceiverComponent.new()
	receiver.name = "DamageReceiverComponent"
	receiver.health = health
	entity.add_child(receiver)

	var perception := PerceptionComponent.new()
	perception.name = "PerceptionComponent"
	perception.auto_tick = false
	entity.add_child(perception)

	var adapter := DamagePerceptionAdapter.new()
	adapter.name = "DamagePerceptionAdapter"
	entity.add_child(adapter)

	var context := EntityContext.create(entity, null, null)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)
	return entity


func _attacker(position: Vector3 = Vector3(5.0, 0.0, 0.0)) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Sniper"
	entity.global_position = position
	return entity


func _perception_of(entity: Node) -> PerceptionComponent:
	for child in entity.get_children():
		if child is PerceptionComponent:
			return child as PerceptionComponent
	return null


func _receiver_of(entity: Node) -> DamageReceiverComponent:
	for child in entity.get_children():
		if child is DamageReceiverComponent:
			return child as DamageReceiverComponent
	return null


func test_being_shot_records_who_did_it() -> void:
	var guard := _guard()
	var sniper := _attacker()

	_receiver_of(guard).receive(DamageContext.create(20.0, sniper))

	var entry := _perception_of(guard).get_memory().get_entry(sniper)
	assert_not_null(entry, "The attacker is not in memory at all")
	assert_true(entry.attacked_us)
	assert_eq(entry.damage_taken_from, 20.0)


func test_an_unseen_attacker_is_noticed_without_a_sight_line() -> void:
	# The case that matters. Being shot from cover has to make an NPC react;
	# an NPC that only reacts to what it can see never fights back.
	var guard := _guard()
	var sniper := _attacker(Vector3(500.0, 0.0, 0.0))

	_receiver_of(guard).receive(DamageContext.create(10.0, sniper))

	var entry := _perception_of(guard).get_memory().get_entry(sniper)
	assert_true(entry.noticed, "Half a kilometre away and behind cover, but noticed")
	assert_false(entry.visible, "Noticed is not the same as seen")


func test_the_attack_is_announced_once_rather_than_per_shot() -> void:
	var guard := _guard()
	var sniper := _attacker()
	var announcements: Array[Node] = []
	_perception_of(guard).get_memory().attacked_by.connect(
		func(entry: MemoryEntry) -> void: announcements.append(entry.target)
	)

	for _shot in 3:
		_receiver_of(guard).receive(DamageContext.create(5.0, sniper))

	assert_size(announcements, 1, "Three shots, one 'we are under attack'")


func test_damage_accumulates_so_a_brain_can_pick_the_bigger_threat() -> void:
	var guard := _guard()
	var pistol := _attacker(Vector3(3.0, 0.0, 0.0))
	var rifle := _attacker(Vector3(9.0, 0.0, 0.0))
	rifle.name = "Rifleman"

	_receiver_of(guard).receive(DamageContext.create(5.0, pistol))
	_receiver_of(guard).receive(DamageContext.create(40.0, rifle))
	_receiver_of(guard).receive(DamageContext.create(5.0, pistol))

	var attackers := _perception_of(guard).get_memory().get_attackers()
	assert_size(attackers, 2)
	assert_eq(attackers[0].target, rifle, "The one doing the most damage comes first")
	assert_eq(attackers[1].damage_taken_from, 10.0, "And the pistol's shots were summed")


func test_hurting_yourself_does_not_make_you_your_own_enemy() -> void:
	# Falling, poison and standing in your own fire all arrive as damage with
	# an instigator. Without this an NPC hunts itself forever.
	var guard := _guard()
	_receiver_of(guard).receive(DamageContext.create(10.0, guard))
	assert_true(_perception_of(guard).get_memory().is_empty())


func test_damage_from_nobody_records_nobody() -> void:
	var guard := _guard()
	_receiver_of(guard).receive(DamageContext.create(10.0, null))
	assert_true(_perception_of(guard).get_memory().is_empty())


func test_deleting_the_adapter_leaves_damage_working() -> void:
	# Rule 10, stated as a test. Without the adapter the guard still takes the
	# hit; it just never learns who threw it.
	var guard := _guard()
	for child in guard.get_children():
		if child is DamagePerceptionAdapter:
			child.free()
	var sniper := _attacker()

	_receiver_of(guard).receive(DamageContext.create(30.0, sniper))

	assert_true(_perception_of(guard).get_memory().is_empty(), "Nothing was recorded")
	for child in guard.get_children():
		if child is HealthComponent:
			assert_eq((child as HealthComponent).get_current(), 70.0, "But the damage landed")


# --- interaction stimulus -------------------------------------------------

func _watcher(position: Vector3 = Vector3.ZERO, radius: float = 12.0) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Watcher"
	entity.global_position = position

	var perception := PerceptionComponent.new()
	perception.name = "PerceptionComponent"
	perception.auto_tick = false
	entity.add_child(perception)

	var adapter := InteractionPerceptionAdapter.new()
	adapter.name = "InteractionPerceptionAdapter"
	adapter.event_bus = bus
	adapter.notice_radius = radius
	entity.add_child(adapter)

	var context := EntityContext.create(entity, null, null)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)
	return entity


## An interacting entity plus the door it used, published the way a real
## InteractionEventAdapter would.
func _publish_interaction(
	interactor: Node3D, interaction_id: StringName = &"interaction.pick_lock",
	verb: StringName = &"verb.pick"
) -> void:
	var definition := InteractionDefinition.new()
	definition.id = interaction_id
	definition.display_name = str(interaction_id)
	definition.verb = verb

	var door := add_test_node(Node3D.new()) as Node3D
	door.name = "Door"

	var context := InteractionContext.new()
	context.interactor = interactor
	context.target = door
	context.definition = definition

	var script := load("res://addons/universal_gameplay/interaction/interaction_event.gd")
	bus.publish(script.create(context))


func test_an_interaction_nearby_is_noticed() -> void:
	var watcher := _watcher()
	var thief := add_test_node(Node3D.new()) as Node3D
	thief.name = "Thief"
	thief.global_position = Vector3(4.0, 0.0, 0.0)

	_publish_interaction(thief)

	var entry := _perception_of(watcher).get_memory().get_entry(thief)
	assert_not_null(entry, "The thief was not recorded")
	assert_true(entry.interacted)
	assert_eq(entry.last_interaction, &"interaction.pick_lock")


func test_an_interaction_out_of_range_is_ignored() -> void:
	var watcher := _watcher(Vector3.ZERO, 5.0)
	var thief := add_test_node(Node3D.new()) as Node3D
	thief.name = "Thief"
	thief.global_position = Vector3(50.0, 0.0, 0.0)

	_publish_interaction(thief)

	assert_true(_perception_of(watcher).get_memory().is_empty())


func test_only_verbs_of_interest_are_reacted_to() -> void:
	# A guard that investigates every light switch is a guard nobody enjoys.
	var watcher := _watcher()
	for child in watcher.get_children():
		if child is InteractionPerceptionAdapter:
			var wanted: Array[StringName] = [&"verb.pick"]
			(child as InteractionPerceptionAdapter).verbs_of_interest = wanted

	var thief := add_test_node(Node3D.new()) as Node3D
	thief.name = "Thief"
	thief.global_position = Vector3(2.0, 0.0, 0.0)

	_publish_interaction(thief, &"interaction.light", &"verb.switch")
	assert_true(_perception_of(watcher).get_memory().is_empty(), "A light switch is not news")

	_publish_interaction(thief, &"interaction.pick_lock", &"verb.pick")
	assert_false(_perception_of(watcher).get_memory().is_empty(), "A lockpick is")


func test_your_own_interactions_are_not_a_stimulus() -> void:
	var watcher := _watcher()
	_publish_interaction(watcher)
	assert_true(_perception_of(watcher).get_memory().is_empty())


func test_witnessing_an_interaction_notices_a_stranger() -> void:
	var watcher := _watcher()
	var thief := add_test_node(Node3D.new()) as Node3D
	thief.name = "Thief"
	thief.global_position = Vector3(3.0, 0.0, 0.0)

	_publish_interaction(thief)

	assert_true(_perception_of(watcher).get_memory().get_entry(thief).noticed)
