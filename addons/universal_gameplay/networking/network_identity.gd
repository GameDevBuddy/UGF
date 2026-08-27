class_name NetworkIdentity
extends FrameworkComponent
## Who owns this entity across the wire.
##
## [b]A network id is not a save id, and conflating them is the mistake
## Implementation Plan 27 calls out by name.[/b] A save id must be stable
## forever — it is what a record on disk is keyed by. A network id must be
## stable only for one session, is assigned by whoever is hosting, and is
## reassigned freely when a player reconnects. Using one for the other means
## either saves that break when somebody rejoins, or network traffic that
## leaks the shape of a save file.
##
## So this is its own component, sitting alongside [PersistentIdentity] and
## never replacing it.

## Emitted when ownership changes: a player takes control of an NPC, a host
## migrates, a vehicle changes driver.
signal authority_changed(peer_id: int)

## The peer that may act for this entity. Zero is the server, which is also
## the correct value offline — an offline game is a game where the server is
## the only peer, and treating it as a special case is how a codebase ends up
## with two of everything.
@export var authority_peer: int = 0

## Session-scoped id. Assigned by the host; blank until it is.
@export var network_id: StringName = &""

## Whether this entity is replicated at all. Off is scenery: a crate that both
## machines spawn identically from the same definition needs no traffic.
@export var replicated: bool = true


func get_network_id() -> StringName:
	return network_id


func set_network_id(value: StringName) -> void:
	network_id = value


func has_network_id() -> bool:
	return network_id != &""


func get_authority() -> int:
	return authority_peer


## Hands this entity to a peer. What possession, host migration and a player
## joining all call.
func set_authority(peer_id: int) -> void:
	if peer_id == authority_peer:
		return
	authority_peer = peer_id
	authority_changed.emit(peer_id)


## Whether [param peer_id] may act for this entity.
func is_authority(peer_id: int) -> bool:
	return authority_peer == peer_id


## Whether the server owns this. True offline, because offline the server is
## the only peer there is.
func is_server_owned() -> bool:
	return authority_peer == 0


static func find_on(entity: Node) -> NetworkIdentity:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if component is NetworkIdentity:
			return component as NetworkIdentity
	return null


func validate() -> ValidationResult:
	var result := ValidationResult.new()
	if authority_peer < 0:
		result.add_error(
			&"network.negative_peer",
			"A peer id cannot be negative.",
			"",
			"authority_peer"
		)
	if not replicated and authority_peer != 0:
		result.add_warning(
			&"network.unreplicated_client_owned",
			(
				"This entity is not replicated but is owned by a client, so "
				+ "nothing it does will reach anybody."
			),
			"",
			"replicated"
		)
	return result
