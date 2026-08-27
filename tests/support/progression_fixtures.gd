class_name ProgressionFixtures
extends RefCounted
## Builders for the tracks, skills and characters the Progression suites need.
##
## Built in code rather than as [code].tres[/code] files because the addon
## ships no content of its own (rule 29), and because a track assembled in a
## test is one whose curve the test can state.


# --- Tracks ---------------------------------------------------------------

static func track(
	id: StringName = &"track.hero",
	max_level: int = 5,
	base_cost: float = 100.0,
	points_per_level: int = 1
) -> ProgressionTrackDefinition:
	var definition := ProgressionTrackDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.curve = ProgressionTrackDefinition.CostCurve.LINEAR
	definition.base_cost = base_cost
	definition.max_level = max_level
	definition.points_per_level = points_per_level
	return definition


static func geometric_track(
	id: StringName = &"track.geometric",
	max_level: int = 5,
	base_cost: float = 100.0,
	growth: float = 2.0
) -> ProgressionTrackDefinition:
	var definition := track(id, max_level, base_cost)
	definition.curve = ProgressionTrackDefinition.CostCurve.GEOMETRIC
	definition.growth = growth
	return definition


static func explicit_track(
	thresholds: Array[float], id: StringName = &"track.explicit"
) -> ProgressionTrackDefinition:
	var definition := track(id, thresholds.size() + 1)
	definition.curve = ProgressionTrackDefinition.CostCurve.EXPLICIT
	definition.explicit_thresholds = thresholds
	return definition


# --- Skills ---------------------------------------------------------------

static func skill(
	id: StringName,
	track_id: StringName = &"track.hero",
	required_level: int = 1,
	cost: int = 1
) -> SkillDefinition:
	var definition := SkillDefinition.new()
	definition.id = id
	definition.display_name = str(id)
	definition.track_id = track_id
	definition.required_level = required_level
	definition.cost = cost
	return definition


## A skill that actually does something: a flat bonus to one stat.
static func buffing_skill(
	id: StringName,
	stat: StringName = &"stat.power",
	amount: float = 5.0,
	required_level: int = 1,
	cost: int = 1
) -> SkillDefinition:
	var definition := skill(id, &"track.hero", required_level, cost)
	var modifier := StatModifier.new()
	modifier.stat = stat
	modifier.mode = StatModifier.Mode.FLAT
	modifier.value = amount
	var modifiers: Array[StatModifier] = [modifier]
	definition.modifiers = modifiers
	return definition


# --- Profiles -------------------------------------------------------------

static func profile(
	tracks: Array = [], skills: Array = [], starting: Array = []
) -> ProgressionProfile:
	var built := ProgressionProfile.new()
	var typed_tracks: Array[ProgressionTrackDefinition] = []
	typed_tracks.assign(tracks if not tracks.is_empty() else [track()])
	built.tracks = typed_tracks
	var typed_skills: Array[SkillDefinition] = []
	typed_skills.assign(skills)
	built.skills = typed_skills
	var typed_starting: Array[StringName] = []
	typed_starting.assign(starting)
	built.starting_skills = typed_starting
	return built


# --- Characters -----------------------------------------------------------

## Stats carrying one flat number for a skill to raise.
static func stats_profile(stat: StringName = &"stat.power", base: float = 10.0) -> StatsProfile:
	var definition := StatDefinition.new()
	definition.id = stat
	definition.display_name = str(stat)
	definition.default_base = base
	definition.minimum = 0.0

	var built := StatsProfile.new()
	var list: Array[StatDefinition] = [definition]
	built.stats = list
	return built


## A character that levels. [param with_stats] false leaves it without a
## [StatsComponent], which must still level correctly (rule 31).
static func hero(
	progression_profile: ProgressionProfile = null,
	with_stats: bool = true,
	narrative: NarrativeStateService = null
) -> Node3D:
	var entity := Node3D.new()
	entity.name = "Hero"

	var state := SemanticState.new()
	state.name = "SemanticState"
	entity.add_child(state)

	if with_stats:
		var stats := StatsComponent.new()
		stats.name = "StatsComponent"
		stats.profile_override = stats_profile()
		stats.auto_tick = false
		entity.add_child(stats)

	var progression := ProgressionComponent.new()
	progression.name = "ProgressionComponent"
	progression.profile_override = progression_profile if progression_profile != null else profile()
	progression.narrative = narrative
	entity.add_child(progression)
	return entity


static func assemble(entity: Node, core: Node = null) -> void:
	var context := EntityContext.create(entity, null, core)
	for component in DefinitionBinder.collect_components(entity):
		component.initialize(context)


static func progression_of(entity: Node) -> ProgressionComponent:
	return _find(entity, ProgressionComponent) as ProgressionComponent


static func stats_of(entity: Node) -> StatsComponent:
	return _find(entity, StatsComponent) as StatsComponent


static func state_of(entity: Node) -> SemanticState:
	if entity == null:
		return null
	for child in entity.get_children():
		if child is SemanticState:
			return child as SemanticState
	return null


static func _find(entity: Node, type: Variant) -> FrameworkComponent:
	if entity == null:
		return null
	for component in DefinitionBinder.collect_components(entity):
		if is_instance_of(component, type):
			return component
	return null
