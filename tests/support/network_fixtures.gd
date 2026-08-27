class_name NetworkFixtures
extends RefCounted
## Builders for the peers, actors and authorities the M18 suites need.


## A transport that records what was sent instead of sending it, and only
## executes when told. What a test uses to be a client without a server.
class RecordingTransport:
	extends NetworkTransport

	var sent: Array[NetworkIntent] = []
	var broadcasts: Array[NetworkIntent] = []
	var server: bool = true
	var peer_id: int = 0
	var connected: bool = true

	func is_server() -> bool:
		return server

	func get_peer_id() -> int:
		return peer_id

	func is_connected_to_session() -> bool:
		return connected

	func send(intent: NetworkIntent) -> FrameworkResult:
		sent.append(intent)
		return super(intent)

	func broadcast(intent: NetworkIntent) -> void:
		broadcasts.append(intent)

	## Delivers an intent as if it had arrived from [param from_peer], which is
	## the whole point: a test can be a server receiving a client's request
	## without either a socket or a second process.
	func deliver(intent: NetworkIntent, from_peer: int = 1) -> void:
		intent.from_peer = from_peer
		intent_received.emit(intent)


static func transport(is_server: bool = true, peer_id: int = 0) -> RecordingTransport:
	var built := RecordingTransport.new()
	built.server = is_server
	built.peer_id = peer_id
	return built


static func authority(
	p_transport: NetworkTransport = null, p_policy: AuthorityPolicy = null
) -> NetworkAuthority:
	var service := NetworkAuthority.new()
	service.name = "NetworkAuthority"
	service.configure(p_transport, p_policy)
	return service


## An actor with a bag, a network identity and nothing else.
static func actor(
	entity_name: String = "Player",
	network_id: StringName = &"player",
	authority_peer: int = 0
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var identity := PersistentIdentity.new()
	identity.name = "PersistentIdentity"
	identity.persistent_id = StringName(entity_name.to_lower())
	entity.add_child(identity)

	var network := NetworkIdentity.new()
	network.name = "NetworkIdentity"
	network.network_id = network_id
	network.authority_peer = authority_peer
	entity.add_child(network)

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container(20)
	entity.add_child(inventory)
	return entity


## A plain container with a network id, for the far end of a transfer.
static func container(
	entity_name: String = "Chest", network_id: StringName = &"chest", slots: int = 10
) -> Node3D:
	var entity := Node3D.new()
	entity.name = entity_name

	var network := NetworkIdentity.new()
	network.name = "NetworkIdentity"
	network.network_id = network_id
	entity.add_child(network)

	var inventory := InventoryComponent.new()
	inventory.name = "InventoryComponent"
	inventory.profile_override = ItemFixtures.container(slots)
	entity.add_child(inventory)
	return entity


static func assemble(entity: Node, core: Node = null) -> void:
	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


static func find(entity: Node, type: Variant) -> FrameworkComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null


static func inventory_of(entity: Node) -> InventoryComponent:
	return find(entity, InventoryComponent) as InventoryComponent
