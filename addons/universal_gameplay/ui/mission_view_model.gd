class_name MissionViewModel
extends ViewModel
## What a quest log and an objective tracker draw.

## One row per active mission: id, name, and its objectives.
var missions: Array[Dictionary] = []

## Mission ids finished, for a log showing completed entries.
var completed: Array[StringName] = []


func has_missions() -> bool:
	return not missions.is_empty()


func get_mission(mission_id: StringName) -> Dictionary:
	for row in missions:
		if row["mission_id"] == mission_id:
			return row
	return {}


func is_active(mission_id: StringName) -> bool:
	return not get_mission(mission_id).is_empty()


func has_completed(mission_id: StringName) -> bool:
	return completed.has(mission_id)


## The objectives of one mission, or an empty list.
func get_objectives(mission_id: StringName) -> Array:
	return get_mission(mission_id).get("objectives", [])


## The mission a tracker pins to the HUD: the first active one. Which one a
## project actually pins is its own decision; this is the sensible default so
## nobody has to write it.
func get_tracked() -> Dictionary:
	return missions[0] if not missions.is_empty() else {}


func to_dictionary() -> Dictionary:
	var data := super()
	data.merge({
		"missions": missions.duplicate(true),
		"completed": completed.duplicate(),
	})
	return data
