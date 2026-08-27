class_name ServiceInspector
extends RefCounted
## Reports what the services actually hold.
##
## The plan's debug list asks for a mission inspector, a faction matrix, a save
## inspector and a spawn debugger. Those are four panels over four modules —
## and four files here would mean [code]debug/[/code] importing four modules and
## becoming the one thing in the framework that cannot be deleted.
##
## So this asks generically. Every service it describes is found by having the
## methods it needs, never by type, which is why this file names no module and
## why a project's own service gets described for free if it answers the same
## questions (rule 9, rule 23).
##
## Read-only by construction, like [EntityInspector]: every method observes and
## none mutate.


# --- Missions -------------------------------------------------------------

## Active missions and their objectives.
##
## Duck-typed on [code]get_active()[/code], so this works with a
## [MissionService] and equally with a project's own.
static func missions(service: Object) -> Dictionary:
	if service == null or not service.has_method("get_active"):
		return {"error": "no mission service"}
	var rows: Array[Dictionary] = []
	for runtime in service.call("get_active"):
		var objectives: Array[Dictionary] = []
		for objective in runtime.get_objectives():
			objectives.append({
				"id": objective.get_id(),
				"text": objective.describe(),
				"progress": objective.progress,
				"target": objective.get_target(),
				"complete": objective.is_complete(),
				"failed": objective.is_failed(),
			})
		rows.append({
			"id": runtime.get_id(),
			"fraction": runtime.get_fraction(),
			"objectives": objectives,
		})
	var data: Dictionary = {"active": rows}
	if service.has_method("get_completed_ids"):
		data["completed"] = service.call("get_completed_ids")
	return data


# --- Factions -------------------------------------------------------------

## The relation matrix, plus every recorded personal reputation.
##
## The matrix is directional and printed as such: relations are keyed
## subject-to-other, and a one-sided grudge is a real thing the framework
## models. A matrix that folded them would hide exactly the asymmetry somebody
## opened this panel to find.
static func factions(service: Object) -> Dictionary:
	if service == null or not service.has_method("get_faction_ids"):
		return {"error": "no faction service"}
	var ids: Array = service.call("get_faction_ids")
	var matrix: Dictionary = {}
	for subject in ids:
		var row: Dictionary = {}
		for other in ids:
			if subject == other:
				continue
			row[String(other)] = service.call("get_relation", subject, other)
		matrix[String(subject)] = row
	return {"factions": ids, "relations": matrix}


# --- Wanted ---------------------------------------------------------------

static func heat(service: Object) -> Dictionary:
	if service == null or not service.has_method("get_tracked_actors"):
		return {"error": "no heat service"}
	var rows: Array[Dictionary] = []
	for actor in service.call("get_tracked_actors"):
		var row: Dictionary = {
			"actor": actor,
			"total_heat": service.call("get_total_heat", actor),
		}
		if service.has_method("get_wanted_factions"):
			row["wanted_by"] = service.call("get_wanted_factions", actor)
		if service.has_method("get_wanted_states"):
			row["states"] = service.call("get_wanted_states", actor)
		rows.append(row)
	return {"tracked": rows}


# --- World and spawning ---------------------------------------------------

## Region budgets and live populations. The plan's spawn debugger, minus the
## rejection reasons — those are a signal on [SpawnService] and belong on a
## live feed rather than in a snapshot.
static func world(service: Object) -> Dictionary:
	if service == null or not service.has_method("get_region_ids"):
		return {"error": "no world state service"}
	var rows: Array[Dictionary] = []
	for region_id in service.call("get_region_ids"):
		var region: Variant = service.call("get_region", region_id)
		var row: Dictionary = {
			"region": region_id,
			"active": service.call("is_active", region_id),
			"population": service.call("get_population", region_id, &""),
		}
		if region != null and region.has_method("get_budgeted_categories"):
			var budgets: Dictionary = {}
			for category in region.call("get_budgeted_categories"):
				budgets[String(category)] = {
					"used": service.call("get_population", region_id, category),
					"limit": region.call("get_budget", category),
				}
			row["budgets"] = budgets
		rows.append(row)
	return {"regions": rows}


static func spawning(service: Object) -> Dictionary:
	if service == null or not service.has_method("get_last_tick_cost"):
		return {"error": "no spawn service"}
	var data: Dictionary = {
		"last_tick_cost": service.call("get_last_tick_cost"),
		"anchors": service.call("get_anchor_count", &""),
		"tracked": service.call("get_tracked_count"),
	}
	if service.has_method("get_pools"):
		var pools: Array[StringName] = []
		for pool in service.call("get_pools"):
			pools.append(pool.id)
		data["pools"] = pools
	return data


# --- Saves ----------------------------------------------------------------

static func saves(service: Object) -> Dictionary:
	if service == null or not service.has_method("list_slots"):
		return {"error": "no save service"}
	var rows: Array[Dictionary] = []
	for slot in service.call("list_slots"):
		rows.append(slot.to_dictionary())
	var data: Dictionary = {"slots": rows}
	if service.has_method("get_registered_entity_count"):
		data["registered_entities"] = service.call("get_registered_entity_count")
	if service.has_method("get_registered_service_ids"):
		data["registered_services"] = service.call("get_registered_service_ids")
	return data


# --- Everything -----------------------------------------------------------

## Describes every service registered with a core.
##
## Looks each one up by the id it registers under and asks whichever describer
## fits. A core with three modules installed reports three sections rather than
## eight errors, because a describer that found nothing is simply left out.
static func inspect_core(core: Object) -> Dictionary:
	if core == null or not core.has_method("get_service"):
		return {"error": "no core"}
	var data: Dictionary = {}
	for pair in [
		[&"missions", GameplayNames.SERVICE_OBJECTIVE, &"get_active"],
		[&"factions", GameplayNames.SERVICE_FACTION, &"get_faction_ids"],
		[&"heat", GameplayNames.SERVICE_CRIME, &"get_tracked_actors"],
		[&"world", GameplayNames.SERVICE_WORLD_STATE, &"get_region_ids"],
		[&"spawning", GameplayNames.SERVICE_SPAWN, &"get_last_tick_cost"],
		[&"saves", GameplayNames.SERVICE_SAVE, &"list_slots"],
	]:
		var service: Variant = core.call("get_service", pair[1])
		if service == null or not (service as Object).has_method(pair[2]):
			continue
		data[String(pair[0])] = _describe(pair[0], service)
	return data


## Human-readable dump of everything, for a console.
static func describe_core(core: Object) -> String:
	var data := inspect_core(core)
	if data.has("error"):
		return String(data["error"])
	if data.is_empty():
		return "No inspectable services are registered."
	var lines := PackedStringArray()
	for section in data:
		lines.append("[%s]" % section)
		lines.append("  " + JSON.stringify(data[section]))
	return "\n".join(lines)


static func _describe(section: StringName, service: Object) -> Dictionary:
	match section:
		&"missions":
			return missions(service)
		&"factions":
			return factions(service)
		&"heat":
			return heat(service)
		&"world":
			return world(service)
		&"spawning":
			return spawning(service)
		&"saves":
			return saves(service)
	return {}
