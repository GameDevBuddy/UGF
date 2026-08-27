class_name NetworkAuthority
extends FrameworkService
## The facade every mutation can be routed through, and which does nothing at
## all offline.
##
## [b]This is the M18 exit gate.[/b] "Offline mode unchanged" is not something
## you verify by playing; it is a property of there being one code path. A
## command handed to [method execute] offline runs immediately, in-process, on
## the same line — because the offline transport is authoritative and the
## offline policy owns nothing. There is no second branch to drift.
##
## [b]Nothing knows this exists.[/b] Implementation Plan 27 says to define
## mutation APIs so an authority adapter can sit in front of them, and that is
## exactly the shape: the modules already have mutation APIs, and the adapters
## in this folder register handlers that call them. No file outside
## [code]networking/[/code] names a peer, an intent or this service — a test
## asserts it.

## Emitted when an intent is executed on the authoritative machine.
signal intent_executed(intent: NetworkIntent, result: FrameworkResult)

## Emitted when an intent was refused, with why. What an anti-cheat log reads.
signal intent_rejected(intent: NetworkIntent, reason: StringName)

## Emitted when a result comes back for something this peer asked for.
signal request_answered(sequence: int, result: FrameworkResult)

## Where intents go. Offline by default, which is what makes the single-player
## path the same path.
var transport: NetworkTransport = null

## What the server owns. Null owns nothing, which is correct offline.
var policy: AuthorityPolicy = null

## Verb to handler. Registered by adapters, so this file names no module.
var _handlers: Dictionary[StringName, Callable] = {}

## Verb to validators. Run on the authoritative machine before the handler.
var _validators: Dictionary[StringName, Array] = {}

## Network id to entity, so an intent naming an actor can find one without a
## scan — the same registry discipline M14 established.
var _entities: Dictionary[StringName, Node] = {}

var _sequence: int = 0
var _rejections: Dictionary[StringName, int] = {}


func get_service_id() -> StringName:
	return GameplayNames.SERVICE_NETWORK


func configure(
	p_transport: NetworkTransport = null, p_policy: AuthorityPolicy = null
) -> void:
	set_transport(p_transport if p_transport != null else NetworkTransport.new())
	policy = p_policy


func service_stopped() -> void:
	set_transport(null)
	_handlers.clear()
	_validators.clear()
	_entities.clear()


func set_transport(value: NetworkTransport) -> void:
	if transport == value:
		return
	if transport != null:
		if transport.intent_received.is_connected(_on_intent):
			transport.intent_received.disconnect(_on_intent)
		if transport.result_received.is_connected(_on_result):
			transport.result_received.disconnect(_on_result)
	transport = value
	if transport != null:
		transport.intent_received.connect(_on_intent)
		transport.result_received.connect(_on_result)


func _get_transport() -> NetworkTransport:
	if transport == null:
		set_transport(NetworkTransport.new())
	return transport


# --- Queries --------------------------------------------------------------

func is_server() -> bool:
	return _get_transport().is_server()


func get_peer_id() -> int:
	return _get_transport().get_peer_id()


## Whether a session is running at all. False offline, and almost nothing
## should care — the point of the design is that offline and hosting behave
## identically.
func is_networked() -> bool:
	return _get_transport().is_connected_to_session()


## Whether [param verb] must go through the server.
func is_authoritative(verb: StringName) -> bool:
	return policy != null and policy.is_authoritative(verb)


## Whether this peer may execute [param verb] directly.
##
## True offline for everything, because offline this peer is the server.
func may_execute(verb: StringName) -> bool:
	return not is_authoritative(verb) or is_server()


## Whether [param peer_id] may act for [param entity].
func has_authority_over(entity: Node, peer_id: int = -1) -> bool:
	var identity := NetworkIdentity.find_on(entity)
	if identity == null:
		# No network identity is not a refusal. An entity nobody claimed is an
		# entity the server owns, which offline is everybody.
		return true
	var peer := peer_id if peer_id >= 0 else get_peer_id()
	return identity.is_authority(peer) or peer == 0


# --- Registration ---------------------------------------------------------

## Registers what a verb does. Called by the adapters, never by this file.
func register_handler(verb: StringName, handler: Callable) -> FrameworkResult:
	if verb == &"" or not handler.is_valid():
		return FrameworkResult.fail(
			&"network.invalid_handler", "A handler needs a verb and a callable."
		)
	if _handlers.has(verb):
		return FrameworkResult.fail(
			&"network.duplicate_handler", "'%s' already has a handler." % verb
		)
	_handlers[verb] = handler
	return FrameworkResult.ok(verb)


func unregister_handler(verb: StringName) -> bool:
	_validators.erase(verb)
	return _handlers.erase(verb)


func has_handler(verb: StringName) -> bool:
	return _handlers.has(verb)


func get_verbs() -> Array[StringName]:
	var verbs: Array[StringName] = []
	verbs.assign(_handlers.keys())
	verbs.sort()
	return verbs


## Adds a check that runs on the authoritative machine before the handler.
##
## [b]Validation belongs here and only here.[/b] A client can be modified; a
## check that ran client-side is a suggestion. Registering them separately from
## handlers is what makes "did anybody validate this?" answerable per verb.
func register_validator(verb: StringName, validator: Callable) -> FrameworkResult:
	if verb == &"" or not validator.is_valid():
		return FrameworkResult.fail(
			&"network.invalid_validator", "A validator needs a verb and a callable."
		)
	if not _validators.has(verb):
		_validators[verb] = []
	(_validators[verb] as Array).append(validator)
	return FrameworkResult.ok(verb)


func get_validator_count(verb: StringName) -> int:
	return (_validators.get(verb, []) as Array).size()


## Registers an entity by network id, so an intent can name it.
func register_entity(entity: Node) -> FrameworkResult:
	var identity := NetworkIdentity.find_on(entity)
	if identity == null or not identity.has_network_id():
		return FrameworkResult.fail(
			&"network.no_identity",
			"That entity has no network id, so no intent could name it."
		)
	_entities[identity.get_network_id()] = entity
	return FrameworkResult.ok(entity)


func unregister_entity(entity: Node) -> bool:
	var identity := NetworkIdentity.find_on(entity)
	if identity == null:
		return false
	return _entities.erase(identity.get_network_id())


func find_entity(network_id: StringName) -> Node:
	var candidate: Variant = _entities.get(network_id)
	if candidate == null or not is_instance_valid(candidate):
		return null
	return candidate as Node


func get_registered_entity_count() -> int:
	return _entities.size()


# --- Executing ------------------------------------------------------------

## Runs a command, going through the server when the policy says to.
##
## [b]Offline this is a function call.[/b] The policy owns nothing, so
## [method may_execute] is true, so the handler runs on the next line and
## returns its own result — indistinguishable from calling the component
## directly, which is the whole claim.
func execute(
	verb: StringName, actor: Node = null, arguments: Dictionary = {}, target: Node = null
) -> FrameworkResult:
	var intent := NetworkIntent.create(
		verb, _id_of(actor), arguments, _id_of(target)
	)
	_sequence += 1
	intent.sequence = _sequence
	return submit(intent)


## Submits a prepared intent. What a project building its own intents calls.
func submit(intent: NetworkIntent) -> FrameworkResult:
	if intent == null:
		return FrameworkResult.fail(&"network.no_intent", "There is nothing to submit.")
	if not has_handler(intent.verb):
		return _reject(intent, &"network.unknown_verb", "Nothing handles '%s'." % intent.verb)
	if may_execute(intent.verb):
		intent.from_peer = get_peer_id()
		return _run(intent)
	# Not ours to decide. The send is what succeeds here; the outcome arrives
	# on request_answered, because a client that blocked for the server's
	# answer would be a client that stutters.
	return _get_transport().send(intent)


## Runs an intent on this machine, having decided it may.
##
## Public so a project's own transport can hand an arrived intent straight in
## without going back through the policy — the arriving machine has already
## established it is the authority.
func execute_locally(intent: NetworkIntent) -> FrameworkResult:
	return _run(intent)


func get_rejection_counts() -> Dictionary:
	return _rejections.duplicate()


func clear_rejection_counts() -> void:
	_rejections.clear()


# --- Internals ------------------------------------------------------------

func _run(intent: NetworkIntent) -> FrameworkResult:
	var actor := find_entity(intent.actor_id) if intent.actor_id != &"" else null
	if intent.actor_id != &"" and actor == null:
		return _reject(
			intent, &"network.unknown_actor",
			"No entity is registered as '%s'." % intent.actor_id
		)
	# The check a client cannot be trusted to have made: that the peer asking
	# actually owns the thing it is asking about.
	if actor != null and not has_authority_over(actor, intent.from_peer):
		return _reject(
			intent, &"network.not_yours",
			"Peer %d does not own '%s'." % [intent.from_peer, intent.actor_id]
		)

	for validator in _validators.get(intent.verb, []):
		var verdict: Variant = validator.call(intent)
		if verdict is FrameworkResult and (verdict as FrameworkResult).is_err():
			return _reject(intent, (verdict as FrameworkResult).code, (verdict as FrameworkResult).message)
		if verdict is bool and not verdict:
			return _reject(intent, &"network.refused", "'%s' was refused." % intent.verb)

	var answer: Variant = (_handlers[intent.verb] as Callable).call(intent)
	var result: FrameworkResult = (
		answer if answer is FrameworkResult else FrameworkResult.ok(answer)
	)
	intent_executed.emit(intent, result)
	if result.is_ok():
		_get_transport().broadcast(intent)
	_get_transport().reply(intent.from_peer, intent.sequence, result)
	return result


func _reject(intent: NetworkIntent, code: StringName, message: String) -> FrameworkResult:
	_rejections[code] = _rejections.get(code, 0) + 1
	intent_rejected.emit(intent, code)
	var result := FrameworkResult.fail(code, message)
	_get_transport().reply(intent.from_peer, intent.sequence, result)
	return result


func _on_intent(intent: NetworkIntent) -> void:
	# Arrived from the transport. Only the authority runs it; a client seeing
	# its own send echo back must not execute it twice.
	if is_server():
		_run(intent)


func _on_result(sequence: int, result: FrameworkResult) -> void:
	request_answered.emit(sequence, result)


func _id_of(entity: Node) -> StringName:
	var identity := NetworkIdentity.find_on(entity)
	return identity.get_network_id() if identity != null else &""
