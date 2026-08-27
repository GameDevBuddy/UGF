class_name MultiplayerTransport
extends NetworkTransport
## The transport that puts an intent on the wire.
##
## The only place in the framework that touches [MultiplayerAPI], which is the
## whole point of the seam: Implementation Plan 27 says not to expose
## [MultiplayerSpawner] or [MultiplayerSynchronizer] to feature APIs, and this
## is how that stays true — everything upstream speaks in [NetworkIntent]s and
## has never heard of a peer.
##
## It is deliberately thin and deliberately unopinionated about topology. A
## project doing client-server, listen-server or relay writes its own
## [NetworkTransport] and changes nothing else.

## The node whose [member Node.multiplayer] is used, and which owns the RPCs.
## A project points this at its own autoload; without one this behaves exactly
## like the offline base.
var host: Node = null


static func create(p_host: Node) -> MultiplayerTransport:
	var transport := MultiplayerTransport.new()
	transport.host = p_host
	return transport


func is_server() -> bool:
	var api := _api()
	if api == null:
		# No session. The correct answer is "yes": a game that has not
		# connected is a game where this machine decides, which is the same
		# thing offline means.
		return true
	return api.is_server()


func get_peer_id() -> int:
	var api := _api()
	return api.get_unique_id() if api != null else 0


func is_connected_to_session() -> bool:
	return _api() != null


func send(intent: NetworkIntent) -> FrameworkResult:
	if intent == null:
		return FrameworkResult.fail(&"network.no_intent", "There is nothing to send.")
	if not intent.is_serialisable():
		return FrameworkResult.fail(
			&"network.unserialisable",
			"'%s' carries an object in its arguments." % intent.verb
		)
	if is_server():
		# Already authoritative. Executing locally rather than sending to
		# ourselves keeps the single-player path identical to the offline one.
		intent.from_peer = get_peer_id()
		intent_received.emit(intent)
		return FrameworkResult.ok(intent)
	if host == null or not host.has_method("submit_intent"):
		return FrameworkResult.fail(
			&"network.no_host",
			"No host node is wired to carry intents, so nothing can be sent."
		)
	host.call("submit_intent", intent.to_dictionary())
	return FrameworkResult.ok(intent)


func reply(to_peer: int, sequence: int, result: FrameworkResult) -> void:
	if to_peer == get_peer_id() or host == null or not host.has_method("deliver_result"):
		result_received.emit(sequence, result)
		return
	host.call("deliver_result", to_peer, sequence, result.code, result.message)


func broadcast(intent: NetworkIntent) -> void:
	if host != null and host.has_method("broadcast_intent") and is_server():
		host.call("broadcast_intent", intent.to_dictionary())


func _api() -> MultiplayerAPI:
	if host == null or not host.is_inside_tree():
		return null
	var api := host.multiplayer
	# has_multiplayer_peer() is the honest test: an API object exists whether
	# or not anybody is connected, and treating "exists" as "connected" makes
	# a single-player game think it is a client.
	return api if api != null and api.has_multiplayer_peer() else null
