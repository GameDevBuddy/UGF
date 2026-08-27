class_name NetworkIntent
extends RefCounted
## One thing a client is asking the server to do.
##
## [b]Plain data, because it has to cross a wire.[/b] No nodes, no resources,
## no callables — a request carrying a node reference is a request that only
## works when both ends are the same process, which is exactly the illusion an
## offline-first codebase gives you right up until you test it.
##
## Entities are named by network id rather than passed, which is the same
## discipline saves use with persistent ids and for the same reason (rule 32).

## What is being asked: [code]inventory.add[/code], [code]combat.attack[/code].
var verb: StringName = &""

## Who is asking, by network id.
var actor_id: StringName = &""

## What it is being done to, when that is a different entity: the chest, the
## vendor, the target.
var target_id: StringName = &""

## Everything else. Deliberately a plain dictionary: a typed argument list per
## verb would mean a class per verb, and networking would grow a file every
## time a module gained a command.
var arguments: Dictionary = {}

## The peer that sent it. Set by the transport on arrival and never by the
## sender — a client that could name its own peer id could act as anybody.
var from_peer: int = 0

## Client-assigned sequence number, so a reply can be matched to a request and
## a duplicate can be dropped.
var sequence: int = 0


static func create(
	p_verb: StringName,
	p_actor: StringName = &"",
	p_arguments: Dictionary = {},
	p_target: StringName = &""
) -> NetworkIntent:
	var intent := NetworkIntent.new()
	intent.verb = p_verb
	intent.actor_id = p_actor
	intent.arguments = p_arguments.duplicate(true)
	intent.target_id = p_target
	return intent


func get_argument(key: StringName, fallback: Variant = null) -> Variant:
	return arguments.get(key, fallback)


func get_int(key: StringName, fallback: int = 0) -> int:
	var value: Variant = arguments.get(key, fallback)
	return int(value) if value is int or value is float else fallback


func get_string(key: StringName, fallback: StringName = &"") -> StringName:
	var value: Variant = arguments.get(key, fallback)
	return StringName(value) if value is String or value is StringName else fallback


func has_argument(key: StringName) -> bool:
	return arguments.has(key)


## Whether every value in this intent is something a transport can send.
##
## Checked before dispatch rather than trusted, because the failure mode of a
## non-serialisable argument is a request that works perfectly in a
## single-process test and silently does nothing over a real connection.
func is_serialisable() -> bool:
	for key in arguments:
		if arguments[key] is Object:
			return false
	return true


func to_dictionary() -> Dictionary:
	return {
		"verb": String(verb),
		"actor_id": String(actor_id),
		"target_id": String(target_id),
		"arguments": arguments.duplicate(true),
		"sequence": sequence,
	}


static func from_dictionary(data: Dictionary) -> NetworkIntent:
	var intent := NetworkIntent.new()
	intent.verb = StringName(data.get("verb", ""))
	intent.actor_id = StringName(data.get("actor_id", ""))
	intent.target_id = StringName(data.get("target_id", ""))
	intent.arguments = (data.get("arguments", {}) as Dictionary).duplicate(true)
	intent.sequence = int(data.get("sequence", 0))
	return intent


func _to_string() -> String:
	return "NetworkIntent(%s by %s)" % [verb, actor_id if actor_id != &"" else "<nobody>"]
