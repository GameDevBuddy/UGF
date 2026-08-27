extends FrameworkTestCase
## The companion role (Implementation Plan 21) and dialogue actions that issue
## feature commands (Plan 18) -- the last two gaps the spec audit confirmed.
##
## [b]Companion is a capability, not a brain.[/b] The plan says one line above
## the table that NPC roles are additive capabilities and data rather than a
## class hierarchy, so a CompanionBrain would have been the obvious answer and
## the wrong one (rule 6). [RoleBrain] asks whether there is an order and finds
## nothing on every NPC that is not a companion.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")


# --- Companion ------------------------------------------------------------

func _companion(leader: Node = null, follow_distance: float = 3.0) -> CompanionComponent:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Companion"
	var component := CompanionComponent.new()
	component.name = "CompanionComponent"
	component.leader = leader
	component.follow_distance = follow_distance
	component.leash_distance = 30.0
	entity.add_child(component)
	component.initialize(EntityContext.create(entity, null, core))
	return component


func _leader(position: Vector3 = Vector3(10.0, 0.0, 0.0)) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = "Leader"
	entity.global_position = position
	return entity


func test_a_companion_follows_a_leader_that_walked_off() -> void:
	var leader := _leader(Vector3(10.0, 0.0, 0.0))
	var companion := _companion(leader)

	var goal := companion.get_movement_goal()

	assert_true(goal["should_move"])
	assert_eq(goal["point"], Vector3(10.0, 0.0, 0.0))


func test_a_companion_already_close_enough_stays_put() -> void:
	# What stops it jittering against the leader's own motion.
	var leader := _leader(Vector3(1.0, 0.0, 0.0))
	var companion := _companion(leader, 3.0)
	assert_false(companion.get_movement_goal()["should_move"])


func test_a_waiting_companion_holds_position_when_the_leader_leaves() -> void:
	var leader := _leader(Vector3(1.0, 0.0, 0.0))
	var companion := _companion(leader)
	assert_ok(companion.order_wait())

	leader.global_position = Vector3(15.0, 0.0, 0.0)

	assert_false(
		companion.get_movement_goal()["should_move"],
		"A wait order that the leader can cancel by walking away is not a wait order"
	)


func test_the_leash_overrides_every_order() -> void:
	# A companion holding a position two districts behind is one the player has
	# lost.
	var leader := _leader(Vector3(1.0, 0.0, 0.0))
	var companion := _companion(leader)
	companion.order_wait()

	leader.global_position = Vector3(500.0, 0.0, 0.0)

	var goal := companion.get_movement_goal()
	assert_true(goal["should_move"], "Past the leash it should come back")
	assert_eq(goal["point"], Vector3(500.0, 0.0, 0.0))


func test_a_go_to_order_reverts_to_following_on_arrival() -> void:
	var leader := _leader(Vector3(1.0, 0.0, 0.0))
	var companion := _companion(leader)
	companion.order_move_to(Vector3(1.0, 0.0, 1.0))
	assert_eq(companion.get_order(), CompanionComponent.Order.GO_TO)

	# Already within follow_distance of the point.
	companion.get_movement_goal()

	assert_eq(companion.get_order(), CompanionComponent.Order.FOLLOW)


func test_an_engage_order_chases_its_target() -> void:
	var companion := _companion(_leader(Vector3(1.0, 0.0, 0.0)))
	var enemy := _leader(Vector3(-8.0, 0.0, 0.0))
	enemy.name = "Enemy"

	assert_ok(companion.order_engage(enemy))

	assert_eq(companion.get_movement_goal()["point"], Vector3(-8.0, 0.0, 0.0))


func test_an_engage_order_ends_when_its_target_is_gone() -> void:
	# Rather than a companion standing still forever waiting for a corpse.
	var companion := _companion(_leader(Vector3(1.0, 0.0, 0.0)))
	var enemy := add_test_node(Node3D.new()) as Node3D
	companion.order_engage(enemy)
	enemy.free()

	assert_null(companion.get_order_target())
	assert_eq(companion.get_order(), CompanionComponent.Order.FOLLOW)


func test_a_companion_will_not_be_ordered_to_attack_itself() -> void:
	var companion := _companion(_leader())
	assert_err(companion.order_engage(companion.get_parent()), &"companion.self_target")


func test_following_nobody_is_reported_as_waiting() -> void:
	# Rather than a companion that reports FOLLOW while standing still.
	var companion := _companion(_leader(Vector3(1.0, 0.0, 0.0)))
	companion.set_leader(null)
	assert_eq(companion.get_order(), CompanionComponent.Order.WAIT)


func test_the_order_survives_a_save_and_the_leader_does_not() -> void:
	# A leader is a live node reference; writing an instance id into a save is
	# exactly what rule 32 forbids.
	var companion := _companion(_leader(Vector3(1.0, 0.0, 0.0)))
	companion.order_move_to(Vector3(5.0, 0.0, 5.0))
	var saved := companion.capture_state()

	var restored := _companion(null)
	restored.restore_state(saved)

	assert_eq(restored.get_order(), CompanionComponent.Order.GO_TO)
	assert_eq(restored.get_order_point(), Vector3(5.0, 0.0, 5.0))
	assert_false(saved.has("leader"), "The save carried a node reference")


func test_an_npc_that_is_not_a_companion_has_no_order() -> void:
	# The whole integration cost on every other NPC in the game.
	var plain := add_test_node(Node3D.new())
	assert_null(CompanionComponent.find_on(plain))


# --- Dialogue feature commands --------------------------------------------

func _talker(entity_name: String) -> Node3D:
	var entity := add_test_node(Node3D.new()) as Node3D
	entity.name = entity_name
	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	var profile := InventoryProfile.new()
	profile.slot_count = 20
	inventory.profile_override = profile
	entity.add_child(inventory)
	inventory.initialize(EntityContext.create(entity, null, core))
	return entity


func _inventory_of(entity: Node) -> InventoryComponent:
	for child in entity.get_children():
		if child is InventoryComponent:
			return child as InventoryComponent
	return null


func _register_key() -> ItemDefinition:
	var definition := ItemDefinition.new()
	definition.id = &"item.key"
	definition.display_name = "Key"
	definition.category = &"item.key"
	definition.max_stack = 9
	core.register_definition(definition)
	return definition


func _context(speaker: Node, listener: Node) -> DialogueContext:
	var context := DialogueContext.new()
	context.speaker = speaker
	context.listener = listener
	context.extras["core"] = core
	return context


func test_a_dialogue_action_hands_an_item_over() -> void:
	_register_key()
	var giver := _talker("QuestGiver")
	var taker := _talker("Player")

	var action := ItemTransferAction.new()
	action.item_id = &"item.key"
	action.quantity = 1

	assert_ok(action.execute(_context(giver, taker)))

	assert_eq(_inventory_of(taker).count(&"item.key"), 1)


func test_a_quest_giver_conjuring_a_key_needs_no_key() -> void:
	# The common case. A quest giver handing over a key almost never has one in
	# a bag -- the key exists because the conversation says so.
	_register_key()
	var giver := _talker("QuestGiver")
	var taker := _talker("Player")

	var action := ItemTransferAction.new()
	action.item_id = &"item.key"

	assert_ok(action.execute(_context(giver, taker)))
	assert_true(_inventory_of(giver).is_empty())


func test_a_real_transfer_takes_it_out_of_the_givers_bag() -> void:
	var definition := _register_key()
	var giver := _talker("Player")
	var taker := _talker("Guard")
	_inventory_of(giver).add(ItemInstance.create(definition, 2))

	var action := ItemTransferAction.new()
	action.item_id = &"item.key"
	action.direction = ItemTransferAction.Direction.TO_SPEAKER
	action.from_giver_inventory = true

	# Speaker is the guard, listener the player, so this takes from the player.
	assert_ok(action.execute(_context(taker, giver)))

	assert_eq(_inventory_of(giver).count(&"item.key"), 1)
	assert_eq(_inventory_of(taker).count(&"item.key"), 1)


func test_a_transfer_the_giver_cannot_pay_for_moves_nothing() -> void:
	# Rule 17. Taken before given, so a failure leaves both bags untouched
	# rather than duplicating the item.
	_register_key()
	var giver := _talker("Player")
	var taker := _talker("Guard")

	var action := ItemTransferAction.new()
	action.item_id = &"item.key"
	action.direction = ItemTransferAction.Direction.TO_SPEAKER
	action.from_giver_inventory = true

	assert_err(action.execute(_context(taker, giver)))
	assert_true(_inventory_of(taker).is_empty(), "It was created out of nothing")


func test_handing_over_an_unregistered_item_is_refused() -> void:
	var action := ItemTransferAction.new()
	action.item_id = &"item.nonsense"
	assert_err(
		action.execute(_context(_talker("A"), _talker("B"))), &"dialogue.unknown_item"
	)


func test_a_dialogue_action_starts_a_mission() -> void:
	var narrative := NarrativeStateService.new()
	narrative.name = "NarrativeStateService"
	add_test_node(narrative)
	var missions := MissionService.new()
	missions.name = "MissionService"
	add_test_node(missions)
	missions.configure(core, null, narrative)
	core.register_service(GameplayNames.SERVICE_OBJECTIVE, missions)

	var definition := MissionFixtures.mission(
		&"mission.errand", [MissionFixtures.acquire_objective(&"item.key", 1)]
	)
	core.register_definition(definition)

	var action := MissionAction.new()
	action.mission_id = &"mission.errand"

	assert_ok(action.execute(_context(_talker("Giver"), _talker("Player"))))

	assert_true(missions.is_active(&"mission.errand"))


func test_a_mission_action_with_no_mission_service_reports_it() -> void:
	# Rule 10: Dialogue compiles and runs with Missions deleted. It simply says
	# there is nothing to start.
	var action := MissionAction.new()
	action.mission_id = &"mission.errand"
	assert_err(
		action.execute(_context(_talker("A"), _talker("B"))),
		&"dialogue.no_mission_service"
	)


func test_dialogue_names_no_mission_type() -> void:
	# The reason the service is duck-typed off the registry.
	var source := _read_without_comments(
		"res://addons/universal_gameplay/dialogue/mission_action.gd"
	)
	for forbidden in ["MissionService", "MissionRuntime", "MissionDefinition"]:
		assert_false(source.contains(forbidden), "mission_action.gd names %s" % forbidden)


func test_an_action_that_names_nothing_is_rejected() -> void:
	assert_true(ItemTransferAction.new().validate().has_errors())
	assert_true(MissionAction.new().validate().has_errors())


func _read_without_comments(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var kept: Array[String] = []
	while not file.eof_reached():
		var line := file.get_line()
		if not line.strip_edges().begins_with("#"):
			kept.append(line)
	file.close()
	return "\n".join(kept)
