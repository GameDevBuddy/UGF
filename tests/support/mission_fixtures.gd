class_name MissionFixtures
extends RefCounted
## Builders for the missions and objectives the M9 suites need.
##
## Every objective here is built by [method objective] with a different event
## name and a different matcher, which is the exit gate stated as code: kill,
## acquire and talk are not three shapes, they are three configurations.


# --- Matchers -------------------------------------------------------------

static func matcher(
	field: StringName,
	value: Variant = null,
	mode: EventMatcher.Mode = EventMatcher.Mode.EQUALS
) -> EventMatcher:
	var check := EventMatcher.new()
	check.field = field
	check.value = value
	check.mode = mode
	return check


static func by_subject(field: StringName) -> EventMatcher:
	return matcher(field, null, EventMatcher.Mode.IS_SUBJECT)


static func tagged(field: StringName, tag: StringName) -> EventMatcher:
	return matcher(field, tag, EventMatcher.Mode.HAS_TAG)


# --- Objectives -----------------------------------------------------------

static func objective(
	id: StringName,
	event_name: StringName,
	matchers: Array = [],
	required: int = 1
) -> ObjectiveDefinition:
	var definition := ObjectiveDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.description = str(id)
	definition.event_name = event_name
	definition.required_count = required
	var typed: Array[EventMatcher] = []
	typed.assign(matchers)
	definition.matchers = typed
	return definition


## "Kill five bandits." Counts deaths whose instigator is the mission's
## subject and whose victim is tagged.
static func kill_objective(
	count: int = 5, tag: StringName = &"actor.bandit"
) -> ObjectiveDefinition:
	var definition := objective(
		&"objective.kill_bandits",
		GameplayNames.EVENT_ACTOR_DIED,
		[by_subject(&"get_instigator"), tagged(&"actor", tag)],
		count
	)
	definition.kind = GameplayNames.OBJECTIVE_KILL
	return definition


## "Collect ten planks." Counts acquisitions of one item id, using the
## event's quantity so a stack of ten counts as ten.
static func acquire_objective(
	item_id: StringName = &"item.plank", count: int = 10
) -> ObjectiveDefinition:
	var definition := objective(
		&"objective.collect",
		GameplayNames.EVENT_ITEM_ACQUIRED,
		[matcher(&"item_id", item_id)],
		count
	)
	definition.kind = GameplayNames.OBJECTIVE_ACQUIRE
	definition.count_field = &"quantity"
	return definition


## "Take the job." Counts one dialogue choice by id.
static func talk_objective(
	choice_id: StringName = &"choice.accept"
) -> ObjectiveDefinition:
	var definition := objective(
		&"objective.accept",
		GameplayNames.EVENT_DIALOGUE_CHOICE,
		[matcher(&"choice_id", choice_id)]
	)
	definition.kind = GameplayNames.OBJECTIVE_TALK
	return definition


## "Get to the docks."
static func reach_objective(area_id: StringName = &"area.docks") -> ObjectiveDefinition:
	var definition := objective(
		&"objective.reach",
		GameplayNames.EVENT_AREA_ENTERED,
		[matcher(&"area_id", area_id), by_subject(&"body")]
	)
	definition.kind = GameplayNames.OBJECTIVE_REACH
	return definition


## "Hold out for thirty seconds."
static func survive_objective(seconds: float = 30.0) -> ObjectiveDefinition:
	var definition := ObjectiveDefinition.new()
	definition.id = &"objective.survive"
	definition.display_name = "Survive"
	definition.description = "Hold out"
	definition.kind = GameplayNames.OBJECTIVE_SURVIVE
	definition.duration = seconds
	return definition


## An objective that fails when the escort dies.
static func escort_objective() -> ObjectiveDefinition:
	var definition := reach_objective(&"area.safehouse")
	definition.id = &"objective.escort"
	definition.failure_event_name = GameplayNames.EVENT_ACTOR_DIED
	var failure: Array[EventMatcher] = [
		MissionFixtures.tagged(&"actor", &"actor.escort")
	]
	definition.failure_matchers = failure
	return definition


# --- Missions -------------------------------------------------------------

static func mission(
	id: StringName, objectives: Array, sequential: bool = false
) -> MissionDefinition:
	var definition := MissionDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.description = str(id)
	var typed: Array[ObjectiveDefinition] = []
	typed.assign(objectives)
	definition.objectives = typed
	definition.sequential = sequential
	return definition


## The mission the exit gate is stated against: one objective per source.
static func cross_feature_mission() -> MissionDefinition:
	return mission(
		&"mission.cross_feature",
		[kill_objective(2), acquire_objective(&"item.plank", 3), talk_objective()]
	)


static func rewards(entries: Array) -> Array[MissionReward]:
	var typed: Array[MissionReward] = []
	typed.assign(entries)
	return typed


static func flag_reward(flag: StringName) -> NarrativeReward:
	var reward := NarrativeReward.new()
	reward.operation = NarrativeReward.Operation.SET_FLAG
	reward.key = flag
	reward.value = true
	return reward


static func item_reward(item_id: StringName, quantity: int = 1) -> ItemReward:
	var reward := ItemReward.new()
	reward.item_id = item_id
	reward.quantity = quantity
	return reward
