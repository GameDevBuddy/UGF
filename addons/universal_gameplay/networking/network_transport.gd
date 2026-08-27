class_name NetworkTransport
extends RefCounted
## Where intents actually go. The seam between the framework and Godot's
## multiplayer API.
##
## [b]The default is offline, and offline is not a special case.[/b] This base
## executes every intent immediately in-process, which is exactly right for a
## single-player game — the server is the only peer, so the round trip is a
## function call. That is what makes "offline mode unchanged" true by
## construction rather than by careful maintenance: there is no second code
## path to keep in step.
##
## [MultiplayerTransport] is the subclass that puts an intent on the wire, and
## it is the only file in the framework that touches [MultiplayerAPI].

## Emitted when an intent arrives to be executed, on whichever machine is
## authoritative.
signal intent_received(intent: NetworkIntent)

## Emitted when a result comes back to the peer that asked.
signal result_received(sequence: int, result: FrameworkResult)


## Whether this machine decides. Always true offline.
func is_server() -> bool:
	return true


## This machine's peer id. Zero offline, which is the server's id.
func get_peer_id() -> int:
	return 0


func is_connected_to_session() -> bool:
	return false


## Sends an intent to whoever is authoritative.
##
## Offline that is this machine, so it arrives on the next line. Networked it
## is an RPC and arrives later, which is why callers get a
## [FrameworkResult] describing the *send* and hear about the outcome through
## [signal result_received].
func send(intent: NetworkIntent) -> FrameworkResult:
	if intent == null:
		return FrameworkResult.fail(&"network.no_intent", "There is nothing to send.")
	if not intent.is_serialisable():
		return FrameworkResult.fail(
			&"network.unserialisable",
			(
				"'%s' carries an object in its arguments, which would work here "
				+ "and fail over a real connection."
			) % intent.verb
		)
	intent.from_peer = get_peer_id()
	intent_received.emit(intent)
	return FrameworkResult.ok(intent)


## Sends a result back to the peer that asked. A no-op offline: the caller
## already has it.
func reply(_to_peer: int, sequence: int, result: FrameworkResult) -> void:
	result_received.emit(sequence, result)


## Announces state a client should apply. Offline nobody is listening, and
## that is the correct amount of work to do about it.
func broadcast(_intent: NetworkIntent) -> void:
	pass
