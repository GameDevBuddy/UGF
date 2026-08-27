class_name AIInspector
extends RefCounted
## The plan's AI Debug Panel: brain state, target, perception facts and path.
##
## [b]It reads and never touches.[/b] Rule 21 in its bluntest form: a debug
## panel that could set an NPC's target would be a second owner of that state,
## and the bug you were chasing would move whenever you looked at it.
##
## [b]It names no module.[/b] Like [ServiceInspector], every read is duck-typed
## through [method Object.has_method], so this file compiles and runs in a
## project with the AI module deleted -- it just reports that the entity has no
## brain, which is true (rule 10, rule 31).
##
## Returns plain dictionaries and strings rather than drawing anything. What
## draws it is the project's own [Control], because the framework ships no
## widgets (M17's decision, unchanged here).


## Everything the panel shows for one entity, as plain data.
##
## Every key is always present, so a panel binding to it does not have to
## branch on which modules the project installed. Absent capabilities report
## themselves rather than being missing.
static func inspect(entity: Node) -> Dictionary:
	if entity == null or not is_instance_valid(entity):
		return {
			"entity": "<none>",
			"has_ai": false,
			"state": &"",
			"role": &"",
			"active": false,
			"target": "",
			"target_position": Vector3.ZERO,
			"facts": [],
			"path": {},
		}

	var controller := _find(entity, "get_ai_state")
	var perception := _find(entity, "get_memory")
	var navigation := _find(entity, "get_destination")

	return {
		"entity": String(entity.name),
		"has_ai": controller != null,
		"state": _call(controller, "get_ai_state", &""),
		"role": _role_id(controller),
		"active": _call(controller, "is_active", false),
		"target": _target_name(controller, perception),
		"target_position": _target_position(perception),
		"facts": describe_facts(perception),
		"path": describe_path(navigation),
	}


## One line per remembered entity, in the order a brain would care about:
## what is attacking us, then what we can see, then what we merely remember.
##
## [b]Sorted rather than raw.[/b] A memory dictionary in insertion order tells
## you nothing at a glance, and the whole value of the panel is the glance.
static func describe_facts(perception: Object) -> Array[Dictionary]:
	var facts: Array[Dictionary] = []
	if perception == null or not perception.has_method("get_memory"):
		return facts

	var memory: Object = perception.call("get_memory")
	if memory == null or not memory.has_method("get_entries"):
		return facts

	for entry in memory.call("get_entries"):
		if entry == null or not entry.is_valid():
			continue
		facts.append({
			"target": String(entry.target.name),
			"visible": entry.visible,
			"noticed": entry.noticed,
			"heard": entry.heard,
			"attacked_us": entry.attacked_us,
			"damage_from": entry.damage_taken_from,
			"interacted": entry.interacted,
			"last_interaction": entry.last_interaction,
			"threat": entry.threat,
			"since_seen": entry.time_since_seen,
			"last_known": entry.last_known_position,
		})

	facts.sort_custom(_more_urgent_first)
	return facts


## Where this NPC is going and how far it has to go.
static func describe_path(navigation: Object) -> Dictionary:
	if navigation == null or not navigation.has_method("has_destination"):
		return {"has_destination": false, "destination": Vector3.ZERO, "remaining": 0.0, "direction": Vector3.ZERO}
	return {
		"has_destination": navigation.call("has_destination"),
		"destination": _call(navigation, "get_destination", Vector3.ZERO),
		"remaining": _call(navigation, "get_remaining_distance", 0.0),
		"direction": _call(navigation, "get_desired_direction", Vector3.ZERO),
	}


## The panel as text, for a console or a log line.
static func format(entity: Node) -> String:
	var data := inspect(entity)
	if not data["has_ai"]:
		return "%s: no AI controller." % data["entity"]

	var lines: Array[String] = []
	lines.append(
		"%s  state=%s  role=%s  %s"
		% [
			data["entity"],
			data["state"] if data["state"] != &"" else "<none>",
			data["role"] if data["role"] != &"" else "<none>",
			"active" if data["active"] else "idle",
		]
	)
	lines.append("  target: %s" % (data["target"] if data["target"] != "" else "<none>"))

	var path: Dictionary = data["path"]
	if path["has_destination"]:
		lines.append(
			"  path:   %.1fm to %v" % [path["remaining"], path["destination"]]
		)
	else:
		lines.append("  path:   <none>")

	var facts: Array = data["facts"]
	if facts.is_empty():
		lines.append("  knows:  nothing")
	else:
		lines.append("  knows:")
		for fact in facts:
			lines.append("    %s" % _format_fact(fact))
	return "\n".join(lines)


static func _format_fact(fact: Dictionary) -> String:
	var marks: Array[String] = []
	if fact["attacked_us"]:
		marks.append("ATTACKER(%.0f)" % fact["damage_from"])
	if fact["visible"]:
		marks.append("visible")
	elif fact["heard"]:
		marks.append("heard")
	else:
		marks.append("%.1fs ago" % fact["since_seen"])
	if fact["interacted"]:
		marks.append("used %s" % fact["last_interaction"])
	if not fact["noticed"]:
		marks.append("unnoticed")
	return "%-16s %s" % [fact["target"], " ".join(marks)]


## Attackers first, then what is visible, then by how recently it was seen.
static func _more_urgent_first(a: Dictionary, b: Dictionary) -> bool:
	if a["attacked_us"] != b["attacked_us"]:
		return a["attacked_us"]
	if a["visible"] != b["visible"]:
		return a["visible"]
	return a["since_seen"] < b["since_seen"]


static func _target_name(controller: Object, perception: Object) -> String:
	# A brain's current target is not stored anywhere in the framework: brains
	# decide it per tick from memory rather than holding it, which is what
	# makes them stateless and testable. So the panel reports the entity a
	# brain would most likely pick, and says so rather than inventing a field.
	var facts := describe_facts(perception)
	if facts.is_empty():
		return ""
	var best: Dictionary = facts[0]
	if not best["noticed"]:
		return ""
	return String(best["target"])


static func _target_position(perception: Object) -> Vector3:
	var facts := describe_facts(perception)
	if facts.is_empty():
		return Vector3.ZERO
	return facts[0]["last_known"]


static func _role_id(controller: Object) -> StringName:
	if controller == null or not controller.has_method("get_role"):
		return &""
	var role: Object = controller.call("get_role")
	if role == null:
		return &""
	return role.get("id")


static func _find(entity: Node, method: String) -> Object:
	for child in entity.get_children():
		if child.has_method(method):
			return child
	return null


static func _call(target: Object, method: String, fallback: Variant) -> Variant:
	if target == null or not target.has_method(method):
		return fallback
	return target.call(method)
