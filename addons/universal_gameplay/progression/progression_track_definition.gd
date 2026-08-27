class_name ProgressionTrackDefinition
extends FrameworkDefinition
## One thing a character gets better at, and what it costs to do so.
##
## A track is a curve and a set of rewards, not a class of character. "Player
## level", "Rifles", "Lockpicking" and "Guild standing with the Smiths" are all
## the same shape: experience goes in, a level comes out, and crossing a level
## boundary hands out points to spend. A project wanting one global level
## authors one track; a project wanting a skill per weapon authors ten
## (rule 24).
##
## [b]The curve is data, not code.[/b] Implementation Plan 12 asks for XP
## tracks and levels without saying what shape the curve is, because that is a
## design decision per game. Two shapes cover almost everything and both are
## authored here rather than subclassed (rule 23).

## Named CostCurve rather than Curve: a bare [code]Curve[/code] shadows
## Godot's native resource type of that name, which is a parse error rather
## than a scoped enum.
enum CostCurve {
	## Every level costs the same. Honest, predictable, and what most skill
	## tracks actually want.
	LINEAR,
	## Each level costs [member growth] times the last. The classic RPG
	## treadmill.
	GEOMETRIC,
	## Costs are read straight from [member explicit_thresholds], for a
	## designer who wants to hand-place every boundary.
	EXPLICIT,
}

@export var curve: CostCurve = CostCurve.LINEAR

## Experience needed to go from level 1 to level 2. Every later cost is
## derived from this one, except under [constant CostCurve.EXPLICIT].
@export_range(1.0, 1000000.0, 1.0, "or_greater") var base_cost: float = 100.0

## Multiplier per level under [constant CostCurve.GEOMETRIC]. Ignored otherwise.
@export_range(1.0, 4.0, 0.01, "or_greater") var growth: float = 1.5

## Cumulative experience needed to reach each level beyond the first, under
## [constant CostCurve.EXPLICIT]. The first entry is the cost of level 2.
@export var explicit_thresholds: Array[float] = []

## Highest level reachable. Experience beyond it is not lost -- it is refused,
## so a caller can tell the difference between "awarded" and "wasted".
@export_range(1, 999) var max_level: int = 20

## Level a fresh character starts at.
@export_range(1, 999) var starting_level: int = 1

@export_group("Rewards")
## Skill points handed out on each level gained.
@export_range(0, 99) var points_per_level: int = 1

## Stat raised by [member stat_per_level] every level. Empty means the track
## grants no stat growth of its own, which is the normal case for a skill.
@export var stat_per_level_id: StringName = &""

@export var stat_per_level: float = 0.0

@export_group("Vocabulary")
## Semantic state set while this track is at its maximum. Empty for none.
@export var mastered_state: StringName = &""


## Cumulative experience needed to be [param level].
##
## Level 1 costs nothing by definition: a character starts there. Asking for a
## level past [member max_level] returns the cost of the maximum, so a caller
## clamping its own arithmetic gets the same answer this class would.
func get_threshold(level: int) -> float:
	var target := clampi(level, 1, max_level)
	if target <= 1:
		return 0.0

	match curve:
		CostCurve.LINEAR:
			return base_cost * float(target - 1)
		CostCurve.GEOMETRIC:
			# Sum of the geometric series, not the nth term. The threshold is
			# what it costs to *have reached* this level, and summing as we go
			# is the difference between "level 10 costs 3,800" and "level 10
			# costs 57" -- a bug that only shows up at high level, by which
			# point somebody's save has the wrong number in it.
			var total := 0.0
			var step := base_cost
			for _index in range(target - 1):
				total += step
				step *= growth
			return total
		CostCurve.EXPLICIT:
			var index := target - 2
			if index < 0 or index >= explicit_thresholds.size():
				return explicit_thresholds[explicit_thresholds.size() - 1] if not explicit_thresholds.is_empty() else 0.0
			return explicit_thresholds[index]
	return 0.0


## The level [param experience] buys, clamped to [member max_level].
func get_level_for(experience: float) -> int:
	var level := 1
	while level < max_level and experience >= get_threshold(level + 1):
		level += 1
	return level


## Experience still needed to reach the next level, or zero at the maximum.
func get_remaining(experience: float) -> float:
	var level := get_level_for(experience)
	if level >= max_level:
		return 0.0
	return maxf(0.0, get_threshold(level + 1) - experience)


## How far through the current level, from 0.0 to 1.0. Returns 1.0 at the
## maximum, because a full bar is the honest way to draw a finished track.
func get_fraction(experience: float) -> float:
	var level := get_level_for(experience)
	if level >= max_level:
		return 1.0
	var floor_cost := get_threshold(level)
	var span := get_threshold(level + 1) - floor_cost
	if span <= 0.0:
		return 1.0
	return clampf((experience - floor_cost) / span, 0.0, 1.0)


func is_maxed(experience: float) -> bool:
	return get_level_for(experience) >= max_level


func validate() -> ValidationResult:
	var result := super()
	if starting_level > max_level:
		result.add_error(
			&"progression.starting_level_above_max",
			(
				"%s starts at level %d but tops out at %d, so a fresh character "
				+ "would begin past the end of its own track."
			) % [get_debug_name(), starting_level, max_level],
			resource_path,
			"starting_level"
		)
	if curve == CostCurve.EXPLICIT:
		if explicit_thresholds.size() < max_level - 1:
			result.add_error(
				&"progression.short_threshold_table",
				(
					"%s reaches level %d but lists only %d threshold(s); the "
					+ "levels past the table would all cost the same."
				) % [get_debug_name(), max_level, explicit_thresholds.size()],
				resource_path,
				"explicit_thresholds"
			)
		var previous := 0.0
		for threshold in explicit_thresholds:
			if threshold <= previous:
				result.add_error(
					&"progression.thresholds_not_ascending",
					(
						"%s has a threshold of %.1f after %.1f. Costs that do not "
						+ "ascend make a level unreachable or free."
					) % [get_debug_name(), threshold, previous],
					resource_path,
					"explicit_thresholds"
				)
				break
			previous = threshold
	if stat_per_level != 0.0 and stat_per_level_id == &"":
		result.add_warning(
			&"progression.unnamed_stat_growth",
			(
				"%s grants %.1f per level to no stat, so the growth is silently "
				+ "discarded."
			) % [get_debug_name(), stat_per_level],
			resource_path,
			"stat_per_level_id"
		)
	return result
