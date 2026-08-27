class_name EncounterDefinition
extends FrameworkDefinition
## A group that appears together: an ambush, a patrol, a convoy, a market
## stall and its keeper.
##
## [b]Not a spawn pool with a bigger batch size.[/b] A pool keeps a population
## topped up and each placement is independent; an encounter is one authored
## event whose members are placed together, in a shape, once, and usually
## because something in the story asked for it. Collapsing the two would mean
## a pool carrying "am I a one-off?" on every field.

## Everyone in the group. Unlike a pool, every entry is placed — the weights
## on them are ignored here, which is what "together" means.
@export var members: Array[SpawnEntry] = []

@export_group("Shape")
## How far from the anchor the members are scattered, in metres.
@export_range(0.0, 500.0, 0.1, "or_greater") var spread: float = 4.0

## Minimum gap between members, so a squad does not spawn inside itself.
@export_range(0.0, 50.0, 0.1) var separation: float = 1.5

@export_group("Availability")
## Region tags this encounter can happen in.
@export var region_tags: Array[StringName] = []

## Which budget the members count against.
@export var category: StringName = &"population.encounter"

## Narrative flags required before it can happen.
@export var required_flags: Array[StringName] = []

## Flags that prevent it. What "already done this one" looks like.
@export var forbidden_flags: Array[StringName] = []

## Whether it can happen more than once.
@export var repeatable: bool = false

## Seconds before it may happen again. Ignored when not repeatable.
@export_range(0.0, 86400.0, 1.0, "or_greater") var cooldown: float = 300.0

@export_group("Despawn")
@export var despawn: DespawnPolicy


func get_member_count() -> int:
	var count := 0
	for member in members:
		if member != null:
			count += 1
	return count


func applies_to(region: RegionDefinition) -> bool:
	if region == null:
		return false
	if region_tags.is_empty():
		return true
	for tag in region_tags:
		if region.has_region_tag(tag):
			return true
	return false


## Whether the story allows this encounter right now.
##
## Forbidden flags are checked even with no narrative installed — with no
## store, nothing is raised, so nothing forbids and nothing requires. That
## keeps a missing Narrative module a valid configuration rather than one that
## silently runs every once-only encounter forever (rule 31).
func is_available(narrative: NarrativeStateService) -> bool:
	if not required_flags.is_empty():
		if narrative == null or not narrative.has_all_flags(required_flags):
			return false
	if narrative != null and not forbidden_flags.is_empty():
		if narrative.has_any_flag(forbidden_flags):
			return false
	return true


## Positions for the members around [param origin].
##
## Rejection-sampled against [member separation] with a bounded number of
## attempts, then placed anyway. Bounded because an unsatisfiable separation —
## eight members, one metre of spread, two metres apart — must not hang the
## spawner; a slightly crowded squad is a better failure than a frozen frame.
func get_member_positions(
	origin: Vector3, count: int, rng: RandomNumberGenerator
) -> Array[Vector3]:
	var placed: Array[Vector3] = []
	for index in count:
		var position := origin
		for attempt in 8:
			var angle := rng.randf() * TAU
			var distance := sqrt(rng.randf()) * spread
			position = origin + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
			if _is_clear(position, placed):
				break
		placed.append(position)
	return placed


func validate() -> ValidationResult:
	var result := super()
	if get_member_count() == 0:
		result.add_error(
			&"encounter.no_members",
			"%s has nobody in it." % get_debug_name(),
			resource_path,
			"members"
		)
	if separation > spread and spread > 0.0:
		result.add_warning(
			&"encounter.impossible_separation",
			(
				"%s asks for %.1fm between members within a %.1fm spread, which "
				+ "cannot be satisfied; members will be placed crowded."
			) % [get_debug_name(), separation, spread],
			resource_path,
			"separation"
		)
	if not repeatable and cooldown > 0.0:
		result.add_info(
			&"encounter.cooldown_without_repeat",
			(
				"%s never repeats, so its cooldown is never waited out."
			) % get_debug_name(),
			resource_path,
			"cooldown"
		)
	for member in members:
		if member != null:
			result.merge(member.validate())
	return result


func _is_clear(position: Vector3, placed: Array[Vector3]) -> bool:
	if separation <= 0.0:
		return true
	for other in placed:
		if position.distance_to(other) < separation:
			return false
	return true
