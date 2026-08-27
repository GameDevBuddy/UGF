extends FrameworkTestCase
## The M18 exit gate: offline mode unchanged, and a server-authoritative
## inventory and combat prototype.
##
## [b]"Offline mode unchanged" is the harder half.[/b] It is easy to assert by
## playing and impossible to keep true by remembering, so it is asserted two
## ways here: structurally, that no module names anything in
## [code]networking/[/code]; and behaviourally, that a command routed through
## the authority offline does exactly what calling the component does.

const CORE_SCRIPT: String = "res://addons/universal_gameplay/core/framework_core.gd"

var core: Node = null
var authority: NetworkAuthority = null
var transport: NetworkFixtures.RecordingTransport = null
var sword: ItemDefinition = null


func before_each() -> void:
	core = make_autoload(CORE_SCRIPT, "FrameworkCore")
	sword = ItemFixtures.stackable(&"item.sword", 99, 1.0)
	core.get_definition_registry().register(sword)

	transport = NetworkFixtures.transport()
	authority = NetworkFixtures.authority(transport, AuthorityPolicy.standard())
	add_test_node(authority)


func _actor(
	entity_name: String = "Player",
	network_id: StringName = &"player",
	authority_peer: int = 0
) -> Node3D:
	var entity := NetworkFixtures.actor(entity_name, network_id, authority_peer)
	add_test_node(entity)
	NetworkFixtures.assemble(entity, core)
	assert_ok(authority.register_entity(entity))
	return entity


func _inventory_adapter() -> InventoryAuthorityAdapter:
	var adapter := InventoryAuthorityAdapter.new()
	adapter.name = "InventoryAuthorityAdapter"
	adapter.authority = authority
	adapter.registry = core
	add_test_node(adapter)
	return adapter


# --- Offline mode unchanged -----------------------------------------------

func test_no_module_names_anything_in_networking() -> void:
	# The structural half. Networking is optional, and a module reaching for a
	# peer would make it mandatory.
	var forbidden := [
		"NetworkAuthority", "NetworkIntent", "NetworkIdentity", "NetworkTransport",
		"AuthorityPolicy", "SERVICE_NETWORK", "multiplayer",
	]
	for directory in [
		"res://addons/universal_gameplay/inventory",
		"res://addons/universal_gameplay/combat",
		"res://addons/universal_gameplay/items",
		"res://addons/universal_gameplay/health_damage",
		"res://addons/universal_gameplay/commerce",
		"res://addons/universal_gameplay/missions",
		"res://addons/universal_gameplay/core",
	]:
		var sources := _sources_in(directory)
		for path in sources:
			# gameplay_names.gd is the shared vocabulary: every module's
			# service and module ids live there and none of them is a
			# dependency. A constant is not an import.
			if (path as String).get_file() == "gameplay_names.gd":
				continue
			for name in forbidden:
				assert_false(
					(sources[path] as String).contains(name),
					"%s names %s" % [(path as String).get_file(), name]
				)


func test_only_one_file_touches_godots_multiplayer_api() -> void:
	# The plan forbids exposing MultiplayerSpawner and MultiplayerSynchronizer
	# to feature APIs. One file behind a seam is how that stays true.
	var offenders := PackedStringArray()
	for path in _sources_in("res://addons/universal_gameplay"):
		var code: String = _sources_in("res://addons/universal_gameplay")[path]
		if code.contains("MultiplayerAPI") or code.contains("multiplayer."):
			offenders.append((path as String).get_file())
	assert_eq(offenders.size(), 1, "got %s" % offenders)
	assert_eq(offenders[0], "multiplayer_transport.gd")


func test_offline_a_command_runs_in_process_on_the_same_line() -> void:
	# The behavioural half. Offline the transport is authoritative and the
	# policy owns nothing that matters, so there is no round trip to wait for.
	var offline := NetworkFixtures.authority(NetworkTransport.new(), null)
	add_test_node(offline)
	var player := NetworkFixtures.actor()
	add_test_node(player)
	NetworkFixtures.assemble(player, core)
	assert_ok(offline.register_entity(player))

	var adapter := InventoryAuthorityAdapter.new()
	adapter.name = "InventoryAuthorityAdapter"
	adapter.authority = offline
	adapter.registry = core
	add_test_node(adapter)

	var answer := offline.execute(
		&"inventory.add", player, {&"item_id": &"item.sword", &"quantity": 3}
	)
	assert_ok(answer)
	assert_eq(NetworkFixtures.inventory_of(player).count(&"item.sword"), 3)


func test_offline_the_authority_owns_nothing_and_permits_everything() -> void:
	var offline := NetworkFixtures.authority(NetworkTransport.new(), null)
	add_test_node(offline)
	assert_true(offline.is_server())
	assert_false(offline.is_networked())
	for verb in [&"inventory.add", &"combat.attack", &"anything.at.all"]:
		assert_false(offline.is_authoritative(verb))
		assert_true(offline.may_execute(verb))


func test_an_entity_with_no_network_identity_is_the_servers() -> void:
	# An entity nobody claimed is one the server owns, which offline is
	# everybody. Refusing would make networking mandatory by the back door.
	var plain := Node3D.new()
	plain.name = "Crate"
	add_test_node(plain)
	assert_true(authority.has_authority_over(plain))


func test_the_module_requires_nothing() -> void:
	var module: FrameworkModule = load(
		"res://addons/universal_gameplay/networking/networking_module.gd"
	).new()
	assert_eq(module.get_manifest().id, GameplayNames.MODULE_NETWORKING)
	assert_empty(module.get_manifest().requires)


# --- Server-authoritative inventory ---------------------------------------

func test_the_server_executes_an_inventory_command() -> void:
	_inventory_adapter()
	var player := _actor()
	var answer := authority.execute(
		&"inventory.add", player, {&"item_id": &"item.sword", &"quantity": 2}
	)
	assert_ok(answer)
	assert_eq(NetworkFixtures.inventory_of(player).count(&"item.sword"), 2)


func test_a_client_sends_a_request_rather_than_acting() -> void:
	# The whole point of the facade. A client executing an authoritative verb
	# locally is a client that decides its own inventory.
	_inventory_adapter()
	var player := _actor("Player", &"player", 1)
	transport.server = false
	transport.peer_id = 1

	assert_false(authority.may_execute(&"inventory.add"))
	var answer := authority.execute(
		&"inventory.add", player, {&"item_id": &"item.sword", &"quantity": 2}
	)
	assert_ok(answer, "the send succeeded")
	assert_size(transport.sent, 1, "and it went to the server")
	assert_eq(
		NetworkFixtures.inventory_of(player).count(&"item.sword"), 0,
		"and nothing happened locally"
	)


func test_the_server_runs_what_a_client_asked_for() -> void:
	_inventory_adapter()
	var player := _actor("Player", &"player", 1)
	var intent := NetworkIntent.create(
		&"inventory.add", &"player", {&"item_id": &"item.sword", &"quantity": 2}
	)
	transport.deliver(intent, 1)
	assert_eq(NetworkFixtures.inventory_of(player).count(&"item.sword"), 2)


func test_a_peer_cannot_act_for_somebody_elses_entity() -> void:
	# The check a client cannot be trusted to have made.
	_inventory_adapter()
	var player := _actor("Player", &"player", 1)
	var rejections: Array = []
	authority.intent_rejected.connect(
		func(_intent: NetworkIntent, reason: StringName) -> void: rejections.append(reason)
	)

	var intent := NetworkIntent.create(
		&"inventory.add", &"player", {&"item_id": &"item.sword", &"quantity": 2}
	)
	transport.deliver(intent, 7)
	assert_eq(rejections, [&"network.not_yours"])
	assert_eq(NetworkFixtures.inventory_of(player).count(&"item.sword"), 0)


func test_an_intent_naming_an_unknown_actor_is_refused() -> void:
	_inventory_adapter()
	var answer := authority.submit(
		NetworkIntent.create(&"inventory.add", &"nobody", {&"item_id": &"item.sword"})
	)
	assert_err(answer, &"network.unknown_actor")


func test_an_unhandled_verb_is_refused() -> void:
	assert_err(
		authority.submit(NetworkIntent.create(&"nonsense.verb")), &"network.unknown_verb"
	)


func test_an_absurd_quantity_is_refused_server_side() -> void:
	# The cheapest anti-cheat there is: a number rather than an overflow.
	_inventory_adapter()
	var player := _actor()
	assert_err(
		authority.execute(
			&"inventory.add", player, {&"item_id": &"item.sword", &"quantity": 999999}
		),
		&"inventory.too_many"
	)
	assert_eq(NetworkFixtures.inventory_of(player).count(&"item.sword"), 0)


func test_a_negative_quantity_is_refused() -> void:
	_inventory_adapter()
	var player := _actor()
	assert_err(
		authority.execute(
			&"inventory.add", player, {&"item_id": &"item.sword", &"quantity": -5}
		),
		&"inventory.bad_quantity"
	)


func test_a_transfer_moves_items_between_two_containers() -> void:
	_inventory_adapter()
	var player := _actor()
	var chest := NetworkFixtures.container()
	add_test_node(chest)
	NetworkFixtures.assemble(chest, core)
	assert_ok(authority.register_entity(chest))

	var bag := NetworkFixtures.inventory_of(player)
	assert_ok(bag.add(ItemInstance.create(sword, 5)))

	var answer := authority.execute(
		&"inventory.transfer", player, {&"item_id": &"item.sword", &"quantity": 3}, chest
	)
	assert_ok(answer)
	assert_eq(bag.count(&"item.sword"), 2)
	assert_eq(NetworkFixtures.inventory_of(chest).count(&"item.sword"), 3)


func test_a_transfer_to_nowhere_is_refused() -> void:
	_inventory_adapter()
	var player := _actor()
	assert_err(
		authority.execute(&"inventory.transfer", player, {&"item_id": &"item.sword"}),
		&"inventory.no_target"
	)


func test_a_transfer_to_itself_is_refused() -> void:
	_inventory_adapter()
	var player := _actor()
	assert_err(
		authority.execute(
			&"inventory.transfer", player, {&"item_id": &"item.sword"}, player
		),
		&"inventory.self_transfer"
	)


func test_inventory_needed_no_change_for_any_of_this() -> void:
	# The adapter calls the component's own methods and adds nothing. An
	# adapter with rules of its own would be a second place inventory
	# behaviour lives.
	var source := FileAccess.get_file_as_string(
		"res://addons/universal_gameplay/networking/inventory_authority_adapter.gd"
	)
	for method in ["bag.add(", "bag.remove(", "from.transfer_to("]:
		assert_true(source.contains(method), "the adapter should call %s" % method)


# --- Server-authoritative combat ------------------------------------------

func _combatant(network_id: StringName = &"soldier", peer: int = 0) -> Node3D:
	# Armed, because an unarmed punch has no rate of fire and the check under
	# test is the one that reads the weapon's own numbers.
	var entity := CombatFixtures.fighter(
		"Soldier", Vector3.ZERO, CombatFixtures.rifle()
	)
	var network := NetworkIdentity.new()
	network.name = "NetworkIdentity"
	network.network_id = network_id
	network.authority_peer = peer
	entity.add_child(network)
	add_test_node(entity)
	CombatFixtures.assemble(entity)
	assert_ok(authority.register_entity(entity))
	return entity


func _combat_adapter() -> CombatAuthorityAdapter:
	var adapter := CombatAuthorityAdapter.new()
	adapter.name = "CombatAuthorityAdapter"
	adapter.authority = authority
	add_test_node(adapter)
	return adapter


func test_the_server_executes_an_attack() -> void:
	_combat_adapter()
	var soldier := _combatant()
	var answer := authority.execute(&"combat.attack", soldier)
	assert_ok(answer)


func test_shots_arriving_faster_than_the_weapon_can_fire_are_refused() -> void:
	# The single most valuable server-side check in a shooter: the component's
	# own rate limit runs on the machine that was modified.
	_combat_adapter()
	var soldier := _combatant()
	assert_ok(authority.execute(&"combat.attack", soldier))
	assert_err(authority.execute(&"combat.attack", soldier), &"combat.too_fast")


func test_the_rate_limit_reads_the_weapons_own_numbers() -> void:
	var adapter := _combat_adapter()
	var soldier := _combatant()
	var combat := NetworkFixtures.find(soldier, CombatComponent) as CombatComponent
	assert_true(
		adapter.get_minimum_interval(combat) > 0.0,
		"an attack with timing should have a minimum interval"
	)


func test_a_verb_with_no_component_behind_it_is_refused_cleanly() -> void:
	_combat_adapter()
	var player := _actor()
	assert_err(authority.execute(&"combat.attack", player), &"combat.no_component")


# --- The facade -----------------------------------------------------------

func test_an_intent_carrying_an_object_is_refused_before_it_is_sent() -> void:
	# It would work here and fail over a real connection, which is the worst
	# kind of bug to ship.
	var intent := NetworkIntent.create(&"inventory.add", &"player", {&"node": Node.new()})
	assert_false(intent.is_serialisable())
	var answer := NetworkTransport.new().send(intent)
	assert_err(answer, &"network.unserialisable")
	(intent.arguments[&"node"] as Node).free()


func test_an_intent_round_trips_through_plain_data() -> void:
	var intent := NetworkIntent.create(
		&"inventory.add", &"player", {&"item_id": &"item.sword", &"quantity": 3}, &"chest"
	)
	intent.sequence = 7
	var restored := NetworkIntent.from_dictionary(intent.to_dictionary())
	assert_eq(restored.verb, &"inventory.add")
	assert_eq(restored.actor_id, &"player")
	assert_eq(restored.target_id, &"chest")
	assert_eq(restored.get_int(&"quantity"), 3)
	assert_eq(restored.sequence, 7)


func test_a_validator_can_refuse_before_the_handler_runs() -> void:
	var ran: Array = []
	authority.register_handler(
		&"test.verb", func(_intent: NetworkIntent) -> void: ran.append(1)
	)
	authority.register_validator(
		&"test.verb",
		func(_intent: NetworkIntent) -> FrameworkResult:
			return FrameworkResult.fail(&"test.refused", "no")
	)
	assert_err(authority.submit(NetworkIntent.create(&"test.verb")), &"test.refused")
	assert_empty(ran, "the handler never ran")


func test_a_validator_returning_false_refuses_too() -> void:
	authority.register_handler(&"test.verb", func(_i: NetworkIntent) -> void: pass)
	authority.register_validator(&"test.verb", func(_i: NetworkIntent) -> bool: return false)
	assert_err(authority.submit(NetworkIntent.create(&"test.verb")), &"network.refused")


func test_validators_stack() -> void:
	authority.register_handler(&"test.verb", func(_i: NetworkIntent) -> void: pass)
	authority.register_validator(&"test.verb", func(_i: NetworkIntent) -> bool: return true)
	authority.register_validator(&"test.verb", func(_i: NetworkIntent) -> bool: return false)
	assert_eq(authority.get_validator_count(&"test.verb"), 2)
	assert_err(authority.submit(NetworkIntent.create(&"test.verb")), &"network.refused")


func test_a_duplicate_handler_is_refused() -> void:
	authority.register_handler(&"test.verb", func(_i: NetworkIntent) -> void: pass)
	assert_err(
		authority.register_handler(&"test.verb", func(_i: NetworkIntent) -> void: pass),
		&"network.duplicate_handler"
	)


func test_rejections_are_counted_for_an_anti_cheat_log() -> void:
	_inventory_adapter()
	var player := _actor("Player", &"player", 1)
	for index in 3:
		transport.deliver(
			NetworkIntent.create(&"inventory.add", &"player", {&"item_id": &"item.sword"}), 9
		)
	assert_eq(authority.get_rejection_counts()[&"network.not_yours"], 3)
	authority.clear_rejection_counts()
	assert_empty(authority.get_rejection_counts())


func test_a_successful_command_is_broadcast() -> void:
	_inventory_adapter()
	var player := _actor()
	assert_ok(
		authority.execute(&"inventory.add", player, {&"item_id": &"item.sword"})
	)
	assert_size(transport.broadcasts, 1)


func test_a_refused_command_is_not_broadcast() -> void:
	_inventory_adapter()
	var player := _actor()
	assert_true(
		authority.execute(
			&"inventory.add", player, {&"item_id": &"item.nonsense"}
		).is_err()
	)
	assert_empty(transport.broadcasts)


func test_a_client_hears_the_answer_to_what_it_asked() -> void:
	var answers: Array = []
	authority.request_answered.connect(
		func(sequence: int, result: FrameworkResult) -> void:
			answers.append([sequence, result.is_ok()])
	)
	_inventory_adapter()
	var player := _actor()
	assert_ok(authority.execute(&"inventory.add", player, {&"item_id": &"item.sword"}))
	assert_size(answers, 1)
	assert_true(answers[0][1])


func test_a_network_id_is_not_a_save_id() -> void:
	# Conflating them means saves that break when somebody rejoins, or network
	# traffic that leaks the shape of a save file.
	var player := _actor("Player", &"net_player_1")
	var save_id := (
		NetworkFixtures.find(player, PersistentIdentity) as PersistentIdentity
	).get_persistent_id()
	var net_id := NetworkIdentity.find_on(player).get_network_id()
	assert_eq(save_id, &"player")
	assert_eq(net_id, &"net_player_1")
	assert_ne(save_id, net_id)


func test_authority_can_change_hands() -> void:
	# What possession, host migration and a player joining all do.
	var player := _actor("Player", &"player", 0)
	var identity := NetworkIdentity.find_on(player)
	var changes: Array = []
	identity.authority_changed.connect(func(peer: int) -> void: changes.append(peer))

	identity.set_authority(3)
	assert_eq(changes, [3])
	assert_true(identity.is_authority(3))
	assert_false(identity.is_server_owned())


# --- The policy -----------------------------------------------------------

func test_the_standard_policy_owns_what_the_plan_says_it_should() -> void:
	var policy := AuthorityPolicy.standard()
	for verb in [
		&"inventory.add", &"commerce.buy", &"combat.attack", &"mission.complete",
		&"crime.report",
	]:
		assert_true(policy.is_authoritative(verb), "%s should be the server's" % verb)


func test_looking_around_is_nobodys_business_but_the_clients() -> void:
	# A policy that made presentation round-trip would be correct and
	# unplayable.
	var policy := AuthorityPolicy.standard()
	for verb in [&"camera.look", &"ui.open", &"animation.play"]:
		assert_true(policy.is_local(verb), "%s should stay local" % verb)


func test_a_prefix_covers_a_whole_command_surface() -> void:
	var policy := AuthorityPolicy.new()
	var prefixes: Array[StringName] = [&"inventory."]
	policy.authoritative_prefixes = prefixes
	assert_true(policy.is_authoritative(&"inventory.anything"))
	assert_false(policy.is_authoritative(&"combat.attack"))


func test_a_local_verb_escapes_its_namespaces_prefix() -> void:
	var policy := AuthorityPolicy.standard()
	var local: Array[StringName] = [&"inventory.sort"]
	policy.local_verbs = local
	assert_false(policy.is_authoritative(&"inventory.sort"))
	assert_true(policy.is_authoritative(&"inventory.add"))


func test_a_policy_owning_nothing_says_so() -> void:
	assert_true(AuthorityPolicy.new().validate().has_warnings())


func test_a_contradictory_policy_is_an_error() -> void:
	var policy := AuthorityPolicy.new()
	var both: Array[StringName] = [&"inventory.add"]
	policy.authoritative_verbs = both
	policy.local_verbs = both
	assert_true(policy.validate().has_errors())


# --- Internals ------------------------------------------------------------

var _cache: Dictionary = {}


func _sources_in(directory: String) -> Dictionary:
	if _cache.has(directory):
		return _cache[directory]
	var found: Dictionary = {}
	var handle := DirAccess.open(directory)
	if handle != null:
		handle.list_dir_begin()
		var entry := handle.get_next()
		while entry != "":
			var path := directory.path_join(entry)
			if handle.current_is_dir():
				if not entry.begins_with("."):
					found.merge(_sources_in(path))
			elif entry.ends_with(".gd"):
				found[path] = _strip_comments(FileAccess.get_file_as_string(path))
			entry = handle.get_next()
		handle.list_dir_end()
	_cache[directory] = found
	return found


func _strip_comments(source: String) -> String:
	var kept := PackedStringArray()
	for line in source.split("\n"):
		if not (line as String).strip_edges().begins_with("#"):
			kept.append(line)
	return "\n".join(kept)
